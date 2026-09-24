import Foundation
import CoreGraphics
import Network
import Darwin

/// Whether Sky Bother can show the selected rig's own picture. Decided by
/// the model, not by whether the scope is on right now: a supported scope
/// that's switched off still gets an enabled Connect, and says it wasn't
/// found when you try.
enum LiveImageAvailability: Equatable {
    case supported(port: UInt16)
    case unsupported(String)

    /// The whole Seestar family: one ZWO app drives them all, and the image
    /// socket is the same on each. The S50 Pro's telephoto camera is proven
    /// (firmware 9.31); the S50 and S30 Pro appear in SeeStar-Py's examples
    /// on the same port, and the S30 is the same design. A wide-camera
    /// preset reads the wide camera's own stream, which SeeStar-Py documents
    /// on 4804 but hasn't been tried here. Anything else has no connection
    /// to offer yet, and says so rather than failing.
    static func of(_ rig: Rig) -> LiveImageAvailability {
        let name = rig.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return .unsupported("Select a telescope to check live image availability.")
        }
        let seestars = [Rig.seestarS50, .seestarS50Pro, .seestarS30, .seestarS30Pro].map(\.name)
        let wide = [Rig.seestarS50ProWide, .seestarS30Wide, .seestarS30ProWide].map(\.name)
        if wide.contains(name) { return .supported(port: 4804) }
        if seestars.contains(name) { return .supported(port: 4800) }
        return .unsupported("Live image connection isn't available for \(name). Your planned frame is still available.")
    }
}

/// What the scope sent, as it will be shown.
struct LiveFrame {
    enum Kind: String {
        case stack = "Live stack"
    }

    var image: CGImage
    var kind: Kind
    var receivedAt: Date
    var imageID: Int
}

/// A read-only connection to a Seestar's image socket. It never sends
/// anything but `test_connection` and `get_stacked_img`: no GoTo, no
/// capture control, no settings. The scope's own app stays in charge.
@MainActor
final class LiveTelescope: ObservableObject {
    enum Status: Equatable {
        case idle
        case searching
        case connecting
        /// Connected, but the scope has no stack to give yet.
        case waitingForStack
        case live
        /// Nothing new for a while, or the connection dropped; the last
        /// picture stays up, marked as old, while we keep trying.
        case paused
        case notFound
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var frame: LiveFrame?
    @Published private(set) var address: String?

    private var connection: NWConnection?
    private var reader = SeestarFrames.Reader()
    private var heartbeat: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var port: UInt16 = 4800
    /// A request is out and its frame hasn't finished arriving; don't ask
    /// again on top of it.
    private var awaitingFrame = false
    private var lastRequest = Date.distantPast
    private var ticks = 0
    private var isDecoding = false
    private var wanted = false

    /// How often to ask for the stack. The scope adds a sub-frame every ten
    /// seconds or so; asking faster only resends the same picture.
    private static let requestInterval: TimeInterval = 10
    private static let heartbeatInterval: Duration = .seconds(4)

    var isActive: Bool { wanted }

    func connect(port: UInt16) {
        disconnect()
        wanted = true
        self.port = port
        // Look afresh on every Connect: the scope may have a new address,
        // or be a different scope. Reconnects after a drop reuse it.
        address = nil
        status = .searching
        Task { await findAndOpen() }
    }

    func disconnect() {
        wanted = false
        heartbeat?.cancel(); heartbeat = nil
        reconnect?.cancel(); reconnect = nil
        connection?.cancel(); connection = nil
        reader = SeestarFrames.Reader()
        awaitingFrame = false
        frame = nil
        status = .idle
    }

    // MARK: - Finding the scope

    private func findAndOpen() async {
        let host: String?
        if let address {
            host = address
        } else {
            host = await Task.detached { SeestarDiscovery.find() }.value
        }
        guard wanted else { return }
        guard let host else {
            status = .notFound
            scheduleReconnect()
            return
        }
        address = host
        open(host)
    }

    private func open(_ host: String) {
        status = frame == nil ? .connecting : .paused
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.connectionTimeout = 8
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
                                      using: NWParameters(tls: nil, tcp: tcp))
        self.connection = connection
        reader = SeestarFrames.Reader()
        awaitingFrame = false
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state, of: connection) }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private func handle(_ state: NWConnection.State, of connection: NWConnection) {
        guard connection === self.connection, wanted else { return }
        switch state {
        case .ready:
            if frame == nil { status = .waitingForStack }
            receive(on: connection)
            requestStack()
            startHeartbeat()
        case .waiting(let error), .failed(let error):
            dropped(because: error)
        default:
            break
        }
    }

    private func dropped(because error: NWError?) {
        connection?.cancel(); connection = nil
        heartbeat?.cancel(); heartbeat = nil
        guard wanted else { return }
        if frame != nil {
            status = .paused
        } else if case .posix(let code) = error, code == .ECONNREFUSED || code == .EHOSTUNREACH || code == .ETIMEDOUT {
            // The address we had doesn't answer; look for the scope again
            // next time in case it's moved.
            address = nil
            status = .notFound
        } else if error == nil {
            // The scope closed an idle connection: it's there, just not
            // stacking.
            status = .waitingForStack
        } else {
            address = nil
            status = .notFound
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled, self.wanted else { return }
            if self.status == .notFound { self.status = .searching }
            await self.findAndOpen()
        }
    }

    // MARK: - Talking to it

    private func send(_ method: String, on connection: NWConnection) {
        let message = "{\"id\":2,\"method\":\"\(method)\"}\r\n"
        connection.send(content: Data(message.utf8), completion: .contentProcessed { _ in })
    }

    private func requestStack() {
        guard let connection, !awaitingFrame else { return }
        awaitingFrame = true
        lastRequest = Date()
        send("get_stacked_img", on: connection)
    }

    /// `test_connection` every four seconds keeps the socket open, as the
    /// scope's own app does; the stack is asked for every ten.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard let self, !Task.isCancelled, let connection = self.connection else { return }
                // A request that got no image back (the scope had nothing
                // yet) shouldn't block the next one forever.
                if self.awaitingFrame, Date().timeIntervalSince(self.lastRequest) > 45 {
                    self.awaitingFrame = false
                }
                if Date().timeIntervalSince(self.lastRequest) >= Self.requestInterval {
                    self.requestStack()
                } else {
                    self.send("test_connection", on: connection)
                }
                self.markStaleIfQuiet()
            }
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, connection === self.connection else { return }
                if let data, !data.isEmpty {
                    self.reader.append(data)
                    while let frame = self.reader.nextFrame() { self.handle(frame) }
                }
                if isComplete || error != nil {
                    self.dropped(because: error)
                } else {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func handle(_ frame: SeestarFrames.Frame) {
        let header = frame.header
        guard header.type != .ack, header.length > 0 else {
            // "Nothing to send": no stack exists yet.
            awaitingFrame = false
            if self.frame == nil { status = .waitingForStack }
            return
        }
        guard header.isStack else { return }
        awaitingFrame = false
        if let current = self.frame, current.imageID == header.imageID, header.imageID != 0 {
            if status != .live { status = .live }
            return
        }
        guard !isDecoding else { return }
        isDecoding = true
        Task {
            let image = await Task.detached(priority: .userInitiated) { try? SeestarFrames.image(from: frame) }.value
            isDecoding = false
            guard wanted, let image else { return }
            self.frame = LiveFrame(image: image, kind: .stack, receivedAt: Date(), imageID: header.imageID)
            status = .live
        }
    }

    /// A picture older than a few requests' worth is shown as paused.
    private func markStaleIfQuiet() {
        guard status == .live, let frame else { return }
        if Date().timeIntervalSince(frame.receivedAt) > Self.requestInterval * 6 {
            status = .paused
        }
    }
}

/// Finds a Seestar: by its `seestar.local` name first, then the way ZWO's
/// own app does, a `scan_iscope` broadcast on UDP 4720 that every Seestar on
/// the network answers, and failing both the scope's own hotspot address.
///
/// The name comes first because macOS looks it up itself. Hearing the
/// broadcast's replies means the app receiving on a socket, and with the
/// firewall on that asks "accept incoming network connections?" — the kind
/// of question a beginner says no to.
enum SeestarDiscovery {
    static func find(timeout: TimeInterval = 2.5) -> String? {
        if let named = resolve("seestar.local", within: 2) { return named }
        if let answer = broadcast(timeout: timeout) { return answer }
        // Connected straight to the scope's own Wi-Fi.
        if canConnect(to: "10.0.0.1", port: 4800) { return "10.0.0.1" }
        return nil
    }

    private static func broadcast(timeout: TimeInterval) -> String? {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return nil }
        defer { close(sock) }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var wait = timeval(tv_sec: 0, tv_usec: 200_000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))

        let probe = Array("{\"id\":1,\"method\":\"scan_iscope\",\"params\":\"\"}\n\n".utf8)
        let targets = broadcastAddresses() + ["255.255.255.255"]
        let deadline = Date().addingTimeInterval(timeout)
        var nextProbe = Date.distantPast
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            if Date() >= nextProbe {
                for target in targets {
                    var address = sockaddr_in()
                    address.sin_family = sa_family_t(AF_INET)
                    address.sin_port = in_port_t(4720).bigEndian
                    inet_pton(AF_INET, target, &address.sin_addr)
                    _ = withUnsafePointer(to: &address) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(sock, probe, probe.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                nextProbe = Date().addingTimeInterval(0.5)
            }
            var from = sockaddr_in()
            var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(sock, &buffer, buffer.count, 0, $0, &fromLength)
                }
            }
            guard count > 0 else { continue }
            let reply = Data(buffer[0..<count])
            guard let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
                  let result = json["result"] as? [String: Any], result["sn"] != nil else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &from.sin_addr, &text, socklen_t(INET_ADDRSTRLEN))
            return String(cString: text)
        }
        return nil
    }

    /// The directed broadcast address of each active IPv4 interface.
    private static func broadcastAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var addresses: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_BROADCAST != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                  let broadcast = entry.pointee.ifa_dstaddr else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            broadcast.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                var inAddress = pointer.pointee.sin_addr
                inet_ntop(AF_INET, &inAddress, &text, socklen_t(INET_ADDRSTRLEN))
            }
            addresses.append(String(cString: text))
        }
        return addresses
    }

    /// An IPv4 address for a Bonjour name, or nil if nothing answers in time.
    /// getaddrinfo can sit for several seconds on a missing .local name, so
    /// it runs on its own and is abandoned when the wait is up.
    private static func resolve(_ name: String, within seconds: TimeInterval) -> String? {
        final class Box: @unchecked Sendable { var address: String? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var result: UnsafeMutablePointer<addrinfo>?
            if getaddrinfo(name, nil, &hints, &result) == 0, let result {
                defer { freeaddrinfo(result) }
                if let address = result.pointee.ai_addr {
                    var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                        var inAddress = pointer.pointee.sin_addr
                        inet_ntop(AF_INET, &inAddress, &text, socklen_t(INET_ADDRSTRLEN))
                    }
                    box.address = String(cString: text)
                }
            }
            done.signal()
        }
        return done.wait(timeout: .now() + seconds) == .success ? box.address : nil
    }

    private static func canConnect(to host: String, port: UInt16) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var wait = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, host, &address.sin_addr)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}

import CryptoKit
import Foundation

/// Sync between the Mac app and the web app (skybother.com), with no
/// accounts: a sync code. The web app does the same in web/src/lib/sync.js —
/// keep the two in step.
///
/// The code is 128 random bits, shown as 26 Crockford base32 characters in
/// groups. From it come two values that can't be worked back to the code:
///   id  = hex(SHA-256("skybother-sync-id:" + code bytes))  — where it's stored
///   key = SHA-256("skybother-sync-key:" + code bytes)       — AES-256-GCM
/// The server (web/worker) keeps one encrypted blob per id and never sees
/// what's in it. The blob is base64(12-byte nonce + ciphertext + tag) — what
/// CryptoKit calls `combined`, and what WebCrypto's AES-GCM produces — of
///   { "v": 1, "sections": { name: { "modifiedAt": ms, "value": … } } }
/// Each section merges on its own, newest change winning, so a plan edited on
/// the phone and a rig changed here don't overwrite each other.
enum SyncCode {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return format(encode(bytes))
    }

    /// Upper case, no spaces or dashes, and the letters people mistake for digits.
    static func normalize(_ text: String) -> String {
        text.uppercased()
            .filter { !$0.isWhitespace && $0 != "-" }
            .map { $0 == "I" || $0 == "L" ? "1" : $0 == "O" ? "0" : $0 }
            .reduce(into: "") { $0.append($1) }
    }

    static func format(_ code: String) -> String {
        let clean = Array(normalize(code))
        return stride(from: 0, to: clean.count, by: 4)
            .map { String(clean[$0..<min($0 + 4, clean.count)]) }
            .joined(separator: "-")
    }

    static func isValid(_ text: String) -> Bool { (try? decode(text)) != nil }

    private static func encode(_ bytes: [UInt8]) -> String {
        var bits = 0, value = 0, out = ""
        for byte in bytes {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                out.append(alphabet[(value >> (bits - 5)) & 31])
                bits -= 5
            }
            value &= (1 << bits) - 1
        }
        if bits > 0 { out.append(alphabet[(value << (5 - bits)) & 31]) }
        return out
    }

    static func decode(_ text: String) throws -> [UInt8] {
        let clean = normalize(text)
        guard clean.count == 26 else { throw SyncError.badCode }
        var bits = 0, value = 0
        var out: [UInt8] = []
        for character in clean {
            guard let digit = alphabet.firstIndex(of: character) else { throw SyncError.badCode }
            value = (value << 5) | digit
            bits += 5
            if bits >= 8 {
                out.append(UInt8((value >> (bits - 8)) & 255))
                bits -= 8
            }
            value &= (1 << bits) - 1
        }
        return Array(out.prefix(16))
    }

    static func derive(_ code: String) throws -> (id: String, key: SymmetricKey) {
        let secret = try decode(code)
        let id = SHA256.hash(data: Data("skybother-sync-id:".utf8) + secret)
            .map { String(format: "%02x", $0) }.joined()
        let key = SymmetricKey(data: SHA256.hash(data: Data("skybother-sync-key:".utf8) + secret))
        return (id, key)
    }
}

enum SyncError: LocalizedError {
    case badCode, wrongCode, nothingStored, http(Int), collided

    var errorDescription: String? {
        switch self {
        case .badCode: return "A sync code is 26 letters and digits."
        case .wrongCode: return "This sync code doesn’t match what’s stored. Check the code."
        case .nothingStored: return "Nothing is synced with this code yet. Turn sync on from the device that has your settings."
        case .http(let status): return "Sync failed (HTTP \(status))."
        case .collided: return "Sync kept colliding with another device. It will try again."
        }
    }
}

/// Any JSON value, so a section's value can travel as the web app wrote it.
enum JSONValue: Codable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

struct SyncDocument: Codable, Equatable {
    struct Section: Codable, Equatable {
        var modifiedAt: Double
        var value: JSONValue
    }
    var v: Int = 1
    var sections: [String: Section] = [:]

    static let sectionNames = ["site", "rig", "preferences", "customTargets", "savedSites", "savedRigs", "sessionPlans"]

    /// The newest of each section from two documents.
    static func merge(_ a: SyncDocument?, _ b: SyncDocument?) -> SyncDocument {
        var merged = SyncDocument()
        for name in sectionNames {
            let x = a?.sections[name], y = b?.sections[name]
            if let x, let y { merged.sections[name] = y.modifiedAt > x.modifiedAt ? y : x }
            else if let chosen = x ?? y { merged.sections[name] = chosen }
        }
        return merged
    }

    // MARK: Settings ↔ document

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func json<T: Encodable>(_ value: T) -> JSONValue? {
        guard let data = try? encoder().encode(value) else { return nil }
        return try? decoder().decode(JSONValue.self, from: data)
    }

    private static func typed<T: Decodable>(_ value: JSONValue, as type: T.Type) -> T? {
        guard let data = try? encoder().encode(value) else { return nil }
        return try? decoder().decode(type, from: data)
    }

    /// The same value as the app would write it, for comparing: the web app
    /// may have written the same thing with its keys in another order or a
    /// whole number without its ".0".
    private static func canonical<T: Codable>(_ value: JSONValue, as type: T.Type) -> Data? {
        typed(value, as: type).flatMap { try? encoder().encode($0) }
    }

    private static func values(of settings: StoredSettings) -> [String: (JSONValue?, (JSONValue) -> Data?)] {
        [
            "site": (json(settings.site), { canonical($0, as: Site.self) }),
            "rig": (json(settings.rig), { canonical($0, as: Rig.self) }),
            "preferences": (json(settings.preferences), { canonical($0, as: Preferences.self) }),
            "customTargets": (json(settings.customTargets), { canonical($0, as: [Target].self) }),
            "savedSites": (json(settings.savedSites), { canonical($0, as: [Site].self) }),
            "savedRigs": (json(settings.savedRigs), { canonical($0, as: [Rig].self) }),
            "sessionPlans": (json(settings.sessionPlans), { canonical($0, as: [String: [PlanSegment]].self) }),
        ]
    }

    /// This Mac's document, stamping any section that changed since
    /// `previous` (the last synced document) with now.
    static func from(_ settings: StoredSettings, previous: SyncDocument?) -> SyncDocument {
        let now = Date().timeIntervalSince1970 * 1000
        var document = SyncDocument()
        for (name, (value, canonicalize)) in values(of: settings) {
            guard let value else { continue }
            if let before = previous?.sections[name],
               let then = canonicalize(before.value), let current = canonicalize(value), then == current {
                document.sections[name] = before
            } else {
                document.sections[name] = Section(modifiedAt: now, value: value)
            }
        }
        return document
    }

    /// Settings with every section from the document that reads cleanly.
    func applied(to settings: StoredSettings) -> StoredSettings {
        var updated = settings
        for (name, section) in sections {
            switch name {
            case "site":
                if let site = Self.typed(section.value, as: Site.self) {
                    updated.site = site
                    updated.hasSetLocation = true
                }
            case "rig": if let rig = Self.typed(section.value, as: Rig.self) { updated.rig = rig }
            case "preferences": if let value = Self.typed(section.value, as: Preferences.self) { updated.preferences = value }
            case "customTargets": if let value = Self.typed(section.value, as: [Target].self) { updated.customTargets = value }
            case "savedSites": if let value = Self.typed(section.value, as: [Site].self) { updated.savedSites = value }
            case "savedRigs": if let value = Self.typed(section.value, as: [Rig].self) { updated.savedRigs = value }
            case "sessionPlans": if let value = Self.typed(section.value, as: [String: [PlanSegment]].self) { updated.sessionPlans = value }
            default: break
            }
        }
        return updated
    }
}

/// The network half: one round against the store.
struct SyncClient: Sendable {
    /// SKYBOTHER_SYNC_BASE in the environment points it elsewhere, e.g.
    /// `wrangler dev`'s http://localhost:8787/api/sync/, for testing.
    static let base = ProcessInfo.processInfo.environment["SKYBOTHER_SYNC_BASE"].flatMap(URL.init(string:))
        ?? URL(string: "https://skybother.com/api/sync/")!

    private struct Stored: Decodable { var version: Int; var data: String }
    private struct Put: Encodable { var baseVersion: Int; var data: String }

    /// Fetches what's stored, merges in `local`, writes back if that changed
    /// anything (retrying on a race), and returns the merged document.
    /// `local` nil means joining: take what's there.
    func syncOnce(code: String, local: SyncDocument?) async throws -> SyncDocument {
        let (id, key) = try SyncCode.derive(code)
        let url = Self.base.appendingPathComponent(id)
        let session = URLSession(configuration: .ephemeral)
        for _ in 0..<4 {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            var remote: SyncDocument?
            var version = 0
            if status == 200 {
                let stored = try JSONDecoder().decode(Stored.self, from: data)
                version = stored.version
                guard let sealed = Data(base64Encoded: stored.data),
                      let box = try? AES.GCM.SealedBox(combined: sealed),
                      let plain = try? AES.GCM.open(box, using: key),
                      let document = try? JSONDecoder().decode(SyncDocument.self, from: plain)
                else { throw SyncError.wrongCode }
                remote = document
            } else if status != 404 {
                throw SyncError.http(status)
            }
            if remote == nil && local == nil { throw SyncError.nothingStored }
            let merged = SyncDocument.merge(remote, local)
            if let remote, remote == merged { return merged }

            let plain = try JSONEncoder().encode(merged)
            guard let sealed = try AES.GCM.seal(plain, using: key).combined else { throw SyncError.http(0) }
            var put = URLRequest(url: url)
            put.httpMethod = "PUT"
            put.setValue("application/json", forHTTPHeaderField: "Content-Type")
            put.httpBody = try JSONEncoder().encode(Put(baseVersion: version, data: sealed.base64EncodedString()))
            let (_, putResponse) = try await session.data(for: put)
            let putStatus = (putResponse as? HTTPURLResponse)?.statusCode ?? 0
            if putStatus == 200 { return merged }
            if putStatus != 409 { throw SyncError.http(putStatus) }
        }
        throw SyncError.collided
    }

    /// Stops syncing this code everywhere: the stored copy is deleted.
    func forget(code: String) async throws {
        let (id, _) = try SyncCode.derive(code)
        var request = URLRequest(url: Self.base.appendingPathComponent(id))
        request.httpMethod = "DELETE"
        _ = try await URLSession(configuration: .ephemeral).data(for: request)
    }
}

import Foundation
import SkyBotherEngine

// The WebAssembly exports, used by web/src/engine. Strings cross as UTF-8 in
// linear memory: the page asks for a buffer (`sb_alloc`), writes into it, and
// gets back a pointer to the result whose length is read from `sb_result_length`.

nonisolated(unsafe) private var lastResult: [UInt8] = []

@_expose(wasm, "sb_alloc")
@_cdecl("sb_alloc")
public func sbAlloc(_ count: Int32) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer.allocate(byteCount: Int(count), alignment: 1)
}

@_expose(wasm, "sb_free")
@_cdecl("sb_free")
public func sbFree(_ pointer: UnsafeMutableRawPointer) {
    pointer.deallocate()
}

@_expose(wasm, "sb_result_length")
@_cdecl("sb_result_length")
public func sbResultLength() -> Int32 { Int32(lastResult.count) }

@_expose(wasm, "sb_load_catalog")
@_cdecl("sb_load_catalog")
public func sbLoadCatalog(_ pointer: UnsafeRawPointer, _ count: Int32) -> Int32 {
    Int32(EngineAPI.loadExtendedCatalog(Data(bytes: pointer, count: Int(count))))
}

@_expose(wasm, "sb_defaults")
@_cdecl("sb_defaults")
public func sbDefaults() -> UnsafeRawPointer {
    lastResult = Array(EngineAPI.defaults())
    return lastResult.withUnsafeBytes { UnsafeRawPointer($0.baseAddress!) }
}

@_expose(wasm, "sb_plan_nights")
@_cdecl("sb_plan_nights")
public func sbPlanNights(_ pointer: UnsafeRawPointer, _ count: Int32) -> UnsafeRawPointer {
    lastResult = Array(EngineAPI.planNights(Data(bytes: pointer, count: Int(count))))
    return lastResult.withUnsafeBytes { UnsafeRawPointer($0.baseAddress!) }
}

@_expose(wasm, "sb_target_detail")
@_cdecl("sb_target_detail")
public func sbTargetDetail(_ pointer: UnsafeRawPointer, _ count: Int32) -> UnsafeRawPointer {
    lastResult = Array(EngineAPI.targetDetail(Data(bytes: pointer, count: Int(count))))
    return lastResult.withUnsafeBytes { UnsafeRawPointer($0.baseAddress!) }
}

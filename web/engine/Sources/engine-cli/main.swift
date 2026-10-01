import Foundation
import SkyBotherEngine

// Native twin of engine.wasm for the parity check:
//   engine-cli <ExtendedCatalog.json> <request.json>  → night plans on stdout
let arguments = CommandLine.arguments
guard arguments.count == 3,
      let catalog = FileManager.default.contents(atPath: arguments[1]),
      let request = FileManager.default.contents(atPath: arguments[2]) else {
    FileHandle.standardError.write(Data("usage: engine-cli <ExtendedCatalog.json> <request.json>\n".utf8))
    exit(1)
}
_ = EngineAPI.loadExtendedCatalog(catalog)
FileHandle.standardOutput.write(EngineAPI.planNights(request))

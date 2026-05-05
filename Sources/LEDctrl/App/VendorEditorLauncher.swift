import AppKit
import Foundation
import SigmaProtocol

enum VendorEditorLauncher {
    static func openEditor() {
        let scriptURL = Paths.projectRoot.appendingPathComponent("scripts/open-editor-v399.sh")
        runScript(scriptURL)
    }

    static func openPlay() {
        let scriptURL = Paths.projectRoot.appendingPathComponent("scripts/open-sigma-play.sh")
        runScript(scriptURL)
    }

    private static func runScript(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("Script not found: \(url.path)")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [url.path]
        process.terminationHandler = { p in
            if p.terminationStatus != 0 {
                NSLog("Script exited with status \(p.terminationStatus): \(url.lastPathComponent)")
            }
        }
        do {
            try process.run()
        } catch {
            NSLog("Failed to run script: \(error)")
        }
    }
}

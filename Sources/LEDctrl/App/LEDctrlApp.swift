import AppKit
import Foundation
import SwiftUI

@main
struct LEDctrlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 920, minHeight: 620)
        }
        .commands {
            CommandMenu("Tools") {
                Button("Open Sigma Editor v3.99") {
                    VendorEditorLauncher.openEditor()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Open Sigma Play") {
                    VendorEditorLauncher.openPlay()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

import Foundation

public enum Paths {
    public static var projectRoot: URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        // Navigate from Sources/SigmaProtocol/Paths.swift to project root
        return sourceFile
            .deletingLastPathComponent() // SigmaProtocol
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // LEDctrl package root
    }

    public static var sigmaExtracted: URL {
        projectRoot.appendingPathComponent("sigma3000_extracted")
    }

    public static var fontDirectory: URL {
        sigmaExtracted.appendingPathComponent("FONT")
    }

    public static var editorNmg: URL {
        sigmaExtracted.appendingPathComponent("temp.Nmg")
    }

    public static var editorSequence: URL {
        sigmaExtracted.appendingPathComponent("SequentList.tmps")
    }

    public static var capturesDirectory: URL {
        projectRoot.appendingPathComponent("analysis/captures")
    }

    public static var buildDirectory: URL {
        projectRoot.appendingPathComponent("build")
    }

    public static var demoDirectory: URL {
        projectRoot.appendingPathComponent("demo")
    }

    public static var todaysHeadlines: URL {
        projectRoot.appendingPathComponent("todays-headlines.txt")
    }

    public static var messageLogFile: URL {
        URL(fileURLWithPath: "/tmp/ledctrl-message.log")
    }

    public static var commandFile: URL {
        URL(fileURLWithPath: "/tmp/ledctrl-command.json")
    }

    public static func captureDirectory(named: String) -> URL {
        capturesDirectory.appendingPathComponent(named)
    }
}

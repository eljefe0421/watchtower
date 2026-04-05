import Foundation

/// Simple file-based logger since print() doesn't go to terminal for GUI apps.
enum Log {
    private static let logPath = "/tmp/watchtower.log"
    private static let lock = NSLock()

    static func info(_ message: String) {
        write("[INFO] \(message)")
    }

    static func error(_ message: String) {
        write("[ERROR] \(message)")
    }

    private static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"
        lock.lock()
        defer { lock.unlock() }

        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: logPath, contents: data)
            }
        }
    }
}

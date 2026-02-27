import Foundation

enum TestSupport {
    static func makeTemporaryDirectory(prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func writeJSONLines(_ objects: [[String: Any]], to fileURL: URL) throws {
        let lines = try objects.map { object -> String in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Encoding", code: 1)
            }
            return line
        }
        let payload = lines.joined(separator: "\n") + "\n"
        try payload.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static func appendJSONLines(_ objects: [[String: Any]], to fileURL: URL) throws {
        let lines = try objects.map { object -> String in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "Encoding", code: 1)
            }
            return line
        }
        let payload = lines.joined(separator: "\n") + "\n"
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = payload.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try payload.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

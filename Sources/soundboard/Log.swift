import Foundation

enum Log {
    static var fileURL: URL?

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func info(_ msg: String) { write("INFO", msg) }
    static func error(_ msg: String) { write("ERROR", msg) }

    private static func write(_ level: String, _ msg: String) {
        let line = "\(fmt.string(from: Date())) [\(level)] \(msg)\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
        guard let url = fileURL else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.data(using: .utf8)!.write(to: url)
        }
    }
}

struct SoundboardError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

//
//  Log.swift
//  WorseFiles
//

import Foundation

enum Log {
    private static let lock = NSLock()
    private static var storage: [String] = []
    private static let limit = 300
    private static let fileQueue = DispatchQueue(label: "com.kestrel.worsefiles.logfile")

    private static let fileURL: URL? = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("WorseFiles.log")
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    static var tail: String {
        lines.joined(separator: "\n")
    }

    static var filePath: String? { fileURL?.path }

    static var exportText: String {
        fileQueue.sync {}
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return tail
    }

    static func exportFileURL() -> URL? {
        let text = exportText
        guard !text.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorseFiles-log.txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func info(_ message: String) {
        append("· " + message)
    }

    static func error(_ message: String) {
        append("! " + message)
    }

    private static func append(_ message: String) {
        lock.lock()
        let line = stamp.string(from: Date()) + " " + message
        storage.append(line)
        if storage.count > limit {
            storage.removeFirst(storage.count - limit)
        }
        lock.unlock()
        write(line + "\n")
#if DEBUG
        print(line)
#endif
    }

    private static func write(_ text: String) {
        guard let fileURL else { return }
        fileQueue.async {
            let manager = FileManager.default
            if !manager.fileExists(atPath: fileURL.path) {
                manager.createFile(atPath: fileURL.path, contents: nil)
            }
            if let attributes = try? manager.attributesOfItem(atPath: fileURL.path),
               let size = attributes[.size] as? NSNumber,
               size.uint64Value > 1_500_000 {
                try? manager.removeItem(at: fileURL)
                manager.createFile(atPath: fileURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            if let data = text.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
    }

    static func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
        if let fileURL {
            fileQueue.sync {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }
}

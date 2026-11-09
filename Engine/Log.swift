//
//  Log.swift
//  WorseFiles
//

import Foundation

enum Log {
    private static let lock = NSLock()
    private static var storage: [String] = []
    private static let limit = 300
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
#if DEBUG
        print(line)
#endif
    }

    static func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

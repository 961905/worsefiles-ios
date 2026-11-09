//
//  Paths.swift
//  WorseFiles
//

import Foundation

enum PathTool {
    // /var is a symlink to /private/var on iOS. Container queries work with
    // either, but a stable key keeps the handle cache honest.
    static func canonical(_ path: String) -> String {
        var result = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "/" }
        if result == "/var" {
            result = "/private/var"
        } else if result.hasPrefix("/var/") {
            result = "/private" + result
        }
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    static func parent(of path: String) -> String {
        let canonicalPath = canonical(path)
        guard canonicalPath != "/" else { return "/" }
        let parent = (canonicalPath as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }

    static func name(of path: String) -> String {
        let name = (canonical(path) as NSString).lastPathComponent
        return name.isEmpty ? "/" : name
    }

    static func isDescendant(_ path: String, of parent: String) -> Bool {
        let p = canonical(path)
        let root = canonical(parent)
        return p == root || p.hasPrefix(root + "/")
    }

    static func relative(_ path: String, to base: String) -> String {
        let p = canonical(path)
        let root = canonical(base)
        guard p.hasPrefix(root) else { return p }
        var rest = String(p.dropFirst(root.count))
        while rest.hasPrefix("/") { rest.removeFirst() }
        return rest
    }

    static func components(of path: String) -> [String] {
        canonical(path).split(separator: "/").map(String.init)
    }

    static func short(_ path: String, keep: Int = 3) -> String {
        let parts = components(of: path)
        guard parts.count > keep else { return "/" + parts.joined(separator: "/") }
        return "…/" + parts.suffix(keep).joined(separator: "/")
    }
}

enum Format {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }()

    static func bytes(_ count: Int64) -> String {
        if count < 0 { return "—" }
        return byteFormatter.string(fromByteCount: count)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

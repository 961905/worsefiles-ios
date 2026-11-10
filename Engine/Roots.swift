//
//  Roots.swift
//  WorseFiles
//

import Foundation

struct RootSpec: Identifiable, Hashable {
    enum Access: String {
        // Enumerate the parent directory with a sandbox extension.
        case list
        // The parent cannot be listed, so brute force child paths by inode.
        case scan
    }

    let path: String
    let title: String
    let subtitle: String
    let symbol: String
    let access: Access
    let requiresIOS27: Bool

    var id: String { path }
}

enum Roots {
    static let dataApplication = RootSpec(
        path: "/private/var/mobile/Containers/Data/Application",
        title: "应用数据",
        subtitle: "每个 App 的 Documents、Library 与 tmp",
        symbol: "square.stack.3d.up.fill",
        access: .scan,
        requiresIOS27: false
    )

    static var majorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    static var escapeSupported: Bool { majorVersion >= 26 }

    // The documented support window. Outside it the app still tries, but
    // the UI says so instead of claiming support.
    static var testedWindow: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        switch version.majorVersion {
        case 26:
            return version.minorVersion < 7 || (version.minorVersion == 7 && version.patchVersion <= 2)
        case 27:
            return version.minorVersion <= 2
        default:
            return false
        }
    }

    static var all: [RootSpec] {
        [dataApplication]
    }

    static var containerParents: [String] {
        all.map { PathTool.canonical($0.path) }
    }

    static func spec(for path: String) -> RootSpec? {
        let key = PathTool.canonical(path)
        return all.first { PathTool.canonical($0.path) == key }
    }

    static func isContainerParent(_ path: String) -> Bool {
        spec(for: path) != nil
    }

    static var ownSandbox: String {
        PathTool.canonical(NSHomeDirectory())
    }
}

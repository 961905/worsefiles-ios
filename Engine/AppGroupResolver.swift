//
//  AppGroupResolver.swift
//  WorseFiles
//
//  The App Group is part of the code signature, not a user preference. Read
//  the one the signer actually granted, then pick a group whose container the
//  process can open. No field to fill in.
//

import Foundation

struct AppGroupSnapshot {
    var groups: [String]
    var accessible: [String]
    var active: String

    var hasAccessible: Bool { !accessible.isEmpty }
}

enum AppGroupResolver {
    private static let lock = NSLock()
    private static var cached: AppGroupSnapshot?

    static func snapshot(refresh: Bool = false) -> AppGroupSnapshot {
        lock.lock()
        defer { lock.unlock() }

        if !refresh, let cached { return cached }

        let bundleGroup: String? = {
            guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { return nil }
            return "group." + bundleID
        }()

        var candidates = (WFCurrentAppGroups() ?? []).filter { $0.hasPrefix("group.") }
        var extras: [String] = [AppSettings.defaultGroupID]
        if let bundleGroup { extras.insert(bundleGroup, at: 0) }
        for extra in extras {
            if !candidates.contains(extra),
               FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: extra) != nil {
                candidates.append(extra)
            }
        }

        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0).inserted }

        let accessible = candidates.filter {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }

        var active: String
        if let bundleGroup, accessible.contains(bundleGroup) {
            active = bundleGroup
        } else if accessible.contains(AppSettings.defaultGroupID) {
            active = AppSettings.defaultGroupID
        } else if let first = accessible.first {
            active = first
        } else if let first = candidates.first {
            active = first
        } else {
            active = AppSettings.defaultGroupID
        }

        let snapshot = AppGroupSnapshot(groups: candidates,
                                        accessible: accessible,
                                        active: active)
        cached = snapshot
        return snapshot
    }

    static func refresh() -> AppGroupSnapshot {
        snapshot(refresh: true)
    }

    static var active: String { snapshot().active }
    static var hasAccessibleGroup: Bool { snapshot().hasAccessible }
}

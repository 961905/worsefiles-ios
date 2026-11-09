//
//  AppSettings.swift
//  WorseFiles
//

import Foundation

enum SettingsKey {
    static let appGroupID = "appGroupID"
    static let showHidden = "showHidden"
    static let foldersFirst = "foldersFirst"
    static let sortKey = "sortKey"
    static let sortAscending = "sortAscending"
    static let maxInode = "maxInodeOverride"
}

enum AppSettings {
    static let defaultGroupID = "group.com.kestrel.worsefiles"

    static var appGroupID: String {
        get {
            // Absent means "use the nib default"; an explicitly cleared field
            // means no group, and the runtime should say so instead of
            // silently falling back to an identifier the user removed.
            guard let stored = UserDefaults.standard.object(forKey: SettingsKey.appGroupID) as? String else {
                return defaultGroupID
            }
            return stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                      forKey: SettingsKey.appGroupID)
        }
    }

    static var showHidden: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.showHidden) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.showHidden) }
    }

    static var foldersFirst: Bool {
        get {
            if UserDefaults.standard.object(forKey: SettingsKey.foldersFirst) == nil { return true }
            return UserDefaults.standard.bool(forKey: SettingsKey.foldersFirst)
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.foldersFirst) }
    }

    static var sortKey: SortKey {
        get {
            let raw = UserDefaults.standard.string(forKey: SettingsKey.sortKey) ?? ""
            return SortKey(rawValue: raw) ?? .name
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKey.sortKey) }
    }

    static var sortAscending: Bool {
        get {
            if UserDefaults.standard.object(forKey: SettingsKey.sortAscending) == nil { return true }
            return UserDefaults.standard.bool(forKey: SettingsKey.sortAscending)
        }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.sortAscending) }
    }

    // Blank means "use the inode of a freshly created file as the upper bound",
    // the same trick worse_query's own demo uses.
    static var maxInodeOverride: UInt64? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: SettingsKey.maxInode),
                  let value = UInt64(raw), value > 0 else { return nil }
            return value
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(String(value), forKey: SettingsKey.maxInode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.maxInode)
            }
        }
    }

    static var sortOrder: SortOrder {
        SortOrder(key: sortKey, ascending: sortAscending, foldersFirst: foldersFirst)
    }

    static func save(_ order: SortOrder) {
        sortKey = order.key
        sortAscending = order.ascending
        foldersFirst = order.foldersFirst
    }
}

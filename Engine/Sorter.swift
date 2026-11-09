//
//  Sorter.swift
//  WorseFiles
//

import Foundation

enum Sorter {
    static func sorted(_ items: [FSItem], order: SortOrder) -> [FSItem] {
        items.sorted { first, second in
            if order.foldersFirst && first.isDirectory != second.isDirectory {
                return first.isDirectory
            }

            let result = compare(first, second, key: order.key)
            if result == .orderedSame {
                return first.displayName.localizedStandardCompare(second.displayName) == .orderedAscending
            }
            return order.ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func compare(_ first: FSItem, _ second: FSItem, key: SortKey) -> ComparisonResult {
        switch key {
        case .name:
            return first.displayName.localizedStandardCompare(second.displayName)
        case .modified:
            let a = first.modified?.timeIntervalSince1970 ?? 0
            let b = second.modified?.timeIntervalSince1970 ?? 0
            return compareNumbers(a, b)
        case .size:
            return compareNumbers(Double(first.size), Double(second.size))
        case .kind:
            let a = (first.name as NSString).pathExtension.lowercased()
            let b = (second.name as NSString).pathExtension.lowercased()
            return a.localizedStandardCompare(b)
        }
    }

    private static func compareNumbers(_ a: Double, _ b: Double) -> ComparisonResult {
        if a < b { return .orderedAscending }
        if a > b { return .orderedDescending }
        return .orderedSame
    }
}

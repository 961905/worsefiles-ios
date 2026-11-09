//
//  ContainerMetadata.swift
//  WorseFiles
//

import Foundation

struct ContainerFacts {
    var identifier: String?
    var displayName: String?
    var contentClass: Int?
}

enum ContainerMetadata {
    static let metadataName = ".com.apple.mobile_container_manager.metadata.plist"
    static let identifierXattr = "com.apple.containermanager.identifier"

    static func facts(atPath path: String) -> ContainerFacts? {
        var facts = ContainerFacts()
        facts.identifier = extendedIdentifier(path) ?? plistIdentifier(path)
        if let metadata = plist(path) {
            facts.displayName = displayName(in: metadata)
            facts.contentClass = metadata["MCMMetadataContentClass"] as? Int
        }
        if facts.identifier == nil && facts.displayName == nil {
            return nil
        }
        return facts
    }

    static func identifier(atPath path: String) -> String? {
        extendedIdentifier(path) ?? plistIdentifier(path)
    }

    private static func extendedIdentifier(_ path: String) -> String? {
        let name = identifierXattr
        let needed = getxattr(path, name, nil, 0, 0, 0)
        guard needed > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(needed) + 1)
        let read = getxattr(path, name, &buffer, Int(needed), 0, 0)
        guard read > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func plist(_ path: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: path).appendingPathComponent(metadataName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private static func plistIdentifier(_ path: String) -> String? {
        guard let metadata = plist(path) else { return nil }
        if let identifier = metadata["MCMMetadataIdentifier"] as? String, !identifier.isEmpty {
            return identifier
        }
        return nil
    }

    private static func displayName(in metadata: [String: Any]) -> String? {
        if let name = metadata["MCMMetadataDisplayName"] as? String, !name.isEmpty {
            return name
        }
        if let info = metadata["MCMMetadataInfoPlist"] as? [String: Any] {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = info[key] as? String, !name.isEmpty { return name }
            }
        }
        if let infoData = metadata["MCMMetadataInfoPlist"] as? Data,
           let info = (try? PropertyListSerialization.propertyList(from: infoData, options: [], format: nil)) as? [String: Any] {
            for key in ["CFBundleDisplayName", "CFBundleName"] {
                if let name = info[key] as? String, !name.isEmpty { return name }
            }
        }
        return nil
    }
}

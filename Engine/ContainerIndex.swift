//
//  ContainerIndex.swift
//  WorseFiles
//
//  One inode walk feeds every container root. The shared watermark also
//  makes foreground refreshes cheap: only inodes allocated since the last
//  scan are walked, which is where a newly installed app's container lives.
//

import Foundation
import Combine

extension Notification.Name {
    static let worseFilesIndexUpdated = Notification.Name("WorseFilesIndexUpdated")
}

struct ContainerScanSummary {
    let added: Int
    let total: Int
    let full: Bool
}

enum ContainerIndexError: LocalizedError {
    case noBaseline
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noBaseline:
            return "无法确定 inode 上限。请在设置里填写一个上限，或先让 App 创建临时文件。"
        case .cancelled:
            return "扫描已停止。"
        }
    }
}

// Fast path for "应用数据": scan the Application parent for one bundle id and
// stop everything at the first hit. Falls back to nil when the full index
// scan must run instead.
enum TargetedScan {
    static let dataApplicationNeedle = "com.tencent.tmgp.pubgmhd"

    @discardableResult
    static func findDataApplication(needle: String = dataApplicationNeedle) async -> [String] {
        let root = PathTool.canonical(Roots.dataApplication.path)
        let baseline = AppSettings.maxInodeOverride ?? await Task.detached(priority: .userInitiated) {
            ContainerScanner.shared.baselineInode()
        }.value
        guard baseline > 0 else { return [] }

        // Already known? Report it immediately and skip the walk.
        let cached = Catalog.shared.items(for: root).map { $0.path }
        let known = cached.filter { $0.contains(needle) }
        if let first = known.first { return [first] }

        let token = CancelToken()
        let start: UInt64 = 1
        let end = baseline
        return await Task.detached(priority: .userInitiated) {
            ContainerScanner.shared.scanFirstMatch(root: root,
                                                   needle: needle,
                                                   start: start,
                                                   end: end,
                                                   token: token)
        }.value
    }
}

@MainActor
final class ContainerIndex: ObservableObject {
    static let shared = ContainerIndex()
    static let indexVersion = 2

    @Published private(set) var progress: ScanStatus?
    @Published private(set) var lastCompleted: Date?
    @Published private(set) var lastAdded = 0

    private var running: Task<ContainerScanSummary, Error>?
    private var token: CancelToken?

    var isScanning: Bool { running != nil }

    var shouldRefreshOnOpen: Bool {
        guard let lastCompleted else { return true }
        return Date().timeIntervalSince(lastCompleted) > 30
    }

    @discardableResult
    func ensureScanned(full requestFull: Bool) async throws -> ContainerScanSummary {
        if let running {
            return try await running.value
        }

        let catalog = Catalog.shared
        let roots = Roots.all.map { PathTool.canonical($0.path) }
        let needsFull = requestFull
            || !catalog.hasSharedScan
            || catalog.scanVersion != Self.indexVersion
            || roots.contains(where: { catalog.scanRecord(for: $0) == nil })

        let task = Task { try await self.performScan(full: needsFull, roots: roots) }
        running = task
        do {
            let summary = try await task.value
            running = nil
            return summary
        } catch {
            running = nil
            throw error
        }
    }

    func cancel() {
        token?.cancel()
        token = nil
        progress = nil
    }

    private func performScan(full: Bool, roots: [String]) async throws -> ContainerScanSummary {
        let catalog = Catalog.shared
        let baseline = AppSettings.maxInodeOverride ?? ContainerScanner.shared.baselineInode()
        guard baseline > 0 else { throw ContainerIndexError.noBaseline }

        let watermark = catalog.sharedWatermark
        let replace = full || watermark == 0
        let end = baseline
        if !replace && watermark >= baseline {
            lastCompleted = Date()
            lastAdded = 0
            return ContainerScanSummary(added: 0,
                                        total: roots.reduce(0) { $0 + catalog.count(for: $1) },
                                        full: false)
        }
        let start: UInt64 = replace ? 1 : watermark + 1

        let scanToken = CancelToken()
        token = scanToken
        progress = ScanStatus(done: 0, total: end - start + 1, started: Date())
        Log.info("index scan \(start)…\(end) full=\(replace)")

        let found = await Task.detached(priority: .userInitiated) {
            ContainerScanner.shared.scan(roots: roots,
                                         start: start,
                                         end: end,
                                         token: scanToken) { done in
                Task { @MainActor [weak self] in
                    guard let self, self.token === scanToken, var status = self.progress else { return }
                    let processed = done >= start ? done - start + 1 : 0
                    status.done = min(status.total, processed)
                    self.progress = status
                }
            }
        }.value

        guard token === scanToken else { throw ContainerIndexError.cancelled }
        token = nil
        progress = nil
        if scanToken.isCancelled { throw ContainerIndexError.cancelled }

        let added = catalog.mergeRootScan(results: found,
                                          roots: roots,
                                          watermark: end,
                                          replace: replace,
                                          version: Self.indexVersion)
        let total = roots.reduce(0) { $0 + catalog.count(for: $1) }
        lastCompleted = Date()
        lastAdded = added
        if added > 0 || replace {
            let counts = roots.map { "\(PathTool.name(of: $0)):\(catalog.count(for: $0))" }
                .joined(separator: " ")
            Log.info("index scan done: +\(added), total=\(total) [\(counts)]")
        }
        NotificationCenter.default.post(name: .worseFilesIndexUpdated, object: nil)

        return ContainerScanSummary(added: added, total: total, full: replace)
    }
}

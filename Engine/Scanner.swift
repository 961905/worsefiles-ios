//
//  Scanner.swift
//  WorseFiles
//
//  Container paths whose parent cannot be listed are found the same way
//  pathleak does it: walk inode numbers and ask fsgetpath what lives there.
//  The walk is split into chunks and run on several cores.
//

import Foundation

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

final class ContainerScanner: @unchecked Sendable {
    static let shared = ContainerScanner()

    private let chunkSize: UInt64 = 40_000
    private let targetedChunkSize: UInt64 = 200_000

    // A file just created in our own tmp gives the current high-water inode
    // for this volume. That is the upper bound worth walking.
    func baselineInode() -> UInt64 {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(".worsefiles-baseline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try Data("worse".utf8).write(to: url, options: .atomic)
        } catch {
            Log.error("baseline write failed: \(error.localizedDescription)")
            return 0
        }
        var info = stat()
        guard stat(url.path, &info) == 0 else { return 0 }
        return UInt64(info.st_ino)
    }

    // One inode walk for all container parents. The C side matches each path
    // against every prefix, so six roots do not mean six full scans.
    func scan(roots: [String],
              start: UInt64,
              end: UInt64,
              token: CancelToken,
              progress: @escaping (UInt64) -> Void) -> [String: [String]] {
        guard !roots.isEmpty, end >= 1, end >= start else { return [:] }
        let span = end - start + 1
        let chunks = max(1, Int((span + chunkSize - 1) / chunkSize))
        var results: [String: Set<String>] = [:]
        let lock = NSLock()
        var reported: UInt64 = 0

        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            if token.isCancelled { return }
            let offset = UInt64(index) * chunkSize
            let low = start + offset
            if low > end { return }
            let high = min(end, low + chunkSize - 1)

            let found = pathleak_roots(roots, low, high) ?? [:]
            if token.isCancelled { return }

            var reportValue: UInt64?
            lock.lock()
            for (root, paths) in found {
                results[root, default: []].formUnion(paths)
            }
            // Chunks finish out of order. Never subtract a smaller chunk
            // index from a larger reported one: UInt64 underflow traps.
            let shouldReport = high == end || (high > reported && high - reported >= 600_000)
            if shouldReport {
                reported = max(reported, high)
                reportValue = reported
            }
            lock.unlock()

            if let reportValue {
                progress(reportValue)
            }
        }

        return results.mapValues { Array($0) }
    }

    // Scan only for one child name under one parent. The first chunk that
    // produces the target container cancels all remaining chunks and returns
    // only that container path. Uses the untouched pathleak_roots walk; the
    // bundle-id check happens per chunk on the few paths it returns.
    func scanFirstMatch(root: String,
                        needle: String,
                        start: UInt64,
                        end: UInt64,
                        token: CancelToken,
                        progress: @escaping (Int, Int) -> Void) -> [String] {
        guard end >= 1, end >= start else { return [] }
        let span = end - start + 1
        let chunks = max(1, Int((span + targetedChunkSize - 1) / targetedChunkSize))
        var hit: [String] = []
        let lock = NSLock()
        var doneChunks = 0

        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            lock.lock()
            let alreadyHit = !hit.isEmpty
            lock.unlock()
            if alreadyHit || token.isCancelled { return }

            let low = start + UInt64(index) * targetedChunkSize
            if low > end { return }
            let high = min(end, low + targetedChunkSize - 1)

            let found = pathleak_roots([root], low, high)[root] ?? []

            var target: String?
            for path in found {
                // The container bundle id lives in a directory xattr; one
                // getxattr call, no file open. Plist MCMMetadataIdentifier is
                // the fallback.
                let xattrName = "com.apple.containermanager.identifier"
                let needed = getxattr(path, xattrName, nil, 0, 0, 0)
                var bundleId: String?
                if needed > 0 {
                    var buffer = [CChar](repeating: 0, count: Int(needed) + 1)
                    let read = getxattr(path, xattrName, &buffer, Int(needed), 0, 0)
                    if read > 0 { bundleId = String(cString: buffer) }
                }
                if bundleId == nil,
                   let metadata = NSDictionary(contentsOfFile: path + "/.com.apple.mobile_container_manager.metadata.plist"),
                   let identifier = metadata["MCMMetadataIdentifier"] as? String {
                    bundleId = identifier
                }
                if bundleId?.contains(needle) == true || path.contains(needle) {
                    target = path
                    break
                }
            }

            lock.lock()
            doneChunks += 1
            let done = doneChunks
            if let target, hit.isEmpty && !token.isCancelled {
                hit = [target]
                token.cancel()
            }
            lock.unlock()
            progress(done, chunks)
            guard target != nil else { return }
        }

        return hit
    }
}

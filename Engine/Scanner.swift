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

    func scan(root: String,
              start: UInt64,
              end: UInt64,
              token: CancelToken,
              progress: @escaping (UInt64) -> Void) -> [String] {
        guard end >= 1, end >= start else { return [] }
        let span = end - start + 1
        let chunks = max(1, Int((span + chunkSize - 1) / chunkSize))
        var results = Set<String>()
        let lock = NSLock()
        var reported: UInt64 = 0

        DispatchQueue.concurrentPerform(iterations: chunks) { index in
            if token.isCancelled { return }
            let offset = UInt64(index) * chunkSize
            let low = start + offset
            if low > end { return }
            let high = min(end, low + chunkSize - 1)

            let found = pathleak_range(root, low, high) ?? []
            if token.isCancelled { return }

            // Chunks finish out of order. Never subtract a smaller chunk
            // index from a larger reported one: UInt64 underflow traps.
            var reportValue: UInt64?
            lock.lock()
            results.formUnion(found)
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

        return Array(results)
    }
}

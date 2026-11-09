//
//  BrowserModel.swift
//  WorseFiles
//

import Foundation
import SwiftUI

enum LoadState: Equatable {
    case idle
    case loading
    case refreshing
    case loaded
    case failed(String)

    var isLoading: Bool { self == .loading || self == .refreshing }
}

struct Crumb: Identifiable, Hashable {
    let name: String
    let path: String
    var id: String { path }
}

struct LabelProgress: Equatable {
    var done: Int
    var total: Int
}

struct TextPrompt: Identifiable {
    enum Kind {
        case newFolder
        case rename(FSItem)
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String?
    let initial: String
    let actionTitle: String
}

enum BrowserSheet {
    case info(FSItem)
    case preview(URL)
    case text(FSItem)
    case share([URL])
    case prompt(TextPrompt)
    case importer
}

struct SheetPayload: Identifiable {
    let id = UUID()
    let content: BrowserSheet
}

@MainActor
final class BrowserModel: ObservableObject {
    @Published private(set) var path: String
    @Published private(set) var title: String
    @Published private(set) var items: [FSItem] = []
    @Published private(set) var state: LoadState = .idle
    @Published var query = ""
    @Published var errorMessage: String?
    @Published var selectionMode = false
    @Published var selected: Set<String> = []
    @Published var scanStatus: ScanStatus?
    @Published var labelProgress: LabelProgress?
    @Published var sheet: SheetPayload?
    @Published var busy: String?
    @Published var sortOrder: SortOrder
    @Published var showHidden: Bool
    @Published var confirmDelete = false
    @Published var pendingDelete: [FSItem] = []

    private let catalog = Catalog.shared
    private var backStack: [String] = []
    private var forwardStack: [String] = []
    private var started = false
    private var loadGeneration = 0
    private var scanToken: CancelToken?
    private var labelToken: CancelToken?
    private var labelTask: Task<Void, Never>?

    init(target: BrowseTarget) {
        let canonical = PathTool.canonical(target.path)
        path = canonical
        if let spec = Roots.spec(for: canonical) {
            title = spec.title
        } else if let known = Catalog.shared.label(for: canonical) {
            title = known
        } else {
            title = target.title ?? PathTool.name(of: canonical)
        }
        sortOrder = AppSettings.sortOrder
        showHidden = AppSettings.showHidden
    }

    // MARK: - Derived

    var visibleItems: [FSItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return items }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || ($0.identifier?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    var selectedItems: [FSItem] {
        items.filter { selected.contains($0.path) }
    }

    var isRootContainer: Bool { Roots.spec(for: path) != nil }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { path != "/" }

    func crumbTitle(_ crumb: Crumb) -> String {
        if let spec = Roots.spec(for: crumb.path) { return spec.title }
        if let label = catalog.label(for: crumb.path), !label.isEmpty { return label }
        return crumb.name
    }

    var crumbs: [Crumb] {
        let parts = PathTool.components(of: path)
        var accumulated = ""
        var all: [Crumb] = []
        for part in parts {
            accumulated += "/" + part
            all.append(Crumb(name: part, path: accumulated))
        }
        return Array(all.suffix(4))
    }

    var subtitle: String? {
        let count = visibleItems.count
        var pieces: [String] = []
        if count > 0 { pieces.append("\(count) 项") }
        if let scanStatus {
            pieces.append("扫描 \(scanStatus.done.formatted()) / \(scanStatus.total.formatted())")
        }
        if let labelProgress {
            pieces.append("识别 \(labelProgress.done)/\(labelProgress.total)")
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        await load(forceScan: false)
    }

    func stop() {
        cancelBackgroundWork()
    }

    private func cancelBackgroundWork() {
        scanToken?.cancel()
        scanToken = nil
        scanStatus = nil
        labelToken?.cancel()
        labelToken = nil
        labelTask?.cancel()
        labelTask = nil
        labelProgress = nil
    }

    func refresh() async {
        if isRootContainer {
            await load(forceScan: true)
        } else {
            await load(forceScan: false)
        }
    }

    // MARK: - Loading

    func load(forceScan: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration
        let current = path

        if let spec = Roots.spec(for: current) {
            await loadRoot(spec, forceScan: forceScan, generation: generation)
            return
        }

        if items.isEmpty { state = .loading } else { state = .refreshing }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try FileService.shared.list(path: current,
                                            includeHidden: AppSettings.showHidden,
                                            resolveIdentifiers: true)
            }.value
            guard generation == loadGeneration, path == current else { return }
            absorbIdentifiers(from: loaded)
            items = Sorter.sorted(enrich(loaded), order: sortOrder)
            state = .loaded
            selectionMode = false
            selected.removeAll()
            resolveLabel(for: current)
        } catch {
            guard generation == loadGeneration, path == current else { return }
            if items.isEmpty {
                state = .failed(error.localizedDescription)
            } else {
                state = .loaded
                errorMessage = error.localizedDescription
            }
            Log.error("list \(current): \(error.localizedDescription)")
        }
    }

    private func loadRoot(_ spec: RootSpec, forceScan: Bool, generation: Int) async {
        let cached = catalog.items(for: spec.path)
        if !cached.isEmpty {
            items = Sorter.sorted(cached, order: sortOrder)
            state = .loaded
        } else {
            items = []
            state = .loading
        }

        if spec.access == .list {
            do {
                let listed = try await Task.detached(priority: .userInitiated) {
                    try FileService.shared.list(path: spec.path,
                                                includeHidden: true,
                                                resolveIdentifiers: true)
                }.value
                guard generation == loadGeneration, path == spec.path else { return }
                absorbIdentifiers(from: listed)
                items = Sorter.sorted(enrich(listed), order: sortOrder)
                state = .loaded
                selectionMode = false
                selected.removeAll()
                return
            } catch {
                Log.info("parent listing failed for \(spec.path): \(error.localizedDescription)")
                if cached.isEmpty || forceScan {
                    let fullScan = cached.isEmpty || (forceScan && AppSettings.maxInodeOverride != nil)
                    await scan(spec: spec, full: fullScan, generation: generation)
                    return
                }
                return
            }
        }

        if cached.isEmpty || forceScan {
            let fullScan = cached.isEmpty || (forceScan && AppSettings.maxInodeOverride != nil)
            await scan(spec: spec, full: fullScan, generation: generation)
        }
    }

    private func scan(spec: RootSpec, full: Bool, generation: Int) async {
        guard scanToken == nil else { return }
        let record = catalog.scanRecord(for: spec.path)
        let watermark = record?.watermark ?? 0
        let baseline = AppSettings.maxInodeOverride ?? ContainerScanner.shared.baselineInode()
        guard baseline > 0 else {
            errorMessage = "无法确定 inode 上限。请在设置里填写一个上限，或先让 App 创建临时文件。"
            state = .loaded
            return
        }
        var start: UInt64 = full ? 1 : min(watermark + 1, baseline)
        if !full && watermark == 0 { start = 1 }
        let end = baseline
        guard end >= start else {
            state = .loaded
            return
        }

        let token = CancelToken()
        scanToken = token
        scanStatus = ScanStatus(done: 0, total: end - start + 1, started: Date())
        Log.info("scan \(spec.path) \(start)…\(end)")

        let root = spec.path
        let found = await Task.detached(priority: .userInitiated) {
            ContainerScanner.shared.scan(root: root, start: start, end: end, token: token) { done in
                Task { @MainActor [weak self] in
                    guard let self, self.scanToken === token, var status = self.scanStatus else { return }
                    let processed = done >= start ? done - start + 1 : 0
                    status.done = min(status.total, processed)
                    self.scanStatus = status
                }
            }
        }.value

        guard scanToken === token else { return }
        scanToken = nil
        scanStatus = nil
        if token.isCancelled { return }

        catalog.mergeScan(root: spec.path, paths: found, watermark: end, replace: full)
        guard generation == loadGeneration, path == spec.path else { return }
        let refreshed = catalog.items(for: spec.path)
        items = Sorter.sorted(refreshed, order: sortOrder)
        state = .loaded
        selectionMode = false
        selected.removeAll()
    }

    func cancelScan() {
        scanToken?.cancel()
        scanToken = nil
        scanStatus = nil
        if items.isEmpty {
            state = .loaded
        }
    }

    // MARK: - Navigation

    func open(path newPath: String, title newTitle: String? = nil) {
        let canonical = PathTool.canonical(newPath)
        guard canonical != path else { return }
        cancelBackgroundWork()
        backStack.append(path)
        forwardStack.removeAll()
        path = canonical
        if let spec = Roots.spec(for: canonical) {
            title = spec.title
        } else if let known = catalog.label(for: canonical) {
            title = known
        } else {
            title = newTitle ?? PathTool.name(of: canonical)
        }
        items = []
        state = .loading
        query = ""
        selectionMode = false
        selected.removeAll()
        Task { await load(forceScan: false) }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(path)
        path = previous
        resetForHistory()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(path)
        path = next
        resetForHistory()
    }

    func goUp() {
        guard canGoUp else { return }
        let parent = PathTool.parent(of: path)
        open(path: parent, title: Roots.spec(for: parent)?.title)
    }

    private func resetForHistory() {
        cancelBackgroundWork()
        title = Roots.spec(for: path)?.title
            ?? catalog.label(for: path)
            ?? PathTool.name(of: path)
        items = []
        state = .loading
        query = ""
        selectionMode = false
        selected.removeAll()
        Task { await load(forceScan: false) }
    }

    // MARK: - Title

    private func resolveLabel(for target: String) {
        if let spec = Roots.spec(for: target) {
            title = spec.title
            return
        }
        if let known = catalog.label(for: target) {
            title = known
            return
        }
        Task {
            let identifier = await Task.detached(priority: .utility) {
                FileService.shared.identifier(for: target)
            }.value
            guard path == target, let identifier, !identifier.isEmpty else { return }
            catalog.setLabel(identifier, for: target)
            title = identifier
        }
    }

    private func enrich(_ listed: [FSItem]) -> [FSItem] {
        listed.map { item in
            guard item.identifier == nil else { return item }
            var copy = item
            copy.identifier = catalog.label(for: item.path)
            return copy
        }
    }

    private func absorbIdentifiers(from listed: [FSItem]) {
        var pairs: [String: String] = [:]
        for item in listed {
            if let identifier = item.identifier, !identifier.isEmpty {
                pairs[item.path] = identifier
            }
        }
        catalog.setLabels(pairs)
    }

    // MARK: - Selection

    func toggleSelectionMode() {
        selectionMode.toggle()
        if !selectionMode { selected.removeAll() }
    }

    func toggle(_ item: FSItem) {
        if selected.contains(item.path) {
            selected.remove(item.path)
        } else {
            selected.insert(item.path)
        }
    }

    func selectAllVisible() {
        selected = Set(visibleItems.map { $0.path })
    }

    func tap(_ item: FSItem) {
        if selectionMode {
            toggle(item)
        } else if item.isDirectory {
            open(path: item.path)
        } else {
            preview(item)
        }
    }

    // MARK: - Sort and filter

    func applySort(_ key: SortKey) {
        if sortOrder.key == key {
            sortOrder.ascending.toggle()
        } else {
            sortOrder.key = key
            sortOrder.ascending = true
        }
        AppSettings.save(sortOrder)
        items = Sorter.sorted(items, order: sortOrder)
    }

    func setFoldersFirst(_ value: Bool) {
        sortOrder.foldersFirst = value
        AppSettings.save(sortOrder)
        items = Sorter.sorted(items, order: sortOrder)
    }

    func toggleHidden() {
        showHidden.toggle()
        AppSettings.showHidden = showHidden
        Task { await load(forceScan: false) }
    }

    // MARK: - Operations

    func copySelection(moving: Bool, app: AppModel) {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        app.setClipboard(ClipboardItem(paths: chosen.map { $0.path }, moving: moving))
        selectionMode = false
        selected.removeAll()
    }

    func paste(app: AppModel) {
        guard let clipboard = app.clipboard else { return }
        let destination = path
        busy = clipboard.moving ? "移动中…" : "拷贝中…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileService.shared.transfer(paths: clipboard.paths,
                                            to: destination,
                                            moving: clipboard.moving)
            }.value
            busy = nil
            notify(result, app: app)
            if clipboard.moving && result.failed == 0 {
                catalog.removePaths(clipboard.paths)
                app.clearClipboard()
            }
            await load(forceScan: true)
        }
    }

    func requestDelete(_ chosen: [FSItem]? = nil) {
        let targets = chosen ?? selectedItems
        guard !targets.isEmpty else { return }
        pendingDelete = targets
        confirmDelete = true
    }

    func performDelete(app: AppModel) {
        let targets = pendingDelete
        guard !targets.isEmpty else { return }
        confirmDelete = false
        pendingDelete = []
        busy = "删除中…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileService.shared.remove(paths: targets.map { $0.path })
            }.value
            busy = nil
            notify(result, app: app)
            if result.failed == 0 && result.done > 0 {
                catalog.removePaths(targets.map { $0.path })
            }
            selectionMode = false
            selected.removeAll()
            await load(forceScan: true)
        }
    }

    func newFolderPrompt() {
        sheet = SheetPayload(content: .prompt(TextPrompt(kind: .newFolder,
                                                         title: "新建文件夹",
                                                         message: "位置：\(path)",
                                                         initial: "",
                                                         actionTitle: "创建")))
    }

    func renamePrompt(_ item: FSItem) {
        sheet = SheetPayload(content: .prompt(TextPrompt(kind: .rename(item),
                                                         title: "重命名",
                                                         message: nil,
                                                         initial: item.name,
                                                         actionTitle: "重命名")))
    }

    func submit(prompt: TextPrompt, value: String, app: AppModel) {
        sheet = nil
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = FileService.nameProblem(name) {
            errorMessage = problem
            return
        }
        switch prompt.kind {
        case .newFolder:
            let parent = path
            busy = "创建中…"
            Task {
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        try FileService.shared.createFolder(in: parent, name: name)
                    }.value
                    busy = nil
                    app.flash("已创建 \(name)")
                    await load(forceScan: true)
                } catch {
                    busy = nil
                    errorMessage = error.localizedDescription
                }
            }
        case .rename(let item):
            busy = "重命名中…"
            Task {
                do {
                    let newPath = try await Task.detached(priority: .userInitiated) {
                        try FileService.shared.rename(path: item.path, to: name)
                    }.value
                    busy = nil
                    catalog.noteRename(from: item.path, to: newPath)
                    catalog.removePaths([item.path])
                    app.flash("已重命名为 \(name)")
                    await load(forceScan: true)
                } catch {
                    busy = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func importPicked(_ urls: [URL], app: AppModel) {
        guard !urls.isEmpty else { return }
        let destination = path
        busy = "导入 \(urls.count) 项…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileService.shared.importFiles(urls, into: destination)
            }.value
            busy = nil
            notify(result, app: app)
            await load(forceScan: true)
        }
    }

    func preview(_ item: FSItem) {
        guard !item.isDirectory else {
            open(path: item.path)
            return
        }
        busy = "准备预览…"
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try FileService.shared.exportSingle(path: item.path)
                }.value
                busy = nil
                sheet = SheetPayload(content: .preview(url))
            } catch {
                busy = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func editText(_ item: FSItem) {
        guard !item.isDirectory else { return }
        sheet = SheetPayload(content: .text(item))
    }

    func showInfo(_ item: FSItem) {
        sheet = SheetPayload(content: .info(item))
    }

    func share(_ chosen: [FSItem]) {
        let targets = chosen.isEmpty ? selectedItems : chosen
        guard !targets.isEmpty else { return }
        busy = "准备分享…"
        Task {
            do {
                let urls = try await Task.detached(priority: .userInitiated) {
                    try FileService.shared.export(paths: targets.map { $0.path })
                }.value
                busy = nil
                sheet = SheetPayload(content: .share(urls))
            } catch {
                busy = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func duplicate(_ item: FSItem, app: AppModel) {
        busy = "复制中…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileService.shared.duplicate(paths: [item.path])
            }.value
            busy = nil
            notify(result, app: app)
            await load(forceScan: true)
        }
    }

    func presentImporter() {
        sheet = SheetPayload(content: .importer)
    }

    func startLabelResolution(app: AppModel) {
        guard labelTask == nil else { return }
        let targets = items.filter { $0.isDirectory && $0.identifier == nil }
        guard !targets.isEmpty else {
            app.flash("当前没有待识别的容器")
            return
        }
        let token = CancelToken()
        labelToken = token
        labelProgress = LabelProgress(done: 0, total: targets.count)
        labelTask = Task { [weak self] in
            guard let self else { return }
            var index = 0
            for item in targets {
                if token.isCancelled { break }
                let itemPath = item.path
                let identifier = await Task.detached(priority: .utility) {
                    FileService.shared.identifier(for: itemPath)
                }.value
                if let identifier, !identifier.isEmpty {
                    self.catalog.setLabel(identifier, for: item.path)
                    if let position = self.items.firstIndex(where: { $0.path == item.path }) {
                        self.items[position].identifier = identifier
                    }
                }
                index += 1
                self.labelProgress = LabelProgress(done: index, total: targets.count)
            }
            self.labelProgress = nil
            self.labelTask = nil
            self.labelToken = nil
            self.items = Sorter.sorted(self.items, order: self.sortOrder)
            if token.isCancelled {
                app.flash("已停止识别")
            } else {
                app.flash("识别完成，共 \(targets.count) 个容器")
            }
        }
    }

    func stopLabelResolution() {
        labelToken?.cancel()
    }

    private func notify(_ result: OpFailures, app: AppModel) {
        if result.failed == 0 {
            app.flash(result.summary)
        } else {
            errorMessage = result.summary + (result.messages.count > 1 ? "\n" + result.messages.dropFirst().joined(separator: "\n") : "")
        }
    }
}

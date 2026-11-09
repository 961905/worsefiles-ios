//
//  AppModel.swift
//  WorseFiles
//

import Foundation
import SwiftUI

struct Favorite: Codable, Identifiable, Hashable {
    var path: String
    var title: String
    var id: String { path }
}

struct Recent: Codable, Identifiable, Hashable {
    var path: String
    var title: String
    var date: Date
    var id: String { path }
}

struct Notice: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isError = false
}

@MainActor
final class AppModel: ObservableObject {
    @Published var navPath: [BrowseTarget] = []
    @Published var favorites: [Favorite] = []
    @Published var recents: [Recent] = []
    @Published var clipboard: ClipboardItem?
    @Published var notice: Notice?

    private let favoritesKey = "favorites.v1"
    private let recentsKey = "recents.v1"
    private var noticeTask: Task<Void, Never>?

    init() {
        load()
        FileService.shared.prepare()
        Log.info("WorseFiles started, iOS \(Roots.majorVersion)")
    }

    func open(_ target: BrowseTarget) {
        navPath.append(target)
    }

    var favoritePaths: Set<String> {
        Set(favorites.map { PathTool.canonical($0.path) })
    }

    func isFavorite(_ path: String) -> Bool {
        favoritePaths.contains(PathTool.canonical(path))
    }

    func toggleFavorite(path: String, title: String) {
        let key = PathTool.canonical(path)
        if let index = favorites.firstIndex(where: { PathTool.canonical($0.path) == key }) {
            favorites.remove(at: index)
            save()
            flash("已取消收藏")
        } else {
            favorites.insert(Favorite(path: key, title: title), at: 0)
            save()
            flash("已收藏到主页")
        }
    }

    func removeFavorite(_ favorite: Favorite) {
        favorites.removeAll { $0.path == favorite.path }
        save()
        flash("已取消收藏")
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        save()
    }

    func record(path: String, title: String) {
        let key = PathTool.canonical(path)
        guard key != "/" else { return }
        let entry = Recent(path: key, title: title, date: Date())
        recents.removeAll { $0.path == key }
        recents.insert(entry, at: 0)
        if recents.count > 12 { recents.removeLast(recents.count - 12) }
        save()
    }

    func removeRecent(_ recent: Recent) {
        recents.removeAll { $0.path == recent.path }
        save()
    }

    func setClipboard(_ item: ClipboardItem) {
        clipboard = item
        flash(item.moving ? "已剪切 \(item.paths.count) 项" : "已复制 \(item.paths.count) 项")
    }

    func clearClipboard() {
        clipboard = nil
    }

    func flash(_ text: String, error: Bool = false) {
        noticeTask?.cancel()
        let next = Notice(text: text, isError: error)
        notice = next
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: error ? 5_000_000_000 : 2_400_000_000)
            guard !Task.isCancelled, let self else { return }
            if self.notice?.id == next.id {
                withAnimation(.easeOut(duration: 0.2)) { self.notice = nil }
            }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
        if let data = try? encoder.encode(recents) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let stored = try? decoder.decode([Favorite].self, from: data) {
            favorites = stored
        }
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let stored = try? decoder.decode([Recent].self, from: data) {
            recents = stored
        }
    }
}

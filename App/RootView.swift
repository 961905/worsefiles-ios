//
//  RootView.swift
//  WorseFiles
//

import Foundation
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject private var catalog = Catalog.shared
    @ObservedObject private var index = ContainerIndex.shared
    @State private var activeSheet: RootSheet?

    private enum RootSheet: String, Identifiable {
        case settings
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $app.navPath) {
            List {
                environmentSection
                if index.progress != nil {
                    scanProgressSection
                }
                if !catalog.items(for: Roots.dataApplication.path).isEmpty {
                    containersSection
                }
                if !app.favorites.isEmpty { favoritesSection }
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("小天工具箱")
            .onReceive(NotificationCenter.default.publisher(for: .worseFilesIndexUpdated)) { _ in
                catalog.objectWillChange.send()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                }
            }
            .navigationDestination(for: BrowseTarget.self) { target in
                BrowserView(target: target)
            }
            .task {
                await License.fetchNetworkTime()
                await scanIfNeeded()
            }
            .sheet(item: $activeSheet) { sheet in
                Group {
                    switch sheet {
                    case .settings:
                        SettingsView()
                    }
                }
                .environmentObject(app)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = app.notice {
                NoticeBanner(notice: notice)
                    .padding(.bottom, 14)
                    .onTapGesture { app.notice = nil }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: app.notice)
    }

    // MARK: - Sections

    private var environmentSection: some View {
        Section {
            if License.expired {
                RootRow(symbol: "lock.shield.fill",
                        tint: .red,
                        title: "授权已到期",
                        subtitle: "软件已停用，请联系作者获取新版本。",
                        detail: nil)
            } else if !License.hasTime {
                RootRow(symbol: "hourglass",
                        tint: .orange,
                        title: "正在校时",
                        subtitle: "等待 NTP 时间响应…",
                        detail: nil)
            } else if groupAvailable && Roots.testedWindow {
                RootRow(symbol: "checkmark.shield.fill",
                        tint: .green,
                        title: "环境就绪",
                        subtitle: timeSubtitle,
                        detail: nil)
            } else {
                RootRow(symbol: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: "App Group 不可用",
                        subtitle: "当前签名没有可用的 App Group。用包含 App Groups 的配置重新签名。",
                        detail: "设置")
            }
        } header: {
            Text("环境")
        } footer: {
            Text("支持和平精英手动修改画质、分辨率、广角等")
        }
    }

    private var timeSubtitle: String {
        let base = "App Group 可用"
        guard let time = License.networkTime else { return base }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return "\(base)。NTP \(formatter.string(from: time))"
    }

    private var containersSection: some View {
        Section {
            // Direct links to the tracked app's container: the UUID row is
            // what the user actually wants on the home screen.
            ForEach(catalog.items(for: Roots.dataApplication.path)) { item in
                NavigationLink(value: BrowseTarget(path: item.path, title: item.displayName)) {
                    RootRow(symbol: "app.badge.fill",
                            tint: .blue,
                            title: item.displayName,
                            subtitle: item.name,
                            detail: nil)
                }
            }
        } header: {
            Text("游戏")
        }
    }

    private var scanProgressSection: some View {
        Section {
            if let status = index.progress {
                ScanProgressView(status: status) {
                    index.cancel()
                }
            }
        } header: {
            Text("扫描")
        } footer: {
            Text("首次启动或目标容器不存在时自动扫描 inode。")
        }
    }

    private func scanIfNeeded() async {
        await app.refreshIndexOnLaunch()
        let containers = catalog.items(for: Roots.dataApplication.path)
        guard containers.isEmpty else { return }
        // No known container yet: run the scan here so the home screen fills
        // in the UUID row as soon as it is found.
        _ = try? await ContainerIndex.shared.ensureScanned(full: false)
    }

    private var favoritesSection: some View {
        Section {
            ForEach(app.favorites) { favorite in
                NavigationLink(value: BrowseTarget(path: favorite.path, title: favorite.title)) {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(favorite.title)
                                .lineLimit(1)
                            Text(PathTool.short(favorite.path))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        app.removeFavorite(favorite)
                    } label: {
                        Label("移除", systemImage: "star.slash")
                    }
                }
            }
        } header: {
            Text("收藏")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("支持版本")
                Spacer()
                Text("iOS 26.0–27.2")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("版本")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } header: {
            Text("关于")
        }
    }

    // MARK: - Helpers

    private var groupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppSettings.appGroupID) != nil
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func tint(for root: RootSpec) -> Color {
        switch root.access {
        case .scan: return .teal
        case .list: return .indigo
        }
    }

}

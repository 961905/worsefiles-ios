//
//  RootView.swift
//  WorseFiles
//

import Foundation
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject private var catalog = Catalog.shared
    @State private var activeSheet: RootSheet?

    private enum RootSheet: String, Identifiable {
        case settings
        case diagnostics
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack(path: $app.navPath) {
            List {
                environmentSection
                containersSection
                if !app.favorites.isEmpty { favoritesSection }
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("容器文件")
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
                await app.refreshIndexOnLaunch()
            }
            .sheet(item: $activeSheet) { sheet in
                Group {
                    switch sheet {
                    case .settings:
                        SettingsView()
                    case .diagnostics:
                        DiagnosticsView()
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
            Button {
                activeSheet = .diagnostics
            } label: {
                if !Roots.escapeSupported {
                    RootRow(symbol: "exclamationmark.shield.fill",
                            tint: .orange,
                            title: "系统不受支持",
                            subtitle: "worse_query 面向 iOS 26 与 27。当前 iOS \(Roots.majorVersion)，本应用沙盒与 App Group 仍可浏览。",
                            detail: nil)
                } else if groupAvailable && Roots.testedWindow {
                    RootRow(symbol: "checkmark.shield.fill",
                            tint: .green,
                            title: "环境就绪",
                            subtitle: "App Group 可用，容器路径按 worse_query 的范围访问。",
                            detail: nil)
                } else if groupAvailable {
                    RootRow(symbol: "exclamationmark.triangle.fill",
                            tint: .orange,
                            title: "系统版本未测试",
                            subtitle: "当前 iOS \(Roots.majorVersion)。worse_query 文档区间是 26.0–26.7.2 / 27.2，仍可尝试。",
                            detail: "诊断")
                } else {
                    RootRow(symbol: "exclamationmark.triangle.fill",
                            tint: .orange,
                            title: "App Group 不可用",
                            subtitle: "当前签名没有可用的 App Group。用包含 App Groups 的配置重新签名；应用会自动读取，不需要手填。",
                            detail: "设置")
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("环境")
        } footer: {
            Text("仅用于自己的设备与容器调试。系统版本需在 iOS 26.0–26.7.2 或 27.2；App Group 由签名提供并自动读取。")
        }
    }

    private var containersSection: some View {
        Section {
            ForEach(Roots.all) { root in
                NavigationLink(value: BrowseTarget(path: root.path, title: root.title)) {
                    RootRow(symbol: root.symbol,
                            tint: tint(for: root),
                            title: root.title,
                            subtitle: root.subtitle,
                            detail: countDetail(for: root))
                }
            }
        } header: {
            Text("容器")
        } footer: {
            Text("应用数据、扩展和守护进程需要首次 inode 扫描，结果会缓存。App 组与 iOS 27 的系统路径优先直接列举。")
        }
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
            Button {
                activeSheet = .diagnostics
            } label: {
                Label("诊断与日志", systemImage: "stethoscope")
            }
            Link(destination: URL(string: "https://github.com/forcequitOS/worse_query")!) {
                Label("worse_query 项目", systemImage: "arrow.up.right.square")
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
        } footer: {
            Text("worse_query 与 pathleak © 2026 Taj C (forcequit)，GPL-3.0。本应用同以 GPL-3.0 发布，源码在项目仓库。")
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

    private func countDetail(for root: RootSpec) -> String? {
        let count = catalog.count(for: root.path)
        return count > 0 ? "\(count)" : nil
    }
}

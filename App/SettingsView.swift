//
//  SettingsView.swift
//  WorseFiles
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog = Catalog.shared

    @AppStorage(SettingsKey.showHidden) private var showHidden = false
    @AppStorage(SettingsKey.autoResolveLabels) private var autoResolveLabels = true
    @AppStorage(SettingsKey.foldersFirst) private var foldersFirst = true
    @AppStorage(SettingsKey.sortKey) private var sortRaw = SortKey.name.rawValue
    @AppStorage(SettingsKey.sortAscending) private var sortAscending = true
    @AppStorage(SettingsKey.maxInode) private var maxInode = ""

    @State private var groupSnapshot = AppGroupResolver.snapshot()
    @State private var clearTarget: ClearTarget?

    private enum ClearTarget: String, Identifiable, Equatable {
        case all = "缓存"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                groupSection
                browsingSection
                cacheSection
                sandboxSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                groupSnapshot = AppGroupResolver.snapshot(refresh: true)
            }
            .confirmationDialog("清除缓存",
                                isPresented: Binding(
                                    get: { clearTarget != nil },
                                    set: { if !$0 { clearTarget = nil } }
                                ),
                                titleVisibility: .visible,
                                presenting: clearTarget) { target in
                Button("清除\(target.rawValue)", role: .destructive) {
                    catalog.clearScans()
                    catalog.clearLabels()
                    clearTarget = nil
                    app.flash("已清除\(target.rawValue)")
                }
                Button("取消", role: .cancel) { clearTarget = nil }
            } message: { target in
                Text("已发现的容器路径与容器名称会全部丢弃，下次打开根目录重新扫描。")
            }
        }
    }

    // MARK: - Sections

    private var groupSection: some View {
        Section {
            LabeledContent("当前使用") {
                Text(groupSnapshot.active)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            LabeledContent("容器访问") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(groupSnapshot.hasAccessible ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(groupSnapshot.hasAccessible ? "可用" : "不可用")
                        .foregroundStyle(.secondary)
                }
            }
            if let groupURL = groupContainerURL {
                Text(groupURL.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if groupSnapshot.groups.isEmpty {
                Label("签名里没有读到 App Group。重签时必须授予 App Groups entitlement。",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                ForEach(groupSnapshot.groups, id: \.self) { group in
                    HStack(spacing: 7) {
                        Image(systemName: groupSnapshot.accessible.contains(group)
                              ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(groupSnapshot.accessible.contains(group)
                                             ? Color.green : Color.secondary)
                        Text(group)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            Button {
                groupSnapshot = AppGroupResolver.refresh()
                app.flash("已重新检测 App Group")
            } label: {
                Label("重新检测", systemImage: "arrow.clockwise")
            }
            Button {
                FileService.shared.releaseAllExtensions()
                app.flash("已释放沙盒句柄")
            } label: {
                Label("释放所有沙盒句柄", systemImage: "lock.open")
            }
            NavigationLink {
                DiagnosticsView()
            } label: {
                Label("运行诊断", systemImage: "stethoscope")
            }
        } header: {
            Text("App Group")
        } footer: {
            Text("应用从自己的代码签名读取 App Group，不需要手动填写。重签时必须授予 App Groups entitlement；免费 Apple ID 通常不支持 App Groups。")
        }
    }

    private var browsingSection: some View {
        Section {
            Toggle("显示隐藏文件", isOn: $showHidden)
            Toggle("扫描后自动识别容器名称", isOn: $autoResolveLabels)
            Toggle("文件夹优先", isOn: $foldersFirst)
            Picker("默认排序", selection: $sortRaw) {
                ForEach(SortKey.allCases) { key in
                    Text(key.title).tag(key.rawValue)
                }
            }
            Toggle("升序", isOn: $sortAscending)
            HStack {
                Text("inode 上限")
                Spacer()
                TextField("自动", text: $maxInode)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 130)
            }
        } header: {
            Text("浏览")
        } footer: {
            Text("inode 上限留空时，使用新建临时文件的 inode 作为扫描终点。填写数字后，下拉刷新会对该根路径全量扫描 1…N 并重建缓存；设备不同，数字差别很大。")
        }
    }

    private var cacheSection: some View {
        Section {
            LabeledContent("已缓存根路径", value: "\(catalog.disk.scans.count)")
            LabeledContent("已知容器名称", value: "\(catalog.disk.labels.count)")
            Button(role: .destructive) {
                clearTarget = .all
            } label: {
                Text("清除缓存")
            }
        } header: {
            Text("缓存")
        } footer: {
            Text("扫描结果保存在本应用 Application Support，删除应用即清除。")
        }
    }

    private var sandboxSection: some View {
        Section {
            LabeledContent("系统", value: "iOS \(Roots.majorVersion)")
            LabeledContent("逃逸支持", value: escapeStatus)
            LabeledContent("已消费句柄", value: "\(SandboxBroker.shared.count)")
        } header: {
            Text("沙盒")
        } footer: {
            Text("仅覆盖 iOS 26.0–27.2，且只适用于自己的设备。不是越狱，也不提供越狱能力。")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: versionText)
        } header: {
            Text("关于")
        }
    }

    // MARK: - Helpers

    private var groupContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupSnapshot.active)
    }

    private var escapeStatus: String {
        if !Roots.escapeSupported { return "不可用" }
        return Roots.testedWindow ? "测试区间内" : "未测试"
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

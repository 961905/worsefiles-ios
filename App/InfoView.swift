//
//  InfoView.swift
//  WorseFiles
//

import SwiftUI
import UIKit

struct InfoView: View {
    let item: FSItem

    @Environment(\.dismiss) private var dismiss
    @State private var info: FileInfo?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        FileGlyph(item: item)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.headline)
                                .lineLimit(2)
                            Text(item.isDirectory ? "文件夹" : "文件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                if let info {
                    if !info.readable {
                        Section {
                            Label("无法读取完整属性。可能没有这个路径的沙盒扩展。",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("路径") {
                        Text(info.path)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Section("属性") {
                        InfoRow(label: "类型", value: typeName(info))
                        InfoRow(label: "大小", value: sizeText(info))
                        if let count = info.itemCount, info.isDirectory {
                            InfoRow(label: "项目数", value: count >= 100_000 ? "≥ 100,000" : "\(count)")
                        }
                        InfoRow(label: "创建", value: Format.date(info.created))
                        InfoRow(label: "修改", value: Format.date(info.modified))
                        InfoRow(label: "权限", value: info.permissions)
                        InfoRow(label: "所有者", value: "\(info.owner)")
                        InfoRow(label: "用户组", value: "\(info.group)")
                        InfoRow(label: "inode", value: "\(info.inode)")
                        InfoRow(label: "链接数", value: "\(info.linkCount)")
                    }

                    if info.identifier != nil || info.symlinkTarget != nil {
                        Section("容器") {
                            if let identifier = info.identifier {
                                InfoRow(label: "标识", value: identifier, monospaced: true)
                            }
                            if let target = info.symlinkTarget {
                                InfoRow(label: "符号链接指向", value: target, monospaced: true)
                            }
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("读取属性…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = info?.path ?? item.path
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("复制路径")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                let path = item.path
                let result = await Task.detached(priority: .userInitiated) {
                    FileService.shared.info(path: path)
                }.value
                info = result
            }
        }
    }

    private func typeName(_ info: FileInfo) -> String {
        if info.isSymbolicLink { return "符号链接" }
        if info.isDirectory { return info.identifier == nil ? "文件夹" : "容器文件夹" }
        let ext = (info.name as NSString).pathExtension
        return ext.isEmpty ? "文件" : "\(ext.uppercased()) 文件"
    }

    private func sizeText(_ info: FileInfo) -> String {
        if info.isDirectory {
            return "\(Format.bytes(info.size))（递归）"
        }
        return Format.bytes(info.size)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .body)
                .foregroundStyle(.secondary)
        } label: {
            Text(label)
        }
    }
}

//
//  DiagnosticsView.swift
//  WorseFiles
//

import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DiagnosticsContent()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}

struct DiagnosticsContent: View {
    @EnvironmentObject private var app: AppModel

    @State private var lines: [String] = []
    @State private var logText = ""
    @State private var running = true
    @State private var copied = false

    var body: some View {
        List {
            Section {
                if running {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("检测中…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(lines.indices, id: \.self) { index in
                            Text(lines[index])
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("检测结果")
            }

            Section {
                if logText.isEmpty {
                    Text("暂无日志")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(logText)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                HStack {
                    Text("日志")
                    Spacer()
                    Text("\(Log.lines.count) 行")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task { await run() }
                } label: {
                    Label("重新运行", systemImage: "arrow.clockwise")
                }
                .disabled(running)

                Button {
                    UIPasteboard.general.string = lines.joined(separator: "\n")
                    copied = true
                    app.flash("已复制诊断结果")
                } label: {
                    Label(copied ? "已复制" : "复制诊断结果", systemImage: "doc.on.doc")
                }
                .disabled(running || lines.isEmpty)

                Button(role: .destructive) {
                    Log.clear()
                    logText = ""
                    app.flash("日志已清空")
                } label: {
                    Label("清空日志", systemImage: "trash")
                }
            } header: {
                Text("操作")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await run() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(running)
            }
        }
        .task {
            await run()
        }
    }

    private func run() async {
        running = true
        copied = false
        let result = await Task.detached(priority: .userInitiated) {
            FileService.shared.diagnose()
        }.value
        lines = result
        logText = Log.tail
        running = false
    }
}

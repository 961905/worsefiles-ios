//
//  DiagnosticsView.swift
//  WorseFiles
//

import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Environment(\(.dismiss)) private var dismiss
    @EnvironmentObject private var app: AppModel
    @State private var lines: [String] = []
    @State private var running = false

    var body: some View {
        List {
            Section {
                ForEach(Array(lines.enumerated()), id: \\.offset) { pair in
                    Text(pair.element)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            } header: {
                Text("诊断输出")
            }
        }
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if running { ProgressView("正在收集诊断信息…") }
        }
        .task {
            await runDiagnostics()
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    UIPasteboard.general.string = lines.joined(separator: "\n")
                    app.flash("已复制诊断信息")
                } label: {
                    Label("复制全部", systemImage: "doc.on.doc")
                }
            }
        }
    }

    private func runDiagnostics() async {
        running = true
        let result = await Task.detached(priority: .userInitiated) {
            FileService.shared.diagnose()
        }.value
        lines = result
        running = false
    }
}

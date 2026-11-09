//
//  TextEditorSheet.swift
//  WorseFiles
//

import SwiftUI

struct TextEditorSheet: View {
    let item: FSItem
    let onSaved: () -> Void

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var loadedText = ""
    @State private var details: TextReadResult?
    @State private var loading = true
    @State private var saving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var confirmDiscard = false

    private var hasChanges: Bool { !loading && text != loadedText }
    private var truncated: Bool { details?.truncated ?? false }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                infoStrip
                Divider()
                editor
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        if hasChanges {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("保存") { save() }
                            .disabled(loading || !hasChanges || truncated)
                    }
                }
            }
            .task { await load() }
            .confirmationDialog("放弃更改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .interactiveDismissDisabled(hasChanges || saving)
        }
    }

    @ViewBuilder
    private var infoStrip: some View {
        if let details {
            HStack(spacing: 10) {
                Text(details.encoding)
                Text(Format.bytes(details.bytes))
                if details.truncated {
                    Label("只读", systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                }
                Spacer()
                if hasChanges {
                    Text("未保存")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if loading {
            VStack(spacing: 10) {
                ProgressView()
                Text("读取文本…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            VStack(spacing: 10) {
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                Text("无法作为文本打开")
                    .font(.headline)
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if truncated {
                    Text("文件超过 2 MB，只加载了前 2 MB。为避免截断，保存已禁用。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .disabled(truncated)
                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private func load() async {
        let path = item.path
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try FileService.shared.readText(path: path, maxBytes: 2_000_000)
            }.value
            details = result
            text = result.text
            loadedText = result.text
            loading = false
        } catch {
            loadError = error.localizedDescription
            loading = false
        }
    }

    private func save() {
        let path = item.path
        let value = text
        let sourceEncoding = details?.encoding
        saving = true
        saveError = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileService.shared.writeText(path: path, text: value, encoding: sourceEncoding)
                }.value
                loadedText = value
                saving = false
                app.flash("已保存 \(item.name)")
                onSaved()
                dismiss()
            } catch {
                saving = false
                saveError = error.localizedDescription
            }
        }
    }
}

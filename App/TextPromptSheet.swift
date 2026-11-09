//
//  TextPromptSheet.swift
//  WorseFiles
//

import SwiftUI

struct TextPromptSheet: View {
    let prompt: TextPrompt
    let onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    init(prompt: TextPrompt, onCommit: @escaping (String) -> Void) {
        self.prompt = prompt
        self.onCommit = onCommit
        _text = State(initialValue: prompt.initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(prompt.initial.isEmpty ? "名称" : prompt.initial, text: $text)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { commit() }
                } header: {
                    Text("名称")
                } footer: {
                    if let message = prompt.message {
                        Text(message)
                    }
                }
            }
            .navigationTitle(prompt.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(prompt.actionTitle, action: commit)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                focused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func commit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onCommit(value)
        dismiss()
    }
}

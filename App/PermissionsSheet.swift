//
//  PermissionsSheet.swift
//  WorseFiles
//

import SwiftUI

struct PermissionsSheet: View {
    let item: FSItem
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var octal: String = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("权限（八进制，如 755）", text: $octal)
                        .keyboardType(.numbersAndPunctuation)
                        .monospacedDigit()
                } header: {
                    Text(item.name)
                } footer: {
                    Text("三位八进制：所有者/组/其他，各为 读4+写2+执行1 的和。例如 755 = rwxr-xr-x。")
                }
            }
            .navigationTitle("权限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(octal)
                        dismiss()
                    }
                    .disabled(octal.trimmingCharacters(in: .whitespaces).count != 3)
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                let current = await Task.detached(priority: .userInitiated) {
                    FileService.shared.permissions(path: item.path)
                }.value
                if let current { octal = current }
            }
        }
    }
}

//
//  PermissionsSheet.swift
//  WorseFiles
//

import SwiftUI

struct PermissionsSheet: View {
    let item: FSItem
    let onApply: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    // rows: owner, group, others; columns: read, write, execute
    @State private var flags = [[false, false, false],
                                [false, false, false],
                                [false, false, false]]
    @State private var loaded = false

    private static let rowNames = ["所有者", "群组", "其它"]
    private static let columnNames = ["读", "写", "执行"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(0..<3, id: \.self) { row in
                        HStack {
                            Text(Self.rowNames[row])
                                .frame(width: 60, alignment: .leading)
                            ForEach(0..<3, id: \.self) { column in
                                Spacer()
                                toggle(row: row, column: column)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text(item.name)
                } footer: {
                    Text(octalText)
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
                        onApply(octalText)
                        dismiss()
                    }
                }
            }
            .task {
                guard !loaded else { return }
                loaded = true
                let current = await Task.detached(priority: .userInitiated) {
                    FileService.shared.permissions(path: item.path)
                }.value
                applyOctal(current)
            }
        }
    }

    private func toggle(row: Int, column: Int) -> some View {
        Button {
            flags[row][column].toggle()
        } label: {
            Image(systemName: flags[row][column] ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(flags[row][column] ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary))
                .font(.title3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.rowNames[row])\(Self.columnNames[column])")
    }

    private var octalText: String {
        flags.map { row in
            let value = (row[0] ? 4 : 0) + (row[1] ? 2 : 0) + (row[2] ? 1 : 0)
            return String(value)
        }.joined()
    }

    private func applyOctal(_ text: String?) {
        guard let text, text.count == 3 else { return }
        var parsed = [[Bool]](repeating: [false, false, false], count: 3)
        for (rowIndex, character) in text.enumerated() {
            guard let value = Int(String(character)), (0...7).contains(value) else { return }
            parsed[rowIndex][0] = value & 4 != 0
            parsed[rowIndex][1] = value & 2 != 0
            parsed[rowIndex][2] = value & 1 != 0
        }
        flags = parsed
    }
}

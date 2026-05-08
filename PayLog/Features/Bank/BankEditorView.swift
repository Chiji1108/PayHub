//
//  BankEditorView.swift
//  PayLog
//
//  Created by 千々岩真吾 on 2026/03/28.
//

import SwiftUI
import SwiftData

struct BankEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\Bank.sortOrder),
            SortDescriptor(\Bank.createdAt, order: .reverse),
            SortDescriptor(\Bank.name)
        ]
    ) private var banks: [Bank]

    private let bank: Bank?
    private let onDelete: (() -> Void)?
    private let onCreate: (() -> Void)?
    private let onCreateBank: ((Bank) -> Void)?
    @State private var name = ""
    @State private var branchName = ""
    @State private var accountNumber = ""
    @State private var notes = ""
    @State private var isActive = true
    @State private var deleteRequest: DeleteRequest<Bank>?
    @State private var hasAttemptedSave = false

    init(
        bank: Bank? = nil,
        onDelete: (() -> Void)? = nil,
        onCreate: (() -> Void)? = nil,
        onCreateBank: ((Bank) -> Void)? = nil
    ) {
        self.bank = bank
        self.onDelete = onDelete
        self.onCreate = onCreate
        self.onCreateBank = onCreateBank
        _name = State(initialValue: bank?.name ?? "")
        _branchName = State(initialValue: bank?.branchName ?? "")
        _accountNumber = State(initialValue: bank?.accountNumber ?? "")
        _notes = State(initialValue: bank?.notes ?? "")
        _isActive = State(initialValue: bank?.isActive ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("銀行名", text: $name)
                    Toggle("利用中", isOn: $isActive)
                        .sensoryFeedback(.selection, trigger: isActive)
                    TextField("支店名", text: $branchName)
                    TextField("口座番号", text: $accountNumber)
                        .keyboardType(.numberPad)
                        .onChange(of: accountNumber) { _, newValue in
                            accountNumber = newValue.filter(\.isNumber)
                        }
                } header: {
                    Text("基本情報")
                } footer: {
                    if let basicInformationMessage {
                        Text(basicInformationMessage)
                    }
                }

                Section("メモ") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                if bank != nil {
                    Section("削除") {
                        Button("銀行口座を削除", role: .destructive) {
                            guard let bank else {
                                return
                            }

                            deleteRequest = DeleteRequest(item: bank)
                        }
                        .deleteConfirmation(request: $deleteRequest, onConfirm: deleteBank)
                    }
                }
            }
            .navigationTitle(bank == nil ? "銀行口座を追加" : "銀行口座を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        hasAttemptedSave = true

                        guard !trimmedName.isEmpty else {
                            return
                        }

                        if let bank {
                            let didChangeActiveState = bank.isActive != isActive
                            bank.name = trimmedName
                            bank.branchName = trimmedBranchName
                            bank.accountNumber = trimmedAccountNumber
                            bank.notes = trimmedNotes
                            bank.isActive = isActive
                            if didChangeActiveState {
                                bank.sortOrder = modelContext.nextSortOrder(for: Bank.self, isActive: isActive)
                            }
                        } else {
                            let bank = Bank(
                                name: trimmedName,
                                branchName: trimmedBranchName,
                                accountNumber: trimmedAccountNumber,
                                notes: trimmedNotes,
                                isActive: isActive,
                                sortOrder: modelContext.nextSortOrder(for: Bank.self, isActive: isActive)
                            )
                            modelContext.insert(bank)
                            onCreate?()
                            onCreateBank?(bank)
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBranchName: String? {
        normalizedOptionalText(branchName)
    }

    private var trimmedAccountNumber: String? {
        normalizedOptionalText(accountNumber)
    }

    private var trimmedNotes: String? {
        normalizedOptionalText(notes)
    }

    private var basicInformationMessage: String? {
        if hasAttemptedSave, trimmedName.isEmpty {
            return "銀行名を入力してください。"
        }

        if trimmedAccountNumber != nil {
            return "口座情報を扱うため、必要に応じてホーム画面でこのアプリを長押しして、Face IDロックを設定しておくと安心です。"
        }

        return nil
    }

    private func normalizedOptionalText(_ text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private func deleteBank(_ bank: Bank) {
        modelContext.delete(bank)
        try? modelContext.save()
        onDelete?()
        dismiss()
    }
}

#Preview("Bank Editor", traits: .sampleData) {
    @Previewable @Query(sort: \Bank.name) var banks: [Bank]

    BankEditorView(bank: banks.first!)
}

#Preview("Bank Add", traits: .sampleData) {
    BankEditorView()
}

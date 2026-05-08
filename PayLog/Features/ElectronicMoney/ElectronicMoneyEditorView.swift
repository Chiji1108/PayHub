//
//  ElectronicMoneyEditorView.swift
//  PayLog
//
//  Created by 千々岩真吾 on 2026/03/28.
//

import SwiftUI
import SwiftData

struct ElectronicMoneyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\ElectronicMoney.sortOrder),
            SortDescriptor(\ElectronicMoney.createdAt, order: .reverse),
            SortDescriptor(\ElectronicMoney.name)
        ]
    ) private var electronicMoneys: [ElectronicMoney]
    @Query(sort: \Card.name) private var cards: [Card]
    @Query(sort: \Bank.name) private var banks: [Bank]

    private let electronicMoney: ElectronicMoney?
    private let onDelete: (() -> Void)?
    private let onCreate: (() -> Void)?
    @State private var name = ""
    @State private var notes = ""
    @State private var isActive = true
    @State private var fundingSource: ElectronicMoneyFundingSource = .unspecified
    @State private var selectedCardID: PersistentIdentifier?
    @State private var selectedBankID: PersistentIdentifier?
    @State private var deleteRequest: DeleteRequest<ElectronicMoney>?
    @State private var showingCardSheet = false
    @State private var showingBankSheet = false

    init(
        electronicMoney: ElectronicMoney? = nil,
        onDelete: (() -> Void)? = nil,
        onCreate: (() -> Void)? = nil
    ) {
        self.electronicMoney = electronicMoney
        self.onDelete = onDelete
        self.onCreate = onCreate
        _name = State(initialValue: electronicMoney?.name ?? "")
        _notes = State(initialValue: electronicMoney?.notes ?? "")
        _isActive = State(initialValue: electronicMoney?.isActive ?? true)
        _fundingSource = State(initialValue: electronicMoney?.fundingSource ?? .unspecified)
        _selectedCardID = State(initialValue: electronicMoney?.card?.persistentModelID)
        _selectedBankID = State(initialValue: electronicMoney?.bank?.persistentModelID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本情報") {
                    TextField("ウォレット名", text: $name)
                    Toggle("利用中", isOn: $isActive)
                        .sensoryFeedback(.selection, trigger: isActive)
                }

                Section("入金元") {
                    Picker("方法", selection: $fundingSource) {
                        ForEach(ElectronicMoneyFundingSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }

                    switch fundingSource {
                    case .card:
                        if cards.isEmpty {
                            RelatedItemCreationPrompt(
                                message: "利用可能なカードがありません。",
                                buttonTitle: "カードを追加"
                            ) {
                                showingCardSheet = true
                            }
                        } else {
                            Picker("カード", selection: $selectedCardID) {
                                Text("未設定").tag(Optional<PersistentIdentifier>.none)

                                ForEach(cards) { card in
                                    Text(card.name).tag(Optional(card.persistentModelID))
                                }
                            }
                        }
                    case .bankAccount:
                        if banks.isEmpty {
                            RelatedItemCreationPrompt(
                                message: "利用可能な銀行口座がありません。",
                                buttonTitle: "銀行口座を追加"
                            ) {
                                showingBankSheet = true
                            }
                        } else {
                            Picker("銀行口座", selection: $selectedBankID) {
                                Text("未設定").tag(Optional<PersistentIdentifier>.none)

                                ForEach(banks) { bank in
                                    Text(bank.name).tag(Optional(bank.persistentModelID))
                                }
                            }
                        }
                    case .cash, .unspecified:
                        EmptyView()
                    }
                }

                Section("メモ") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                if electronicMoney != nil {
                    Section("削除") {
                        Button("ウォレットを削除", role: .destructive) {
                            guard let electronicMoney else {
                                return
                            }

                            deleteRequest = DeleteRequest(item: electronicMoney)
                        }
                        .deleteConfirmation(request: $deleteRequest, onConfirm: deleteElectronicMoney)
                    }
                }
            }
            .navigationTitle(electronicMoney == nil ? "ウォレットを追加" : "ウォレットを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if let electronicMoney {
                            let didChangeActiveState = electronicMoney.isActive != isActive
                            electronicMoney.name = trimmedName
                            electronicMoney.notes = trimmedNotes
                            electronicMoney.fundingSource = fundingSource
                            electronicMoney.card = selectedCard
                            electronicMoney.bank = selectedBank
                            electronicMoney.isActive = isActive
                            if didChangeActiveState {
                                electronicMoney.sortOrder = modelContext.nextSortOrder(
                                    for: ElectronicMoney.self,
                                    isActive: isActive
                                )
                            }
                        } else {
                            let electronicMoney = ElectronicMoney(
                                name: trimmedName,
                                notes: trimmedNotes,
                                fundingSource: fundingSource,
                                card: selectedCard,
                                bank: selectedBank,
                                isActive: isActive,
                                sortOrder: modelContext.nextSortOrder(for: ElectronicMoney.self, isActive: isActive)
                            )
                            modelContext.insert(electronicMoney)
                            onCreate?()
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
            .sheet(isPresented: $showingCardSheet) {
                CardEditorView(onCreateCard: handleCardCreated)
            }
            .sheet(isPresented: $showingBankSheet) {
                BankEditorView(onCreateBank: handleBankCreated)
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String? {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNotes.isEmpty ? nil : trimmedNotes
    }

    private var selectedCard: Card? {
        guard fundingSource == .card else {
            return nil
        }

        guard let selectedCardID else {
            return nil
        }

        return cards.first { $0.persistentModelID == selectedCardID }
    }

    private var selectedBank: Bank? {
        guard fundingSource == .bankAccount else {
            return nil
        }

        guard let selectedBankID else {
            return nil
        }

        return banks.first { $0.persistentModelID == selectedBankID }
    }

    private func deleteElectronicMoney(_ electronicMoney: ElectronicMoney) {
        modelContext.delete(electronicMoney)
        try? modelContext.save()
        onDelete?()
        dismiss()
    }

    private func handleCardCreated(_ card: Card) {
        selectedCardID = card.persistentModelID
        fundingSource = .card
    }

    private func handleBankCreated(_ bank: Bank) {
        selectedBankID = bank.persistentModelID
        fundingSource = .bankAccount
    }
}

#Preview("Electronic Money Editor", traits: .sampleData) {
    @Previewable @Query(sort: \ElectronicMoney.name) var electronicMoneys: [ElectronicMoney]

    ElectronicMoneyEditorView(electronicMoney: electronicMoneys.first!)
}

#Preview("Electronic Money Add", traits: .sampleData) {
    ElectronicMoneyEditorView()
}

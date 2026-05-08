//
//  CardEditorView.swift
//  PayLog
//
//  Created by 千々岩真吾 on 2026/03/28.
//

import SwiftUI
import SwiftData

struct CardEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\Card.sortOrder),
            SortDescriptor(\Card.createdAt, order: .reverse),
            SortDescriptor(\Card.name)
        ]
    ) private var cards: [Card]
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \SubscriptionItem.name) private var subscriptions: [SubscriptionItem]

    private let card: Card?
    private let onDelete: (() -> Void)?
    private let onCreate: (() -> Void)?
    private let onCreateCard: ((Card) -> Void)?
    @State private var name = ""
    @State private var lastFourDigits = ""
    @State private var closingDay: Int?
    @State private var withdrawalDay: Int?
    @State private var notes = ""
    @State private var isActive = true
    @State private var selectedBankID: PersistentIdentifier?
    @State private var annualFeeSetting: CardAnnualFeeSetting
    @State private var selectedAnnualFeeSubscriptionID: PersistentIdentifier?
    @State private var deleteRequest: DeleteRequest<Card>?
    @State private var hasAttemptedSave = false
    @State private var showingAnnualFeeSubscriptionSheet = false
    @State private var showingBankSheet = false

    init(
        card: Card? = nil,
        onDelete: (() -> Void)? = nil,
        onCreate: (() -> Void)? = nil,
        onCreateCard: ((Card) -> Void)? = nil
    ) {
        self.card = card
        self.onDelete = onDelete
        self.onCreate = onCreate
        self.onCreateCard = onCreateCard
        _name = State(initialValue: card?.name ?? "")
        _lastFourDigits = State(initialValue: card?.lastFourDigits ?? "")
        _closingDay = State(initialValue: card?.closingDay)
        _withdrawalDay = State(initialValue: card?.withdrawalDay)
        _notes = State(initialValue: card?.notes ?? "")
        _isActive = State(initialValue: card?.isActive ?? true)
        _selectedBankID = State(initialValue: card?.bank?.persistentModelID)
        _annualFeeSetting = State(initialValue: card?.annualFeeSetting ?? .unspecified)
        _selectedAnnualFeeSubscriptionID = State(initialValue: card?.annualFeeSubscription?.persistentModelID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("カード名", text: $name)
                    Toggle("利用中", isOn: $isActive)
                        .sensoryFeedback(.selection, trigger: isActive)
                    TextField("末尾4桁", text: $lastFourDigits)
                        .keyboardType(.numberPad)
                        .onChange(of: lastFourDigits) { _, newValue in
                            lastFourDigits = String(newValue.filter(\.isNumber).prefix(4))
                        }
                } header: {
                    Text("基本情報")
                } footer: {
                    if let basicInformationMessage {
                        Text(basicInformationMessage)
                    }
                }

                Section {
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
                } header: {
                    Text("引き落とし口座")
                } footer: {
                }

                Section {
                    Picker("料金", selection: $annualFeeSetting) {
                        ForEach(CardAnnualFeeSetting.allCases) { setting in
                            Text(setting.label).tag(setting)
                        }
                    }

                    if annualFeeSetting == .paid {
                        Picker("固定費", selection: $selectedAnnualFeeSubscriptionID) {
                            Text("未設定").tag(Optional<PersistentIdentifier>.none)

                            ForEach(availableAnnualFeeSubscriptions) { subscription in
                                Text(subscription.name).tag(Optional(subscription.persistentModelID))
                            }
                        }

                        Button {
                            showingAnnualFeeSubscriptionSheet = true
                        } label: {
                            Label("年会費の固定費を作成", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("年会費")
                } footer: {
                    Text(annualFeeFooterText)
                }

                if isActive {
                    Section {
                        DayOfMonthPicker(title: "締日", selection: $closingDay)
                        DayOfMonthPicker(title: "引き落とし日", selection: $withdrawalDay)
                    } footer: {
                        Text("31日を指定した場合、30日までの月は月末扱いになります。")
                    }
                }

                Section("メモ") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                if card != nil {
                    Section("削除") {
                        Button("カードを削除", role: .destructive) {
                            guard let card else {
                                return
                            }

                            deleteRequest = DeleteRequest(item: card)
                        }
                        .deleteConfirmation(request: $deleteRequest, onConfirm: deleteCard)
                    }
                }
            }
            .navigationTitle(card == nil ? "カードを追加" : "カードを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        hasAttemptedSave = true

                        guard !isSaveDisabled else {
                            return
                        }

                        if let card {
                            let didChangeActiveState = card.isActive != isActive
                            card.name = trimmedName
                            card.lastFourDigits = trimmedLastFourDigits
                            card.closingDay = closingDay
                            card.withdrawalDay = withdrawalDay
                            card.notes = trimmedNotes
                            card.bank = selectedBank
                            card.annualFeeSetting = annualFeeSetting
                            card.annualFeeSubscription = annualFeeSetting == .paid
                                ? selectedAnnualFeeSubscription
                                : nil
                            card.isActive = isActive
                            if didChangeActiveState {
                                card.sortOrder = modelContext.nextSortOrder(for: Card.self, isActive: isActive)
                            }
                        } else {
                            let card = Card(
                                name: trimmedName,
                                lastFourDigits: trimmedLastFourDigits,
                                closingDay: closingDay,
                                withdrawalDay: withdrawalDay,
                                notes: trimmedNotes,
                                bank: selectedBank,
                                annualFeeSetting: annualFeeSetting,
                                annualFeeSubscription: annualFeeSetting == .paid
                                    ? selectedAnnualFeeSubscription
                                    : nil,
                                isActive: isActive,
                                sortOrder: modelContext.firstSortOrder(for: Card.self, isActive: isActive)
                            )
                            modelContext.insert(card)
                            onCreate?()
                            onCreateCard?(card)
                        }
                        try? modelContext.save()
                        Task {
                            await NotificationScheduler.shared.rescheduleAll(using: modelContext)
                        }
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
            .sheet(isPresented: $showingAnnualFeeSubscriptionSheet) {
                SubscriptionEditorView(
                    initialName: annualFeeSubscriptionName,
                    initialBillingUnit: .year,
                    onCreateSubscription: handleAnnualFeeSubscriptionCreated
                )
            }
            .sheet(isPresented: $showingBankSheet) {
                BankEditorView(onCreateBank: handleBankCreated)
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastFourDigits: String? {
        normalizedOptionalText(lastFourDigits)
    }

    private var trimmedNotes: String? {
        normalizedOptionalText(notes)
    }

    private var selectedBank: Bank? {
        guard let selectedBankID else {
            return nil
        }

        return banks.first { $0.persistentModelID == selectedBankID }
    }

    private var selectedAnnualFeeSubscription: SubscriptionItem? {
        guard let selectedAnnualFeeSubscriptionID else {
            return nil
        }

        return subscriptions.first { $0.persistentModelID == selectedAnnualFeeSubscriptionID }
    }

    private var availableAnnualFeeSubscriptions: [SubscriptionItem] {
        subscriptions
            .filter { subscription in
                if subscription.persistentModelID == selectedAnnualFeeSubscriptionID {
                    return true
                }

                guard subscription.billingUnit == .year else {
                    return false
                }

                guard let annualFeeCard = subscription.annualFeeCard else {
                    return true
                }

                return annualFeeCard.persistentModelID == card?.persistentModelID
            }
            .sortedForDisplay()
    }

    private var annualFeeFooterText: String {
        guard annualFeeSetting == .paid else {
            return ""
        }

        if annualFeeSetting == .paid, availableAnnualFeeSubscriptions.isEmpty {
            return "年会費を管理するには、年単位の固定費を作成してください。"
        }

        if annualFeeSetting == .paid, selectedAnnualFeeSubscription == nil {
            return "必要なら、このカードの年会費用の固定費を紐付けられます。"
        }

        return ""
    }

    private var annualFeeSubscriptionName: String {
        let baseName = trimmedName.isEmpty ? "カード" : trimmedName
        return "\(baseName) 年会費"
    }

    private var isSaveDisabled: Bool {
        trimmedName.isEmpty || lastFourDigitsValidationMessage != nil
    }

    private var basicInformationMessage: String? {
        guard hasAttemptedSave else {
            return nil
        }

        if trimmedName.isEmpty {
            return "カード名を入力してください。"
        }

        return lastFourDigitsValidationMessage
    }

    private var lastFourDigitsValidationMessage: String? {
        guard !lastFourDigits.isEmpty else {
            return nil
        }

        return lastFourDigits.count == 4 ? nil : "末尾4桁は数字4桁で入力してください。"
    }

    private func normalizedOptionalText(_ text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }

    private func deleteCard(_ card: Card) {
        modelContext.delete(card)
        try? modelContext.save()
        Task {
            await NotificationScheduler.shared.rescheduleAll(using: modelContext)
        }
        onDelete?()
        dismiss()
    }

    private func handleAnnualFeeSubscriptionCreated(_ subscription: SubscriptionItem) {
        selectedAnnualFeeSubscriptionID = subscription.persistentModelID
    }

    private func handleBankCreated(_ bank: Bank) {
        selectedBankID = bank.persistentModelID
    }
}

#Preview("Card Editor", traits: .sampleData) {
    @Previewable @Query(sort: \Card.name) var cards: [Card]

    CardEditorView(card: cards.first!)
}

#Preview("Card Add", traits: .sampleData) {
    CardEditorView()
}

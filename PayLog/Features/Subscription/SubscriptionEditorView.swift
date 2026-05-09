//
//  SubscriptionEditorView.swift
//  PayLog
//
//  Created by 千々岩真吾 on 2026/03/28.
//

import SwiftUI
import SwiftData

struct SubscriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\SubscriptionItem.sortOrder),
            SortDescriptor(\SubscriptionItem.createdAt, order: .reverse),
            SortDescriptor(\SubscriptionItem.name)
        ]
    ) private var subscriptions: [SubscriptionItem]
    @Query(sort: \Card.name) private var cards: [Card]
    @Query(sort: \Bank.name) private var banks: [Bank]

    private let subscription: SubscriptionItem?
    private let onDelete: (() -> Void)?
    private let onCreate: (() -> Void)?
    private let onCreateSubscription: ((SubscriptionItem) -> Void)?
    @State private var name = ""
    @State private var amountText = ""
    @State private var billingInterval = 1
    @State private var billingUnit: SubscriptionBillingUnit = .month
    @State private var currency: SubscriptionCurrency = .jpy
    @State private var hasBillingAnchorDate = false
    @State private var billingAnchorDate = Calendar.autoupdatingCurrent.startOfDay(for: Date.now)
    @State private var paymentMethod: SubscriptionPaymentMethod = .unspecified
    @State private var notes = ""
    @State private var isActive = true
    @State private var cancellationScheduledDate: Date?
    @State private var selectedCardID: PersistentIdentifier?
    @State private var selectedBankID: PersistentIdentifier?
    @State private var deleteRequest: DeleteRequest<SubscriptionItem>?
    @State private var hasAttemptedSave = false
    @State private var showingCardSheet = false
    @State private var showingBankSheet = false

    init(
        subscription: SubscriptionItem? = nil,
        initialName: String? = nil,
        initialBillingUnit: SubscriptionBillingUnit? = nil,
        onDelete: (() -> Void)? = nil,
        onCreate: (() -> Void)? = nil,
        onCreateSubscription: ((SubscriptionItem) -> Void)? = nil
    ) {
        self.subscription = subscription
        self.onDelete = onDelete
        self.onCreate = onCreate
        self.onCreateSubscription = onCreateSubscription
        _name = State(initialValue: subscription?.name ?? initialName ?? "")
        _amountText = State(
            initialValue: Self.editingAmountText(
                for: subscription?.amount,
                currency: subscription?.currency ?? .jpy
            )
        )
        _billingInterval = State(initialValue: max(subscription?.billingInterval ?? 1, 1))
        _billingUnit = State(initialValue: subscription?.billingUnit ?? initialBillingUnit ?? .month)
        _currency = State(initialValue: subscription?.currency ?? .jpy)
        _hasBillingAnchorDate = State(initialValue: subscription?.billingAnchorDate != nil)
        _billingAnchorDate = State(
            initialValue: Calendar.autoupdatingCurrent.startOfDay(for: subscription?.billingAnchorDate ?? .now)
        )
        _paymentMethod = State(initialValue: subscription?.paymentMethod ?? .unspecified)
        _notes = State(initialValue: subscription?.notes ?? "")
        _isActive = State(initialValue: subscription?.isActive ?? true)
        _cancellationScheduledDate = State(initialValue: subscription?.cancellationScheduledDate)
        _selectedCardID = State(initialValue: subscription?.card?.persistentModelID)
        _selectedBankID = State(initialValue: subscription?.bank?.persistentModelID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("固定費名", text: $name)
                    Toggle("利用中", isOn: $isActive)
                        .sensoryFeedback(.selection, trigger: isActive)

                    if subscription != nil, isActive {
                        cancellationScheduleControl
                    }
                } header: {
                    Text("基本情報")
                } footer: {
                    if hasAttemptedSave, trimmedName.isEmpty {
                        Text("固定費名を入力してください。")
                    }
                }

                Section {
                    TextField("金額", text: $amountText)
                        .keyboardType(currency.fractionDigits == 0 ? .numberPad : .decimalPad)

                    Picker("通貨", selection: $currency) {
                        ForEach(SubscriptionCurrency.allCases) { currency in
                            Text(currency.pickerLabel).tag(currency)
                        }
                    }
                } header: {
                    Text("料金")
                } footer: {
                    if let amountValidationMessage, hasAttemptedSave {
                        Text(amountValidationMessage)
                    }
                }

                Section {
                    Picker("単位", selection: $billingUnit) {
                        ForEach(SubscriptionBillingUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }

                    Stepper(value: $billingInterval, in: 1...24) {
                        Text(billingFrequency.editorIntervalDescription)
                    }

                    Toggle("\(billingDateLabel)を設定", isOn: $hasBillingAnchorDate)
                        .sensoryFeedback(.selection, trigger: hasBillingAnchorDate)

                    if hasBillingAnchorDate {
                        DatePicker(billingDateLabel, selection: $billingAnchorDate, displayedComponents: .date)
                    }
                } header: {
                    Text("支払い周期")
                } footer: {
                    Text(billingScheduleFooter)
                }

                Section {
                    Picker("方法", selection: $paymentMethod) {
                        ForEach(SubscriptionPaymentMethod.allCases) { method in
                            Text(method.label).tag(method)
                        }
                    }

                    switch paymentMethod {
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
                    case .invoice, .onSite, .unspecified:
                        EmptyView()
                    }
                } header: {
                    Text("支払い方法")
                } footer: {
                }

                Section("メモ") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }

                if subscription != nil {
                    Section("削除") {
                        Button("固定費を削除", role: .destructive) {
                            guard let subscription else {
                                return
                            }

                            deleteRequest = DeleteRequest(item: subscription)
                        }
                        .deleteConfirmation(request: $deleteRequest, onConfirm: deleteSubscription)
                    }
                }
            }
            .navigationTitle(subscription == nil ? "固定費を追加" : "固定費を編集")
            .onChange(of: currency) { oldValue, newValue in
                guard oldValue != newValue,
                      let amount = Self.decimalValue(from: trimmedAmountText, currency: oldValue) else {
                    return
                }

                amountText = Self.editingAmountText(for: amount, currency: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        hasAttemptedSave = true

                        guard let amount = parsedAmount, amount >= 0 else {
                            return
                        }

                        let selectedCard = paymentMethod == .card ? selectedCard : nil
                        let selectedBank = paymentMethod == .bankAccount ? selectedBank : nil

                        if let subscription {
                            let didChangeActiveState = subscription.isActive != isActive
                            subscription.name = trimmedName
                            subscription.amount = amount
                            subscription.billingInterval = billingInterval
                            subscription.billingUnit = billingUnit
                            subscription.currency = currency
                            subscription.billingAnchorDate = normalizedAnchorDate
                            subscription.paymentMethod = paymentMethod
                            subscription.notes = trimmedNotes
                            subscription.card = selectedCard
                            subscription.bank = selectedBank
                            subscription.isActive = isActive
                            subscription.cancellationScheduledDate = normalizedCancellationScheduledDate
                            if didChangeActiveState {
                                subscription.sortOrder = modelContext.nextSortOrder(
                                    for: SubscriptionItem.self,
                                    isActive: isActive
                                )
                            }
                        } else {
                            let subscription = SubscriptionItem(
                                name: trimmedName,
                                amount: amount,
                                billingInterval: billingInterval,
                                billingUnit: billingUnit,
                                currency: currency,
                                billingAnchorDate: normalizedAnchorDate,
                                paymentMethod: paymentMethod,
                                notes: trimmedNotes,
                                card: selectedCard,
                                bank: selectedBank,
                                isActive: isActive,
                                cancellationScheduledDate: normalizedCancellationScheduledDate,
                                sortOrder: modelContext.firstSortOrder(for: SubscriptionItem.self, isActive: isActive)
                            )
                            modelContext.insert(subscription)
                            onCreate?()
                            onCreateSubscription?(subscription)
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
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

    private var trimmedAmountText: String {
        amountText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String? {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedNotes.isEmpty ? nil : trimmedNotes
    }

    private var selectedCard: Card? {
        guard let selectedCardID else {
            return nil
        }

        return cards.first { $0.persistentModelID == selectedCardID }
    }

    private var selectedBank: Bank? {
        guard let selectedBankID else {
            return nil
        }

        return banks.first { $0.persistentModelID == selectedBankID }
    }

    private var billingFrequency: SubscriptionBillingFrequency {
        SubscriptionBillingFrequency(interval: billingInterval, unit: billingUnit)
    }

    @ViewBuilder
    private var cancellationScheduleControl: some View {
        if cancellationScheduledDate != nil {
            DatePicker(
                "解約予定日",
                selection: cancellationScheduledDateBinding,
                in: cancellationScheduledDateRange,
                displayedComponents: .date
            )

            Button("解約予定を取り消す", role: .cancel) {
                self.cancellationScheduledDate = nil
            }
        } else if let nextDate = draftBillingStatus?.nextDate {
            Button("解約予定にする") {
                cancellationScheduledDate = Calendar.autoupdatingCurrent.startOfDay(for: nextDate)
            }
        }
    }

    private var cancellationScheduledDateBinding: Binding<Date> {
        Binding {
            cancellationScheduledDate
                ?? draftBillingStatus?.nextDate
                ?? Calendar.autoupdatingCurrent.startOfDay(for: .now)
        } set: { newValue in
            cancellationScheduledDate = Calendar.autoupdatingCurrent.startOfDay(for: newValue)
        }
    }

    private var cancellationScheduledDateRange: PartialRangeFrom<Date> {
        Calendar.autoupdatingCurrent.startOfDay(for: .now)...
    }

    private var billingDateLabel: String {
        switch paymentMethod {
        case .onSite:
            "予定日"
        case .card, .bankAccount, .invoice, .unspecified:
            "請求日"
        }
    }

    private var billingCountdownLabel: String {
        paymentMethod.billingCountdownLabel
    }

    private var draftBillingStatus: BillingScheduleStatus? {
        guard let normalizedAnchorDate else {
            return nil
        }

        return BillingScheduleCalculator.recurringStatus(
            unit: billingUnit,
            interval: billingInterval,
            anchorDate: normalizedAnchorDate
        )
    }

    private var normalizedAnchorDate: Date? {
        guard hasBillingAnchorDate else {
            return nil
        }

        return Calendar.autoupdatingCurrent.startOfDay(for: billingAnchorDate)
    }

    private var normalizedCancellationScheduledDate: Date? {
        guard isActive,
              hasBillingAnchorDate,
              let cancellationScheduledDate else {
            return nil
        }

        return Calendar.autoupdatingCurrent.startOfDay(for: cancellationScheduledDate)
    }

    private var parsedAmount: Decimal? {
        Self.decimalValue(from: trimmedAmountText, currency: currency)
    }

    private var hasValidAmount: Bool {
        guard let amount = parsedAmount else {
            return false
        }

        return amount >= 0
    }

    private var isSaveDisabled: Bool {
        trimmedName.isEmpty || !hasValidAmount
    }

    private var amountValidationMessage: String? {
        if trimmedAmountText.isEmpty {
            return "0以上の金額を入力してください。"
        }

        guard let amount = parsedAmount else {
            return "金額の形式を確認してください。"
        }

        guard amount >= 0 else {
            return "0以上の金額を入力してください。"
        }

        return nil
    }

    private var billingScheduleFooter: String {
        guard hasBillingAnchorDate else {
            return ""
        }

        return switch billingUnit {
        case .week:
            "設定した\(billingDateLabel)の曜日で繰り返します。"
        case .month:
            "設定した\(billingDateLabel)の日付で繰り返します。存在しない日は月末に丸めます。"
        case .year:
            "設定した\(billingDateLabel)の月日で繰り返します。2月29日は平年では2月28日扱いです。"
        }
    }

    private func deleteSubscription(_ subscription: SubscriptionItem) {
        modelContext.delete(subscription)
        try? modelContext.save()
        onDelete?()
        dismiss()
    }

    private func handleCardCreated(_ card: Card) {
        selectedCardID = card.persistentModelID
        paymentMethod = .card
    }

    private func handleBankCreated(_ bank: Bank) {
        selectedBankID = bank.persistentModelID
        paymentMethod = .bankAccount
    }

    private static func editingAmountText(
        for amount: Decimal?,
        currency: SubscriptionCurrency
    ) -> String {
        guard let amount else {
            return ""
        }

        let roundedAmount = roundedAmount(amount, currency: currency)
        let formatter = amountFormatter(for: currency)
        return formatter.string(from: roundedAmount as NSDecimalNumber) ?? ""
    }

    private static func decimalValue(from text: String, currency: SubscriptionCurrency) -> Decimal? {
        guard !text.isEmpty else {
            return nil
        }

        let formatter = amountFormatter(for: currency)
        guard let number = formatter.number(from: text) else {
            return nil
        }

        return roundedAmount(number.decimalValue, currency: currency)
    }

    private static func amountFormatter(for currency: SubscriptionCurrency) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = currency.fractionDigits
        return formatter
    }

    private static func roundedAmount(_ amount: Decimal, currency: SubscriptionCurrency) -> Decimal {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, currency.fractionDigits, .plain)
        return rounded
    }
}

#Preview("Subscription Editor", traits: .sampleData) {
    @Previewable @Query(sort: \SubscriptionItem.name) var subscriptions: [SubscriptionItem]

    SubscriptionEditorView(subscription: subscriptions.first!)
}

#Preview("Subscription Add", traits: .sampleData) {
    SubscriptionEditorView()
}

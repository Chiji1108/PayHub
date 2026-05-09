//
//  SubscriptionTabView.swift
//  PayLog
//
//  Created by 千々岩真吾 on 2026/03/28.
//

import SwiftUI
import SwiftData
import TipKit

struct SubscriptionTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        sort: [
            SortDescriptor(\SubscriptionItem.sortOrder),
            SortDescriptor(\SubscriptionItem.createdAt, order: .reverse),
            SortDescriptor(\SubscriptionItem.name)
        ]
    ) private var subscriptions: [SubscriptionItem]
    @State private var showingAddSheet = false
    @State private var selectedFilter: SubscriptionFilter = .all
    @State private var hasCreatedItemInPresentedSheet = false
    @State private var reviewRequestTrigger = 0

    init() {}

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("固定費")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(!allowsManualReordering)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditModeDisabledToolbarContent {
                        Menu {
                            Picker("請求サイクル", selection: $selectedFilter) {
                                Text("すべて").tag(SubscriptionFilter.all)

                                ForEach(availableFrequencies) { frequency in
                                    Text(frequency.filterLabel).tag(SubscriptionFilter.frequency(frequency))
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease")
                        }
                        .accessibilityLabel("請求サイクルで絞り込む")

                        NavigationLink {
                            SubscriptionInsightsView()
                        } label: {
                            Label("分析を見る", systemImage: "chart.bar.xaxis")
                        }

                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("固定費を追加", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet, onDismiss: handleAddSheetDismiss) {
                SubscriptionEditorView(subscription: nil, onDelete: nil, onCreate: {
                    hasCreatedItemInPresentedSheet = true
                })
            }
            .onChange(of: availableFrequencies) { _, newValue in
                if case let .frequency(frequency) = selectedFilter, !newValue.contains(frequency) {
                    selectedFilter = .all
                }
            }
            .onChange(of: subscriptions.count) { oldValue, newValue in
                handleSubscriptionCountChange(from: oldValue, to: newValue)
            }
        }
        .reviewRequestAfterCreation(trigger: reviewRequestTrigger)
    }

    @ViewBuilder
    private var content: some View {
        if subscriptions.isEmpty {
            SampleDataContentUnavailableView(
                title: "固定費がまだありません",
                systemImage: "repeat.circle",
                description: "カードや銀行口座を登録しておくと、スムーズに追加できます。",
                shouldConfirmReplacement: shouldConfirmSampleDataReplacement,
                applySampleData: applySampleData
            )
        } else {
            subscriptionList
        }
    }

    private var subscriptionList: some View {
        List {
            if filteredSubscriptions.isEmpty {
                filteredEmptySection
            } else {
                if selectedFilter != .all {
                    filteredSummaryListSection
                }

                activeSubscriptionSection
                inactiveSubscriptionSection
            }
        }
    }

    private var filteredEmptySection: some View {
        Section {
            ContentUnavailableView(
                selectedFilter.emptyTitle,
                systemImage: "repeat.circle",
                description: Text(selectedFilter.emptyDescription)
            )
        }
    }

    private var filteredSummaryListSection: some View {
        Section {
            filteredSummarySection
        } header: {
            if hasMixedCurrenciesInFilteredSummary {
                Text("合計")
            }
        } footer: {
            if let footer = filteredSummaryFooterText {
                Text(footer)
            }
        }
    }

    @ViewBuilder
    private var activeSubscriptionSection: some View {
        if !activeSubscriptions.isEmpty {
            Section {
                if allowsManualReordering {
                    ForEach(activeSubscriptions) { subscription in
                        subscriptionNavigationLink(for: subscription)
                    }
                    .onDelete(perform: deleteActiveSubscriptions)
                    .onMove(perform: moveActiveSubscriptions)
                } else {
                    ForEach(activeSubscriptions) { subscription in
                        subscriptionNavigationLink(for: subscription)
                    }
                    .onDelete(perform: deleteActiveSubscriptions)
                }
            } header: {
                ActiveStatusSectionHeader(isActive: true)
            }
        }
    }

    @ViewBuilder
    private var inactiveSubscriptionSection: some View {
        if !inactiveSubscriptions.isEmpty {
            Section {
                if allowsManualReordering {
                    ForEach(inactiveSubscriptions) { subscription in
                        subscriptionNavigationLink(for: subscription)
                    }
                    .onDelete(perform: deleteInactiveSubscriptions)
                    .onMove(perform: moveInactiveSubscriptions)
                } else {
                    ForEach(inactiveSubscriptions) { subscription in
                        subscriptionNavigationLink(for: subscription)
                    }
                    .onDelete(perform: deleteInactiveSubscriptions)
                }
            } header: {
                ActiveStatusSectionHeader(isActive: false)
            }
        }
    }

    private func deleteActiveSubscriptions(offsets: IndexSet) {
        deleteSubscriptions(offsets: offsets, from: activeSubscriptions)
    }

    private func deleteInactiveSubscriptions(offsets: IndexSet) {
        deleteSubscriptions(offsets: offsets, from: inactiveSubscriptions)
    }

    private func moveActiveSubscriptions(from source: IndexSet, to destination: Int) {
        moveSubscriptions(from: source, to: destination, in: activeSubscriptions)
    }

    private func moveInactiveSubscriptions(from source: IndexSet, to destination: Int) {
        moveSubscriptions(from: source, to: destination, in: inactiveSubscriptions)
    }

    private func deleteSubscriptions(offsets: IndexSet, from subscriptions: [SubscriptionItem]) {
        let remainingSubscriptions = subscriptions.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)

        for index in offsets {
            modelContext.delete(subscriptions[index])
        }

        remainingSubscriptions.normalizeSortOrders()
        saveModelContext()
    }

    private func moveSubscriptions(from source: IndexSet, to destination: Int, in subscriptions: [SubscriptionItem]) {
        var reorderedSubscriptions = subscriptions
        reorderedSubscriptions.move(fromOffsets: source, toOffset: destination)
        reorderedSubscriptions.normalizeSortOrders()
        saveModelContext()
    }

    private var filteredSubscriptions: [SubscriptionItem] {
        let sortedSubscriptions = subscriptions.sortedForDisplay()

        return switch selectedFilter {
        case .all:
            sortedSubscriptions
        case let .frequency(frequency):
            sortedSubscriptions.filter { $0.billingFrequency == frequency }
        }
    }

    private var availableFrequencies: [SubscriptionBillingFrequency] {
        Array(Set(subscriptions.map(\.billingFrequency))).sorted()
    }

    private var filteredCurrencyTotals: [FilteredCurrencyTotal] {
        let totalsByCurrency = activeSubscriptions.reduce(into: [SubscriptionCurrency: Decimal]()) { partialResult, subscription in
            partialResult[subscription.currency, default: .zero] += subscription.amount
        }

        return SubscriptionCurrency.allCases.compactMap { currency in
            guard let amount = totalsByCurrency[currency] else {
                return nil
            }

            return FilteredCurrencyTotal(currency: currency, amount: amount)
        }
    }

    private var hasMixedCurrenciesInFilteredSummary: Bool {
        filteredCurrencyTotals.count > 1
    }

    private var activeSubscriptions: [SubscriptionItem] {
        filteredSubscriptions.filter(\.isActive)
    }

    private var inactiveSubscriptions: [SubscriptionItem] {
        filteredSubscriptions.filter { !$0.isActive }
    }

    private var allowsManualReordering: Bool {
        selectedFilter == .all
    }

    private var filteredSummaryFooterText: String? {
        guard selectedFilter != .all else {
            return nil
        }

        if activeSubscriptions.isEmpty {
            return "利用中の固定費を集計します。"
        }

        return "アクティブな固定費 \(activeSubscriptions.count) 件を集計しています。"
    }

    private var firstFilteredSubscriptionID: PersistentIdentifier? {
        filteredSubscriptions.first?.persistentModelID
    }

    @ViewBuilder
    private func subscriptionNavigationLink(for subscription: SubscriptionItem) -> some View {
        NavigationLink {
            SubscriptionDetailView(subscription: subscription)
        } label: {
            SubscriptionRow(subscription: subscription)
        }
        .swipeToDeleteTip(isPresented: subscription.persistentModelID == firstFilteredSubscriptionID)
    }

    @ViewBuilder
    private var filteredSummarySection: some View {
        if filteredCurrencyTotals.isEmpty {
            Text("集計できる利用中の固定費はありません")
                .foregroundStyle(.secondary)
        } else if !hasMixedCurrenciesInFilteredSummary, let total = filteredCurrencyTotals.first {
            LabeledContent("合計") {
                Text(filteredSummaryValueText(for: total))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        } else {
            ForEach(filteredCurrencyTotals) { total in
                LabeledContent(total.currency.displayLabel) {
                    Text(filteredSummaryValueText(for: total))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
    }

    private func filteredSummaryValueText(for total: FilteredCurrencyTotal) -> String {
        let amountText = total.currency.formattedAmount(total.amount)

        guard let frequency = selectedFilter.frequency else {
            return amountText
        }

        return "\(amountText) / \(frequency.intervalDescription)"
    }

    private func shouldConfirmSampleDataReplacement() -> Bool {
        SampleDataSeeder.hasAnyData(in: modelContext)
    }

    private func applySampleData() {
        SampleDataSeeder.replaceAllWithSampleData(in: modelContext)
    }

    private func handleAddSheetDismiss() {
        guard hasCreatedItemInPresentedSheet else {
            return
        }

        hasCreatedItemInPresentedSheet = false
        reviewRequestTrigger += 1
    }

    private func handleSubscriptionCountChange(from oldValue: Int, to newValue: Int) {
        guard oldValue == 0, newValue > 0 else {
            return
        }

        Task {
            await donateSwipeTip()
        }
    }

    private func donateSwipeTip() async {
        await SwipeToDeleteTip.listReceivedFirstItem.donate()
    }

    private func saveModelContext() {
        try? modelContext.save()
    }
}

private enum SubscriptionFilter: Hashable, Identifiable {
    case all
    case frequency(SubscriptionBillingFrequency)

    var id: String {
        switch self {
        case .all:
            "all"
        case let .frequency(frequency):
            frequency.id
        }
    }

    var frequency: SubscriptionBillingFrequency? {
        switch self {
        case .all:
            nil
        case let .frequency(frequency):
            frequency
        }
    }

    var emptyTitle: String {
        switch self {
        case .all:
            "固定費がまだありません"
        case let .frequency(frequency):
            "\(frequency.filterLabel)の固定費がまだありません"
        }
    }

    var emptyDescription: String {
        switch self {
        case .all:
            "固定費を追加するとここに表示されます。"
        case let .frequency(frequency):
            "\(frequency.filterLabel)の固定費を追加するとここに表示されます。"
        }
    }
}

private struct SubscriptionRow: View {
    let subscription: SubscriptionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ActiveStatusRow(
                subscription,
                title: subscription.name,
                trailingText: subscription.amountWithBillingCycleText,
                showIndicator: false
            )

            if let billingStatus = subscription.nextBillingStatus,
               shouldShowBillingStatus(billingStatus) {
                BillingScheduleProgressView(
                    scheduleLabel: subscription.billingDateLabel,
                    countdownLabel: subscription.billingCountdownLabel,
                    status: billingStatus,
                    isActive: subscription.isActive
                )
            }

            if let cancellationStatus = subscription.nextCancellationStatus {
                BillingScheduleProgressView(
                    scheduleLabel: "解約予定日",
                    countdownLabel: "解約",
                    status: cancellationStatus,
                    isActive: subscription.isActive,
                    systemImage: "xmark.circle"
                )
            } else if subscription.isActive, let billingStatus = subscription.nextBillingStatus {
                BillingScheduleProgressView(
                    scheduleLabel: subscription.billingDateLabel,
                    countdownLabel: subscription.billingCountdownLabel,
                    status: billingStatus,
                    isActive: subscription.isActive
                )
            }
        }
    }

    private func shouldShowBillingStatus(_ billingStatus: BillingScheduleStatus) -> Bool {
        guard subscription.isActive else {
            return false
        }

        guard let cancellationScheduledDate = subscription.cancellationScheduledDate else {
            return false
        }

        return Calendar.autoupdatingCurrent.startOfDay(for: billingStatus.nextDate)
            < Calendar.autoupdatingCurrent.startOfDay(for: cancellationScheduledDate)
    }
}

private struct FilteredCurrencyTotal: Identifiable {
    let currency: SubscriptionCurrency
    let amount: Decimal

    var id: SubscriptionCurrency { currency }
}

#Preview {
    SubscriptionTabView()
        .modelContainer(PreviewData.makeModelContainer())
}

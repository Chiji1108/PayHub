//
//  SubscriptionDetailView.swift
//  PayLog
//
//  Created by 千々岩真吾 on 2026/03/28.
//

import SwiftUI
import SwiftData

struct SubscriptionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var subscription: SubscriptionItem
    @State private var showingEditSheet = false

    var body: some View {
        List {
            Section("固定費") {
                ActiveStatusLabeledContent(item: subscription)
                LabeledContent("金額", value: subscription.amountWithBillingCycleText)
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
                } else if let billingStatus = subscription.nextBillingStatus {
                    BillingScheduleProgressView(
                        scheduleLabel: subscription.billingDateLabel,
                        countdownLabel: subscription.billingCountdownLabel,
                        status: billingStatus,
                        isActive: subscription.isActive
                    )
                } else {
                    LabeledContent(subscription.billingDateLabel, value: "未設定")
                }
                LabeledContent("支払い方法", value: subscription.paymentMethod.label)

                switch subscription.paymentMethod {
                case .card:
                    if let card = subscription.card {
                        ActiveStatusLabeledNavigationRow(
                            "支払いカード",
                            item: card,
                            title: card.name
                        ) {
                            CardDetailView(card: card)
                        }
                    } else {
                        LabeledContent("支払いカード") {
                            Text("未設定")
                        }
                    }
                case .bankAccount:
                    if let bank = subscription.bank {
                        ActiveStatusLabeledNavigationRow(
                            "引き落とし口座",
                            item: bank,
                            title: bank.name
                        ) {
                            BankDetailView(bank: bank)
                        }
                    } else {
                        LabeledContent("引き落とし口座") {
                            Text("未設定")
                        }
                    }
                case .invoice, .onSite, .unspecified:
                    EmptyView()
                }

            }

            if let notes = subscription.trimmedNotes {
                Section("メモ") {
                    Text(notes)
                }
            }

        }
        .navigationTitle(subscription.name)
        .toolbar {
            if let calendarEventDraft {
                ToolbarItem(placement: .topBarTrailing) {
                    CalendarEventAddButton(
                        title: calendarEventTitle,
                        draft: calendarEventDraft
                    ) {
                        Image(systemName: "calendar.badge.plus")
                    }
                    .accessibilityLabel(calendarEventTitle)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            SubscriptionEditorView(subscription: subscription, onCreate: {
                dismiss()
            })
        }
    }

    private var calendarEventTitle: String {
        if subscription.nextCancellationStatus != nil {
            return "解約予定日をカレンダーに追加"
        }

        return "\(subscription.billingCountdownLabel)日をカレンダーに追加"
    }

    private var calendarEventDraft: CalendarEventDraft? {
        cancellationEventDraft ?? billingEventDraft
    }

    private var cancellationEventDraft: CalendarEventDraft? {
        guard let status = subscription.nextCancellationStatus else {
            return nil
        }

        let startDate = status.nextDate
        let endDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        let notes = [subscription.amountWithBillingCycleText, subscription.trimmedNotes]
            .compactMap { $0 }
            .joined(separator: "\n")

        return CalendarEventDraft(
            title: "\(subscription.name) 解約予定日",
            startDate: startDate,
            endDate: endDate,
            isAllDay: true,
            notes: notes.isEmpty ? nil : notes,
            recurrence: nil
        )
    }

    private var billingEventDraft: CalendarEventDraft? {
        guard let status = subscription.nextBillingStatus else {
            return nil
        }

        let startDate = status.nextDate
        let endDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        let notes = [subscription.amountWithBillingCycleText, subscription.trimmedNotes]
            .compactMap { $0 }
            .joined(separator: "\n")

        return CalendarEventDraft(
            title: "\(subscription.name) \(subscription.billingCountdownLabel)日",
            startDate: startDate,
            endDate: endDate,
            isAllDay: true,
            notes: notes.isEmpty ? nil : notes,
            recurrence: subscription.calendarEventRecurrence
        )
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

#Preview("Subscription Detail", traits: .sampleData) {
    @Previewable @Query(sort: \SubscriptionItem.name) var subscriptions: [SubscriptionItem]

    NavigationStack {
        SubscriptionDetailView(subscription: subscriptions.first!)
    }
}

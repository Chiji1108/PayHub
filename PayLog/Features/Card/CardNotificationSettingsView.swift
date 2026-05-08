//
//  CardNotificationSettingsView.swift
//  PayLog
//
//  Created by Codex on 2026/03/29.
//

import SwiftUI
import SwiftData
import UserNotifications
import UIKit

struct CardNotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \Card.name) private var cards: [Card]

    @State private var settings = NotificationSettingsStore.loadCardSettings()
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingSettingsAlert = false

    var body: some View {
        Form {
            notificationSection(
                title: "締日通知",
                isEnabled: $settings.closingReminderEnabled,
                daysBefore: $settings.closingReminderDaysBefore,
                time: $settings.closingReminderTime,
                footer: "締日が設定されている利用中カードだけ通知します。"
            )

            notificationSection(
                title: "引き落とし日通知",
                isEnabled: $settings.withdrawalReminderEnabled,
                daysBefore: $settings.withdrawalReminderDaysBefore,
                time: $settings.withdrawalReminderTime,
                footer: "引き落とし日が設定されている利用中カードだけ通知します。"
            )

            if shouldShowDeniedGuidance {
                Section("通知を使うには") {
                    Text("設定アプリでPayLogの通知をオンにしてください。")

                    Button("設定アプリを開く") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }

                        openURL(url)
                    }
                }
            }

            if !deliveryWarnings.isEmpty {
                Section("補足") {
                    Text("次のカードは通知予定日が月末のため、iOSの仕様によりアプリを3ヶ月以上起動していないと、通知が届かないことがあります。")

                    ForEach(deliveryWarnings) { warning in
                        LabeledContent(warning.card.name) {
                            Text(warning.summaryText)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("カード通知")
        .task {
            authorizationStatus = await NotificationScheduler.shared.authorizationStatus()
        }
        .onChange(of: settings.closingReminderEnabled) { _, isEnabled in
            Task {
                await handleEnabledChange(isEnabled, keyPath: \.closingReminderEnabled)
            }
        }
        .onChange(of: settings.withdrawalReminderEnabled) { _, isEnabled in
            Task {
                await handleEnabledChange(isEnabled, keyPath: \.withdrawalReminderEnabled)
            }
        }
        .onChange(of: settings.closingReminderDaysBefore) { _, _ in
            persistAndReschedule()
        }
        .onChange(of: settings.withdrawalReminderDaysBefore) { _, _ in
            persistAndReschedule()
        }
        .onChange(of: settings.closingReminderTime) { _, _ in
            persistAndReschedule()
        }
        .onChange(of: settings.withdrawalReminderTime) { _, _ in
            persistAndReschedule()
        }
        .alert("通知を許可してください", isPresented: $showingSettingsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("カード通知を使うには、設定アプリで通知を許可してください。")
        }
    }

    private var shouldShowDeniedGuidance: Bool {
        authorizationStatus == .denied && hasEnabledNotification
    }

    private var hasEnabledNotification: Bool {
        settings.closingReminderEnabled || settings.withdrawalReminderEnabled
    }

    private var deliveryWarnings: [CardNotificationDeliveryWarning] {
        NotificationScheduler.shared.deliveryWarnings(for: cards, settings: settings)
    }

    private func notificationSection(
        title: String,
        isEnabled: Binding<Bool>,
        daysBefore: Binding<Int>,
        time: Binding<NotificationTime>,
        footer: String
    ) -> some View {
        Section {
            Toggle("\(title)をオン", isOn: isEnabled)
                .sensoryFeedback(.selection, trigger: isEnabled.wrappedValue)

            if isEnabled.wrappedValue {
                Stepper(value: daysBefore, in: 0...30) {
                    LabeledContent("通知タイミング", value: dayBeforeText(daysBefore.wrappedValue))
                }

                DatePicker(
                    "通知時刻",
                    selection: Binding(
                        get: { time.wrappedValue.date },
                        set: { time.wrappedValue = NotificationTime(date: $0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    private func handleEnabledChange(
        _ isEnabled: Bool,
        keyPath: WritableKeyPath<CardNotificationSettings, Bool>
    ) async {
        guard isEnabled else {
            persistAndReschedule()
            authorizationStatus = await NotificationScheduler.shared.authorizationStatus()
            return
        }

        let granted = await NotificationScheduler.shared.requestAuthorizationIfNeeded()
        authorizationStatus = await NotificationScheduler.shared.authorizationStatus()

        guard granted else {
            settings[keyPath: keyPath] = false
            showingSettingsAlert = true
            persistAndReschedule()
            return
        }

        persistAndReschedule()
    }

    private func persistAndReschedule() {
        NotificationSettingsStore.saveCardSettings(settings)
        Task {
            try? modelContext.save()
            await NotificationScheduler.shared.rescheduleAll(using: modelContext)
        }
    }

    private func dayBeforeText(_ value: Int) -> String {
        value == 0 ? "当日" : "\(value)日前"
    }
}

#Preview("Card Notification Settings", traits: .sampleData) {
    NavigationStack {
        CardNotificationSettingsView()
    }
}

//
//  SubscriptionItem.swift
//  PayLog
//
//  Created by 千々岩真吾 on 2026/03/28.
//

import Foundation
import SwiftData

enum SubscriptionBillingUnit: String, CaseIterable, Codable, Identifiable {
    case week
    case month
    case year

    var id: Self { self }

    var label: String {
        switch self {
        case .week:
            "週"
        case .month:
            "月"
        case .year:
            "年"
        }
    }

    var durationLabel: String {
        switch self {
        case .week:
            "週間"
        case .month:
            "ヶ月"
        case .year:
            "年"
        }
    }

    var amountSuffix: String {
        switch self {
        case .week:
            "週"
        case .month:
            "月"
        case .year:
            "年"
        }
    }

    var sortOrder: Int {
        switch self {
        case .week:
            0
        case .month:
            1
        case .year:
            2
        }
    }
}

enum SubscriptionCurrency: String, CaseIterable, Codable, Identifiable {
    case jpy = "JPY"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case aud = "AUD"
    case cad = "CAD"
    case cny = "CNY"
    case hkd = "HKD"
    case krw = "KRW"

    var id: Self { self }

    var code: String { rawValue }

    var label: String {
        switch self {
        case .jpy:
            "日本円"
        case .usd:
            "米ドル"
        case .eur:
            "ユーロ"
        case .gbp:
            "英ポンド"
        case .aud:
            "豪ドル"
        case .cad:
            "カナダドル"
        case .cny:
            "人民元"
        case .hkd:
            "香港ドル"
        case .krw:
            "韓国ウォン"
        }
    }

    var symbol: String {
        switch self {
        case .jpy, .cny:
            "¥"
        case .usd, .cad, .aud, .hkd:
            "$"
        case .eur:
            "€"
        case .gbp:
            "£"
        case .krw:
            "₩"
        }
    }

    var fractionDigits: Int {
        switch self {
        case .jpy, .krw:
            0
        case .usd, .eur, .gbp, .aud, .cad, .cny, .hkd:
            2
        }
    }

    var pickerLabel: String {
        "\(label) (\(symbol) \(code))"
    }

    var displayLabel: String {
        "\(label) (\(code))"
    }

    var editorUnitLabel: String {
        "\(symbol) \(code)"
    }

    func formattedAmount(_ amount: Decimal) -> String {
        amount.formatted(
            .currency(code: code)
                .precision(.fractionLength(fractionDigits))
        )
    }
}

struct SubscriptionBillingFrequency: Hashable, Identifiable, Comparable {
    let interval: Int
    let unit: SubscriptionBillingUnit

    init(interval: Int, unit: SubscriptionBillingUnit) {
        self.interval = max(interval, 1)
        self.unit = unit
    }

    var id: String {
        "\(unit.rawValue)-\(interval)"
    }

    var filterLabel: String {
        intervalDescription
    }

    var intervalDescription: String {
        "\(interval)\(unit.durationLabel)"
    }

    var editorIntervalDescription: String {
        switch unit {
        case .week:
            interval == 1 ? "毎週" : "\(interval)週間ごと"
        case .month:
            interval == 1 ? "毎月" : "\(interval)ヶ月ごと"
        case .year:
            interval == 1 ? "毎年" : "\(interval)年ごと"
        }
    }

    func formattedAmount(_ amount: Decimal, currency: SubscriptionCurrency) -> String {
        let amountText = currency.formattedAmount(amount)
        let suffix = interval == 1 ? unit.amountSuffix : "\(interval)\(unit.durationLabel)"
        return "\(amountText) / \(suffix)"
    }

    static func < (lhs: SubscriptionBillingFrequency, rhs: SubscriptionBillingFrequency) -> Bool {
        if lhs.unit.sortOrder == rhs.unit.sortOrder {
            return lhs.interval < rhs.interval
        }

        return lhs.unit.sortOrder < rhs.unit.sortOrder
    }
}

enum SubscriptionPaymentMethod: String, CaseIterable, Codable, Identifiable {
    case card
    case bankAccount
    case invoice
    case onSite
    case unspecified

    var id: Self { self }

    var label: String {
        switch self {
        case .card:
            "カード"
        case .bankAccount:
            "口座振替"
        case .invoice:
            "請求書払い"
        case .onSite:
            "現地払い"
        case .unspecified:
            "未設定"
        }
    }

    var billingCountdownLabel: String {
        switch self {
        case .onSite:
            "予定"
        case .card, .bankAccount, .invoice, .unspecified:
            "請求"
        }
    }
}

@Model
final class SubscriptionItem {
    var name: String = ""
    var amount: Decimal = 0
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var billingInterval: Int = 1
    var billingAnchorDate: Date?
    private var billingUnitRawValue: String = SubscriptionBillingUnit.month.rawValue
    private var currencyCodeRawValue: String = SubscriptionCurrency.jpy.rawValue
    private var paymentMethodRawValue: String?
    var notes: String?
    var isActive: Bool = true
    var cancellationScheduledDate: Date?
    var card: Card?
    var bank: Bank?
    var annualFeeCard: Card?

    var billingUnit: SubscriptionBillingUnit {
        get { SubscriptionBillingUnit(rawValue: billingUnitRawValue) ?? .month }
        set { billingUnitRawValue = newValue.rawValue }
    }

    var billingFrequency: SubscriptionBillingFrequency {
        SubscriptionBillingFrequency(interval: billingInterval, unit: billingUnit)
    }

    var currency: SubscriptionCurrency {
        get { SubscriptionCurrency(rawValue: currencyCodeRawValue) ?? .jpy }
        set { currencyCodeRawValue = newValue.rawValue }
    }

    var paymentMethod: SubscriptionPaymentMethod {
        get {
            if let paymentMethodRawValue,
               let paymentMethod = SubscriptionPaymentMethod(rawValue: paymentMethodRawValue) {
                return paymentMethod
            }

            if bank != nil {
                return .bankAccount
            }

            if card != nil {
                return .card
            }

            return .unspecified
        }
        set { paymentMethodRawValue = newValue.rawValue }
    }

    var amountWithBillingCycleText: String {
        billingFrequency.formattedAmount(amount, currency: currency)
    }

    var formattedAmountText: String {
        currency.formattedAmount(amount)
    }

    var billingCountdownLabel: String {
        paymentMethod.billingCountdownLabel
    }

    var billingDateLabel: String {
        switch paymentMethod {
        case .onSite:
            "予定日"
        case .card, .bankAccount, .invoice, .unspecified:
            "請求日"
        }
    }

    var missingBillingDateText: String {
        "\(billingDateLabel)未設定"
    }

    init(
        name: String,
        amount: Decimal,
        createdAt: Date = Date.now,
        billingInterval: Int = 1,
        billingUnit: SubscriptionBillingUnit = .month,
        currency: SubscriptionCurrency = .jpy,
        billingAnchorDate: Date? = nil,
        paymentMethod: SubscriptionPaymentMethod = .unspecified,
        notes: String? = nil,
        card: Card? = nil,
        bank: Bank? = nil,
        isActive: Bool = true,
        cancellationScheduledDate: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.amount = amount
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.billingInterval = max(billingInterval, 1)
        if let billingAnchorDate {
            self.billingAnchorDate = Calendar.autoupdatingCurrent.startOfDay(for: billingAnchorDate)
        } else {
            self.billingAnchorDate = nil
        }
        self.billingUnitRawValue = billingUnit.rawValue
        self.currencyCodeRawValue = currency.rawValue
        self.paymentMethodRawValue = paymentMethod.rawValue
        self.notes = notes
        self.card = paymentMethod == .card ? card : nil
        self.bank = paymentMethod == .bankAccount ? bank : nil
        self.isActive = isActive
        if isActive, let cancellationScheduledDate {
            self.cancellationScheduledDate = Calendar.autoupdatingCurrent.startOfDay(for: cancellationScheduledDate)
        } else {
            self.cancellationScheduledDate = nil
        }
    }
}

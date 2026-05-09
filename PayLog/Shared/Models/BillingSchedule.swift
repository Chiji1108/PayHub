//
//  BillingSchedule.swift
//  PayLog
//
//  Created by Codex on 2026/03/28.
//

import Foundation

struct BillingScheduleStatus {
    let previousDate: Date
    let nextDate: Date
    let referenceDate: Date
    private let calendar: Calendar

    init(
        previousDate: Date,
        nextDate: Date,
        referenceDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.previousDate = previousDate
        self.nextDate = nextDate
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    var progress: Double {
        let totalInterval = nextDate.timeIntervalSince(previousDate)
        guard totalInterval > 0 else {
            return 0
        }

        let elapsedInterval = min(max(referenceDate.timeIntervalSince(previousDate), 0), totalInterval)
        return elapsedInterval / totalInterval
    }

    var daysUntilNext: Int {
        let startOfReferenceDate = calendar.startOfDay(for: referenceDate)
        let startOfNextDate = calendar.startOfDay(for: nextDate)
        return max(calendar.dateComponents([.day], from: startOfReferenceDate, to: startOfNextDate).day ?? 0, 0)
    }
}

enum BillingScheduleCalculator {
    static func normalizedDay(_ day: Int?) -> Int? {
        guard let day, (1...31).contains(day) else {
            return nil
        }

        return day
    }

    static func monthlyAnchorDate(
        day: Int,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let normalizedDay = normalizedDay(day) else {
            return nil
        }

        let startOfReferenceDate = calendar.startOfDay(for: referenceDate)
        let components = calendar.dateComponents([.year, .month], from: startOfReferenceDate)

        guard let year = components.year,
              let month = components.month else {
            return nil
        }

        let resolvedDay = min(normalizedDay, dayCount(in: month, year: year, calendar: calendar))
        return calendar.date(from: DateComponents(year: year, month: month, day: resolvedDay))
    }

    static func recurringStatus(
        unit: SubscriptionBillingUnit,
        interval: Int,
        anchorDate: Date,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BillingScheduleStatus? {
        let normalizedInterval = max(interval, 1)
        let startOfAnchorDate = calendar.startOfDay(for: anchorDate)
        let startOfReferenceDate = calendar.startOfDay(for: referenceDate)

        switch unit {
        case .week:
            return weeklyStatus(
                interval: normalizedInterval,
                anchorDate: startOfAnchorDate,
                referenceDate: startOfReferenceDate,
                calendar: calendar
            )
        case .month:
            return monthlyRecurringStatus(
                interval: normalizedInterval,
                anchorDate: startOfAnchorDate,
                referenceDate: startOfReferenceDate,
                calendar: calendar
            )
        case .year:
            return yearlyRecurringStatus(
                interval: normalizedInterval,
                anchorDate: startOfAnchorDate,
                referenceDate: startOfReferenceDate,
                calendar: calendar
            )
        }
    }

    private static func weeklyStatus(
        interval: Int,
        anchorDate: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> BillingScheduleStatus? {
        let dayDifference = calendar.dateComponents([.day], from: anchorDate, to: referenceDate).day ?? 0
        let intervalInDays = interval * 7
        let intervalsElapsed = floorDiv(dayDifference, by: intervalInDays)

        guard let previousDate = calendar.date(byAdding: .day, value: intervalsElapsed * intervalInDays, to: anchorDate),
              let nextDate = calendar.date(byAdding: .day, value: intervalInDays, to: previousDate) else {
            return nil
        }

        return BillingScheduleStatus(
            previousDate: previousDate,
            nextDate: nextDate,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    private static func monthlyRecurringStatus(
        interval: Int,
        anchorDate: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> BillingScheduleStatus? {
        let anchorComponents = calendar.dateComponents([.year, .month, .day], from: anchorDate)
        let monthDifference = totalMonthDifference(from: anchorDate, to: referenceDate, calendar: calendar)
        var intervalsElapsed = floorDiv(monthDifference, by: interval)

        guard var previousDate = monthlyOccurrence(
            for: intervalsElapsed,
            interval: interval,
            anchorComponents: anchorComponents,
            calendar: calendar
        ) else {
            return nil
        }

        while previousDate > referenceDate {
            intervalsElapsed -= 1

            guard let adjustedDate = monthlyOccurrence(
                for: intervalsElapsed,
                interval: interval,
                anchorComponents: anchorComponents,
                calendar: calendar
            ) else {
                return nil
            }

            previousDate = adjustedDate
        }

        guard let nextDate = monthlyOccurrence(
            for: intervalsElapsed + 1,
            interval: interval,
            anchorComponents: anchorComponents,
            calendar: calendar
        ) else {
            return nil
        }

        return BillingScheduleStatus(
            previousDate: previousDate,
            nextDate: nextDate,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    private static func yearlyRecurringStatus(
        interval: Int,
        anchorDate: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> BillingScheduleStatus? {
        let anchorComponents = calendar.dateComponents([.year, .month, .day], from: anchorDate)
        let yearDifference = totalYearDifference(from: anchorDate, to: referenceDate, calendar: calendar)
        var intervalsElapsed = floorDiv(yearDifference, by: interval)

        guard var previousDate = yearlyOccurrence(
            for: intervalsElapsed,
            interval: interval,
            anchorComponents: anchorComponents,
            calendar: calendar
        ) else {
            return nil
        }

        while previousDate > referenceDate {
            intervalsElapsed -= 1

            guard let adjustedDate = yearlyOccurrence(
                for: intervalsElapsed,
                interval: interval,
                anchorComponents: anchorComponents,
                calendar: calendar
            ) else {
                return nil
            }

            previousDate = adjustedDate
        }

        guard let nextDate = yearlyOccurrence(
            for: intervalsElapsed + 1,
            interval: interval,
            anchorComponents: anchorComponents,
            calendar: calendar
        ) else {
            return nil
        }

        return BillingScheduleStatus(
            previousDate: previousDate,
            nextDate: nextDate,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    private static func monthlyOccurrence(
        for intervalIndex: Int,
        interval: Int,
        anchorComponents: DateComponents,
        calendar: Calendar
    ) -> Date? {
        guard let anchorYear = anchorComponents.year,
              let anchorMonth = anchorComponents.month,
              let anchorDay = anchorComponents.day else {
            return nil
        }

        let totalMonths = (anchorYear * 12) + (anchorMonth - 1) + (intervalIndex * interval)
        let year = floorDiv(totalMonths, by: 12)
        let month = totalMonths - (year * 12) + 1
        let resolvedDay = clampedDay(anchorDay, year: year, month: month, calendar: calendar)
        return calendar.date(from: DateComponents(year: year, month: month, day: resolvedDay))
    }

    private static func yearlyOccurrence(
        for intervalIndex: Int,
        interval: Int,
        anchorComponents: DateComponents,
        calendar: Calendar
    ) -> Date? {
        guard let anchorYear = anchorComponents.year,
              let anchorMonth = anchorComponents.month,
              let anchorDay = anchorComponents.day else {
            return nil
        }

        let year = anchorYear + (intervalIndex * interval)
        let resolvedDay = clampedDay(anchorDay, year: year, month: anchorMonth, calendar: calendar)
        return calendar.date(from: DateComponents(year: year, month: anchorMonth, day: resolvedDay))
    }

    private static func totalMonthDifference(from startDate: Date, to endDate: Date, calendar: Calendar) -> Int {
        let startComponents = calendar.dateComponents([.year, .month], from: startDate)
        let endComponents = calendar.dateComponents([.year, .month], from: endDate)

        let startMonthValue = (startComponents.year ?? 0) * 12 + (startComponents.month ?? 1)
        let endMonthValue = (endComponents.year ?? 0) * 12 + (endComponents.month ?? 1)
        return endMonthValue - startMonthValue
    }

    private static func totalYearDifference(from startDate: Date, to endDate: Date, calendar: Calendar) -> Int {
        let startYear = calendar.component(.year, from: startDate)
        let endYear = calendar.component(.year, from: endDate)
        return endYear - startYear
    }

    private static func floorDiv(_ dividend: Int, by divisor: Int) -> Int {
        let quotient = dividend / divisor
        let remainder = dividend % divisor

        if remainder != 0, dividend < 0 {
            return quotient - 1
        }

        return quotient
    }

    // Clamp recurring day values to the last valid day of the target month.
    private static func clampedDay(
        _ day: Int,
        year: Int,
        month: Int,
        calendar: Calendar
    ) -> Int {
        min(day, daysInMonth(year: year, month: month, calendar: calendar))
    }

    private static func daysInMonth(
        year: Int,
        month: Int,
        calendar: Calendar
    ) -> Int {
        let components = DateComponents(year: year, month: month)

        guard let date = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: date) else {
            return fallbackDayCount(in: month)
        }

        return range.count
    }

    private static func dayCount(
        in month: Int,
        year: Int,
        calendar: Calendar
    ) -> Int {
        daysInMonth(year: year, month: month, calendar: calendar)
    }

    private static func fallbackDayCount(in month: Int) -> Int {
        switch month {
        case 2:
            29
        case 4, 6, 9, 11:
            30
        default:
            31
        }
    }
}

extension Card {
    var normalizedClosingDay: Int? {
        BillingScheduleCalculator.normalizedDay(closingDay)
    }

    var normalizedWithdrawalDay: Int? {
        BillingScheduleCalculator.normalizedDay(withdrawalDay)
    }

    private func monthlyAnchorDate(
        day: Int?,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        guard let day else {
            return nil
        }

        return BillingScheduleCalculator.monthlyAnchorDate(
            day: day,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func closingAnchorDate(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        monthlyAnchorDate(
            day: closingDay,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func withdrawalAnchorDate(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        monthlyAnchorDate(
            day: withdrawalDay,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    var nextClosingStatus: BillingScheduleStatus? {
        closingStatus()
    }

    func closingStatus(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BillingScheduleStatus? {
        guard let closingAnchorDate = closingAnchorDate(referenceDate: referenceDate, calendar: calendar) else {
            return nil
        }

        return BillingScheduleCalculator.recurringStatus(
            unit: .month,
            interval: 1,
            anchorDate: closingAnchorDate,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    var nextWithdrawalStatus: BillingScheduleStatus? {
        withdrawalStatus()
    }

    func withdrawalStatus(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BillingScheduleStatus? {
        guard let withdrawalAnchorDate = withdrawalAnchorDate(referenceDate: referenceDate, calendar: calendar) else {
            return nil
        }

        return BillingScheduleCalculator.recurringStatus(
            unit: .month,
            interval: 1,
            anchorDate: withdrawalAnchorDate,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }
}

extension SubscriptionBillingFrequency {
    func scheduleDescription(
        anchorDate: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let anchorComponents = calendar.dateComponents([.year, .month, .day], from: anchorDate)
        let year = anchorComponents.year ?? calendar.component(.year, from: anchorDate)
        let month = anchorComponents.month ?? calendar.component(.month, from: anchorDate)
        let day = anchorComponents.day ?? calendar.component(.day, from: anchorDate)
        let weekdayText = anchorDate.formatted(.dateTime.weekday(.wide))
        let fullDateText = anchorDate.formatted(.dateTime.year().month(.defaultDigits).day(.defaultDigits))

        switch unit {
        case .week:
            if interval == 1 {
                return "毎週\(weekdayText)"
            }

            return "\(interval)週間ごと \(weekdayText) \(fullDateText)起点"
        case .month:
            if interval == 1 {
                return "毎月\(day)日"
            }

            return "\(interval)ヶ月ごと \(month)月\(day)日起点"
        case .year:
            if interval == 1 {
                return "毎年\(month)月\(day)日"
            }

            return "\(interval)年ごと \(year)年\(month)月\(day)日起点"
        }
    }
}

extension SubscriptionItem {
    var calendarEventRecurrence: CalendarEventRecurrence? {
        let interval = normalizedBillingInterval
        let calendar = Calendar.autoupdatingCurrent
        guard let billingAnchorDate else {
            return nil
        }
        let components = calendar.dateComponents([.month, .day], from: billingAnchorDate)

        switch billingUnit {
        case .week:
            return .weekly(interval: interval)
        case .month:
            guard let day = components.day else {
                return nil
            }

            return .monthly(interval: interval, dayOfMonth: day)
        case .year:
            guard let month = components.month,
                  let day = components.day else {
                return nil
            }

            return .yearly(interval: interval, month: month, dayOfMonth: day)
        }
    }

    var normalizedBillingInterval: Int {
        max(billingInterval, 1)
    }

    var billingScheduleText: String {
        guard let billingAnchorDate else {
            return missingBillingDateText
        }

        return billingFrequency.scheduleDescription(anchorDate: billingAnchorDate)
    }

    var nextBillingStatus: BillingScheduleStatus? {
        billingStatus()
    }

    var nextCancellationStatus: BillingScheduleStatus? {
        cancellationStatus()
    }

    func billingStatus(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BillingScheduleStatus? {
        guard let billingAnchorDate else {
            return nil
        }

        return BillingScheduleCalculator.recurringStatus(
            unit: billingUnit,
            interval: normalizedBillingInterval,
            anchorDate: billingAnchorDate,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func cancellationStatus(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> BillingScheduleStatus? {
        guard isActive,
              let cancellationScheduledDate else {
            return nil
        }

        let startOfReferenceDate = calendar.startOfDay(for: referenceDate)
        let targetDate = calendar.startOfDay(for: cancellationScheduledDate)
        guard targetDate > startOfReferenceDate else {
            return nil
        }

        let billingPreviousDate = billingStatus(referenceDate: referenceDate, calendar: calendar)?.previousDate
        let previousDate = if let billingPreviousDate, billingPreviousDate < targetDate {
            billingPreviousDate
        } else {
            startOfReferenceDate
        }

        return BillingScheduleStatus(
            previousDate: previousDate,
            nextDate: targetDate,
            referenceDate: startOfReferenceDate,
            calendar: calendar
        )
    }

    func isCancellationDue(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard isActive,
              let cancellationScheduledDate else {
            return false
        }

        return calendar.startOfDay(for: cancellationScheduledDate) <= calendar.startOfDay(for: referenceDate)
    }
}

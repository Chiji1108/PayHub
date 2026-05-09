//
//  SubscriptionLifecycleUpdater.swift
//  PayLog
//
//  Created by Codex on 2026/05/09.
//

import Foundation
import SwiftData

@MainActor
enum SubscriptionLifecycleUpdater {
    @discardableResult
    static func stopDueCancellations(using context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<SubscriptionItem>()
        let subscriptions = (try? context.fetch(descriptor)) ?? []
        let dueSubscriptions = subscriptions.filter { $0.isCancellationDue() }
        guard !dueSubscriptions.isEmpty else {
            return false
        }

        var nextInactiveSortOrder = context.nextSortOrder(
            for: SubscriptionItem.self,
            isActive: false
        )

        for subscription in dueSubscriptions {
            subscription.isActive = false
            subscription.cancellationScheduledDate = nil
            subscription.sortOrder = nextInactiveSortOrder
            nextInactiveSortOrder += 1
        }

        try? context.save()
        return true
    }
}

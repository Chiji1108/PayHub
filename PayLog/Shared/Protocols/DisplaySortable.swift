//
//  DisplaySortable.swift
//  PayLog
//
//  Created by Codex on 2026/03/28.
//

import Foundation
import SwiftData

protocol DisplaySortable: AnyObject, Activatable {
    var name: String { get }
    var createdAt: Date { get }
    var sortOrder: Int { get set }
}

extension Sequence where Element: DisplaySortable {
    func sortedForDisplay() -> [Element] {
        sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }

            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    @discardableResult
    func normalizeSortOrders() -> Bool {
        var didChange = false

        for (index, element) in enumerated() where element.sortOrder != index {
            element.sortOrder = index
            didChange = true
        }

        return didChange
    }
}

extension ModelContext {
    func nextSortOrder<Model: PersistentModel & DisplaySortable>(
        for modelType: Model.Type,
        isActive: Bool
    ) -> Int {
        let descriptor = FetchDescriptor<Model>()
        let currentMaxSortOrder = (try? fetch(descriptor))?
            .lazy
            .filter { $0.isActive == isActive }
            .map(\.sortOrder)
            .max() ?? -1
        return currentMaxSortOrder + 1
    }

    func firstSortOrder<Model: PersistentModel & DisplaySortable>(
        for modelType: Model.Type,
        isActive: Bool
    ) -> Int {
        let descriptor = FetchDescriptor<Model>()
        let matchingItems = (try? fetch(descriptor))?
            .filter { $0.isActive == isActive } ?? []

        for item in matchingItems {
            item.sortOrder += 1
        }

        return 0
    }
}

extension Bank: DisplaySortable {}
extension Card: DisplaySortable {}
extension ElectronicMoney: DisplaySortable {}
extension SubscriptionItem: DisplaySortable {}

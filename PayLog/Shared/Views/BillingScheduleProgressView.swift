//
//  BillingScheduleStatusSection.swift
//  PayLog
//
//  Created by Codex on 2026/03/28.
//

import SwiftUI

struct BillingScheduleProgressView: View {
    @Environment(\.editMode) private var editMode
    let scheduleLabel: String
    let countdownLabel: String
    let status: BillingScheduleStatus?
    let isActive: Bool
    let systemImage: String

    init(
        scheduleLabel: String,
        countdownLabel: String,
        status: BillingScheduleStatus?,
        isActive: Bool,
        systemImage: String = "repeat"
    ) {
        self.scheduleLabel = scheduleLabel
        self.countdownLabel = countdownLabel
        self.status = status
        self.isActive = isActive
        self.systemImage = systemImage
    }

    var body: some View {
        if editMode?.wrappedValue != .active {
            if let status {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: systemImage)
                            Text(status.nextDate.formatted(.dateTime.year().month(.defaultDigits).day(.defaultDigits).weekday(.abbreviated)))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        
                        Spacer()
                        
                        Text("\(countdownLabel)まであと\(status.daysUntilNext)日")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView(value: status.progress)
                        .tint(isActive ? .accentColor : .secondary)
                }
                .padding(.vertical, 4)
            } else {
                LabeledContent(scheduleLabel) {
                    Text("未設定")
                }
            }
        }
    }
}

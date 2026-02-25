import Foundation
import SwiftData
import SwiftUI

enum RepeatRule: String, Codable, CaseIterable {
    case none, daily, weeklyOnDay, monthlyOnOrdinal, yearly, everyWeekday, custom
}

enum RecurrenceUnit: String, CaseIterable {
    case day, week, month, year

    var displayName: String {
        switch self {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        }
    }

    var pluralDisplayName: String {
        switch self {
        case .day: return "days"
        case .week: return "weeks"
        case .month: return "months"
        case .year: return "years"
        }
    }
}

@Model
final class TaskBlock {
    var id: UUID
    var title: String
    var note: String
    var colorHex: String
    var startTime: Date
    var endTime: Date
    var isDone: Bool
    var repeatRuleRaw: String = "none"
    var doneDatesRaw: [String] = []
    var recurrenceInterval: Int = 1
    var recurrenceUnit: String = "week"
    var recurrenceWeekdays: String = ""
    var recurrenceEndDate: Date? = nil
    var recurrenceOccurrenceLimit: Int = 0
    var aiActivity: String = ""
    var aiLastDetected: Date? = nil

    @Transient
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    @Transient
    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRaw) ?? .none }
        set { repeatRuleRaw = newValue.rawValue }
    }

    @Transient
    var doneDates: Set<String> {
        get { Set(doneDatesRaw) }
        set { doneDatesRaw = Array(newValue).sorted() }
    }

    @Transient
    var recurrenceUnitEnum: RecurrenceUnit {
        get { RecurrenceUnit(rawValue: recurrenceUnit) ?? .week }
        set { recurrenceUnit = newValue.rawValue }
    }

    @Transient
    var recurrenceWeekdaySet: Set<Int> {
        get {
            guard !recurrenceWeekdays.isEmpty else { return [] }
            return Set(recurrenceWeekdays.split(separator: ",").compactMap { Int($0) })
        }
        set {
            recurrenceWeekdays = newValue.sorted().map(String.init).joined(separator: ",")
        }
    }

    var isRecurring: Bool {
        repeatRule != .none
    }

    init(
        title: String,
        note: String = "",
        colorHex: String = "#007AFF",
        startTime: Date,
        endTime: Date,
        isDone: Bool = false,
        repeatRule: RepeatRule = .none
    ) {
        self.id = UUID()
        self.title = title
        self.note = note
        self.colorHex = colorHex
        self.startTime = startTime
        self.endTime = endTime
        self.isDone = isDone
        self.repeatRuleRaw = repeatRule.rawValue
        self.doneDatesRaw = []
    }
}

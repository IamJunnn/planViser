import Foundation

struct TaskOccurrence: Identifiable {
    let id: String
    let sourceTask: TaskBlock
    let startTime: Date
    let endTime: Date
    let occurrenceDate: Date

    var isDone: Bool {
        get {
            if sourceTask.isRecurring {
                return sourceTask.doneDates.contains(dateKey)
            }
            return sourceTask.isDone
        }
    }

    var dateKey: String {
        Self.dateKeyFormatter.string(from: occurrenceDate)
    }

    func toggleDone() {
        if sourceTask.isRecurring {
            let key = dateKey
            if sourceTask.doneDates.contains(key) {
                sourceTask.doneDates.remove(key)
            } else {
                sourceTask.doneDates.insert(key)
            }
        } else {
            sourceTask.isDone.toggle()
        }
    }

    private static let dateKeyFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()
}

enum RecurrenceEngine {
    private static let calendar = Calendar.current

    static func occurrences(for task: TaskBlock, on date: Date) -> [TaskOccurrence] {
        guard occurs(task: task, on: date) else { return [] }
        let occ = makeOccurrence(task: task, on: date)
        return [occ]
    }

    static func allOccurrences(tasks: [TaskBlock], on date: Date) -> [TaskOccurrence] {
        tasks.flatMap { occurrences(for: $0, on: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    static func occurrenceCount(tasks: [TaskBlock], on date: Date) -> Int {
        tasks.reduce(0) { count, task in
            count + (occurs(task: task, on: date) ? 1 : 0)
        }
    }

    // MARK: - Private

    private static func occurs(task: TaskBlock, on date: Date) -> Bool {
        let rule = task.repeatRule

        if rule == .none {
            return calendar.isDate(task.startTime, inSameDayAs: date)
        }

        // Recurring: must be on or after start date
        guard calendar.compare(date, to: task.startTime, toGranularity: .day) != .orderedAscending else {
            return false
        }

        // Check end conditions for custom rules
        if rule == .custom {
            if let endDate = task.recurrenceEndDate,
               calendar.compare(date, to: endDate, toGranularity: .day) == .orderedDescending {
                return false
            }
            if task.recurrenceOccurrenceLimit > 0 {
                if let limitDate = effectiveEndDate(for: task),
                   calendar.compare(date, to: limitDate, toGranularity: .day) == .orderedDescending {
                    return false
                }
            }
        }

        guard matchesPattern(task: task, on: date) else { return false }
        return true
    }

    private static func matchesPattern(task: TaskBlock, on date: Date) -> Bool {
        switch task.repeatRule {
        case .none:
            return false
        case .daily:
            return true
        case .weeklyOnDay:
            return calendar.component(.weekday, from: date) == calendar.component(.weekday, from: task.startTime)
        case .monthlyOnOrdinal:
            let taskWeekday = calendar.component(.weekday, from: task.startTime)
            let taskOrdinal = calendar.component(.weekdayOrdinal, from: task.startTime)
            return calendar.component(.weekday, from: date) == taskWeekday
                && calendar.component(.weekdayOrdinal, from: date) == taskOrdinal
        case .yearly:
            return calendar.component(.month, from: date) == calendar.component(.month, from: task.startTime)
                && calendar.component(.day, from: date) == calendar.component(.day, from: task.startTime)
        case .everyWeekday:
            let weekday = calendar.component(.weekday, from: date)
            return weekday >= 2 && weekday <= 6
        case .custom:
            return matchesCustomPattern(task: task, on: date)
        }
    }

    private static func matchesCustomPattern(task: TaskBlock, on date: Date) -> Bool {
        let interval = max(1, task.recurrenceInterval)
        let startDay = calendar.startOfDay(for: task.startTime)
        let targetDay = calendar.startOfDay(for: date)

        switch task.recurrenceUnitEnum {
        case .day:
            let days = calendar.dateComponents([.day], from: startDay, to: targetDay).day ?? 0
            return days >= 0 && days % interval == 0

        case .week:
            let weekdays = task.recurrenceWeekdaySet
            let dateWeekday = calendar.component(.weekday, from: date)

            // If weekdays specified, check membership
            if !weekdays.isEmpty && !weekdays.contains(dateWeekday) {
                return false
            }

            // Check week interval
            let weeks = calendar.dateComponents([.weekOfYear], from: startDay, to: targetDay).weekOfYear ?? 0
            return weeks >= 0 && weeks % interval == 0

        case .month:
            let comps = calendar.dateComponents([.month], from: startDay, to: targetDay)
            let months = comps.month ?? 0
            guard months >= 0 && months % interval == 0 else { return false }

            // Same day-of-month (with end-of-month clamping)
            let startDOM = calendar.component(.day, from: task.startTime)
            let dateDOM = calendar.component(.day, from: date)
            let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
            let expectedDOM = min(startDOM, daysInMonth)
            return dateDOM == expectedDOM

        case .year:
            let comps = calendar.dateComponents([.year], from: startDay, to: targetDay)
            let years = comps.year ?? 0
            guard years >= 0 && years % interval == 0 else { return false }

            return calendar.component(.month, from: date) == calendar.component(.month, from: task.startTime)
                && calendar.component(.day, from: date) == calendar.component(.day, from: task.startTime)
        }
    }

    /// Compute the date of the Nth occurrence for occurrence-count end conditions.
    private static func effectiveEndDate(for task: TaskBlock) -> Date? {
        let limit = task.recurrenceOccurrenceLimit
        guard limit > 0 else { return nil }

        let startDay = calendar.startOfDay(for: task.startTime)
        var current = startDay
        var count = 0

        // Search forward up to a reasonable bound (10 years)
        let maxSearchDate = calendar.date(byAdding: .year, value: 10, to: startDay) ?? startDay

        while current <= maxSearchDate {
            if matchesCustomPattern(task: task, on: current) {
                count += 1
                if count >= limit {
                    return current
                }
            }
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
        }

        return nil // limit not reached within search window
    }

    private static func makeOccurrence(task: TaskBlock, on date: Date) -> TaskOccurrence {
        let cal = calendar
        let startComps = cal.dateComponents([.hour, .minute, .second], from: task.startTime)
        let endComps = cal.dateComponents([.hour, .minute, .second], from: task.endTime)

        let occStart = cal.date(bySettingHour: startComps.hour ?? 0,
                                minute: startComps.minute ?? 0,
                                second: startComps.second ?? 0,
                                of: date) ?? date
        let occEnd = cal.date(bySettingHour: endComps.hour ?? 0,
                              minute: endComps.minute ?? 0,
                              second: endComps.second ?? 0,
                              of: date) ?? date

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateKey = fmt.string(from: date)

        return TaskOccurrence(
            id: "\(task.id.uuidString)_\(dateKey)",
            sourceTask: task,
            startTime: occStart,
            endTime: occEnd,
            occurrenceDate: date
        )
    }
}

import Foundation

enum CalendarHelpers {
    private static let calendar = Calendar.current

    static func firstOfMonth(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    static func daysInMonth(for date: Date) -> Int {
        calendar.range(of: .day, in: .month, for: date)!.count
    }

    /// 1 = Sunday … 7 = Saturday (Calendar default)
    static func firstWeekdayOfMonth(for date: Date) -> Int {
        let first = firstOfMonth(for: date)
        return calendar.component(.weekday, from: first)
    }

    /// Returns a 6×7 grid of optional dates for the month containing `date`.
    static func calendarGrid(for date: Date) -> [[Date?]] {
        let first = firstOfMonth(for: date)
        let days = daysInMonth(for: date)
        let startOffset = firstWeekdayOfMonth(for: date) - 1 // 0-based offset

        var grid: [[Date?]] = []
        var dayCounter = 1

        for row in 0..<6 {
            var week: [Date?] = []
            for col in 0..<7 {
                let index = row * 7 + col
                if index < startOffset || dayCounter > days {
                    week.append(nil)
                } else {
                    week.append(calendar.date(byAdding: .day, value: dayCounter - 1, to: first))
                    dayCounter += 1
                }
            }
            grid.append(week)
        }
        return grid
    }

    static func offsetMonth(_ date: Date, by months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: date)!
    }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }

    static func monthTitle(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: date)
    }
}

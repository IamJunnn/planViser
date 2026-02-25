import Foundation
import SwiftData

@Model
final class WeeklyReview {
    var id: UUID
    var weekStartDate: Date
    var weekEndDate: Date
    var reflectionNote: String
    var nextWeekPriorities: String
    var aiSummary: String?
    var plannedTaskCount: Int
    var completedTaskCount: Int
    var meetingCount: Int
    var unfinishedTasks: String
    var createdAt: Date

    init(
        weekStartDate: Date,
        weekEndDate: Date,
        reflectionNote: String = "",
        nextWeekPriorities: String = "",
        aiSummary: String? = nil,
        plannedTaskCount: Int = 0,
        completedTaskCount: Int = 0,
        meetingCount: Int = 0,
        unfinishedTasks: String = "[]",
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.reflectionNote = reflectionNote
        self.nextWeekPriorities = nextWeekPriorities
        self.aiSummary = aiSummary
        self.plannedTaskCount = plannedTaskCount
        self.completedTaskCount = completedTaskCount
        self.meetingCount = meetingCount
        self.unfinishedTasks = unfinishedTasks
        self.createdAt = createdAt
    }

    /// Decode the unfinished tasks JSON string into an array of titles.
    @Transient
    var unfinishedTaskTitles: [String] {
        get {
            guard let data = unfinishedTasks.data(using: .utf8),
                  let titles = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return titles
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                unfinishedTasks = json
            }
        }
    }

    var completionPercentage: Double {
        guard plannedTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(plannedTaskCount) * 100
    }

    var weekLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "\(fmt.string(from: weekStartDate)) – \(fmt.string(from: weekEndDate))"
    }
}

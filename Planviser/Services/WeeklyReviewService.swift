import Foundation
import SwiftData
import UserNotifications

struct WeeklyStats {
    let planned: Int
    let completed: Int
    let unfinishedTitles: [String]
    let meetingCount: Int
    let weekStart: Date
    let weekEnd: Date
}

final class WeeklyReviewService {
    static let shared = WeeklyReviewService()
    private init() {}

    private let calendar = Calendar.current

    // MARK: - Stats Computation

    /// Compute stats for the week ending on `weekEnd` (Sunday).
    func computeStats(weekEnd: Date, allTasks: [TaskBlock], allMeetings: [MeetingInvite]) -> WeeklyStats {
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: weekEnd))!

        var totalPlanned = 0
        var totalCompleted = 0
        var unfinished: [String] = []
        var meetingCount = 0

        // Iterate Mon–Sun (7 days)
        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else { continue }

            let occurrences = RecurrenceEngine.allOccurrences(tasks: allTasks, on: day)
            totalPlanned += occurrences.count

            for occ in occurrences {
                if occ.isDone {
                    totalCompleted += 1
                } else {
                    // Only count as unfinished if the day is in the past or today
                    if calendar.compare(day, to: Date.now, toGranularity: .day) != .orderedDescending {
                        if !unfinished.contains(occ.sourceTask.title) {
                            unfinished.append(occ.sourceTask.title)
                        }
                    }
                }
            }

            // Count meetings for this day
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            meetingCount += allMeetings.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }.count
        }

        return WeeklyStats(
            planned: totalPlanned,
            completed: totalCompleted,
            unfinishedTitles: unfinished,
            meetingCount: meetingCount,
            weekStart: weekStart,
            weekEnd: weekEnd
        )
    }

    // MARK: - AI Summary

    func generateAISummary(stats: WeeklyStats, reflection: String, priorities: String) async throws -> String {
        guard let apiKey = ClaudeVisionService.shared.getAPIKey(), !apiKey.isEmpty else {
            throw APIError.unauthorized
        }

        let prompt = """
        You are a productivity coach. Based on the following weekly review data, write a brief, \
        encouraging summary (3-5 sentences) with one actionable suggestion for next week.

        Week: \(formatDate(stats.weekStart)) – \(formatDate(stats.weekEnd))
        Tasks planned: \(stats.planned)
        Tasks completed: \(stats.completed)
        Completion rate: \(stats.planned > 0 ? Int(Double(stats.completed) / Double(stats.planned) * 100) : 0)%
        Meetings attended: \(stats.meetingCount)
        Unfinished tasks: \(stats.unfinishedTitles.joined(separator: ", "))

        User's reflection: \(reflection.isEmpty ? "(none provided)" : reflection)
        Next week priorities: \(priorities.isEmpty ? "(none provided)" : priorities)
        """

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "max_tokens": 512,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.httpError(code)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw APIError.decodingError
        }

        return text
    }

    // MARK: - Review Prompt Check

    func shouldPromptReview(existingReviews: [WeeklyReview]) -> Bool {
        let weekday = calendar.component(.weekday, from: Date.now)
        guard weekday == 1 else { return false } // 1 = Sunday

        let todayStart = calendar.startOfDay(for: Date.now)
        return !existingReviews.contains { calendar.isDate($0.weekEndDate, inSameDayAs: todayStart) }
    }

    /// Returns the Monday..Sunday range for the current week (ending today if Sunday, else last Sunday).
    func currentWeekRange() -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: Date.now)
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        // We want Mon–Sun. If today is Sunday (1), end=today, start=today-6.
        // Otherwise, go back to previous Sunday as end, and the Monday before that as start.
        let sundayEnd: Date
        if weekday == 1 {
            sundayEnd = today
        } else {
            // Go back to previous Sunday
            sundayEnd = calendar.date(byAdding: .day, value: -(weekday - 1), to: today)!
        }
        let mondayStart = calendar.date(byAdding: .day, value: -6, to: sundayEnd)!
        return (mondayStart, sundayEnd)
    }

    // MARK: - Sunday Notification

    func scheduleSundayNotification() {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }

            center.removePendingNotificationRequests(withIdentifiers: ["weeklyReview"])

            let content = UNMutableNotificationContent()
            content.title = "Weekly Review"
            content.body = "Time to reflect on your week and plan ahead!"
            content.sound = .default

            let hour = UserDefaults.standard.integer(forKey: "reviewNotificationHour")
            let minute = UserDefaults.standard.integer(forKey: "reviewNotificationMinute")

            var dateComponents = DateComponents()
            dateComponents.weekday = 1 // Sunday
            dateComponents.hour = hour > 0 ? hour : 10
            dateComponents.minute = minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "weeklyReview", content: content, trigger: trigger)

            center.add(request) { error in
                if let error {
                    print("[WeeklyReview] Failed to schedule notification: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

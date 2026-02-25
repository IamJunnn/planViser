import SwiftUI
import SwiftData

struct WeeklyReviewView: View {
    @Query(sort: \WeeklyReview.weekEndDate, order: .reverse)
    private var reviews: [WeeklyReview]

    @Query(sort: \TaskBlock.startTime)
    private var allTasks: [TaskBlock]

    @Query(sort: \MeetingInvite.startTime)
    private var allMeetings: [MeetingInvite]

    @Environment(\.modelContext) private var modelContext

    @State private var selectedReview: WeeklyReview?
    @State private var isCreatingNew = false
    @State private var stats: WeeklyStats?

    // Editor state
    @State private var reflectionText = ""
    @State private var prioritiesText = ""
    @State private var aiSummary: String?
    @State private var isGeneratingAI = false
    @State private var aiError: String?

    private let service = WeeklyReviewService.shared

    var body: some View {
        HSplitView {
            // Left sidebar: past reviews list
            VStack(spacing: 0) {
                HStack {
                    Text("Weekly Reviews")
                        .scaledFont(.headline)
                    Spacer()
                    Button {
                        startNewReview()
                    } label: {
                        Image(systemName: "plus")
                            .scaledFont(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("New Review")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                if reviews.isEmpty && !isCreatingNew {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .scaledFont(size: 28)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No reviews yet")
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)
                        Button("Start Your First Review") {
                            startNewReview()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: Binding(
                        get: { isCreatingNew ? nil : selectedReview?.id },
                        set: { newID in
                            if let newID, let review = reviews.first(where: { $0.id == newID }) {
                                selectedReview = review
                                isCreatingNew = false
                            }
                        }
                    )) {
                        if isCreatingNew {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("New Review")
                                        .scaledFont(.subheadline, weight: .medium)
                                    if let s = stats {
                                        Text("\(s.planned) tasks, \(s.meetingCount) meetings")
                                            .scaledFont(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                            .listRowBackground(Color.accentColor.opacity(0.12))
                        }

                        ForEach(reviews) { review in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(review.weekLabel)
                                        .scaledFont(.subheadline, weight: .medium)
                                    Text("\(review.completedTaskCount)/\(review.plannedTaskCount) tasks")
                                        .scaledFont(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("\(Int(review.completionPercentage))%")
                                    .scaledFont(.caption, weight: .medium)
                                    .foregroundColor(review.completionPercentage >= 80 ? .green : (review.completionPercentage >= 50 ? .orange : .red))
                            }
                            .padding(.vertical, 2)
                            .tag(review.id)
                        }
                    }
                }
            }
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            // Right detail
            if isCreatingNew {
                newReviewEditor
            } else if let review = selectedReview {
                pastReviewDetail(review)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .scaledFont(size: 36)
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Select a review or start a new one")
                        .scaledFont(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - New Review Editor

    private var newReviewEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("New Weekly Review")
                        .scaledFont(.title2, weight: .semibold)
                    Spacer()
                    Button("Cancel") {
                        isCreatingNew = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                if let s = stats {
                    // Week range
                    Text(weekRangeLabel(start: s.weekStart, end: s.weekEnd))
                        .scaledFont(.subheadline)
                        .foregroundColor(.secondary)

                    // Stat cards
                    HStack(spacing: 12) {
                        statCard(title: "Planned", value: "\(s.planned)", icon: "list.bullet", color: .blue)
                        statCard(title: "Completed", value: "\(s.completed)", icon: "checkmark.circle", color: .green)
                        statCard(title: "Meetings", value: "\(s.meetingCount)", icon: "person.2", color: .purple)
                        statCard(title: "Completion", value: "\(s.planned > 0 ? Int(Double(s.completed) / Double(s.planned) * 100) : 0)%", icon: "chart.pie", color: completionColor(s))
                    }

                    // Unfinished tasks
                    if !s.unfinishedTitles.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Unfinished Tasks")
                                .scaledFont(.subheadline, weight: .medium)
                            ForEach(s.unfinishedTitles, id: \.self) { title in
                                HStack(spacing: 6) {
                                    Image(systemName: "circle")
                                        .scaledFont(size: 9)
                                        .foregroundColor(.orange)
                                    Text(title)
                                        .scaledFont(.caption)
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
                    }
                }

                Divider()

                // Reflection
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reflection")
                        .scaledFont(.subheadline, weight: .medium)
                    Text("What went well? What was challenging?")
                        .scaledFont(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $reflectionText)
                        .scaledFont(.body)
                        .frame(minHeight: 80)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                }

                // Priorities
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next Week Priorities")
                        .scaledFont(.subheadline, weight: .medium)
                    Text("What are your top priorities for next week?")
                        .scaledFont(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $prioritiesText)
                        .scaledFont(.body)
                        .frame(minHeight: 80)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                }

                // AI Summary
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("AI Summary")
                            .scaledFont(.subheadline, weight: .medium)
                        Spacer()
                        Button {
                            generateAISummary()
                        } label: {
                            HStack(spacing: 4) {
                                if isGeneratingAI {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(isGeneratingAI ? "Generating..." : "Generate AI Summary")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isGeneratingAI || stats == nil)
                    }

                    if let summary = aiSummary {
                        Text(summary)
                            .scaledFont(.body)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.08)))
                    }

                    if let error = aiError {
                        Text(error)
                            .scaledFont(.caption)
                            .foregroundColor(.red)
                    }
                }

                Divider()

                // Save button
                HStack {
                    Spacer()
                    Button("Save Review") {
                        saveReview()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(stats == nil)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Past Review Detail

    private func pastReviewDetail(_ review: WeeklyReview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(review.weekLabel)
                        .scaledFont(.title2, weight: .semibold)
                    Spacer()
                    Button(role: .destructive) {
                        deleteReview(review)
                    } label: {
                        Image(systemName: "trash")
                            .scaledFont(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }

                // Stats
                HStack(spacing: 12) {
                    statCard(title: "Planned", value: "\(review.plannedTaskCount)", icon: "list.bullet", color: .blue)
                    statCard(title: "Completed", value: "\(review.completedTaskCount)", icon: "checkmark.circle", color: .green)
                    statCard(title: "Meetings", value: "\(review.meetingCount)", icon: "person.2", color: .purple)
                    statCard(title: "Completion", value: "\(Int(review.completionPercentage))%", icon: "chart.pie", color: review.completionPercentage >= 80 ? .green : (review.completionPercentage >= 50 ? .orange : .red))
                }

                // Unfinished
                if !review.unfinishedTaskTitles.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unfinished Tasks")
                            .scaledFont(.subheadline, weight: .medium)
                        ForEach(review.unfinishedTaskTitles, id: \.self) { title in
                            HStack(spacing: 6) {
                                Image(systemName: "circle")
                                    .scaledFont(size: 9)
                                    .foregroundColor(.orange)
                                Text(title)
                                    .scaledFont(.caption)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
                }

                Divider()

                if !review.reflectionNote.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reflection")
                            .scaledFont(.subheadline, weight: .medium)
                        Text(review.reflectionNote)
                            .scaledFont(.body)
                            .foregroundColor(.secondary)
                    }
                }

                if !review.nextWeekPriorities.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next Week Priorities")
                            .scaledFont(.subheadline, weight: .medium)
                        Text(review.nextWeekPriorities)
                            .scaledFont(.body)
                            .foregroundColor(.secondary)
                    }
                }

                if let summary = review.aiSummary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Summary")
                            .scaledFont(.subheadline, weight: .medium)
                        Text(summary)
                            .scaledFont(.body)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.08)))
                    }
                }

                Text("Created \(review.createdAt, style: .date)")
                    .scaledFont(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(20)
        }
    }

    // MARK: - Helpers

    private func startNewReview() {
        let range = service.currentWeekRange()
        stats = service.computeStats(weekEnd: range.end, allTasks: allTasks, allMeetings: allMeetings)
        reflectionText = ""
        prioritiesText = ""
        aiSummary = nil
        aiError = nil
        isCreatingNew = true
        selectedReview = nil
    }

    private func generateAISummary() {
        guard let s = stats else { return }
        isGeneratingAI = true
        aiError = nil

        Task {
            do {
                let summary = try await service.generateAISummary(
                    stats: s,
                    reflection: reflectionText,
                    priorities: prioritiesText
                )
                await MainActor.run {
                    aiSummary = summary
                    isGeneratingAI = false
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    isGeneratingAI = false
                }
            }
        }
    }

    private func saveReview() {
        guard let s = stats else { return }

        let review = WeeklyReview(
            weekStartDate: s.weekStart,
            weekEndDate: s.weekEnd,
            reflectionNote: reflectionText,
            nextWeekPriorities: prioritiesText,
            aiSummary: aiSummary,
            plannedTaskCount: s.planned,
            completedTaskCount: s.completed,
            meetingCount: s.meetingCount,
            unfinishedTasks: {
                if let data = try? JSONEncoder().encode(s.unfinishedTitles),
                   let json = String(data: data, encoding: .utf8) {
                    return json
                }
                return "[]"
            }()
        )

        modelContext.insert(review)
        try? modelContext.save()

        isCreatingNew = false
        selectedReview = review
    }

    private func deleteReview(_ review: WeeklyReview) {
        if selectedReview?.id == review.id {
            selectedReview = nil
        }
        modelContext.delete(review)
        try? modelContext.save()
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .scaledFont(size: 16)
                .foregroundColor(color)
            Text(value)
                .scaledFont(.title3, weight: .semibold)
            Text(title)
                .scaledFont(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.08)))
    }

    private func completionColor(_ stats: WeeklyStats) -> Color {
        let pct = stats.planned > 0 ? Double(stats.completed) / Double(stats.planned) * 100 : 0
        if pct >= 80 { return .green }
        if pct >= 50 { return .orange }
        return .red
    }

    private func weekRangeLabel(start: Date, end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMM d"
        return "\(fmt.string(from: start)) – \(fmt.string(from: end))"
    }
}

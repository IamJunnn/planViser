import Foundation
import SwiftData
import Combine
import AppKit

struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let summary: String
    let matchedTaskTitle: String?
    let confidence: Double
}

@MainActor
final class ScreenMonitorManager: ObservableObject {
    static let shared = ScreenMonitorManager()

    @Published var isEnabled = false
    @Published var intervalMinutes = 5
    @Published var isCapturing = false
    @Published var hasPermission = false
    @Published var activityLog: [ActivityLogEntry] = []
    @Published var lastError: String?

    private var timer: Timer?
    private var modelContext: ModelContext?

    private init() {}

    // MARK: - Lifecycle

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        Task {
            hasPermission = await ScreenCaptureService.shared.checkPermission()
        }
    }

    func toggle() {
        isEnabled.toggle()
        if isEnabled {
            scheduleTimer()
        } else {
            stopTimer()
        }
    }

    func setInterval(minutes: Int) {
        intervalMinutes = min(30, max(1, minutes))
        if isEnabled {
            scheduleTimer()
        }
    }

    // MARK: - Timer

    private func scheduleTimer() {
        stopTimer()
        let interval = TimeInterval(intervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.captureAndAnalyzeNow()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Capture & Analyze

    func captureAndAnalyzeNow() async {
        guard !isCapturing else { return }
        guard let modelContext = modelContext else { return }
        guard ClaudeVisionService.shared.getAPIKey() != nil else {
            lastError = "No API key configured"
            return
        }

        isCapturing = true
        lastError = nil
        defer { isCapturing = false }

        do {
            // Fetch today's tasks
            let todayTasks = fetchTodayTasks(modelContext: modelContext)
            guard !todayTasks.isEmpty else {
                lastError = "No tasks scheduled for today"
                return
            }

            // Build task summaries
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let summaries = todayTasks.map { task in
                TaskSummary(
                    id: task.id.uuidString,
                    title: task.title,
                    startTime: formatter.string(from: task.startTime),
                    endTime: formatter.string(from: task.endTime)
                )
            }

            // Capture screenshot
            let imageData = try await ScreenCaptureService.shared.captureScreen()

            // Send to Claude
            let analysis = try await ClaudeVisionService.shared.analyzeScreen(
                imageData: imageData,
                tasks: summaries
            )

            // Update matched task
            if let taskIdString = analysis.currentTaskId,
               let taskUUID = UUID(uuidString: taskIdString),
               let matchedTask = todayTasks.first(where: { $0.id == taskUUID }) {
                matchedTask.aiActivity = analysis.activitySummary
                matchedTask.aiLastDetected = Date.now
                try? modelContext.save()
            }

            // Log the activity
            let entry = ActivityLogEntry(
                timestamp: Date.now,
                summary: analysis.activitySummary,
                matchedTaskTitle: analysis.currentTaskId.flatMap { idStr in
                    UUID(uuidString: idStr).flatMap { uuid in
                        todayTasks.first(where: { $0.id == uuid })?.title
                    }
                },
                confidence: analysis.confidence
            )
            activityLog.insert(entry, at: 0)
            if activityLog.count > 50 {
                activityLog = Array(activityLog.prefix(50))
            }

        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func fetchTodayTasks(modelContext: ModelContext) -> [TaskBlock] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date.now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        let descriptor = FetchDescriptor<TaskBlock>(
            predicate: #Predicate<TaskBlock> { task in
                task.startTime >= startOfDay && task.startTime < endOfDay
            },
            sortBy: [SortDescriptor(\.startTime)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Permission

    func requestPermission() async {
        hasPermission = await ScreenCaptureService.shared.checkPermission()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

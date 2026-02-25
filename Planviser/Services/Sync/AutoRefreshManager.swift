import Foundation
import SwiftData
import Combine

final class AutoRefreshManager: ObservableObject {
    static let shared = AutoRefreshManager()

    @Published var isEnabled = true
    @Published var intervalMinutes = 1

    private var timer: Timer?
    private var modelContext: ModelContext?

    private init() {}

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Sync immediately on launch, then schedule recurring timer
        refresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setInterval(minutes: Int) {
        intervalMinutes = minutes
        if isEnabled {
            scheduleTimer()
        }
    }

    func toggle() {
        isEnabled.toggle()
        if isEnabled {
            scheduleTimer()
        } else {
            stop()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()

        let interval = TimeInterval(intervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let modelContext = modelContext else { return }

        DispatchQueue.main.async {
            EmailSyncService.shared.syncAll(modelContext: modelContext)
        }
    }
}

import Foundation
import LocalAuthentication
import Combine

enum UnlockDuration: Int, CaseIterable, Identifiable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case untilAppCloses = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .untilAppCloses: return "Until app closes"
        }
    }
}

@MainActor
final class NoteUnlockManager: ObservableObject {
    static let shared = NoteUnlockManager()

    @Published var isUnlocked = false
    @Published var authError: String?

    private var lockTimer: Timer?

    private init() {}

    var selectedDuration: UnlockDuration {
        let raw = UserDefaults.standard.integer(forKey: "noteUnlockDuration")
        return UnlockDuration(rawValue: raw) ?? .fifteenMinutes
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = error?.localizedDescription ?? "Biometric authentication unavailable"
            return
        }

        authError = nil

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your secure notes") { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isUnlocked = true
                    self?.authError = nil
                    self?.startLockTimer()
                } else {
                    self?.authError = error?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }

    func lock() {
        isUnlocked = false
        authError = nil
        lockTimer?.invalidate()
        lockTimer = nil
    }

    private func startLockTimer() {
        lockTimer?.invalidate()
        lockTimer = nil

        let duration = selectedDuration
        guard duration != .untilAppCloses else { return }

        let interval = TimeInterval(duration.rawValue * 60)
        lockTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.lock()
            }
        }
    }
}

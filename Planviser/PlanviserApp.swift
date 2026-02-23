import SwiftUI
import SwiftData

@main
struct PlanviserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: EmailAccount.self, EmailMessage.self, MeetingInvite.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra("Planviser", systemImage: "calendar.badge.clock") {
            ContentView()
                .onAppear {
                    AutoRefreshManager.shared.start(modelContext: container.mainContext)
                }
        }
        .menuBarExtraStyle(.window)
        .modelContainer(container)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if GmailAuthService.shared.handleRedirect(url: url) {
                return
            }
        }
    }
}

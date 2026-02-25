import SwiftUI
import SwiftData

@main
struct PlanviserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: EmailAccount.self, EmailMessage.self, MeetingInvite.self, TaskBlock.self, WeeklyReview.self, SecureNote.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.modelContext, container.mainContext)
                .onAppear {
                    reconcileAccounts(modelContext: container.mainContext)
                    EmailSyncService.shared.deduplicateMeetings(modelContext: container.mainContext)
                    AutoRefreshManager.shared.start(modelContext: container.mainContext)
                    ScreenMonitorManager.shared.start(modelContext: container.mainContext)
                    WeeklyReviewService.shared.scheduleSundayNotification()
                }
        }
        .modelContainer(container)
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
    }

    /// Ensure every authenticated account has a matching SwiftData EmailAccount record.
    private func reconcileAccounts(modelContext: ModelContext) {
        let existing = (try? modelContext.fetch(FetchDescriptor<EmailAccount>())) ?? []
        print("[Reconcile] Existing SwiftData accounts: \(existing.map { "\($0.provider.rawValue):\($0.email)" })")

        let gmailAccounts = GmailAuthService.shared.connectedAccounts
        let outlookAccounts = OutlookAuthService.shared.connectedAccounts
        let imapAccounts = IMAPAuthService.shared.connectedAccounts
        print("[Reconcile] Auth accounts — Gmail: \(gmailAccounts.count), Outlook: \(outlookAccounts.count), IMAP: \(imapAccounts.count)")

        var inserted = 0

        for info in gmailAccounts {
            let alreadyExists = existing.contains { $0.provider == .gmail && $0.email == info.email }
            if !alreadyExists {
                let account = EmailAccount(provider: .gmail, email: info.email, displayName: info.displayName)
                modelContext.insert(account)
                inserted += 1
                print("[Reconcile] Inserted Gmail: \(info.email)")
            }
        }
        for info in outlookAccounts {
            let alreadyExists = existing.contains { $0.provider == .outlook && $0.email == info.email }
            if !alreadyExists {
                let account = EmailAccount(provider: .outlook, email: info.email, displayName: info.displayName)
                modelContext.insert(account)
                inserted += 1
                print("[Reconcile] Inserted Outlook: \(info.email)")
            }
        }
        for info in imapAccounts {
            let alreadyExists = existing.contains { $0.provider == .imap && $0.email == info.email }
            if !alreadyExists {
                let account = EmailAccount(provider: .imap, email: info.email, displayName: info.displayName)
                modelContext.insert(account)
                inserted += 1
                print("[Reconcile] Inserted IMAP: \(info.email)")
            }
        }

        if inserted > 0 {
            do {
                try modelContext.save()
                print("[Reconcile] Saved \(inserted) new account(s)")
            } catch {
                print("[Reconcile] Save FAILED: \(error)")
            }
        } else {
            print("[Reconcile] No new accounts to insert")
        }
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

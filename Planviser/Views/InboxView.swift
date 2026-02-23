import SwiftUI
import SwiftData

enum InboxFilter: String, CaseIterable {
    case all = "All"
    case gmail = "Gmail"
    case outlook = "Outlook"
}

struct InboxView: View {
    @Query(sort: \EmailMessage.date, order: .reverse)
    private var allMessages: [EmailMessage]

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var syncService = EmailSyncService.shared
    @State private var selectedFilter: InboxFilter = .all

    private var filteredMessages: [EmailMessage] {
        switch selectedFilter {
        case .all:
            return allMessages
        case .gmail:
            return allMessages.filter { $0.account?.provider == .gmail }
        case .outlook:
            return allMessages.filter { $0.account?.provider == .outlook }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar + refresh
            HStack {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) {
                        selectedFilter = filter
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(selectedFilter == filter ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(6)
                    .foregroundColor(selectedFilter == filter ? .accentColor : .secondary)
                    .font(.caption)
                }

                Spacer()

                Button {
                    syncService.syncAll(modelContext: modelContext)
                } label: {
                    if syncService.isSyncing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .disabled(syncService.isSyncing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Message list
            if filteredMessages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No emails yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Connect an account in Settings to get started.")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredMessages) { message in
                    EmailRowView(message: message)
                }
            }

            // Error bar
            if let error = syncService.lastError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                    Text(error)
                        .font(.caption2)
                    Spacer()
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
            }
        }
    }
}

struct EmailRowView: View {
    let message: EmailMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Provider badge
                if let provider = message.account?.provider {
                    ProviderBadge(provider: provider)
                }

                Text(message.sender)
                    .font(.headline)
                    .lineLimit(1)

                if !message.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }

                Spacer()

                if message.hasCalendarInvite {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                Text(message.date, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(message.subject)
                .font(.subheadline)
                .lineLimit(1)
            Text(message.preview)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct ProviderBadge: View {
    let provider: EmailProvider

    var body: some View {
        Text(provider == .gmail ? "G" : "O")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 16, height: 16)
            .background(provider == .gmail ? Color.red : Color.blue)
            .cornerRadius(3)
    }
}

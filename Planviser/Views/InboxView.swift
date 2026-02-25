import SwiftUI
import SwiftData
import WebKit

enum InboxFilter: String, CaseIterable {
    case all = "All"
    case gmail = "Gmail"
    case outlook = "Outlook"
    case imap = "IMAP"
}

struct InboxView: View {
    @Query(sort: \EmailMessage.date, order: .reverse)
    private var allMessages: [EmailMessage]

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var syncService = EmailSyncService.shared
    @State private var selectedFilter: InboxFilter = .all
    @State private var selectedMessage: EmailMessage?

    private var filteredMessages: [EmailMessage] {
        switch selectedFilter {
        case .all:
            return allMessages
        case .gmail:
            return allMessages.filter { $0.account?.provider == .gmail }
        case .outlook:
            return allMessages.filter { $0.account?.provider == .outlook }
        case .imap:
            return allMessages.filter { $0.account?.provider == .imap }
        }
    }

    var body: some View {
        HSplitView {
            // MARK: - Left: Email List
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
                        .scaledFont(.caption)
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
                                .scaledFont(.caption)
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
                            .scaledFont(size: 36)
                            .foregroundColor(.secondary)
                        Text("No emails yet")
                            .scaledFont(.headline)
                            .foregroundColor(.secondary)
                        Text("Connect an account in Settings to get started.")
                            .scaledFont(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredMessages, selection: $selectedMessage) { message in
                        EmailRowView(message: message) {
                            syncService.deleteMessage(message, modelContext: modelContext)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            syncService.markAsRead(message: message, modelContext: modelContext)
                            selectedMessage = message
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                syncService.deleteMessage(message, modelContext: modelContext)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedMessage?.id == message.id ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                    }
                }

                // Error bar
                if let error = syncService.lastError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .scaledFont(.caption2)
                        Text(error)
                            .scaledFont(.caption2)
                        Spacer()
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.1))
                }
            }
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

            // MARK: - Right: Email Detail
            if let message = selectedMessage {
                EmailDetailView(message: message)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "envelope.open")
                        .scaledFont(size: 40)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select an email to read")
                        .scaledFont(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct EmailRowView: View {
    let message: EmailMessage
    var onDelete: (() -> Void)? = nil
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Provider badge
                if let provider = message.account?.provider {
                    ProviderBadge(provider: provider, colorOverride: message.account?.color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(message.sender)
                        .scaledFont(.headline)
                        .lineLimit(1)
                    if let email = message.account?.email {
                        Text("to \(email)")
                            .scaledFont(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if !message.isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }

                Spacer()

                if message.hasCalendarInvite {
                    Image(systemName: "calendar")
                        .scaledFont(.caption2)
                        .foregroundColor(.orange)
                }

                // Trash button — visible on hover
                if isHovered, let onDelete = onDelete {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .scaledFont(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete from server")
                }

                Text(message.date, style: .relative)
                    .scaledFont(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(message.subject)
                .scaledFont(.subheadline)
                .lineLimit(1)
            Text(message.preview)
                .scaledFont(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Email Detail View

struct EmailDetailView: View {
    let message: EmailMessage

    var body: some View {
        VStack(spacing: 0) {
            // Header area (scrollable if needed, but usually short)
            VStack(alignment: .leading, spacing: 12) {
                // Subject
                Text(message.subject)
                    .scaledFont(.title2, weight: .bold)
                    .textSelection(.enabled)

                Divider()

                // Sender info
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(avatarColor)
                            .frame(width: 40, height: 40)
                        Text(avatarInitial)
                            .scaledFont(size: 16, weight: .semibold)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(message.sender)
                                .scaledFont(.headline)
                            if let provider = message.account?.provider {
                                ProviderBadge(provider: provider, colorOverride: message.account?.color)
                            }
                        }
                        Text(message.senderEmail)
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(message.date, format: .dateTime.month().day().year())
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)
                        Text(message.date, format: .dateTime.hour().minute())
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let email = message.account?.email {
                    Text("to \(email)")
                        .scaledFont(.caption)
                        .foregroundColor(.secondary)
                }

                if message.hasCalendarInvite {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundColor(.orange)
                        Text("This email contains a calendar invite")
                            .scaledFont(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                Divider()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 8)

            // Body area
            if let htmlBody = message.htmlBody, !htmlBody.isEmpty {
                EmailHTMLView(html: htmlBody)
            } else {
                ScrollView {
                    Text(message.preview)
                        .scaledFont(.body)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var avatarInitial: String {
        String(message.sender.prefix(1)).uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .teal, .indigo]
        let hash = abs(message.sender.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - HTML Email Renderer

struct EmailHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload if HTML actually changed
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        // Open links in default browser instead of inside the WebView
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

struct ProviderBadge: View {
    let provider: EmailProvider
    var colorOverride: Color? = nil

    private var badgeColor: Color {
        if let color = colorOverride { return color }
        switch provider {
        case .gmail: return .red
        case .outlook: return .blue
        case .imap: return .teal
        }
    }

    private var badgeLetter: String {
        switch provider {
        case .gmail: return "G"
        case .outlook: return "O"
        case .imap: return "I"
        }
    }

    var body: some View {
        Text(badgeLetter)
            .scaledFont(size: 9, weight: .bold)
            .foregroundColor(.white)
            .frame(width: 16, height: 16)
            .background(badgeColor)
            .cornerRadius(3)
    }
}

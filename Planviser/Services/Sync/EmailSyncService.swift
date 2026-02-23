import Foundation
import SwiftData

final class EmailSyncService: ObservableObject {
    static let shared = EmailSyncService()

    @Published var isSyncing = false
    @Published var lastError: String?

    private init() {}

    func syncGmail(modelContext: ModelContext) {
        guard !isSyncing else { return }

        DispatchQueue.main.async { self.isSyncing = true }

        GmailAuthService.shared.getValidAccessToken { [weak self] token in
            guard let self = self, let token = token else {
                DispatchQueue.main.async {
                    self?.isSyncing = false
                    self?.lastError = "Not authenticated"
                }
                return
            }

            self.fetchGmailMessages(accessToken: token, modelContext: modelContext)
        }
    }

    private func fetchGmailMessages(accessToken: String, modelContext: ModelContext) {
        GmailAPIService.shared.fetchMessageList(accessToken: accessToken) { [weak self] result in
            switch result {
            case .success(let listResponse):
                guard let messageRefs = listResponse.messages else {
                    DispatchQueue.main.async {
                        self?.isSyncing = false
                    }
                    return
                }

                let group = DispatchGroup()

                for ref in messageRefs.prefix(50) {
                    group.enter()
                    GmailAPIService.shared.fetchMessageDetail(
                        accessToken: accessToken,
                        messageId: ref.id
                    ) { detailResult in
                        if case .success(let gmailMessage) = detailResult {
                            self?.processGmailMessage(gmailMessage, accessToken: accessToken, modelContext: modelContext)
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    self?.updateGmailSyncDate(modelContext: modelContext)
                    self?.processCalendarInvites(modelContext: modelContext)
                    self?.isSyncing = false
                    self?.lastError = nil
                }

            case .failure(let error):
                if case APIError.httpError(401) = error {
                    // Token expired, try refresh
                    GmailAuthService.shared.refreshAccessToken { [weak self] newToken in
                        if let newToken = newToken {
                            self?.fetchGmailMessages(accessToken: newToken, modelContext: modelContext)
                        } else {
                            DispatchQueue.main.async {
                                self?.isSyncing = false
                                self?.lastError = "Authentication expired"
                            }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.isSyncing = false
                        self?.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func processGmailMessage(_ gmailMessage: GmailMessage, accessToken: String, modelContext: ModelContext) {
        let headers = gmailMessage.payload.headers
        let subject = headers.first(where: { $0.name == "Subject" })?.value ?? "(no subject)"
        let from = headers.first(where: { $0.name == "From" })?.value ?? "Unknown"

        // Parse sender name and email
        let (senderName, senderEmail) = parseSender(from)

        // Parse date
        let dateMillis = Double(gmailMessage.internalDate) ?? 0
        let date = Date(timeIntervalSince1970: dateMillis / 1000)

        // Check for ICS attachments
        let hasCalendar = hasCalendarAttachment(gmailMessage.payload)

        DispatchQueue.main.async {
            // Check for duplicates
            let messageId = gmailMessage.id
            let descriptor = FetchDescriptor<EmailMessage>(
                predicate: #Predicate { $0.messageId == messageId }
            )
            let existing = (try? modelContext.fetch(descriptor)) ?? []

            if existing.isEmpty {
                let emailMessage = EmailMessage(
                    messageId: gmailMessage.id,
                    sender: senderName,
                    senderEmail: senderEmail,
                    subject: subject,
                    preview: gmailMessage.snippet,
                    date: date,
                    hasCalendarInvite: hasCalendar
                )

                // Associate with Gmail account
                let accountDescriptor = FetchDescriptor<EmailAccount>()
                if let account = (try? modelContext.fetch(accountDescriptor))?.first(where: { $0.provider == .gmail }) {
                    emailMessage.account = account
                }

                modelContext.insert(emailMessage)

                // If there's a calendar attachment, try to fetch the ICS data
                if hasCalendar {
                    self.fetchICSAttachment(
                        from: gmailMessage,
                        accessToken: accessToken,
                        emailMessage: emailMessage,
                        modelContext: modelContext
                    )
                }

                try? modelContext.save()
            }
        }
    }

    private func hasCalendarAttachment(_ payload: GmailPayload) -> Bool {
        if payload.mimeType == "text/calendar" {
            return true
        }
        if let parts = payload.parts {
            for part in parts {
                if part.mimeType == "text/calendar" ||
                   part.mimeType == "application/ics" ||
                   (part.filename?.hasSuffix(".ics") ?? false) {
                    return true
                }
                if let subParts = part.parts {
                    for sub in subParts {
                        if sub.mimeType == "text/calendar" ||
                           sub.mimeType == "application/ics" ||
                           (sub.filename?.hasSuffix(".ics") ?? false) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func fetchICSAttachment(
        from gmailMessage: GmailMessage,
        accessToken: String,
        emailMessage: EmailMessage,
        modelContext: ModelContext
    ) {
        guard let parts = gmailMessage.payload.parts else { return }

        for part in parts {
            if part.mimeType == "text/calendar" || part.mimeType == "application/ics" {
                // Inline ICS data
                if let body = part.body, let data = body.data {
                    let standardBase64 = data
                        .replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")
                    if let decoded = Data(base64Encoded: standardBase64) {
                        DispatchQueue.main.async {
                            emailMessage.icsData = decoded
                            try? modelContext.save()
                        }
                    }
                }
                // Or fetch by attachment ID
                else if let body = part.body, let attachmentId = body.attachmentId {
                    GmailAPIService.shared.fetchAttachment(
                        accessToken: accessToken,
                        messageId: gmailMessage.id,
                        attachmentId: attachmentId
                    ) { result in
                        if case .success(let data) = result {
                            DispatchQueue.main.async {
                                emailMessage.icsData = data
                                try? modelContext.save()
                            }
                        }
                    }
                }
                return
            }

            // Check nested parts
            if let subParts = part.parts {
                for sub in subParts {
                    if sub.mimeType == "text/calendar" || sub.mimeType == "application/ics" {
                        if let body = sub.body, let attachmentId = body.attachmentId {
                            GmailAPIService.shared.fetchAttachment(
                                accessToken: accessToken,
                                messageId: gmailMessage.id,
                                attachmentId: attachmentId
                            ) { result in
                                if case .success(let data) = result {
                                    DispatchQueue.main.async {
                                        emailMessage.icsData = data
                                        try? modelContext.save()
                                    }
                                }
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    private func parseSender(_ from: String) -> (name: String, email: String) {
        // Format: "Name <email@example.com>" or just "email@example.com"
        if let angleBracketRange = from.range(of: "<"),
           let closeRange = from.range(of: ">") {
            let name = String(from[from.startIndex..<angleBracketRange.lowerBound]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let email = String(from[angleBracketRange.upperBound..<closeRange.lowerBound])
            return (name.isEmpty ? email : name, email)
        }
        return (from, from)
    }

    // MARK: - Outlook Sync

    func syncOutlook(modelContext: ModelContext) {
        guard !isSyncing else { return }

        DispatchQueue.main.async { self.isSyncing = true }

        OutlookAuthService.shared.getValidAccessToken { [weak self] token in
            guard let self = self, let token = token else {
                DispatchQueue.main.async {
                    self?.isSyncing = false
                    self?.lastError = "Outlook not authenticated"
                }
                return
            }

            self.fetchOutlookMessages(accessToken: token, modelContext: modelContext)
        }
    }

    private func fetchOutlookMessages(accessToken: String, modelContext: ModelContext) {
        OutlookAPIService.shared.fetchMessages(accessToken: accessToken) { [weak self] result in
            switch result {
            case .success(let messages):
                let group = DispatchGroup()

                for graphMessage in messages {
                    group.enter()
                    self?.processOutlookMessage(graphMessage, accessToken: accessToken, modelContext: modelContext)
                    group.leave()
                }

                group.notify(queue: .main) {
                    self?.updateOutlookSyncDate(modelContext: modelContext)
                    self?.processCalendarInvites(modelContext: modelContext)
                    self?.isSyncing = false
                    self?.lastError = nil
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self?.isSyncing = false
                    self?.lastError = error.localizedDescription
                }
            }
        }
    }

    private func processOutlookMessage(_ graphMessage: GraphMessage, accessToken: String, modelContext: ModelContext) {
        let date = OutlookAPIService.shared.parseDate(graphMessage.receivedDateTime)
        let senderName = graphMessage.from?.emailAddress.name ?? "Unknown"
        let senderEmail = graphMessage.from?.emailAddress.address ?? ""

        DispatchQueue.main.async {
            let messageId = graphMessage.id
            let descriptor = FetchDescriptor<EmailMessage>(
                predicate: #Predicate { $0.messageId == messageId }
            )
            let existing = (try? modelContext.fetch(descriptor)) ?? []

            if existing.isEmpty {
                let emailMessage = EmailMessage(
                    messageId: graphMessage.id,
                    sender: senderName,
                    senderEmail: senderEmail,
                    subject: graphMessage.subject ?? "(no subject)",
                    preview: graphMessage.bodyPreview ?? "",
                    date: date,
                    isRead: graphMessage.isRead,
                    hasCalendarInvite: false
                )

                // Associate with Outlook account
                let accountDescriptor = FetchDescriptor<EmailAccount>()
                if let account = (try? modelContext.fetch(accountDescriptor))?.first(where: { $0.provider == .outlook }) {
                    emailMessage.account = account
                }

                modelContext.insert(emailMessage)

                // Check for ICS attachments
                if graphMessage.hasAttachments {
                    self.fetchOutlookAttachments(
                        accessToken: accessToken,
                        messageId: graphMessage.id,
                        emailMessage: emailMessage,
                        modelContext: modelContext
                    )
                }

                try? modelContext.save()
            }
        }
    }

    private func fetchOutlookAttachments(
        accessToken: String,
        messageId: String,
        emailMessage: EmailMessage,
        modelContext: ModelContext
    ) {
        OutlookAPIService.shared.fetchAttachments(
            accessToken: accessToken,
            messageId: messageId
        ) { result in
            if case .success(let attachments) = result {
                for attachment in attachments {
                    let isICS = attachment.contentType == "text/calendar" ||
                                attachment.contentType == "application/ics" ||
                                attachment.name.hasSuffix(".ics")
                    if isICS, let base64 = attachment.contentBytes,
                       let data = Data(base64Encoded: base64) {
                        DispatchQueue.main.async {
                            emailMessage.icsData = data
                            emailMessage.hasCalendarInvite = true
                            try? modelContext.save()
                        }
                        return
                    }
                }
            }
        }
    }

    private func updateOutlookSyncDate(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<EmailAccount>()
        if let account = (try? modelContext.fetch(descriptor))?.first(where: { $0.provider == .outlook }) {
            account.lastSyncDate = Date()
            try? modelContext.save()
        }
    }

    // MARK: - Sync All

    func syncAll(modelContext: ModelContext) {
        if GmailAuthService.shared.isAuthenticated {
            syncGmail(modelContext: modelContext)
        }
        // Outlook sync will run after Gmail finishes (isSyncing guard)
        // For simplicity, queue it with a delay
        if OutlookAuthService.shared.isAuthenticated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.syncOutlook(modelContext: modelContext)
            }
        }
    }

    private func processCalendarInvites(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<EmailMessage>(
            predicate: #Predicate { $0.hasCalendarInvite == true && $0.icsData != nil }
        )
        guard let messagesWithICS = try? modelContext.fetch(descriptor) else { return }

        for message in messagesWithICS {
            if let icsData = message.icsData {
                ICSParser.shared.createMeetingInvites(
                    from: icsData,
                    sourceMessage: message,
                    modelContext: modelContext
                )
            }
        }
    }

    private func updateGmailSyncDate(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<EmailAccount>()
        if let account = (try? modelContext.fetch(descriptor))?.first(where: { $0.provider == .gmail }) {
            account.lastSyncDate = Date()
            try? modelContext.save()
        }
    }
}

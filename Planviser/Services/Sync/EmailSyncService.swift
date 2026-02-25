import Foundation
import SwiftData

final class EmailSyncService: ObservableObject {
    static let shared = EmailSyncService()

    @Published var isSyncing = false
    @Published var lastError: String?

    private init() {}

    func syncGmail(modelContext: ModelContext) {
        guard !isSyncing else {
            print("[Sync] Already syncing, skipping")
            return
        }

        let accounts = GmailAuthService.shared.connectedAccounts
        guard !accounts.isEmpty else {
            print("[Sync] No Gmail accounts connected")
            return
        }

        print("[Sync] Starting Gmail sync for \(accounts.count) account(s)...")
        DispatchQueue.main.async { self.isSyncing = true }

        let group = DispatchGroup()

        for account in accounts {
            group.enter()
            GmailAuthService.shared.getValidAccessToken(for: account.email) { [weak self] token in
                guard let self = self, let token = token else {
                    print("[Sync] No valid access token for \(account.email)")
                    group.leave()
                    return
                }

                print("[Sync] Got access token for \(account.email), fetching messages...")
                self.fetchGmailMessages(accessToken: token, accountEmail: account.email, modelContext: modelContext) {
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isSyncing = false
            self?.lastError = nil
            print("[Sync] All Gmail accounts synced!")
        }
    }

    private func fetchGmailMessages(accessToken: String, accountEmail: String, modelContext: ModelContext, completion: @escaping () -> Void) {
        GmailAPIService.shared.fetchMessageList(accessToken: accessToken) { [weak self] result in
            switch result {
            case .success(let listResponse):
                print("[Sync] [\(accountEmail)] Message list response: \(listResponse.messages?.count ?? 0) messages")
                guard let messageRefs = listResponse.messages else {
                    print("[Sync] [\(accountEmail)] No messages found")
                    completion()
                    return
                }

                let group = DispatchGroup()
                var fetchedMessages: [(GmailMessage)] = []
                let lock = NSLock()

                for ref in messageRefs.prefix(50) {
                    group.enter()
                    GmailAPIService.shared.fetchMessageDetail(
                        accessToken: accessToken,
                        messageId: ref.id
                    ) { detailResult in
                        if case .success(let gmailMessage) = detailResult {
                            lock.lock()
                            fetchedMessages.append(gmailMessage)
                            lock.unlock()
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    print("[Sync] [\(accountEmail)] Processing \(fetchedMessages.count) messages in batch...")

                    let fetchedIds = Set(fetchedMessages.map { $0.id })

                    for gmailMessage in fetchedMessages {
                        self?.processGmailMessage(gmailMessage, accessToken: accessToken, accountEmail: accountEmail, modelContext: modelContext)
                    }

                    // Remove local messages no longer in the primary inbox
                    print("[Sync] [\(accountEmail)] Fetched \(fetchedIds.count) primary IDs, cleaning up stale messages...")
                    let accountDescriptor = FetchDescriptor<EmailAccount>()
                    if let account = (try? modelContext.fetch(accountDescriptor))?.first(where: {
                        $0.provider == .gmail && $0.email == accountEmail
                    }) {
                        let allLocalDescriptor = FetchDescriptor<EmailMessage>()
                        if let localMessages = try? modelContext.fetch(allLocalDescriptor) {
                            var removedCount = 0
                            for msg in localMessages where msg.account == account {
                                if !fetchedIds.contains(msg.messageId) {
                                    print("[Sync] [\(accountEmail)] Removing: \(msg.subject)")
                                    modelContext.delete(msg)
                                    removedCount += 1
                                }
                            }
                            print("[Sync] [\(accountEmail)] Removed \(removedCount) non-primary messages")
                        }
                    }

                    do {
                        try modelContext.save()
                        print("[Sync] [\(accountEmail)] Saved all messages to database")
                    } catch {
                        print("[Sync] [\(accountEmail)] Save error: \(error)")
                    }
                    self?.updateGmailSyncDate(accountEmail: accountEmail, modelContext: modelContext)
                    // Gmail meetings come from the Google Calendar API — skip ICS parsing
                    // to avoid duplicates. ICS parsing is only used for Outlook accounts.
                    completion()
                }

            case .failure(let error):
                print("[Sync] [\(accountEmail)] Fetch failed: \(error.localizedDescription)")
                if case APIError.httpError(401) = error {
                    // Token expired, try refresh
                    GmailAuthService.shared.refreshAccessToken(for: accountEmail) { [weak self] newToken in
                        if let newToken = newToken {
                            self?.fetchGmailMessages(accessToken: newToken, accountEmail: accountEmail, modelContext: modelContext, completion: completion)
                        } else {
                            DispatchQueue.main.async {
                                self?.lastError = "Authentication expired for \(accountEmail)"
                            }
                            completion()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.lastError = error.localizedDescription
                    }
                    completion()
                }
            }
        }
    }

    private func processGmailMessage(_ gmailMessage: GmailMessage, accessToken: String, accountEmail: String, modelContext: ModelContext) {
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

        // Check for duplicates
        let messageId = gmailMessage.id
        let descriptor = FetchDescriptor<EmailMessage>(
            predicate: #Predicate { $0.messageId == messageId }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []

            let isRead = !(gmailMessage.labelIds?.contains("UNREAD") ?? true)

        if existing.isEmpty {
            let htmlBody = extractHtmlBody(from: gmailMessage.payload)

            let emailMessage = EmailMessage(
                messageId: gmailMessage.id,
                sender: senderName,
                senderEmail: senderEmail,
                subject: subject,
                preview: gmailMessage.snippet,
                date: date,
                isRead: isRead,
                hasCalendarInvite: hasCalendar,
                htmlBody: htmlBody
            )

            // Associate with the correct Gmail account by matching email
            let accountDescriptor = FetchDescriptor<EmailAccount>()
            if let account = (try? modelContext.fetch(accountDescriptor))?.first(where: {
                $0.provider == .gmail && $0.email == accountEmail
            }) {
                emailMessage.account = account
            }

            modelContext.insert(emailMessage)
            print("[Sync] [\(accountEmail)] Inserted: \(subject)")

            // If there's a calendar attachment, try to fetch the ICS data
            if hasCalendar {
                self.fetchICSAttachment(
                    from: gmailMessage,
                    accessToken: accessToken,
                    emailMessage: emailMessage,
                    modelContext: modelContext
                )
            }
        } else if let existingMessage = existing.first {
            if existingMessage.isRead != isRead {
                existingMessage.isRead = isRead
            }
            // Backfill HTML body for messages synced before this feature
            if existingMessage.htmlBody == nil {
                existingMessage.htmlBody = extractHtmlBody(from: gmailMessage.payload)
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

    /// Extract HTML body from a Gmail message's MIME payload.
    /// Walks the part tree looking for text/html first, then text/plain.
    private func extractHtmlBody(from payload: GmailPayload) -> String? {
        // Single-part message (no parts array)
        if payload.parts == nil || payload.parts?.isEmpty == true {
            if let data = payload.body?.data {
                return decodeBase64URL(data)
            }
            return nil
        }

        // Walk parts — prefer text/html over text/plain
        var htmlContent: String?
        var plainContent: String?

        func walkParts(_ parts: [GmailPart]) {
            for part in parts {
                if part.mimeType == "text/html", let data = part.body?.data {
                    if htmlContent == nil {
                        htmlContent = decodeBase64URL(data)
                    }
                } else if part.mimeType == "text/plain", let data = part.body?.data {
                    if plainContent == nil {
                        plainContent = decodeBase64URL(data)
                    }
                }
                if let subParts = part.parts {
                    walkParts(subParts)
                }
            }
        }

        walkParts(payload.parts ?? [])

        // Return HTML if available, otherwise wrap plain text in basic HTML
        if let html = htmlContent {
            return html
        }
        if let plain = plainContent {
            let escaped = plain
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            return "<html><body style=\"font-family:-apple-system,sans-serif;font-size:14px;color:#333;padding:16px;\">\(escaped)</body></html>"
        }
        return nil
    }

    private func decodeBase64URL(_ base64url: String) -> String? {
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Pad if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
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

        let accounts = OutlookAuthService.shared.connectedAccounts
        guard !accounts.isEmpty else {
            print("[Sync] No Outlook accounts connected")
            return
        }

        print("[Sync] Starting Outlook sync for \(accounts.count) account(s)...")
        DispatchQueue.main.async { self.isSyncing = true }

        let group = DispatchGroup()

        for account in accounts {
            group.enter()
            OutlookAuthService.shared.getValidAccessToken(for: account.email) { [weak self] token in
                guard let self = self, let token = token else {
                    print("[Sync] No valid access token for Outlook \(account.email)")
                    group.leave()
                    return
                }

                print("[Sync] Got access token for Outlook \(account.email), fetching messages...")
                self.fetchOutlookMessages(accessToken: token, accountEmail: account.email, modelContext: modelContext) {
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isSyncing = false
            self?.lastError = nil
            print("[Sync] All Outlook accounts synced!")
        }
    }

    private func fetchOutlookMessages(accessToken: String, accountEmail: String, modelContext: ModelContext, completion: @escaping () -> Void) {
        OutlookAPIService.shared.fetchMessages(accessToken: accessToken) { [weak self] result in
            switch result {
            case .success(let messages):
                let group = DispatchGroup()

                for graphMessage in messages {
                    group.enter()
                    self?.processOutlookMessage(graphMessage, accessToken: accessToken, accountEmail: accountEmail, modelContext: modelContext)
                    group.leave()
                }

                group.notify(queue: .main) {
                    self?.updateOutlookSyncDate(accountEmail: accountEmail, modelContext: modelContext)
                    self?.processCalendarInvites(modelContext: modelContext)
                    completion()
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                }
                completion()
            }
        }
    }

    private func processOutlookMessage(_ graphMessage: GraphMessage, accessToken: String, accountEmail: String, modelContext: ModelContext) {
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
                let htmlBody: String? = graphMessage.body?.content

                let emailMessage = EmailMessage(
                    messageId: graphMessage.id,
                    sender: senderName,
                    senderEmail: senderEmail,
                    subject: graphMessage.subject ?? "(no subject)",
                    preview: graphMessage.bodyPreview ?? "",
                    date: date,
                    isRead: graphMessage.isRead,
                    hasCalendarInvite: false,
                    htmlBody: htmlBody
                )

                // Associate with correct Outlook account by email
                let accountDescriptor = FetchDescriptor<EmailAccount>()
                if let account = (try? modelContext.fetch(accountDescriptor))?.first(where: {
                    $0.provider == .outlook && $0.email == accountEmail
                }) {
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
            } else if let existingMessage = existing.first {
                if existingMessage.isRead != graphMessage.isRead {
                    existingMessage.isRead = graphMessage.isRead
                }
                // Backfill HTML body
                if existingMessage.htmlBody == nil, let content = graphMessage.body?.content {
                    existingMessage.htmlBody = content
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

    private func updateOutlookSyncDate(accountEmail: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<EmailAccount>()
        if let account = (try? modelContext.fetch(descriptor))?.first(where: {
            $0.provider == .outlook && $0.email == accountEmail
        }) {
            account.lastSyncDate = Date()
            try? modelContext.save()
        }
    }

    // MARK: - IMAP Sync

    func syncIMAP(modelContext: ModelContext) {
        guard !isSyncing else { return }

        let accounts = IMAPAuthService.shared.connectedAccounts
        guard !accounts.isEmpty else {
            print("[Sync] No IMAP accounts connected")
            return
        }

        print("[Sync] Starting IMAP sync for \(accounts.count) account(s)...")
        DispatchQueue.main.async { self.isSyncing = true }

        let group = DispatchGroup()

        for account in accounts {
            group.enter()
            guard let creds = IMAPAuthService.shared.getCredentials(for: account.email) else {
                print("[Sync] No credentials for IMAP \(account.email)")
                group.leave()
                continue
            }

            fetchIMAPMessages(
                email: account.email,
                host: creds.host,
                port: creds.port,
                password: creds.password,
                modelContext: modelContext
            ) {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isSyncing = false
            self?.lastError = nil
            print("[Sync] All IMAP accounts synced!")
        }
    }

    private func fetchIMAPMessages(email: String, host: String, port: UInt16, password: String, modelContext: ModelContext, completion: @escaping () -> Void) {
        IMAPAPIService.shared.fetchInboxMessages(
            email: email,
            host: host,
            port: port,
            password: password
        ) { [weak self] result in
            switch result {
            case .success(let messages):
                DispatchQueue.main.async {
                    print("[Sync] [\(email)] Processing \(messages.count) IMAP messages...")

                    let fetchedIds = Set(messages.map { IMAPAPIService.messageId(uid: $0.uid, accountEmail: email) })

                    for imapMessage in messages {
                        self?.processIMAPMessage(imapMessage, accountEmail: email, modelContext: modelContext)
                    }

                    // Remove local messages no longer on server
                    let accountDescriptor = FetchDescriptor<EmailAccount>()
                    if let account = (try? modelContext.fetch(accountDescriptor))?.first(where: {
                        $0.provider == .imap && $0.email == email
                    }) {
                        let allLocalDescriptor = FetchDescriptor<EmailMessage>()
                        if let localMessages = try? modelContext.fetch(allLocalDescriptor) {
                            var removedCount = 0
                            for msg in localMessages where msg.account == account {
                                if !fetchedIds.contains(msg.messageId) {
                                    modelContext.delete(msg)
                                    removedCount += 1
                                }
                            }
                            if removedCount > 0 {
                                print("[Sync] [\(email)] Removed \(removedCount) stale IMAP messages")
                            }
                        }
                    }

                    do {
                        try modelContext.save()
                        print("[Sync] [\(email)] Saved IMAP messages to database")
                    } catch {
                        print("[Sync] [\(email)] Save error: \(error)")
                    }

                    self?.updateIMAPSyncDate(accountEmail: email, modelContext: modelContext)
                    self?.processCalendarInvites(modelContext: modelContext)
                    completion()
                }

            case .failure(let error):
                print("[Sync] [\(email)] IMAP fetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.lastError = error.localizedDescription
                }
                completion()
            }
        }
    }

    private func processIMAPMessage(_ imapMessage: IMAPMessage, accountEmail: String, modelContext: ModelContext) {
        let messageId = IMAPAPIService.messageId(uid: imapMessage.uid, accountEmail: accountEmail)

        let descriptor = FetchDescriptor<EmailMessage>(
            predicate: #Predicate { $0.messageId == messageId }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        if existing.isEmpty {
            let emailMessage = EmailMessage(
                messageId: messageId,
                sender: imapMessage.from,
                senderEmail: imapMessage.fromEmail,
                subject: imapMessage.subject,
                preview: imapMessage.preview,
                date: imapMessage.date,
                isRead: imapMessage.isRead,
                hasCalendarInvite: imapMessage.hasCalendarInvite
            )

            let accountDescriptor = FetchDescriptor<EmailAccount>()
            if let account = (try? modelContext.fetch(accountDescriptor))?.first(where: {
                $0.provider == .imap && $0.email == accountEmail
            }) {
                emailMessage.account = account
            }

            modelContext.insert(emailMessage)
            print("[Sync] [\(accountEmail)] Inserted IMAP: \(imapMessage.subject)")
        } else if let existingMessage = existing.first, existingMessage.isRead != imapMessage.isRead {
            existingMessage.isRead = imapMessage.isRead
        }
    }

    private func updateIMAPSyncDate(accountEmail: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<EmailAccount>()
        if let account = (try? modelContext.fetch(descriptor))?.first(where: {
            $0.provider == .imap && $0.email == accountEmail
        }) {
            account.lastSyncDate = Date()
            try? modelContext.save()
        }
    }

    // MARK: - Sync All

    func syncAll(modelContext: ModelContext) {
        if GmailAuthService.shared.hasConnectedAccounts {
            syncGmail(modelContext: modelContext)
            syncGoogleCalendar(modelContext: modelContext)
        }
        // Outlook sync will run after Gmail finishes (isSyncing guard)
        // For simplicity, queue it with a delay
        if OutlookAuthService.shared.hasConnectedAccounts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.syncOutlook(modelContext: modelContext)
            }
        }
        if IMAPAuthService.shared.hasConnectedAccounts {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.syncIMAP(modelContext: modelContext)
            }
        }
    }

    // MARK: - Mark as Read

    func markAsRead(message: EmailMessage, modelContext: ModelContext) {
        guard !message.isRead else { return }
        message.isRead = true
        try? modelContext.save()

        guard let account = message.account else { return }

        switch account.provider {
        case .gmail:
            GmailAuthService.shared.getValidAccessToken(for: account.email) { token in
                guard let token = token else { return }
                GmailAPIService.shared.markAsRead(
                    accessToken: token,
                    messageId: message.messageId
                ) { result in
                    if case .failure(let error) = result {
                        print("[Sync] Failed to mark Gmail message as read: \(error)")
                    }
                }
            }
        case .outlook:
            OutlookAuthService.shared.getValidAccessToken(for: account.email) { token in
                guard let token = token else { return }
                OutlookAPIService.shared.markAsRead(
                    accessToken: token,
                    messageId: message.messageId
                ) { result in
                    if case .failure(let error) = result {
                        print("[Sync] Failed to mark Outlook message as read: \(error)")
                    }
                }
            }
        case .imap:
            if let uid = IMAPAPIService.uidFromMessageId(message.messageId),
               let creds = IMAPAuthService.shared.getCredentials(for: account.email) {
                IMAPAPIService.shared.markAsRead(
                    email: account.email,
                    host: creds.host,
                    port: creds.port,
                    password: creds.password,
                    uid: uid
                ) { result in
                    if case .failure(let error) = result {
                        print("[Sync] Failed to mark IMAP message as read: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Delete (Trash)

    func deleteMessage(_ message: EmailMessage, modelContext: ModelContext) {
        let account = message.account
        let messageId = message.messageId

        // Remove locally
        modelContext.delete(message)
        try? modelContext.save()

        guard let account = account else { return }

        switch account.provider {
        case .gmail:
            GmailAuthService.shared.getValidAccessToken(for: account.email) { token in
                guard let token = token else { return }
                GmailAPIService.shared.trashMessage(
                    accessToken: token,
                    messageId: messageId
                ) { result in
                    if case .failure(let error) = result {
                        print("[Sync] Failed to trash Gmail message: \(error)")
                    }
                }
            }
        case .outlook:
            OutlookAuthService.shared.getValidAccessToken(for: account.email) { token in
                guard let token = token else { return }
                OutlookAPIService.shared.trashMessage(
                    accessToken: token,
                    messageId: messageId
                ) { result in
                    if case .failure(let error) = result {
                        print("[Sync] Failed to trash Outlook message: \(error)")
                    }
                }
            }
        case .imap:
            if let uid = IMAPAPIService.uidFromMessageId(messageId),
               let creds = IMAPAuthService.shared.getCredentials(for: account.email) {
                IMAPAPIService.shared.trashMessage(
                    email: account.email,
                    host: creds.host,
                    port: creds.port,
                    password: creds.password,
                    uid: uid
                ) { result in
                    if case .failure(let error) = result {
                        print("[Sync] Failed to trash IMAP message: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Google Calendar API Sync

    func syncGoogleCalendar(modelContext: ModelContext) {
        let accounts = GmailAuthService.shared.connectedAccounts
        guard !accounts.isEmpty else { return }

        print("[CalSync] Starting Google Calendar sync for \(accounts.count) account(s)...")

        for account in accounts {
            GmailAuthService.shared.getValidAccessToken(for: account.email) { [weak self] token in
                guard let self = self, let token = token else { return }
                // Collect all event IDs across pages, then clean up deleted ones
                var allFetchedIds: Set<String> = []
                self.fetchCalendarEventsAllPages(
                    accessToken: token,
                    accountEmail: account.email,
                    modelContext: modelContext,
                    collectedIds: &allFetchedIds
                )
            }
        }
    }

    private func fetchCalendarEventsAllPages(accessToken: String, accountEmail: String, modelContext: ModelContext, collectedIds: inout Set<String>, pageToken: String? = nil) {
        let calendar = Calendar.current
        let now = Date()
        let timeMin = calendar.date(byAdding: .month, value: -1, to: now) ?? now
        let timeMax = calendar.date(byAdding: .month, value: 2, to: now) ?? now
        // Capture as a local mutable copy for the closure
        var ids = collectedIds

        GoogleCalendarAPIService.shared.fetchEvents(
            accessToken: accessToken,
            timeMin: timeMin,
            timeMax: timeMax,
            pageToken: pageToken
        ) { [weak self] result in
            switch result {
            case .success(let response):
                let events = response.items ?? []
                print("[CalSync] [\(accountEmail)] Fetched \(events.count) calendar events (page)")

                for event in events {
                    ids.insert(event.id)
                }

                DispatchQueue.main.async {
                    for event in events {
                        self?.processCalendarEvent(event, accountEmail: accountEmail, modelContext: modelContext)
                    }
                    try? modelContext.save()
                }

                if let nextPage = response.nextPageToken {
                    self?.fetchCalendarEventsAllPages(
                        accessToken: accessToken,
                        accountEmail: accountEmail,
                        modelContext: modelContext,
                        collectedIds: &ids,
                        pageToken: nextPage
                    )
                } else {
                    // All pages fetched — remove local meetings that no longer exist
                    let fetchedIds = ids
                    DispatchQueue.main.async {
                        self?.removeDeletedCalendarEvents(
                            accountEmail: accountEmail,
                            fetchedEventIds: fetchedIds,
                            modelContext: modelContext
                        )
                    }
                }

            case .failure(let error):
                print("[CalSync] [\(accountEmail)] Failed: \(error.localizedDescription)")
                if case APIError.httpError(401) = error {
                    GmailAuthService.shared.refreshAccessToken(for: accountEmail) { [weak self] newToken in
                        if let newToken = newToken {
                            self?.fetchCalendarEventsAllPages(
                                accessToken: newToken,
                                accountEmail: accountEmail,
                                modelContext: modelContext,
                                collectedIds: &ids,
                                pageToken: pageToken
                            )
                        }
                    }
                }
            }
        }
    }

    /// Cleanup: remove duplicate meetings and ICS-sourced orphans.
    /// Gmail meetings come solely from the Calendar API, so any meeting with
    /// empty accountEmail that isn't linked to an Outlook source is stale.
    func deduplicateMeetings(modelContext: ModelContext) {
        var descriptor = FetchDescriptor<MeetingInvite>()
        descriptor.sortBy = [SortDescriptor(\MeetingInvite.startTime)]
        guard let all = try? modelContext.fetch(descriptor) else { return }

        let cal = Calendar.current
        var seen: [String: MeetingInvite] = [:]  // "title|yyyy-MM-dd" → best entry
        var toDelete: [MeetingInvite] = []

        // Collect Outlook account emails so we don't remove their ICS meetings
        let accountDescriptor = FetchDescriptor<EmailAccount>()
        let outlookEmails = Set(
            ((try? modelContext.fetch(accountDescriptor)) ?? [])
                .filter { $0.provider == .outlook }
                .map { $0.email }
        )

        for meeting in all {
            // Remove ICS-sourced orphans: empty accountEmail and not from Outlook
            if meeting.accountEmail.isEmpty {
                let isOutlookSource = meeting.sourceMessage?.account.map { outlookEmails.contains($0.email) } ?? false
                if !isOutlookSource {
                    toDelete.append(meeting)
                    continue
                }
            }

            let dayStr = cal.startOfDay(for: meeting.startTime).timeIntervalSince1970.description
            let key = "\(meeting.title)|\(dayStr)"

            if let existing = seen[key] {
                // Prefer the one with a non-empty accountEmail (Calendar API source)
                if existing.accountEmail.isEmpty && !meeting.accountEmail.isEmpty {
                    toDelete.append(existing)
                    seen[key] = meeting
                } else {
                    toDelete.append(meeting)
                }
            } else {
                seen[key] = meeting
            }
        }

        if !toDelete.isEmpty {
            for dup in toDelete {
                print("[Dedup] Removing: \"\(dup.title)\" eventId=\(dup.eventId) accountEmail=\(dup.accountEmail)")
                modelContext.delete(dup)
            }
            try? modelContext.save()
            print("[Dedup] Removed \(toDelete.count) stale/duplicate meeting(s)")
        }
    }

    /// Nuclear option: delete all local meetings and re-sync from Calendar API.
    func resetAllMeetings(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<MeetingInvite>()
        guard let all = try? modelContext.fetch(descriptor) else { return }
        for meeting in all {
            modelContext.delete(meeting)
        }
        try? modelContext.save()
        print("[CalSync] Reset: deleted \(all.count) meetings. Re-syncing...")
        syncGoogleCalendar(modelContext: modelContext)
    }

    private func removeDeletedCalendarEvents(accountEmail: String, fetchedEventIds: Set<String>, modelContext: ModelContext) {
        let email = accountEmail
        let descriptor = FetchDescriptor<MeetingInvite>(
            predicate: #Predicate { $0.accountEmail == email }
        )
        guard let localMeetings = try? modelContext.fetch(descriptor) else { return }

        var removedCount = 0
        for meeting in localMeetings {
            if !meeting.eventId.isEmpty && !fetchedEventIds.contains(meeting.eventId) {
                print("[CalSync] [\(accountEmail)] Removing deleted event: \(meeting.title)")
                modelContext.delete(meeting)
                removedCount += 1
            }
        }

        if removedCount > 0 {
            try? modelContext.save()
            print("[CalSync] [\(accountEmail)] Removed \(removedCount) deleted events")
        }
    }

    private func processCalendarEvent(_ event: GoogleCalendarEvent, accountEmail: String, modelContext: ModelContext) {
        // Skip cancelled events
        if event.status == "cancelled" { return }

        let eventId = event.id

        // Check for existing meeting with same eventId
        let descriptor = FetchDescriptor<MeetingInvite>(
            predicate: #Predicate { $0.eventId == eventId }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        // Parse start/end times
        let startDate = parseGoogleDateTime(event.start) ?? Date()
        let endDate = parseGoogleDateTime(event.end) ?? startDate.addingTimeInterval(3600)

        // Parse response status from attendees
        let responseStatus = parseResponseStatus(from: event.attendees, selfEmail: accountEmail)

        // Extract video link
        let videoLink = event.hangoutLink
            ?? event.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" })?.uri
            ?? ""

        let description = event.eventDescription ?? ""

        // Also check for ICS-sourced duplicates: same title on the same day
        // ICS UIDs differ from Calendar API event IDs, so exact eventId match misses these.
        var icsDuplicate: MeetingInvite?
        if existing.isEmpty, let title = event.summary, !title.isEmpty {
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: startDate)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let matchTitle = title
            let icsDescriptor = FetchDescriptor<MeetingInvite>(
                predicate: #Predicate {
                    $0.title == matchTitle &&
                    $0.startTime >= dayStart &&
                    $0.startTime < dayEnd &&
                    $0.eventId != eventId
                }
            )
            icsDuplicate = (try? modelContext.fetch(icsDescriptor))?.first
        }

        if let existingMeeting = existing.first ?? icsDuplicate {
            // Update existing meeting (adopt Calendar API eventId for future syncs)
            existingMeeting.eventId = eventId
            existingMeeting.title = event.summary ?? "(No title)"
            existingMeeting.startTime = startDate
            existingMeeting.endTime = endDate
            existingMeeting.location = event.location ?? ""
            existingMeeting.videoLink = videoLink
            existingMeeting.responseStatus = responseStatus
            existingMeeting.accountEmail = accountEmail
            existingMeeting.meetingDescription = description
        } else {
            // Create new meeting
            let meeting = MeetingInvite(
                title: event.summary ?? "(No title)",
                organizer: event.organizer?.displayName ?? event.organizer?.email ?? "",
                organizerEmail: event.organizer?.email ?? "",
                startTime: startDate,
                endTime: endDate,
                location: event.location ?? "",
                videoLink: videoLink,
                responseStatus: responseStatus,
                eventId: eventId,
                accountEmail: accountEmail,
                meetingDescription: description
            )
            modelContext.insert(meeting)
        }
    }

    private func parseGoogleDateTime(_ dt: GoogleCalendarDateTime?) -> Date? {
        guard let dt = dt else { return nil }

        if let dateTimeStr = dt.dateTime {
            // ISO 8601 format: 2026-02-17T09:00:00-05:00
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateTimeStr) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateTimeStr)
        }

        if let dateStr = dt.date {
            // All-day event: 2026-02-17 — use local timezone so it appears on the correct day
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            return formatter.date(from: dateStr)
        }

        return nil
    }

    private func parseResponseStatus(from attendees: [GoogleCalendarAttendee]?, selfEmail: String) -> MeetingResponse {
        guard let attendees = attendees else { return .accepted }

        // Find the self attendee
        if let selfAttendee = attendees.first(where: { $0.isSelf == true })
            ?? attendees.first(where: { $0.email?.lowercased() == selfEmail.lowercased() }) {
            switch selfAttendee.responseStatus {
            case "accepted": return .accepted
            case "declined": return .declined
            case "tentative": return .tentative
            case "needsAction": return .pending
            default: return .pending
            }
        }

        // If we're the organizer and not in attendees, assume accepted
        return .accepted
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

    private func updateGmailSyncDate(accountEmail: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<EmailAccount>()
        if let account = (try? modelContext.fetch(descriptor))?.first(where: {
            $0.provider == .gmail && $0.email == accountEmail
        }) {
            account.lastSyncDate = Date()
            try? modelContext.save()
        }
    }
}

# Planviser — Product Requirements Document

**Version:** 1.0
**Date:** February 22, 2026
**Status:** Draft
**Owner:** [Your Name]
**Repository:** [https://github.com/IamJunnn/planViser.git](https://github.com/IamJunnn/planViser.git)
**License:** Open Source

---

## Table of Contents

1. [Overview](#1-overview)
2. [Problem Statement](#2-problem-statement)
3. [Goals & Success Metrics](#3-goals--success-metrics)
4. [Users & Use Cases](#4-users--use-cases)
5. [System Architecture](#5-system-architecture)
6. [Feature Requirements](#6-feature-requirements)
   - [Phase 1: Email & Meeting Hub](#phase-1-email--meeting-hub)
   - [Phase 2: Hourly Planner & Sunday Review](#phase-2-hourly-planner--sunday-review)
   - [Phase 3: Real-Time Reminders](#phase-3-real-time-reminders)
   - [Phase 4: AI Productivity Layer](#phase-4-ai-productivity-layer)
7. [Non-Functional Requirements](#7-non-functional-requirements)
8. [Technical Stack](#8-technical-stack)
9. [API Integrations](#9-api-integrations)
10. [Phased Roadmap & Timeline](#10-phased-roadmap--timeline)
11. [Open Questions & Risks](#11-open-questions--risks)
12. [Out of Scope](#12-out-of-scope)

---

## 1. Overview

**Planviser** is a native macOS productivity application that lives in the menu bar. It unifies a user's email accounts and calendars, provides an hourly task planner with a weekly review system, delivers smart reminders, and uses AI (Claude API) to monitor activity and generate daily productivity insights.

The app is designed for professionals who manage multiple email accounts (Gmail, Outlook, and company Exchange/IMAP), have frequent meetings, and want a single focused place to plan and reflect on their work — without switching between multiple tools.

---

## 2. Problem Statement

Modern professionals suffer from **context switching overhead**: email is in one app, calendar in another, tasks in a third, and productivity insights (if any) in yet another. Key pain points include:

- Meeting invites arrive across multiple inboxes and are easy to miss or double-book
- There is no structured way to plan work hour-by-hour and reflect weekly
- Reminders are generic and not tied to actual calendar or task context
- Users have no clear picture of how they actually spent their day vs. how they planned to

Planviser solves all four problems in one lightweight, always-available Mac app.

---

## 3. Goals & Success Metrics

### Primary Goals

| Goal | Description |
|------|-------------|
| Unified inbox | User can see all emails and meeting invites from Gmail, Outlook, and Exchange in one place |
| Structured planning | User can plan their day hour-by-hour and review weekly every Sunday |
| Timely reminders | User receives contextual macOS notifications before meetings and task blocks |
| AI productivity insight | User receives an AI-generated summary of what they did and how productive they were |

### Success Metrics

| Metric | Target |
|--------|--------|
| Daily active usage | User opens app ≥ 5 times per day |
| Meeting capture rate | 100% of incoming meeting invites surfaced within 2 minutes |
| Reminder accuracy | Reminders fire within ±30 seconds of scheduled time |
| Weekly review completion | User completes Sunday review ≥ 80% of weeks |
| AI summary satisfaction | User rates AI summary as "useful" ≥ 70% of the time |

---

## 4. Users & Use Cases

### Primary User

A professional who:
- Works across Gmail and Outlook/Microsoft 365 accounts simultaneously
- Has a company email hosted on Exchange or IMAP
- Attends multiple meetings per day
- Wants to be more intentional about how they spend their time

### Core Use Cases

**UC-01: Receive and accept a meeting invite**  
User gets a meeting invite to their Gmail. Planviser surfaces it in the Meeting Hub with a one-click Accept/Decline. The event is added to the hourly planner automatically.

**UC-02: Plan the work day**  
Each morning, user opens Planviser, sees their meetings auto-populated, and fills in task blocks for the remaining hours.

**UC-03: Get a reminder before a meeting**  
10 minutes before a scheduled meeting, a native macOS notification fires with the meeting title, attendees, and a join link if available.

**UC-04: Sunday weekly review**  
Every Sunday, Planviser prompts the user to review the past week — what was planned vs. done — and plan the coming week. AI generates a summary of accomplishments and productivity patterns.

**UC-05: View AI daily summary**  
At end of day, user opens Planviser and sees an AI-generated report: which apps were used, how time was distributed, and a productivity score with brief commentary.

---

## 5. System Architecture

```
┌─────────────────────────────────────────────────────┐
│                  macOS Menu Bar App                  │
│                  (SwiftUI / AppKit)                  │
└────────────────────────┬────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
┌───────▼──────┐  ┌──────▼──────┐  ┌─────▼──────────┐
│  Email Layer  │  │ Planner     │  │  AI Layer      │
│               │  │ & Review    │  │                │
│ Gmail API     │  │ Layer       │  │ Claude API     │
│ MS Graph API  │  │             │  │ Activity       │
│ IMAP/Exchange │  │ EventKit    │  │ Monitor        │
└───────────────┘  └─────────────┘  └────────────────┘
        │                │                │
        └────────────────▼────────────────┘
                  ┌──────────────┐
                  │  Local Store │
                  │  (SwiftData) │
                  └──────────────┘
```

All data is stored **locally on device** by default. No user data is sent to any cloud server except the email/calendar APIs the user explicitly authorizes and the Claude API for AI features.

---

## 6. Feature Requirements

### Phase 1: Email & Meeting Hub

**Priority: P0 — Must Have**

#### 1.1 Multi-Account Email Connection

| ID | Requirement |
|----|-------------|
| F-101 | User can connect a Gmail account via OAuth 2.0 |
| F-102 | User can connect a Microsoft 365 / Outlook account via OAuth 2.0 (Microsoft Graph API) |
| F-103 | User can connect a company Exchange or IMAP account via username/password or app password |
| F-104 | User can connect multiple accounts simultaneously (e.g., two Gmails + one Outlook) |
| F-105 | Account credentials are stored securely in macOS Keychain |

#### 1.2 Unified Inbox View

| ID | Requirement |
|----|-------------|
| F-111 | All inboxes are displayed in a unified list, sorted by date |
| F-112 | Each email shows sender, subject, preview, account badge, and timestamp |
| F-113 | User can filter view by account |
| F-114 | Emails are refreshed every 5 minutes automatically; user can trigger manual refresh |

#### 1.3 Meeting Invite Detection & Management

| ID | Requirement |
|----|-------------|
| F-121 | Incoming meeting invites (iCalendar / .ics format) are auto-detected across all inboxes |
| F-122 | Detected invites are surfaced in a dedicated **Meeting Hub** tab |
| F-123 | User can Accept, Decline, or mark Tentative directly from the Meeting Hub |
| F-124 | Accepted meetings are automatically added to the Hourly Planner |
| F-125 | Invite details shown: title, organizer, time, location/video link, attendees |

---

### Phase 2: Hourly Planner & Sunday Review

**Priority: P0 — Must Have**

#### 2.1 Daily Hourly Planner

| ID | Requirement |
|----|-------------|
| F-201 | Day view shows all 24 hours with 30-minute slots |
| F-202 | Accepted meetings are auto-populated into their time slots |
| F-203 | User can add, edit, and delete task blocks in free slots |
| F-204 | Task blocks have a title, optional note, and optional color label |
| F-205 | User can drag and resize task blocks to change time/duration |
| F-206 | Completed blocks can be marked as done ✓ |

#### 2.2 Sunday Weekly Review

| ID | Requirement |
|----|-------------|
| F-211 | Every Sunday at a user-configured time (default: 10:00 AM), Planviser prompts a weekly review |
| F-212 | Review screen shows: last week's planned tasks vs. completed tasks, meetings attended, and any unfinished blocks |
| F-213 | User can write a free-text reflection note for the week |
| F-214 | User can plan next week's priority areas in the same screen |
| F-215 | AI (Claude API) generates a summary of the week based on planner data and reflection note |
| F-216 | Historical weekly reviews are stored locally and browsable |

---

### Phase 3: Real-Time Reminders

**Priority: P1 — Should Have**

| ID | Requirement |
|----|-------------|
| F-301 | Native macOS notifications (UserNotifications framework) are used — no third-party service |
| F-302 | Meeting reminders fire at user-configurable intervals before start (default: 10 min and 1 min) |
| F-303 | Task block reminders fire at the start of each planned task block |
| F-304 | Notification includes: title, time, and action buttons ("Open Planviser", "Snooze 5 min") |
| F-305 | User can configure which reminder types to enable/disable in Settings |
| F-306 | A daily "plan your day" reminder fires each morning at a user-set time (default: 8:00 AM) |
| F-307 | Sunday review reminder fires at configured time if review not yet opened |

---

### Phase 4: AI Productivity Layer

**Priority: P1 — Should Have**

#### 4.1 Screen Activity Monitoring

| ID | Requirement |
|----|-------------|
| F-401 | App monitors the active application and window title every 60 seconds using macOS Accessibility APIs |
| F-402 | User must explicitly grant Screen Recording permission in macOS Privacy settings; app guides user through this |
| F-403 | Raw activity data is stored locally only — never sent externally except when generating AI summaries |
| F-404 | User can pause monitoring at any time from the menu bar icon |

#### 4.2 AI Daily Summary

| ID | Requirement |
|----|-------------|
| F-411 | At a user-configured time (default: 6:00 PM), Planviser sends the day's activity log and planner data to Claude API |
| F-412 | Claude generates a natural-language summary: time breakdown by category, highlights, and a productivity score (1–10) |
| F-413 | Summary is displayed in a dedicated "Today's Report" view |
| F-414 | User can manually trigger summary generation at any time |
| F-415 | AI summaries are stored locally alongside the planner data for each day |

#### 4.3 AI-Powered Suggestions

| ID | Requirement |
|----|-------------|
| F-421 | Claude suggests time blocks for unscheduled tasks based on patterns (e.g., "You focus best 9–11 AM") |
| F-422 | During Sunday review, Claude highlights recurring productivity patterns across weeks |

---

## 7. Non-Functional Requirements

| Category | Requirement |
|----------|-------------|
| **Performance** | App launches in < 2 seconds; email sync completes in < 5 seconds |
| **Privacy** | All personal data stored in local SwiftData database; no analytics or telemetry by default |
| **Security** | OAuth tokens and IMAP passwords stored in macOS Keychain; never written to disk in plaintext |
| **Reliability** | App must not crash on API failure; graceful degradation with user-facing error messages |
| **Accessibility** | Supports macOS VoiceOver and Dynamic Type |
| **macOS Version** | Minimum macOS 14 (Sonoma) for full SwiftUI and SwiftData support |
| **Permissions** | App requests only required permissions (Calendar, Notifications, Accessibility/Screen Recording) with clear explanations |

---

## 8. Technical Stack

| Component | Technology | Reason |
|-----------|-----------|--------|
| Language | Swift 5.9+ | Native Mac performance, access to all Apple frameworks |
| UI Framework | SwiftUI | Modern declarative UI, easiest path for new Swift developers |
| Data Persistence | SwiftData | Apple's modern local database, tight SwiftUI integration |
| Email (Gmail) | Gmail REST API v1 | Full read/send/label access via OAuth 2.0 |
| Email (Outlook) | Microsoft Graph API v1.0 | Full mail and calendar access via OAuth 2.0 |
| Email (Exchange/IMAP) | MailCore2 or native URLSession | Open IMAP protocol support |
| Calendar | EventKit | Native Apple Calendar & Reminders access |
| Notifications | UserNotifications framework | Native macOS notification delivery |
| Activity Monitoring | NSWorkspace + Accessibility API | Track active app and window title |
| AI | Anthropic Claude API (claude-sonnet-4-6) | Productivity summaries, weekly review, suggestions |
| Keychain | Security framework | Secure credential storage |

---

## 9. API Integrations

### Gmail API
- **Auth:** OAuth 2.0 with scopes: `gmail.readonly`, `gmail.modify`, `calendar.readonly`
- **Key Endpoints:** `users.messages.list`, `users.messages.get`, `users.settings`
- **Quota:** 1 billion units/day (free tier sufficient for personal use)

### Microsoft Graph API
- **Auth:** OAuth 2.0 via Microsoft Identity Platform (MSAL library)
- **Key Endpoints:** `/me/messages`, `/me/events`, `/me/calendar`
- **Quota:** Standard Microsoft 365 throttling limits apply

### Exchange / IMAP
- **Protocol:** IMAP4rev1 (RFC 3501) for email, SMTP for sending
- **Auth:** Username + app-specific password, stored in Keychain
- **Library:** MailCore2 (open source, widely used in iOS/macOS apps)

### Anthropic Claude API
- **Model:** `claude-sonnet-4-6`
- **Use cases:** Daily productivity summary, weekly review generation, task suggestions
- **Data sent:** Anonymized activity log (app names, durations), planner task titles, reflection notes
- **User control:** User can preview what data will be sent before any API call is made

---

## 10. Phased Roadmap & Timeline

| Phase | Features | Estimated Duration |
|-------|----------|-------------------|
| **Setup** | Xcode project, menu bar skeleton, SwiftData schema | Week 1 |
| **Phase 1A** | Gmail OAuth + inbox view | Week 2–3 |
| **Phase 1B** | Microsoft Graph + unified inbox | Week 4 |
| **Phase 1C** | IMAP/Exchange connection + meeting invite detection | Week 5–6 |
| **Phase 2** | Hourly planner, task blocks, Sunday review | Week 7–9 |
| **Phase 3** | macOS notifications + reminder system | Week 10 |
| **Phase 4A** | Activity monitoring | Week 11–12 |
| **Phase 4B** | Claude API integration + daily/weekly AI reports | Week 13–14 |
| **Polish** | Settings screen, onboarding flow, edge cases | Week 15–16 |

> **Note:** Timeline assumes part-time development (~10–15 hrs/week). Adjust based on your available time.

---

## 11. Open Questions & Risks

| # | Question / Risk | Mitigation |
|---|----------------|------------|
| 1 | IMAP company email may require IT approval or an app-specific password | Document setup steps; offer OAuth where available |
| 2 | macOS Screen Recording permission is intrusive — some users may not grant it | Make Phase 4 fully optional; app works without it |
| 3 | Claude API costs could grow with heavy daily usage | Batch and summarize locally before sending; add usage cap in settings |
| 4 | Microsoft OAuth app registration requires Azure Portal setup | Document the Azure app registration steps clearly in onboarding |
| 5 | SwiftUI learning curve for a new developer | Build in small, testable increments; prioritize working over perfect |
| 6 | Meeting invite formats vary (Google Meet, Zoom, Teams links) | Use regex patterns for common video link formats; fallback to raw location field |

---

## 12. Out of Scope

The following are explicitly **not** included in v1.0:

- Sending or replying to emails from within Planviser (read-only inbox in Phase 1)
- iOS / iPadOS version (Mac only)
- Team or shared workspace features (single-user only)
- Integration with task managers like Notion, Todoist, or Jira
- Custom AI model training or fine-tuning
- Cloud sync across multiple Macs
- iCloud Keychain sync of accounts

These may be considered for a future v2.0.

---

*Document last updated: February 22, 2026*  
*Next review: After Phase 1 completion*

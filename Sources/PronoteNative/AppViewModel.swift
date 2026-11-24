import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var credentials: SavedCredentials?
    @Published var selectedSection: AppSection = .home

    @Published var courses: [CourseItem] = []
    @Published var currentWeekStart: Date
    @Published var weekLabels: [String: String] = [:]

    @Published var assignments: [AssignmentItem] = []
    @Published var resources: [LessonResourceItem] = []
    @Published var grades: GradesSnapshot?
    @Published var notebook: NotebookSnapshot?
    @Published var messages: MessagesSnapshot?
    @Published var menus: MenusSnapshot?
    @Published var menusDate: Date = Date()
    @Published var stickyNote: String = ""

    @Published var selectedDiscussionMessages: [DiscussionMessageItem] = []
    @Published var isLoadingDiscussion: Bool = false

    @Published var isLoading: Bool = false
    @Published var isManualRefreshing: Bool = false
    @Published var errorMessage: String?
    @Published var statusNotice: String?
    @Published var rateLimitUntil: Date?

    private let client = PronoteClient()
    private let settings: AppSettings?
    private var weekCache: [String: [CourseItem]]
    private var sectionCache: SectionCachePayload
    private var hasSyncedOnLaunch: Bool = false
    private var noticeTask: Task<Void, Never>?

    private var cacheTTL: TimeInterval {
        settings?.cacheTTLSeconds ?? (10 * 60)
    }
    private let smartRefreshMinInterval: TimeInterval = 2 * 60

    init(settings: AppSettings? = nil) {
        self.settings = settings
        let weekStart = Self.mondayOfWeek(for: Date())
        let loadedTimetable = TimetableCacheStore.load()
        let loadedSections = SectionCacheStore.load()

        self.currentWeekStart = weekStart
        self.weekCache = loadedTimetable
        self.sectionCache = loadedSections
        self.credentials = CredentialsStore.load()
        self.rateLimitUntil = loadedSections.rateLimitUntil
        if let startSection = settings?.startSection {
            self.selectedSection = startSection
        }

        self.courses = loadedTimetable[TimetableCacheStore.weekKey(for: weekStart)] ?? []
        self.weekLabels = loadedSections.weekLabels ?? [:]
        self.assignments = loadedSections.assignments ?? []
        self.resources = loadedSections.resources ?? []
        self.grades = loadedSections.grades
        self.notebook = loadedSections.notebook
        self.messages = loadedSections.messages
        self.menus = loadedSections.menus
        self.stickyNote = loadedSections.stickyNote ?? ""
    }

    var currentWeekLabel: String? {
        weekLabels[TimetableCacheStore.weekKey(for: currentWeekStart)]
    }

    var undoneAssignmentsCount: Int {
        assignments.filter { !$0.done }.count
    }

    var unreadMessagesCount: Int {
        guard let messages else { return 0 }
        let discUnread = messages.discussions.reduce(0) { $0 + $1.unreadCount }
        let newsUnread = messages.news.filter { !$0.read }.count
        return discUnread + newsUnread
    }

    func updateStickyNote(_ text: String) {
        stickyNote = text
        sectionCache.stickyNote = text
        SectionCacheStore.save(sectionCache)
    }

    func cacheKey(for section: AppSection) -> String {
        switch section {
        case .home:
            return "timetable:\(TimetableCacheStore.weekKey(for: Self.mondayOfWeek(for: Date())))"
        case .timetable:
            return "timetable:\(TimetableCacheStore.weekKey(for: currentWeekStart))"
        case .assignments:
            return "assignments"
        case .grades:
            return "grades"
        case .notebook:
            return "notebook"
        case .messages:
            return "messages"
        case .menus:
            return "menus:\(TimetableCacheStore.weekKey(for: Self.mondayOfWeek(for: menusDate)))"
        }
    }

    func lastUpdatedDate(for section: AppSection) -> Date? {
        sectionCache.lastFetched?[cacheKey(for: section)]
    }

    private func isCacheFresh(for cacheKey: String) -> Bool {
        guard let fetchedAt = sectionCache.lastFetched?[cacheKey] else { return false }
        return Date().timeIntervalSince(fetchedAt) < cacheTTL
    }

    private func markFetched(_ cacheKey: String) {
        var map = sectionCache.lastFetched ?? [:]
        map[cacheKey] = Date()
        sectionCache.lastFetched = map
        SectionCacheStore.save(sectionCache)
    }

    private func showStatusNotice(_ text: String) {
        noticeTask?.cancel()
        statusNotice = text
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                statusNotice = nil
            }
        }
    }

    private func checkCooldown() -> Bool {
        if let until = rateLimitUntil {
            if Date() < until {
                let remainingMin = max(1, Int(ceil(until.timeIntervalSinceNow / 60)))
                errorMessage = "Pause anti-rate-limit active (encore \(remainingMin) min). Données affichées depuis le cache."
                return false
            } else {
                rateLimitUntil = nil
                sectionCache.rateLimitUntil = nil
                SectionCacheStore.save(sectionCache)
            }
        }
        return true
    }

    private func handleNetworkError(_ error: Error) {
        let msg = error.localizedDescription
        let lower = msg.lowercased()
        if lower.contains("rate-limit") || lower.contains("limite temporairement") || lower.contains("suspended") {
            let until = Date().addingTimeInterval(10 * 60)
            rateLimitUntil = until
            sectionCache.rateLimitUntil = until
            SectionCacheStore.save(sectionCache)
            errorMessage = "IP temporairement limitée par Pronote — pause de 10 min activée. Données affichées depuis le cache."
        } else {
            errorMessage = msg
        }
    }

    func autoLoginIfNeeded() async {
        guard credentials != nil, !hasSyncedOnLaunch, !isLoading else { return }
        hasSyncedOnLaunch = true

        let key = TimetableCacheStore.weekKey(for: currentWeekStart)
        if weekCache[key] != nil, isCacheFresh(for: "timetable:\(key)") {
            return
        }
        guard checkCooldown() else { return }
        await loadTimetable(forceRefresh: true, bypassSmartCheck: true)
    }

    func loginWithQRCode(payload: QRCodePayload, pin: String) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        rateLimitUntil = nil
        sectionCache.rateLimitUntil = nil
        let deviceUUID = credentials?.deviceUUID ?? UUID().uuidString
        do {
            let saved = try await client.loginWithQRCode(payload: payload, pin: pin, deviceUUID: deviceUUID)
            let updated = try await syncFourWeeksTimetable(credentials: saved, anchorWeek: currentWeekStart)
            credentials = updated
            CredentialsStore.save(updated)
            hasSyncedOnLaunch = true
        } catch {
            handleNetworkError(error)
        }
        isLoading = false
    }

    func loadSection(_ section: AppSection, forceRefresh: Bool = false) async {
        if forceRefresh {
            guard checkCooldown() else { return }
            if let last = lastUpdatedDate(for: section),
               Date().timeIntervalSince(last) < smartRefreshMinInterval {
                errorMessage = nil
                showStatusNotice("Déjà à jour")
                return
            }
            isManualRefreshing = true
        }
        defer {
            if forceRefresh {
                isManualRefreshing = false
            }
        }

        switch section {
        case .home:
            await loadTimetable(forceRefresh: forceRefresh, bypassSmartCheck: true)
        case .timetable:
            await loadTimetable(forceRefresh: forceRefresh, bypassSmartCheck: true)
        case .assignments:
            await loadAssignments(forceRefresh: forceRefresh)
        case .grades:
            await loadGrades(periodID: grades?.selectedPeriodID, forceRefresh: forceRefresh)
        case .notebook:
            await loadNotebook(periodID: notebook?.selectedPeriodID, forceRefresh: forceRefresh)
        case .messages:
            await loadMessages(forceRefresh: forceRefresh)
        case .menus:
            await loadMenus(forceRefresh: forceRefresh)
        }
    }

    func loadTimetable(forceRefresh: Bool = false, bypassSmartCheck: Bool = false) async {
        guard let saved = credentials else { return }
        let targetWeek = currentWeekStart
        let key = TimetableCacheStore.weekKey(for: targetWeek)
        let cKey = "timetable:\(key)"

        if let cached = weekCache[key] {
            courses = cached
            if !forceRefresh && isCacheFresh(for: cKey) {
                errorMessage = nil
                return
            }
        }

        if forceRefresh && !bypassSmartCheck {
            if let last = sectionCache.lastFetched?[cKey],
               Date().timeIntervalSince(last) < smartRefreshMinInterval {
                errorMessage = nil
                showStatusNotice("Déjà à jour")
                return
            }
        }

        guard checkCooldown(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let updated = try await syncFourWeeksTimetable(credentials: saved, anchorWeek: targetWeek)
            credentials = updated
            CredentialsStore.save(updated)
        } catch {
            handleNetworkError(error)
        }
        isLoading = false
    }

    /// Charge 4 semaines d'un coup (-1 semaine à +2 semaines) en 1 seule requête HTTP.
    private func syncFourWeeksTimetable(credentials: SavedCredentials, anchorWeek: Date) async throws -> SavedCredentials {
        let cal = Calendar(identifier: .iso8601)
        let rangeStart = cal.date(byAdding: .day, value: -7, to: anchorWeek) ?? anchorWeek
        let rangeEnd = cal.date(byAdding: .day, value: 20, to: anchorWeek) ?? anchorWeek

        let (updated, allCourses, fetchedLabels) = try await client.fetchTimetableRange(
            credentials: credentials,
            fromDate: rangeStart,
            toDate: rangeEnd
        )

        var grouped: [String: [CourseItem]] = [:]
        for offset in [-7, 0, 7, 14] {
            if let wk = cal.date(byAdding: .day, value: offset, to: anchorWeek) {
                grouped[TimetableCacheStore.weekKey(for: wk)] = []
            }
        }
        for course in allCourses {
            let monday = Self.mondayOfWeek(for: course.startDate)
            let wkKey = TimetableCacheStore.weekKey(for: monday)
            grouped[wkKey, default: []].append(course)
        }

        let now = Date()
        var fetchedMap = sectionCache.lastFetched ?? [:]
        for (wkKey, wkCourses) in grouped {
            weekCache[wkKey] = wkCourses
            fetchedMap["timetable:\(wkKey)"] = now
        }
        for (wkKey, lbl) in fetchedLabels {
            weekLabels[wkKey] = lbl
        }

        sectionCache.weekLabels = weekLabels
        sectionCache.lastFetched = fetchedMap
        TimetableCacheStore.save(weekCache)
        SectionCacheStore.save(sectionCache)

        let currentKey = TimetableCacheStore.weekKey(for: currentWeekStart)
        if let currentCourses = weekCache[currentKey] {
            courses = currentCourses
        }

        return updated
    }

    func loadAssignments(forceRefresh: Bool = false) async {
        guard let saved = credentials else { return }
        if !forceRefresh, sectionCache.assignments != nil, isCacheFresh(for: "assignments") {
            errorMessage = nil
            return
        }
        guard checkCooldown(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let (updated, items) = try await client.fetchAssignments(credentials: saved)
            assignments = items
            sectionCache.assignments = items
            markFetched("assignments")
            credentials = updated
            CredentialsStore.save(updated)
        } catch {
            handleNetworkError(error)
        }
        isLoading = false
    }

    func loadResources(forceRefresh: Bool = false) async {
        guard let saved = credentials else { return }
        if !forceRefresh, sectionCache.resources != nil, isCacheFresh(for: "resources") {
            errorMessage = nil
            return
        }
        guard checkCooldown(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let (updated, items) = try await client.fetchResources(credentials: saved)
            resources = items
            sectionCache.resources = items
            markFetched("resources")
            credentials = updated
            CredentialsStore.save(updated)
        } catch {
            handleNetworkError(error)
        }
        isLoading = false
    }

    func toggleAssignmentDone(_ item: AssignmentItem) async {
        guard let saved = credentials,
              let index = assignments.firstIndex(where: { $0.id == item.id }) else { return }
        let newState = !item.done
        assignments[index].done = newState
        sectionCache.assignments = assignments
        SectionCacheStore.save(sectionCache)

        do {
            try await client.setAssignmentDone(credentials: saved, assignmentID: item.id, done: newState)
        } catch {
            if let rollbackIndex = assignments.firstIndex(where: { $0.id == item.id }) {
                assignments[rollbackIndex].done = !newState
                sectionCache.assignments = assignments
                SectionCacheStore.save(sectionCache)
            }
            handleNetworkError(error)
        }
    }

    func loadGrades(periodID: String?, forceRefresh: Bool = false) async {
        guard let saved = credentials else { return }
        if !forceRefresh, let cached = sectionCache.grades,
           (periodID == nil || cached.selectedPeriodID == periodID),
           isCacheFresh(for: "grades") {
            errorMessage = nil
            return
        }
        guard checkCooldown(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let (updated, snapshot) = try await client.fetchGrades(credentials: saved, periodID: periodID)
            grades = snapshot
            sectionCache.grades = snapshot
            markFetched("grades")
            credentials = updated
            CredentialsStore.save(updated)
        } catch {
            handleNetworkError(error)
        }
        isLoading = false
    }

    func selectGradesPeriod(_ periodID: String) async {
        await loadGrades(periodID: periodID, forceRefresh: true)
    }

    func openGradebookPDF() async {
        guard let saved = credentials else { return }
        errorMessage = nil
        do {
            let url = try await client.fetchGradebookPDF(credentials: saved, periodID: grades?.selectedPeriodID)
            NSWorkspace.shared.open(url)
        } catch {
            handleNetworkError(error)
        }
    }

    func loadNotebook(periodID: String?, forceRefresh: Bool = false) async {
        guard let saved = credentials else { return }
        if !forceRefresh, let cached = sectionCache.notebook,
           (periodID == nil || cached.selectedPeriodID == periodID),
           isCacheFresh(for: "notebook") {
            errorMessage = nil
            return
        }
        guard checkCooldown(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let (updated, snapshot) = try await client.fetchNotebook(credentials: saved, periodID: periodID)
            notebook = snapshot
            sectionCache.notebook = snapshot
            markFetched("notebook")
            credentials = updated
            CredentialsStore.save(updated)
        } catch {
            handleNetworkError(error)
        }
        isLoading = false
    }

    func selectNotebookPeriod(_ periodID: String) async {
        await loadNotebook(periodID: periodID, forceRefresh: true)
    }

    func loadMessages(forceRefresh: Bool = false) async {
        guard let saved = credentials else { return }
        if !forceRefresh, sectionCache.messages != nil, isCacheFresh(for: "messages") {
            errorMessage = nil
            return
        }
        guard checkCooldown(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let (updated, snapshot) = try await client.fetchMessages(credentials: saved)
            messages = snapshot
            sectionCache.messages = snapshot
            markFetched("messages")
            credentials = updated
            CredentialsStore.save(updated)
        } catch {
            handleNetworkError(error)
        }
        isLoading = false
    }

    func openDiscussion(_ discussion: DiscussionSummary) async {
        guard let saved = credentials, checkCooldown() else { return }
        isLoadingDiscussion = true
        selectedDiscussionMessages = []
        do {
            selectedDiscussionMessages = try await client.fetchDiscussionMessages(
                credentials: saved,
                discussionID: discussion.id
            )
        } catch {
            handleNetworkError(error)
        }
        isLoadingDiscussion = false
    }

    func sendReply(discussionID: String, content: String) async -> Bool {
        guard let saved = credentials else { return false }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await client.sendDiscussionMessage(credentials: saved, discussionID: discussionID, content: trimmed)
            selectedDiscussionMessages.append(
                DiscussionMessageItem(
                    id: UUID().uuidString,
                    author: "Moi",
                    isMe: true,
                    date: Date(),
                    content: trimmed,
                    attachments: []
                )
            )
            return true
        } catch {
            handleNetworkError(error)
            return false
        }
    }

    func markNewsAsRead(_ item: NewsEntry) async {
        guard !item.read, let saved = credentials else { return }
        if let idx = messages?.news.firstIndex(where: { $0.id == item.id }) {
            messages?.news[idx].read = true
            sectionCache.messages = messages
            SectionCacheStore.save(sectionCache)
        }
        try? await client.markNewsRead(credentials: saved, newsID: item.id)
    }

    func loadMenus(forceRefresh: Bool = false) async {
        guard let saved = credentials else { return }
        let key = "menus:\(TimetableCacheStore.weekKey(for: Self.mondayOfWeek(for: menusDate)))"
        if !forceRefresh, sectionCache.menus != nil, isCacheFresh(for: key) {
            errorMessage = nil
            return
        }
        guard checkCooldown(), !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            let (updated, snapshot) = try await client.fetchMenus(credentials: saved, date: menusDate)
            menus = snapshot
            sectionCache.menus = snapshot
            markFetched(key)
            credentials = updated
            CredentialsStore.save(updated)
        } catch {
            handleNetworkError(error)
        }
        isLoading = false
    }

    func shiftMenusWeek(by days: Int) async {
        menusDate = Calendar(identifier: .iso8601).date(byAdding: .day, value: days, to: menusDate) ?? menusDate
        await loadMenus(forceRefresh: true)
    }

    func goToPreviousWeek() async {
        currentWeekStart = Calendar(identifier: .iso8601).date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
        await loadTimetable()
    }

    func goToNextWeek() async {
        currentWeekStart = Calendar(identifier: .iso8601).date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
        await loadTimetable()
    }

    func goToToday() async {
        currentWeekStart = Self.mondayOfWeek(for: Date())
        await loadTimetable()
    }

    func clearCacheOnly() {
        TimetableCacheStore.clear()
        SectionCacheStore.clear()
        weekCache.removeAll()
        weekLabels.removeAll()
        sectionCache = SectionCachePayload()
        rateLimitUntil = nil
        courses = []
        assignments = []
        resources = []
        grades = nil
        notebook = nil
        messages = nil
        menus = nil
    }

    func logout() {
        CredentialsStore.clear()
        TimetableCacheStore.clear()
        SectionCacheStore.clear()
        weekCache.removeAll()
        weekLabels.removeAll()
        sectionCache = SectionCachePayload()
        hasSyncedOnLaunch = false
        rateLimitUntil = nil
        statusNotice = nil
        credentials = nil
        courses = []
        assignments = []
        resources = []
        grades = nil
        notebook = nil
        messages = nil
        menus = nil
        stickyNote = ""
        selectedDiscussionMessages = []
        errorMessage = nil
        Task {
            await client.logout()
        }
    }

    static func mondayOfWeek(for date: Date) -> Date {
        let cal = Calendar(identifier: .iso8601)
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? date
    }
}

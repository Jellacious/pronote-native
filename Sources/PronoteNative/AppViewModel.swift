import AppKit
import Foundation
import Network
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
    @Published var isOffline: Bool = false
    @Published var menuBarText: String?
    @Published var nextAutoRefreshDate: Date?

    private let client = PronoteClient()
    private let settings: AppSettings?
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "PronoteNative.NetworkMonitor")
    private var weekCache: [String: [CourseItem]]
    private var sectionCache: SectionCachePayload
    private var hasSyncedOnLaunch: Bool = false
    private var noticeTask: Task<Void, Never>?
    private var menuBarTimerTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?

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

        networkMonitor.pathUpdateHandler = { [weak self] path in
            let offline = (path.status != .satisfied)
            Task { @MainActor [weak self] in
                self?.isOffline = offline
            }
        }
        networkMonitor.start(queue: monitorQueue)
        refreshMenuBarText()
        menuBarTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                self?.refreshMenuBarText()
            }
        }
        startAutoRefreshLoop()
    }

    deinit {
        networkMonitor.cancel()
        menuBarTimerTask?.cancel()
        autoRefreshTask?.cancel()
    }

    static func nextFixedRefreshSlot(after now: Date) -> Date {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)

        var slots: [Date] = []
        // 07:01 puis toutes les 15 min jusqu'à 19:46
        var minuteOfDay = 7 * 60 + 1
        while minuteOfDay <= 19 * 60 + 46 {
            if let d = cal.date(byAdding: .minute, value: minuteOfDay, to: startOfDay) {
                slots.append(d)
            }
            minuteOfDay += 15
        }
        // Dernier créneau garanti à 19:55
        if let lastSlot = cal.date(byAdding: .minute, value: 19 * 60 + 55, to: startOfDay) {
            slots.append(lastSlot)
        }

        if let nextToday = slots.first(where: { $0 > now }) {
            return nextToday
        }

        let tomorrow = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)
        return cal.date(byAdding: .minute, value: 7 * 60 + 1, to: tomorrow) ?? tomorrow
    }

    private func startAutoRefreshLoop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                let nextSlot = Self.nextFixedRefreshSlot(after: Date())
                self?.nextAutoRefreshDate = nextSlot
                let delay = max(1, nextSlot.timeIntervalSinceNow)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.performScheduledRefresh(at: nextSlot)
            }
        }
    }

    private func performScheduledRefresh(at slot: Date) async {
        guard credentials != nil,
              settings?.autoRefreshEnabled == true,
              !isOffline,
              checkCooldown() else {
            return
        }

        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .weekday], from: slot)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let weekday = comps.weekday ?? 1

        let isAnchorSlot = (hour == 7 && minute == 1) || (hour == 19 && minute == 55)
        let minutesSinceStart = (hour * 60 + minute) - (7 * 60 + 1)
        let isWeekday = (2...6).contains(weekday)

        func shouldRun(intervalMinutes: Int, cacheKey: String, allowWeekend: Bool = true) -> Bool {
            if !allowWeekend && !isWeekday { return false }
            let interval = max(15, intervalMinutes)
            let slotMatches = isAnchorSlot || (minutesSinceStart >= 0 && minutesSinceStart % interval == 0)
            guard slotMatches else { return false }

            // Si un refresh manuel vient d'être fait (< 5 min), on saute ce créneau auto
            if let last = sectionCache.lastFetched?[cacheKey],
               Date().timeIntervalSince(last) < 5 * 60 {
                return false
            }
            return true
        }

        let ttInterval = settings?.refreshTimetableNotebookMinutes ?? 15
        let gradesInterval = settings?.refreshGradesMinutes ?? 15
        let hwInterval = settings?.refreshAssignmentsMinutes ?? 30
        let msgInterval = settings?.refreshMessagesMinutes ?? 60

        let ttKey = "timetable:\(TimetableCacheStore.weekKey(for: currentWeekStart))"
        if shouldRun(intervalMinutes: ttInterval, cacheKey: ttKey) && !isOffline {
            await loadTimetable(forceRefresh: true, bypassSmartCheck: true)
        }
        if shouldRun(intervalMinutes: ttInterval, cacheKey: "notebook") && !isOffline {
            await loadNotebook(periodID: notebook?.selectedPeriodID, forceRefresh: true)
        }
        if shouldRun(intervalMinutes: gradesInterval, cacheKey: "grades") && !isOffline {
            await loadGrades(periodID: grades?.selectedPeriodID, forceRefresh: true)
        }
        if shouldRun(intervalMinutes: hwInterval, cacheKey: "assignments") && !isOffline {
            await loadAssignments(forceRefresh: true)
        }
        if shouldRun(intervalMinutes: msgInterval, cacheKey: "messages", allowWeekend: false) && !isOffline {
            await loadMessages(forceRefresh: true)
        }
    }

    var todayCourses: [CourseItem] {
        let currentWeekKey = TimetableCacheStore.weekKey(for: Self.mondayOfWeek(for: Date()))
        let source = weekCache[currentWeekKey] ?? courses
        return source
            .filter { Calendar.current.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }
    }

    func refreshMenuBarText() {
        guard credentials != nil else {
            menuBarText = nil
            return
        }
        let now = Date()
        let activeTodayCourses = todayCourses.filter { !$0.isCancelled }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let showName = settings?.menuBarShowCourseName ?? false

        let shortSubject: (String) -> String = { raw in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.count <= 16 ? t : String(t.prefix(15)) + "…"
        }

        if let current = activeTodayCourses.first(where: { $0.startDate <= now && $0.endDate > now }) {
            if showName {
                menuBarText = "\(shortSubject(current.subject)) · \(fmt.string(from: current.endDate))"
            } else {
                let rem = max(1, Int(ceil(current.endDate.timeIntervalSince(now) / 60)))
                if rem >= 60 {
                    menuBarText = "\(rem / 60)h\(String(format: "%02d", rem % 60))"
                } else {
                    menuBarText = "\(rem) min"
                }
            }
            return
        }

        if let next = activeTodayCourses.first(where: { $0.startDate > now }) {
            let minutes = max(1, Int(ceil(next.startDate.timeIntervalSince(now) / 60)))
            if showName {
                if minutes <= 60 {
                    menuBarText = "Dans \(minutes) min · \(shortSubject(next.subject))"
                } else {
                    menuBarText = "\(shortSubject(next.subject)) · \(fmt.string(from: next.startDate))"
                }
            } else {
                if minutes <= 60 {
                    menuBarText = "Dans \(minutes) min"
                } else {
                    menuBarText = fmt.string(from: next.startDate)
                }
            }
            return
        }

        menuBarText = nil
    }

    struct ScheduledDay: Identifiable {
        let id: Date
        let title: String
        let isToday: Bool
        let courses: [CourseItem]
    }

    func upcomingScheduledDays(from now: Date) -> [ScheduledDay] {
        let cal = Calendar.current
        let allCourses = weekCache.values
            .flatMap { $0 }
            .sorted { $0.startDate < $1.startDate }

        let source = allCourses.isEmpty ? courses : allCourses
        var result: [ScheduledDay] = []

        let todayRemaining = source.filter { cal.isDateInToday($0.startDate) && $0.endDate > now }
        if !todayRemaining.isEmpty {
            result.append(
                ScheduledDay(
                    id: cal.startOfDay(for: now),
                    title: "Aujourd'hui",
                    isToday: true,
                    courses: todayRemaining
                )
            )
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEEE d MMM"

        let futureCourses = source.filter { !cal.isDateInToday($0.startDate) && $0.startDate > now }
        let grouped = Dictionary(grouping: futureCourses) { cal.startOfDay(for: $0.startDate) }
        for day in grouped.keys.sorted().prefix(10) {
            let dayCourses = (grouped[day] ?? []).sorted { $0.startDate < $1.startDate }
            guard !dayCourses.isEmpty else { continue }
            let title = cal.isDateInTomorrow(day) ? "Demain" : df.string(from: day).capitalized
            result.append(
                ScheduledDay(
                    id: day,
                    title: title,
                    isToday: false,
                    courses: dayCourses
                )
            )
        }

        return result
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
        let isNetworkErr =
            (error as? PronoteClientError).map {
                if case .requestTimedOut = $0 { return true }
                return false
            } == true ||
            lower.contains("réseau indisponible") ||
            lower.contains("impossible de contacter") ||
            lower.contains("enotfound") ||
            lower.contains("econnrefused") ||
            lower.contains("etimedout") ||
            lower.contains("eai_again") ||
            lower.contains("fetch failed") ||
            lower.contains("offline") ||
            lower.contains("hors-ligne")

        if lower.contains("rate-limit") || lower.contains("limite temporairement") || lower.contains("suspended") {
            let until = Date().addingTimeInterval(10 * 60)
            rateLimitUntil = until
            sectionCache.rateLimitUntil = until
            SectionCacheStore.save(sectionCache)
            errorMessage = "IP temporairement limitée par Pronote — pause de 10 min activée. Données affichées depuis le cache."
        } else if isNetworkErr {
            isOffline = true
            if !hasCachedData(for: selectedSection) {
                errorMessage = msg
            }
        } else {
            errorMessage = msg
        }
    }

    private func hasCachedData(for section: AppSection) -> Bool {
        switch section {
        case .home, .timetable:
            return !courses.isEmpty
        case .assignments:
            return !assignments.isEmpty || !resources.isEmpty
        case .grades:
            return grades != nil
        case .notebook:
            return notebook != nil
        case .messages:
            return messages != nil
        case .menus:
            return menus != nil
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
            refreshMenuBarText()
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

        let previousWeekCache = weekCache
        let now = Date()
        var fetchedMap = sectionCache.lastFetched ?? [:]
        for (wkKey, wkCourses) in grouped {
            weekCache[wkKey] = wkCourses
            fetchedMap["timetable:\(wkKey)"] = now
        }
        for (wkKey, lbl) in fetchedLabels {
            weekLabels[wkKey] = lbl
        }

        notifyTimetableDiff(oldCache: previousWeekCache, newGrouped: grouped)

        sectionCache.weekLabels = weekLabels
        sectionCache.lastFetched = fetchedMap
        TimetableCacheStore.save(weekCache)
        SectionCacheStore.save(sectionCache)

        let currentKey = TimetableCacheStore.weekKey(for: currentWeekStart)
        if let currentCourses = weekCache[currentKey] {
            courses = currentCourses
        }

        isOffline = false
        refreshMenuBarText()
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
            isOffline = false
            let previousAssignments = sectionCache.assignments
            assignments = items
            sectionCache.assignments = items
            markFetched("assignments")
            notifyAssignmentsDiff(old: previousAssignments, new: items)
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
            isOffline = false
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
            isOffline = false
            let previousGrades = sectionCache.grades
            grades = snapshot
            sectionCache.grades = snapshot
            markFetched("grades")
            notifyGradesDiff(old: previousGrades, new: snapshot)
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
            guard let safeURL = SafeURL.validatedGradebookURL(url.absoluteString, expectedBaseURL: saved.baseURL) else {
                errorMessage = "URL du bulletin PDF refusée par sécurité."
                return
            }
            NSWorkspace.shared.open(safeURL)
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
            isOffline = false
            let previousNotebook = sectionCache.notebook
            notebook = snapshot
            sectionCache.notebook = snapshot
            markFetched("notebook")
            notifyNotebookDiff(old: previousNotebook, new: snapshot)
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
            isOffline = false
            let previousMessages = sectionCache.messages
            messages = snapshot
            sectionCache.messages = snapshot
            markFetched("messages")
            notifyMessagesDiff(old: previousMessages, new: snapshot)
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
            isOffline = false
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
        refreshMenuBarText()
        Task {
            await client.logout()
        }
    }

    static func mondayOfWeek(for date: Date) -> Date {
        let cal = Calendar(identifier: .iso8601)
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? date
    }

    // MARK: - Notifications différentielles

    private func notifyTimetableDiff(oldCache: [String: [CourseItem]], newGrouped: [String: [CourseItem]]) {
        guard settings?.notificationsEnabled == true,
              settings?.notifyTimetableChanges == true else { return }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let horizon = cal.date(byAdding: .day, value: 14, to: startOfToday) ?? startOfToday
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEE d MMM"

        var changes: [String] = []
        let stableKey: (CourseItem) -> String = { course in
            let startMin = Int(course.startDate.timeIntervalSince1970 / 60)
            let endMin = Int(course.endDate.timeIntervalSince1970 / 60)
            let subj = course.subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "\(startMin)-\(endMin)-\(subj)"
        }

        for (wkKey, newCourses) in newGrouped {
            guard let oldCourses = oldCache[wkKey], !oldCourses.isEmpty else { continue }
            let relevantOld = oldCourses.filter { $0.startDate >= startOfToday && $0.startDate <= horizon }
            let relevantNew = newCourses.filter { $0.startDate >= startOfToday && $0.startDate <= horizon }
            guard !relevantOld.isEmpty else { continue }

            let oldByKey = Dictionary(relevantOld.map { (stableKey($0), $0) }, uniquingKeysWith: { first, _ in first })
            let newByKey = Dictionary(relevantNew.map { (stableKey($0), $0) }, uniquingKeysWith: { first, _ in first })

            for course in relevantNew {
                let k = stableKey(course)
                let dayStr = df.string(from: course.startDate)
                if let old = oldByKey[k] {
                    if !old.isCancelled && course.isCancelled {
                        changes.append("Cours annulé (\(dayStr)) : \(course.subject) (\(course.timeRangeString))")
                    } else if (old.room ?? "") != (course.room ?? ""), let newRoom = course.room, !newRoom.isEmpty {
                        changes.append("Salle modifiée (\(dayStr)) : \(course.subject) → Salle \(newRoom)")
                    }
                } else if !course.isCancelled {
                    changes.append("Cours ajouté (\(dayStr)) : \(course.subject) (\(course.timeRangeString))")
                }
            }

            for old in relevantOld where newByKey[stableKey(old)] == nil && !old.isCancelled {
                let dayStr = df.string(from: old.startDate)
                changes.append("Cours supprimé (\(dayStr)) : \(old.subject) (\(old.timeRangeString))")
            }
        }

        guard !changes.isEmpty else { return }
        if changes.count == 1 {
            NotificationManager.shared.send(
                title: "Emploi du temps modifié",
                body: changes[0],
                section: .timetable
            )
        } else {
            let preview = changes.prefix(2).joined(separator: "\n")
            NotificationManager.shared.send(
                title: "\(changes.count) changements d'emploi du temps",
                body: preview,
                section: .timetable
            )
        }
    }

    private func notifyGradesDiff(old: GradesSnapshot?, new: GradesSnapshot) {
        guard settings?.notificationsEnabled == true,
              settings?.notifyNewGrades == true,
              let old,
              old.selectedPeriodID == new.selectedPeriodID else { return }

        let gradeKey: (GradeItem) -> String = { g in
            "\(g.subject.lowercased())-\(Int(g.date.timeIntervalSince1970 / 86_400))-\(g.valueDisplay)-\(g.outOfDisplay)-\(g.comment ?? "")"
        }
        let oldKeys = Set(old.grades.map(gradeKey))
        let added = new.grades.filter { !oldKeys.contains(gradeKey($0)) }
        guard !added.isEmpty else { return }

        let hideValue = settings?.notifyHideGradeValue == true
        if added.count <= 2 {
            for g in added {
                let body = hideValue
                    ? "Nouvelle note publiée en \(g.subject)"
                    : "\(g.subject) : \(g.valueDisplay)/\(g.outOfDisplay)"
                NotificationManager.shared.send(
                    title: "Nouvelle note",
                    body: body,
                    section: .grades,
                    identifier: "grade-\(g.id)"
                )
            }
        } else {
            let subjects = Array(Set(added.map(\.subject))).prefix(3).joined(separator: ", ")
            NotificationManager.shared.send(
                title: "\(added.count) nouvelles notes",
                body: subjects,
                section: .grades
            )
        }
    }

    private func notifyAssignmentsDiff(old: [AssignmentItem]?, new: [AssignmentItem]) {
        guard settings?.notificationsEnabled == true,
              settings?.notifyNewAssignments == true,
              let old else { return }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        let hwKey: (AssignmentItem) -> String = { hw in
            "\(Int(hw.deadline.timeIntervalSince1970 / 86_400))-\(hw.subject.lowercased())-\(hw.description.prefix(40).lowercased())"
        }
        let oldKeys = Set(old.map(hwKey))
        let added = new.filter { !oldKeys.contains(hwKey($0)) && $0.deadline >= startOfToday }
        guard !added.isEmpty else { return }

        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "EEE d MMM"

        if added.count <= 2 {
            for hw in added {
                let desc = hw.description.isEmpty ? "Nouveau travail à faire" : hw.description
                NotificationManager.shared.send(
                    title: "Nouveau devoir · \(hw.subject)",
                    body: "Pour le \(df.string(from: hw.deadline)) : \(desc)",
                    section: .assignments,
                    identifier: "hw-\(hw.id)"
                )
            }
        } else {
            NotificationManager.shared.send(
                title: "\(added.count) nouveaux devoirs",
                body: Array(Set(added.map(\.subject))).prefix(3).joined(separator: ", "),
                section: .assignments
            )
        }
    }

    private func notifyMessagesDiff(old: MessagesSnapshot?, new: MessagesSnapshot) {
        guard settings?.notificationsEnabled == true,
              settings?.notifyNewMessages == true,
              let old else { return }

        let oldDiscMap = Dictionary(old.discussions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let oldNewsIDs = Set(old.news.map(\.id))

        var alerts: [(String, String, String)] = []
        for disc in new.discussions where disc.unreadCount > 0 {
            let prevUnread = oldDiscMap[disc.id]?.unreadCount ?? 0
            if disc.unreadCount > prevUnread || oldDiscMap[disc.id] == nil {
                alerts.append(("Nouveau message · \(disc.creator)", disc.subject, "disc-\(disc.id)-\(disc.unreadCount)"))
            }
        }
        for item in new.news where !item.read && !oldNewsIDs.contains(item.id) {
            alerts.append(("Nouvelle info · \(item.author)", item.title, "news-\(item.id)"))
        }

        guard !alerts.isEmpty else { return }
        if alerts.count <= 2 {
            for (title, body, id) in alerts {
                NotificationManager.shared.send(title: title, body: body, section: .messages, identifier: id)
            }
        } else {
            NotificationManager.shared.send(
                title: "\(alerts.count) nouveaux messages / infos",
                body: alerts.prefix(2).map(\.1).joined(separator: " · "),
                section: .messages
            )
        }
    }

    private func notifyNotebookDiff(old: NotebookSnapshot?, new: NotebookSnapshot) {
        guard settings?.notificationsEnabled == true,
              settings?.notifyNewAbsences == true,
              let old,
              old.selectedPeriodID == new.selectedPeriodID else { return }

        let absKey: (AbsenceItem) -> String = { a in
            "\(Int(a.startDate.timeIntervalSince1970 / 60))-\(Int(a.endDate.timeIntervalSince1970 / 60))"
        }
        let delayKey: (DelayItem) -> String = { d in
            "\(Int(d.date.timeIntervalSince1970 / 60))-\(d.minutes)"
        }
        let oldAbsKeys = Set(old.absences.map(absKey))
        let newAbs = new.absences.filter { !oldAbsKeys.contains(absKey($0)) }
        let oldDelayKeys = Set(old.delays.map(delayKey))
        let newDelays = new.delays.filter { !oldDelayKeys.contains(delayKey($0)) }

        if newAbs.count == 1, let abs = newAbs.first {
            NotificationManager.shared.send(
                title: "Nouvelle absence",
                body: abs.justified ? "Absence justifiée enregistrée" : "Absence non justifiée enregistrée",
                section: .notebook,
                identifier: "abs-\(abs.id)"
            )
        } else if newAbs.count > 1 {
            NotificationManager.shared.send(
                title: "\(newAbs.count) nouvelles absences",
                body: "Consulte la rubrique Vie scolaire.",
                section: .notebook
            )
        }

        if newDelays.count == 1, let delay = newDelays.first {
            NotificationManager.shared.send(
                title: "Nouveau retard",
                body: "Retard de \(delay.minutes) min enregistré",
                section: .notebook,
                identifier: "delay-\(delay.id)"
            )
        } else if newDelays.count > 1 {
            NotificationManager.shared.send(
                title: "\(newDelays.count) nouveaux retards",
                body: "Consulte la rubrique Vie scolaire.",
                section: .notebook
            )
        }
    }
}

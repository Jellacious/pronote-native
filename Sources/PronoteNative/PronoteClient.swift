import Foundation

enum PronoteClientError: LocalizedError {
    case nodeNotFound
    case bridgeNotFound
    case processFailed(String)
    case authenticationFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .nodeNotFound:
            return "Node.js introuvable sur ce Mac (vérifiez nvm ou Homebrew)."
        case .bridgeNotFound:
            return "Le module Pawnote (bridge.mjs) est introuvable dans le bundle."
        case .processFailed(let msg):
            return "Erreur bridge Pawnote : \(msg)"
        case .authenticationFailed(let msg):
            return msg
        case .invalidResponse:
            return "Réponse invalide du bridge Pawnote."
        }
    }
}

actor PronoteClient {
    private struct BridgeLoginRequest: Encodable {
        let action = "login_qr"
        let qr: QRCodePayload
        let pin: String
        let deviceUUID: String
    }

    private struct BridgeTimetableRequest: Encodable {
        let action = "timetable"
        let credentials: SavedCredentials
        let fromISO: String
        let toISO: String
    }

    private struct BridgeCredentialsRequest: Encodable {
        let action: String
        let credentials: SavedCredentials
    }

    private struct BridgeAssignmentStatusRequest: Encodable {
        let action = "assignment_status"
        let credentials: SavedCredentials
        let assignmentID: String
        let done: Bool
    }

    private struct BridgePeriodRequest: Encodable {
        let action: String
        let credentials: SavedCredentials
        let periodID: String?
    }

    private struct BridgeDiscussionMessagesRequest: Encodable {
        let action = "discussion_messages"
        let credentials: SavedCredentials
        let discussionID: String
    }

    private struct BridgeDiscussionSendRequest: Encodable {
        let action = "discussion_send"
        let credentials: SavedCredentials
        let discussionID: String
        let content: String
    }

    private struct BridgeNewsReadRequest: Encodable {
        let action = "news_read"
        let credentials: SavedCredentials
        let newsID: String
    }

    private struct BridgeMenusRequest: Encodable {
        let action = "menus"
        let credentials: SavedCredentials
        let dateISO: String
    }

    private struct BridgeLogoutRequest: Encodable {
        let action = "logout"
    }

    private struct BridgeCourseDTO: Decodable {
        let id: String
        let subject: String
        let teacher: String?
        let room: String?
        let groups: [String]?
        let startISO: String
        let endISO: String
        let colorHex: String?
        let status: String?
        let isCancelled: Bool
        let isModified: Bool
        let isOuting: Bool
        let memo: String?
    }

    private struct BridgeAssignmentDTO: Decodable {
        let id: String
        let subject: String
        let description: String
        let colorHex: String?
        let done: Bool
        let deadlineISO: String
        let difficulty: Int
        let lengthMinutes: Int?
        let attachments: [AttachmentItem]?
    }

    private struct BridgeResourceContentDTO: Decodable {
        let id: String
        let title: String?
        let description: String
        let attachments: [AttachmentItem]?
    }

    private struct BridgeResourceDTO: Decodable {
        let id: String
        let subject: String
        let colorHex: String?
        let startISO: String
        let endISO: String
        let teachers: [String]
        let groups: [String]
        let contents: [BridgeResourceContentDTO]
    }

    private struct BridgeSubjectAverageDTO: Decodable {
        let id: String
        let subject: String
        let colorHex: String?
        let studentDisplay: String
        let studentNumeric: Double?
        let classDisplay: String
        let outOfDisplay: String
        let outOfNumeric: Double
    }

    private struct BridgeGradeDTO: Decodable {
        let id: String
        let subject: String
        let colorHex: String?
        let comment: String?
        let valueDisplay: String
        let valueNumeric: Double?
        let outOfDisplay: String
        let outOfNumeric: Double
        let classAverageDisplay: String
        let minDisplay: String
        let maxDisplay: String
        let coefficient: Double
        let dateISO: String
        let isBonus: Bool
    }

    private struct BridgeGradesOverviewDTO: Decodable {
        let overallAverage: String?
        let classAverage: String?
        let subjectAverages: [BridgeSubjectAverageDTO]
        let grades: [BridgeGradeDTO]
    }

    private struct BridgeAbsenceDTO: Decodable {
        let id: String
        let startISO: String
        let endISO: String
        let justified: Bool
        let hoursMissed: Int
        let minutesMissed: Int
        let reason: String?
    }

    private struct BridgeDelayDTO: Decodable {
        let id: String
        let dateISO: String
        let minutes: Int
        let justified: Bool
        let reason: String?
    }

    private struct BridgeObservationDTO: Decodable {
        let id: String
        let dateISO: String
        let name: String
        let subject: String?
        let reason: String?
    }

    private struct BridgeNotebookDTO: Decodable {
        let absences: [BridgeAbsenceDTO]
        let delays: [BridgeDelayDTO]
        let observations: [BridgeObservationDTO]
    }

    private struct BridgeDiscussionDTO: Decodable {
        let id: String
        let subject: String
        let creator: String
        let dateISO: String
        let unreadCount: Int
        let messageCount: Int
        let closed: Bool
    }

    private struct BridgeDiscussionMessageDTO: Decodable {
        let id: String
        let author: String
        let isMe: Bool
        let dateISO: String
        let content: String
        let attachments: [AttachmentItem]?
    }

    private struct BridgeNewsDTO: Decodable {
        let id: String
        let title: String
        let author: String
        let category: String?
        let dateISO: String
        let read: Bool
        let content: String
        let attachments: [AttachmentItem]?
    }

    private struct BridgeMenuDayDTO: Decodable {
        let id: String
        let dateISO: String
        let lunch: [MealSectionItem]
        let dinner: [MealSectionItem]
    }

    private struct BridgeMenusDTO: Decodable {
        let days: [BridgeMenuDayDTO]
    }

    private struct BridgeResponse: Decodable {
        let ok: Bool
        let error: String?
        let url: String?
        let weekLabels: [String: String]?
        let credentials: SavedCredentials?
        let courses: [BridgeCourseDTO]?
        let assignments: [BridgeAssignmentDTO]?
        let resources: [BridgeResourceDTO]?
        let periods: [PeriodInfo]?
        let selectedPeriodID: String?
        let overview: BridgeGradesOverviewDTO?
        let notebookData: BridgeNotebookDTO?
        let discussions: [BridgeDiscussionDTO]?
        let news: [BridgeNewsDTO]?
        let messages: [BridgeDiscussionMessageDTO]?
        let menusData: BridgeMenusDTO?
    }

    private var workerProcess: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stdoutBuffer = Data()

    deinit {
        workerProcess?.terminate()
    }

    func loginWithQRCode(payload: QRCodePayload, pin: String, deviceUUID: String) async throws -> SavedCredentials {
        let request = BridgeLoginRequest(qr: payload, pin: pin, deviceUUID: deviceUUID)
        let response = try await sendRequest(request)
        guard response.ok, let credentials = response.credentials else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Échec de connexion par QR Code.")
        }
        return credentials
    }

    func fetchTimetableRange(credentials: SavedCredentials, fromDate: Date, toDate: Date) async throws -> (SavedCredentials, [CourseItem], [String: String]) {
        let endOfDay = Calendar(identifier: .iso8601).date(bySettingHour: 23, minute: 59, second: 59, of: toDate) ?? toDate

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let request = BridgeTimetableRequest(
            credentials: credentials,
            fromISO: iso.string(from: fromDate),
            toISO: iso.string(from: endOfDay)
        )
        let response = try await sendRequest(request)
        guard response.ok, let updated = response.credentials else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de charger l'emploi du temps.")
        }

        let courses: [CourseItem] = (response.courses ?? []).compactMap { dto in
            guard let start = parseISO(dto.startISO),
                  let end = parseISO(dto.endISO) else { return nil }
            return CourseItem(
                id: dto.id,
                subject: dto.subject,
                teacher: dto.teacher,
                room: dto.room,
                groups: dto.groups ?? [],
                startDate: start,
                endDate: end,
                colorHex: dto.colorHex,
                status: dto.status,
                isCancelled: dto.isCancelled,
                isModified: dto.isModified,
                isOuting: dto.isOuting,
                memo: dto.memo
            )
        }.sorted { $0.startDate < $1.startDate }

        return (updated, courses, response.weekLabels ?? [:])
    }

    func fetchAssignments(credentials: SavedCredentials) async throws -> (SavedCredentials, [AssignmentItem]) {
        let response = try await sendRequest(BridgeCredentialsRequest(action: "assignments", credentials: credentials))
        guard response.ok, let updated = response.credentials else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de charger les devoirs.")
        }

        let items: [AssignmentItem] = (response.assignments ?? []).compactMap { dto in
            guard let deadline = parseISO(dto.deadlineISO) else { return nil }
            return AssignmentItem(
                id: dto.id,
                subject: dto.subject,
                description: dto.description,
                colorHex: dto.colorHex,
                done: dto.done,
                deadline: deadline,
                difficulty: dto.difficulty,
                lengthMinutes: dto.lengthMinutes,
                attachments: dto.attachments ?? []
            )
        }.sorted { $0.deadline < $1.deadline }

        return (updated, items)
    }

    func fetchResources(credentials: SavedCredentials) async throws -> (SavedCredentials, [LessonResourceItem]) {
        let response = try await sendRequest(BridgeCredentialsRequest(action: "resources", credentials: credentials))
        guard response.ok, let updated = response.credentials else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de charger les contenus de cours.")
        }

        let items: [LessonResourceItem] = (response.resources ?? []).compactMap { dto in
            guard let start = parseISO(dto.startISO),
                  let end = parseISO(dto.endISO) else { return nil }
            let contents = dto.contents.map { c in
                ResourceContentItem(
                    id: c.id,
                    title: c.title,
                    description: c.description,
                    attachments: c.attachments ?? []
                )
            }
            return LessonResourceItem(
                id: dto.id,
                subject: dto.subject,
                colorHex: dto.colorHex,
                startDate: start,
                endDate: end,
                teachers: dto.teachers,
                groups: dto.groups,
                contents: contents
            )
        }.sorted { $0.startDate > $1.startDate }

        return (updated, items)
    }

    func setAssignmentDone(credentials: SavedCredentials, assignmentID: String, done: Bool) async throws {
        let response = try await sendRequest(
            BridgeAssignmentStatusRequest(credentials: credentials, assignmentID: assignmentID, done: done)
        )
        guard response.ok else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de mettre à jour le devoir.")
        }
    }

    func fetchGrades(credentials: SavedCredentials, periodID: String?) async throws -> (SavedCredentials, GradesSnapshot) {
        let response = try await sendRequest(
            BridgePeriodRequest(action: "grades", credentials: credentials, periodID: periodID)
        )
        guard response.ok, let updated = response.credentials, let ov = response.overview else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de charger les notes.")
        }

        let subjectAverages = ov.subjectAverages.map { sa in
            SubjectAverageItem(
                id: sa.id,
                subject: sa.subject,
                colorHex: sa.colorHex,
                studentDisplay: sa.studentDisplay,
                studentNumeric: sa.studentNumeric,
                classDisplay: sa.classDisplay,
                outOfDisplay: sa.outOfDisplay,
                outOfNumeric: sa.outOfNumeric
            )
        }

        let grades: [GradeItem] = ov.grades.compactMap { g in
            guard let date = parseISO(g.dateISO) else { return nil }
            return GradeItem(
                id: g.id,
                subject: g.subject,
                colorHex: g.colorHex,
                comment: g.comment,
                valueDisplay: g.valueDisplay,
                valueNumeric: g.valueNumeric,
                outOfDisplay: g.outOfDisplay,
                outOfNumeric: g.outOfNumeric,
                classAverageDisplay: g.classAverageDisplay,
                minDisplay: g.minDisplay,
                maxDisplay: g.maxDisplay,
                coefficient: g.coefficient,
                date: date,
                isBonus: g.isBonus
            )
        }

        let snapshot = GradesSnapshot(
            periods: response.periods ?? [],
            selectedPeriodID: response.selectedPeriodID,
            overallAverage: ov.overallAverage,
            classAverage: ov.classAverage,
            subjectAverages: subjectAverages,
            grades: grades
        )
        return (updated, snapshot)
    }

    func fetchGradebookPDF(credentials: SavedCredentials, periodID: String?) async throws -> URL {
        let response = try await sendRequest(
            BridgePeriodRequest(action: "gradebook_pdf", credentials: credentials, periodID: periodID)
        )
        guard response.ok, let raw = response.url, let url = URL(string: raw) else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Bulletin PDF indisponible pour cette période.")
        }
        return url
    }

    func fetchNotebook(credentials: SavedCredentials, periodID: String?) async throws -> (SavedCredentials, NotebookSnapshot) {
        let response = try await sendRequest(
            BridgePeriodRequest(action: "notebook", credentials: credentials, periodID: periodID)
        )
        guard response.ok, let updated = response.credentials, let nb = response.notebookData else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de charger la vie scolaire.")
        }

        let absences: [AbsenceItem] = nb.absences.compactMap { a in
            guard let start = parseISO(a.startISO), let end = parseISO(a.endISO) else { return nil }
            return AbsenceItem(
                id: a.id,
                startDate: start,
                endDate: end,
                justified: a.justified,
                hoursMissed: a.hoursMissed,
                minutesMissed: a.minutesMissed,
                reason: a.reason
            )
        }

        let delays: [DelayItem] = nb.delays.compactMap { d in
            guard let date = parseISO(d.dateISO) else { return nil }
            return DelayItem(
                id: d.id,
                date: date,
                minutes: d.minutes,
                justified: d.justified,
                reason: d.reason
            )
        }

        let observations: [ObservationItem] = nb.observations.compactMap { o in
            guard let date = parseISO(o.dateISO) else { return nil }
            return ObservationItem(
                id: o.id,
                date: date,
                name: o.name,
                subject: o.subject,
                reason: o.reason
            )
        }

        let snapshot = NotebookSnapshot(
            periods: response.periods ?? [],
            selectedPeriodID: response.selectedPeriodID,
            absences: absences,
            delays: delays,
            observations: observations
        )
        return (updated, snapshot)
    }

    func fetchMessages(credentials: SavedCredentials) async throws -> (SavedCredentials, MessagesSnapshot) {
        let response = try await sendRequest(BridgeCredentialsRequest(action: "messages", credentials: credentials))
        guard response.ok, let updated = response.credentials else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de charger les messages.")
        }

        let discussions: [DiscussionSummary] = (response.discussions ?? []).compactMap { d in
            guard let date = parseISO(d.dateISO) else { return nil }
            return DiscussionSummary(
                id: d.id,
                subject: d.subject,
                creator: d.creator,
                date: date,
                unreadCount: d.unreadCount,
                messageCount: d.messageCount,
                closed: d.closed
            )
        }

        let news: [NewsEntry] = (response.news ?? []).compactMap { n in
            guard let date = parseISO(n.dateISO) else { return nil }
            return NewsEntry(
                id: n.id,
                title: n.title,
                author: n.author,
                category: n.category,
                date: date,
                read: n.read,
                content: n.content,
                attachments: n.attachments ?? []
            )
        }

        return (updated, MessagesSnapshot(discussions: discussions, news: news))
    }

    func fetchDiscussionMessages(credentials: SavedCredentials, discussionID: String) async throws -> [DiscussionMessageItem] {
        let response = try await sendRequest(
            BridgeDiscussionMessagesRequest(credentials: credentials, discussionID: discussionID)
        )
        guard response.ok else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de lire la discussion.")
        }
        return (response.messages ?? []).compactMap { m in
            guard let date = parseISO(m.dateISO) else { return nil }
            return DiscussionMessageItem(
                id: m.id,
                author: m.author,
                isMe: m.isMe,
                date: date,
                content: m.content,
                attachments: m.attachments ?? []
            )
        }
    }

    func sendDiscussionMessage(credentials: SavedCredentials, discussionID: String, content: String) async throws {
        let response = try await sendRequest(
            BridgeDiscussionSendRequest(credentials: credentials, discussionID: discussionID, content: content)
        )
        guard response.ok else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible d'envoyer le message.")
        }
    }

    func markNewsRead(credentials: SavedCredentials, newsID: String) async throws {
        let response = try await sendRequest(
            BridgeNewsReadRequest(credentials: credentials, newsID: newsID)
        )
        guard response.ok else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de marquer comme lu.")
        }
    }

    func fetchMenus(credentials: SavedCredentials, date: Date) async throws -> (SavedCredentials, MenusSnapshot) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let response = try await sendRequest(
            BridgeMenusRequest(credentials: credentials, dateISO: iso.string(from: date))
        )
        guard response.ok, let updated = response.credentials else {
            throw PronoteClientError.authenticationFailed(response.error ?? "Impossible de charger le menu de la cantine.")
        }
        let days: [MenuDayItem] = (response.menusData?.days ?? []).compactMap { d in
            guard let date = parseISO(d.dateISO) else { return nil }
            return MenuDayItem(id: d.id, date: date, lunch: d.lunch, dinner: d.dinner)
        }.sorted { $0.date < $1.date }

        return (updated, MenusSnapshot(days: days))
    }

    func logout() async {
        guard let process = workerProcess, process.isRunning else {
            resetWorker()
            return
        }
        _ = try? await sendRequest(BridgeLogoutRequest())
    }

    private func parseISO(_ value: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFrac.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private func ensureWorkerRunning() throws -> (FileHandle, FileHandle) {
        if let process = workerProcess, process.isRunning,
           let stdinHandle, let stdoutHandle {
            return (stdinHandle, stdoutHandle)
        }

        resetWorker()

        let nodeURL = try resolveNodeExecutable()
        let scriptURL = try resolveBridgeScript()

        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = scriptURL.deletingLastPathComponent()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        self.workerProcess = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stdoutBuffer = Data()

        return (stdinPipe.fileHandleForWriting, stdoutPipe.fileHandleForReading)
    }

    private func resetWorker() {
        if let process = workerProcess, process.isRunning {
            process.terminate()
        }
        workerProcess = nil
        stdinHandle = nil
        stdoutHandle = nil
        stdoutBuffer = Data()
    }

    private func sendRequest<T: Encodable>(_ payload: T) async throws -> BridgeResponse {
        let (stdin, stdout) = try ensureWorkerRunning()
        var lineData = try JSONEncoder().encode(payload)
        lineData.append(0x0A)

        let payloadData = lineData
        let existingBuffer = self.stdoutBuffer
        let (lineResult, remainingBuffer): (Data?, Data) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                stdin.write(payloadData)
                var buffer = existingBuffer
                while true {
                    if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                        let line = buffer.subdata(in: 0..<newlineIndex)
                        let rest = buffer.subdata(in: (newlineIndex + 1)..<buffer.count)
                        continuation.resume(returning: (line, rest))
                        return
                    }
                    let chunk = stdout.availableData
                    if chunk.isEmpty {
                        continuation.resume(returning: (nil, Data()))
                        return
                    }
                    buffer.append(chunk)
                }
            }
        }

        self.stdoutBuffer = remainingBuffer

        guard let lineResult else {
            resetWorker()
            throw PronoteClientError.processFailed("Le worker Pawnote s'est arrêté de façon inattendue.")
        }

        do {
            return try JSONDecoder().decode(BridgeResponse.self, from: lineResult)
        } catch {
            throw PronoteClientError.invalidResponse
        }
    }

    private func resolveBridgeScript() throws -> URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("bridge/bridge.mjs"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let devFallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Codes/pronote-native/bridge/bridge.mjs")
        if FileManager.default.fileExists(atPath: devFallback.path) {
            return devFallback
        }

        throw PronoteClientError.bridgeNotFound
    }

    private func resolveNodeExecutable() throws -> URL {
        let fm = FileManager.default
        var candidates: [String] = []

        let nvmDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir.path) {
            for version in versions.sorted().reversed() {
                candidates.append(nvmDir.appendingPathComponent(version).appendingPathComponent("bin/node").path)
            }
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ])

        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        throw PronoteClientError.nodeNotFound
    }
}

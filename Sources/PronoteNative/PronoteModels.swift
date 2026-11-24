import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case home
    case timetable
    case assignments
    case grades
    case notebook
    case messages
    case menus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Accueil"
        case .timetable: return "Emploi du temps"
        case .assignments: return "Cahier de textes"
        case .grades: return "Notes"
        case .notebook: return "Vie scolaire"
        case .messages: return "Messages & Infos"
        case .menus: return "Cantine"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .timetable: return "calendar"
        case .assignments: return "book.closed"
        case .grades: return "chart.bar.xaxis"
        case .notebook: return "person.text.rectangle"
        case .messages: return "tray.full"
        case .menus: return "fork.knife"
        }
    }
}

struct QRCodePayload: Codable, Sendable {
    let url: String
    let login: String
    let jeton: String
}

struct SavedCredentials: Codable, Equatable, Sendable {
    var baseURL: String
    var username: String
    var token: String
    var deviceUUID: String
    var accountKind: Int
    var navigatorIdentifier: String?
    var studentName: String
    var schoolName: String

    init(
        baseURL: String,
        username: String,
        token: String,
        deviceUUID: String,
        accountKind: Int = 6,
        navigatorIdentifier: String? = nil,
        studentName: String,
        schoolName: String
    ) {
        self.baseURL = baseURL
        self.username = username
        self.token = token
        self.deviceUUID = deviceUUID
        self.accountKind = accountKind
        self.navigatorIdentifier = navigatorIdentifier
        self.studentName = studentName
        self.schoolName = schoolName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        username = try c.decode(String.self, forKey: .username)
        token = try c.decode(String.self, forKey: .token)
        deviceUUID = try c.decode(String.self, forKey: .deviceUUID)
        accountKind = try c.decodeIfPresent(Int.self, forKey: .accountKind) ?? 6
        navigatorIdentifier = try c.decodeIfPresent(String.self, forKey: .navigatorIdentifier)
        studentName = try c.decode(String.self, forKey: .studentName)
        schoolName = try c.decodeIfPresent(String.self, forKey: .schoolName) ?? ""
    }
}

struct AttachmentItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let url: String
    let kind: Int // 0 = Link, 1 = File
}

struct CourseItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let subject: String
    let teacher: String?
    let room: String?
    let groups: [String]
    let startDate: Date
    let endDate: Date
    let colorHex: String?
    let status: String?
    let isCancelled: Bool
    let isModified: Bool
    let isOuting: Bool
    let memo: String?

    init(
        id: String,
        subject: String,
        teacher: String?,
        room: String?,
        groups: [String] = [],
        startDate: Date,
        endDate: Date,
        colorHex: String?,
        status: String?,
        isCancelled: Bool,
        isModified: Bool,
        isOuting: Bool,
        memo: String?
    ) {
        self.id = id
        self.subject = subject
        self.teacher = teacher
        self.room = room
        self.groups = groups
        self.startDate = startDate
        self.endDate = endDate
        self.colorHex = colorHex
        self.status = status
        self.isCancelled = isCancelled
        self.isModified = isModified
        self.isOuting = isOuting
        self.memo = memo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        subject = try c.decode(String.self, forKey: .subject)
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher)
        room = try c.decodeIfPresent(String.self, forKey: .room)
        groups = try c.decodeIfPresent([String].self, forKey: .groups) ?? []
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        isCancelled = try c.decodeIfPresent(Bool.self, forKey: .isCancelled) ?? false
        isModified = try c.decodeIfPresent(Bool.self, forKey: .isModified) ?? false
        isOuting = try c.decodeIfPresent(Bool.self, forKey: .isOuting) ?? false
        memo = try c.decodeIfPresent(String.self, forKey: .memo)
    }

    var displayColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }

    var timeRangeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: startDate)) – \(fmt.string(from: endDate))"
    }
}

struct AssignmentItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let subject: String
    let description: String
    let colorHex: String?
    var done: Bool
    let deadline: Date
    let difficulty: Int
    let lengthMinutes: Int?
    let attachments: [AttachmentItem]

    init(
        id: String,
        subject: String,
        description: String,
        colorHex: String?,
        done: Bool,
        deadline: Date,
        difficulty: Int,
        lengthMinutes: Int?,
        attachments: [AttachmentItem] = []
    ) {
        self.id = id
        self.subject = subject
        self.description = description
        self.colorHex = colorHex
        self.done = done
        self.deadline = deadline
        self.difficulty = difficulty
        self.lengthMinutes = lengthMinutes
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        subject = try c.decode(String.self, forKey: .subject)
        description = try c.decode(String.self, forKey: .description)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        done = try c.decode(Bool.self, forKey: .done)
        deadline = try c.decode(Date.self, forKey: .deadline)
        difficulty = try c.decodeIfPresent(Int.self, forKey: .difficulty) ?? 0
        lengthMinutes = try c.decodeIfPresent(Int.self, forKey: .lengthMinutes)
        attachments = try c.decodeIfPresent([AttachmentItem].self, forKey: .attachments) ?? []
    }

    var displayColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }
}

struct ResourceContentItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String?
    let description: String
    let attachments: [AttachmentItem]
}

struct LessonResourceItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let subject: String
    let colorHex: String?
    let startDate: Date
    let endDate: Date
    let teachers: [String]
    let groups: [String]
    let contents: [ResourceContentItem]

    var displayColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }
}

struct PeriodInfo: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
}

struct SubjectAverageItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let subject: String
    let colorHex: String?
    let studentDisplay: String
    let studentNumeric: Double?
    let classDisplay: String
    let outOfDisplay: String
    let outOfNumeric: Double

    var displayColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }
}

struct GradeItem: Identifiable, Hashable, Codable, Sendable {
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
    let date: Date
    let isBonus: Bool

    var displayColor: Color {
        if let hex = colorHex, let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }
}

struct GradesSnapshot: Codable, Sendable {
    let periods: [PeriodInfo]
    let selectedPeriodID: String?
    let overallAverage: String?
    let classAverage: String?
    let subjectAverages: [SubjectAverageItem]
    let grades: [GradeItem]
}

struct AbsenceItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let startDate: Date
    let endDate: Date
    let justified: Bool
    let hoursMissed: Int
    let minutesMissed: Int
    let reason: String?
}

struct DelayItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let date: Date
    let minutes: Int
    let justified: Bool
    let reason: String?
}

struct ObservationItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let date: Date
    let name: String
    let subject: String?
    let reason: String?
}

struct NotebookSnapshot: Codable, Sendable {
    let periods: [PeriodInfo]
    let selectedPeriodID: String?
    let absences: [AbsenceItem]
    let delays: [DelayItem]
    let observations: [ObservationItem]
}

struct DiscussionSummary: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let subject: String
    let creator: String
    let date: Date
    let unreadCount: Int
    let messageCount: Int
    let closed: Bool
}

struct DiscussionMessageItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let author: String
    let isMe: Bool
    let date: Date
    let content: String
    let attachments: [AttachmentItem]

    init(id: String, author: String, isMe: Bool, date: Date, content: String, attachments: [AttachmentItem] = []) {
        self.id = id
        self.author = author
        self.isMe = isMe
        self.date = date
        self.content = content
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        author = try c.decode(String.self, forKey: .author)
        isMe = try c.decode(Bool.self, forKey: .isMe)
        date = try c.decode(Date.self, forKey: .date)
        content = try c.decode(String.self, forKey: .content)
        attachments = try c.decodeIfPresent([AttachmentItem].self, forKey: .attachments) ?? []
    }
}

struct NewsEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let title: String
    let author: String
    let category: String?
    let date: Date
    var read: Bool
    let content: String
    let attachments: [AttachmentItem]

    init(id: String, title: String, author: String, category: String?, date: Date, read: Bool, content: String, attachments: [AttachmentItem] = []) {
        self.id = id
        self.title = title
        self.author = author
        self.category = category
        self.date = date
        self.read = read
        self.content = content
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        date = try c.decode(Date.self, forKey: .date)
        read = try c.decode(Bool.self, forKey: .read)
        content = try c.decode(String.self, forKey: .content)
        attachments = try c.decodeIfPresent([AttachmentItem].self, forKey: .attachments) ?? []
    }
}

struct MessagesSnapshot: Codable, Sendable {
    var discussions: [DiscussionSummary]
    var news: [NewsEntry]
}

struct FoodDishItem: Identifiable, Hashable, Codable, Sendable {
    var id: String { name + labels.joined() }
    let name: String
    let labels: [String]
}

struct MealSectionItem: Identifiable, Hashable, Codable, Sendable {
    var id: String { category }
    let category: String
    let dishes: [FoodDishItem]
}

struct MenuDayItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let date: Date
    let lunch: [MealSectionItem]
    let dinner: [MealSectionItem]
}

struct MenusSnapshot: Codable, Sendable {
    let days: [MenuDayItem]
}

struct SectionCachePayload: Codable, Sendable {
    var assignments: [AssignmentItem]?
    var resources: [LessonResourceItem]?
    var grades: GradesSnapshot?
    var notebook: NotebookSnapshot?
    var messages: MessagesSnapshot?
    var menus: MenusSnapshot?
    var stickyNote: String?
    var weekLabels: [String: String]?
    var lastFetched: [String: Date]?
    var rateLimitUntil: Date?
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6, let rgb = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

enum CredentialsStore {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PronoteNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("credentials.json")
    }

    static func load() -> SavedCredentials? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SavedCredentials.self, from: data)
    }

    static func save(_ credentials: SavedCredentials) {
        if let data = try? JSONEncoder().encode(credentials) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum TimetableCacheStore {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PronoteNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("timetable-cache.json")
    }

    static func weekKey(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    static func load() -> [String: [CourseItem]] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [CourseItem]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    static func save(_ cache: [String: [CourseItem]]) {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum SectionCacheStore {
    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("PronoteNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("section-cache.json")
    }

    static func load() -> SectionCachePayload {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(SectionCachePayload.self, from: data) else {
            return SectionCachePayload()
        }
        return decoded
    }

    static func save(_ payload: SectionCachePayload) {
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

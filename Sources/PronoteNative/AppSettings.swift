import AppKit
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
enum Haptics {
    static func play(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        let enabled = UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }

    @Published var invertTimetableSwipe: Bool {
        didSet { UserDefaults.standard.set(invertTimetableSwipe, forKey: "invertTimetableSwipe") }
    }

    @Published var startSectionRaw: String {
        didSet { UserDefaults.standard.set(startSectionRaw, forKey: "startSectionRaw") }
    }

    @Published var appearanceMode: String {
        didSet { UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode") }
    }

    @Published var glassBackgroundEnabled: Bool {
        didSet { UserDefaults.standard.set(glassBackgroundEnabled, forKey: "glassBackgroundEnabled") }
    }

    @Published var hourHeightPreset: String {
        didSet { UserDefaults.standard.set(hourHeightPreset, forKey: "hourHeightPreset") }
    }

    @Published var alwaysShowSaturday: Bool {
        didSet { UserDefaults.standard.set(alwaysShowSaturday, forKey: "alwaysShowSaturday") }
    }

    @Published var showDinnerMenuOnHome: Bool {
        didSet { UserDefaults.standard.set(showDinnerMenuOnHome, forKey: "showDinnerMenuOnHome") }
    }

    @Published var cacheTTLMinutes: Int {
        didSet { UserDefaults.standard.set(cacheTTLMinutes, forKey: "cacheTTLMinutesV3") }
    }

    @Published var menuBarEnabled: Bool {
        didSet { UserDefaults.standard.set(menuBarEnabled, forKey: "menuBarEnabled") }
    }

    @Published var menuBarShowNextCourseText: Bool {
        didSet { UserDefaults.standard.set(menuBarShowNextCourseText, forKey: "menuBarShowNextCourseText") }
    }

    @Published var menuBarShowCourseName: Bool {
        didSet { UserDefaults.standard.set(menuBarShowCourseName, forKey: "menuBarShowCourseName") }
    }

    @Published var keepInDockWhenClosed: Bool {
        didSet { UserDefaults.standard.set(keepInDockWhenClosed, forKey: "keepInDockWhenClosed") }
    }

    @Published var launchAtLogin: Bool

    @Published var autoRefreshEnabled: Bool {
        didSet { UserDefaults.standard.set(autoRefreshEnabled, forKey: "autoRefreshEnabled") }
    }

    @Published var refreshTimetableNotebookMinutes: Int {
        didSet {
            let clamped = max(15, refreshTimetableNotebookMinutes)
            if clamped != refreshTimetableNotebookMinutes {
                refreshTimetableNotebookMinutes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "refreshTimetableNotebookMinutes")
        }
    }

    @Published var refreshGradesMinutes: Int {
        didSet {
            let clamped = max(15, refreshGradesMinutes)
            if clamped != refreshGradesMinutes {
                refreshGradesMinutes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "refreshGradesMinutes")
        }
    }

    @Published var refreshAssignmentsMinutes: Int {
        didSet {
            let clamped = max(15, refreshAssignmentsMinutes)
            if clamped != refreshAssignmentsMinutes {
                refreshAssignmentsMinutes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "refreshAssignmentsMinutes")
        }
    }

    @Published var refreshMessagesMinutes: Int {
        didSet {
            let clamped = max(15, refreshMessagesMinutes)
            if clamped != refreshMessagesMinutes {
                refreshMessagesMinutes = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: "refreshMessagesMinutes")
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    @Published var notifyTimetableChanges: Bool {
        didSet { UserDefaults.standard.set(notifyTimetableChanges, forKey: "notifyTimetableChanges") }
    }

    @Published var notifyNewGrades: Bool {
        didSet { UserDefaults.standard.set(notifyNewGrades, forKey: "notifyNewGrades") }
    }

    @Published var notifyHideGradeValue: Bool {
        didSet { UserDefaults.standard.set(notifyHideGradeValue, forKey: "notifyHideGradeValue") }
    }

    @Published var notifyNewAssignments: Bool {
        didSet { UserDefaults.standard.set(notifyNewAssignments, forKey: "notifyNewAssignments") }
    }

    @Published var notifyNewMessages: Bool {
        didSet { UserDefaults.standard.set(notifyNewMessages, forKey: "notifyNewMessages") }
    }

    @Published var notifyNewAbsences: Bool {
        didSet { UserDefaults.standard.set(notifyNewAbsences, forKey: "notifyNewAbsences") }
    }

    init() {
        let d = UserDefaults.standard
        self.hapticsEnabled = d.object(forKey: "hapticsEnabled") as? Bool ?? true
        self.invertTimetableSwipe = d.object(forKey: "invertTimetableSwipe") as? Bool ?? false
        self.startSectionRaw = d.string(forKey: "startSectionRaw") ?? AppSection.home.rawValue
        self.appearanceMode = d.string(forKey: "appearanceMode") ?? "system"
        self.glassBackgroundEnabled = d.object(forKey: "glassBackgroundEnabled") as? Bool ?? true
        self.hourHeightPreset = d.string(forKey: "hourHeightPreset") ?? "normal"
        self.alwaysShowSaturday = d.object(forKey: "alwaysShowSaturday") as? Bool ?? false
        self.showDinnerMenuOnHome = d.object(forKey: "showDinnerMenuOnHome") as? Bool ?? false
        let storedTTL = d.integer(forKey: "cacheTTLMinutesV3")
        self.cacheTTLMinutes = storedTTL > 0 ? storedTTL : 10
        self.menuBarEnabled = d.object(forKey: "menuBarEnabled") as? Bool ?? true
        self.menuBarShowNextCourseText = d.object(forKey: "menuBarShowNextCourseText") as? Bool ?? true
        self.menuBarShowCourseName = d.object(forKey: "menuBarShowCourseName") as? Bool ?? false
        self.keepInDockWhenClosed = d.object(forKey: "keepInDockWhenClosed") as? Bool ?? false
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.autoRefreshEnabled = d.object(forKey: "autoRefreshEnabled") as? Bool ?? true
        let tt = d.integer(forKey: "refreshTimetableNotebookMinutes")
        self.refreshTimetableNotebookMinutes = max(15, tt > 0 ? tt : 15)
        let gr = d.integer(forKey: "refreshGradesMinutes")
        self.refreshGradesMinutes = max(15, gr > 0 ? gr : 15)
        let hw = d.integer(forKey: "refreshAssignmentsMinutes")
        self.refreshAssignmentsMinutes = max(15, hw > 0 ? hw : 30)
        let msg = d.integer(forKey: "refreshMessagesMinutes")
        self.refreshMessagesMinutes = max(15, msg > 0 ? msg : 60)
        self.notificationsEnabled = d.object(forKey: "notificationsEnabled") as? Bool ?? false
        self.notifyTimetableChanges = d.object(forKey: "notifyTimetableChanges") as? Bool ?? true
        self.notifyNewGrades = d.object(forKey: "notifyNewGrades") as? Bool ?? true
        self.notifyHideGradeValue = d.object(forKey: "notifyHideGradeValue") as? Bool ?? false
        self.notifyNewAssignments = d.object(forKey: "notifyNewAssignments") as? Bool ?? true
        self.notifyNewMessages = d.object(forKey: "notifyNewMessages") as? Bool ?? true
        self.notifyNewAbsences = d.object(forKey: "notifyNewAbsences") as? Bool ?? true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Ignore registration errors on unsigned/dev builds
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var startSection: AppSection {
        AppSection(rawValue: startSectionRaw) ?? .home
    }

    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var hourHeight: CGFloat {
        switch hourHeightPreset {
        case "compact": return 54
        case "large": return 84
        default: return 68
        }
    }

    var cacheTTLSeconds: TimeInterval {
        TimeInterval(cacheTTLMinutes * 60)
    }
}

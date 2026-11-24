import AppKit
import Foundation
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

    @Published var cacheTTLMinutes: Int {
        didSet { UserDefaults.standard.set(cacheTTLMinutes, forKey: "cacheTTLMinutesV3") }
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
        let storedTTL = d.integer(forKey: "cacheTTLMinutesV3")
        self.cacheTTLMinutes = storedTTL > 0 ? storedTTL : 10
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

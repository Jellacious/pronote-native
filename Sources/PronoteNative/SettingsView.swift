import AppKit
import SwiftUI
import UserNotifications

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case refresh
    case notifications
    case appearance
    case account
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Général"
        case .refresh: return "Actualisation"
        case .notifications: return "Notifications"
        case .appearance: return "Apparence"
        case .account: return "Compte"
        case .about: return "À propos"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .refresh: return "arrow.clockwise"
        case .notifications: return "bell.badge"
        case .appearance: return "paintbrush"
        case .account: return "person.crop.circle"
        case .about: return "info.circle"
        }
    }

    var badgeColor: Color {
        switch self {
        case .general: return .gray
        case .refresh: return .green
        case .notifications: return .red
        case .appearance: return .purple
        case .account: return .blue
        case .about: return .teal
        }
    }
}

private enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate(String)
    case updateAvailable(version: String, url: URL)
    case failed(String)
}

private struct GitHubReleaseDTO: Decodable {
    let tagName: String
    let htmlURL: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case name
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedTab: SettingsTab = .general
    @State private var updateState: UpdateCheckState = .idle
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                HStack(spacing: 10) {
                    SectionIconBadge(systemImage: tab.systemImage, color: tab.badgeColor)
                    Text(tab.title)
                        .font(.body.weight(.medium))
                }
                .padding(.vertical, 3)
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 185, ideal: 195, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case .general:
                        generalPane
                    case .refresh:
                        refreshPane
                    case .notifications:
                        notificationsPane
                    case .appearance:
                        appearancePane
                    case .account:
                        accountPane
                    case .about:
                        aboutPane
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selectedTab.title)
        }
        .frame(width: 720, height: 520)
    }

    private var generalPane: some View {
        Form {
            Section {
                Picker("Page au démarrage", selection: $settings.startSectionRaw) {
                    ForEach(AppSection.allCases) { section in
                        Text(section.title).tag(section.rawValue)
                    }
                }

                Toggle("Ouvrir à l'ouverture de session", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))

                Toggle("Afficher le menu du soir sur l'accueil", isOn: $settings.showDinnerMenuOnHome)
            }

            Section("Trackpad & Gestes") {
                Toggle("Retour haptique (vibrations)", isOn: $settings.hapticsEnabled)
                    .onChange(of: settings.hapticsEnabled) { _, enabled in
                        if enabled {
                            Haptics.play(.alignment)
                        }
                    }

                Toggle("Inverser le sens du swipe dans l'EDT", isOn: $settings.invertTimetableSwipe)
            }

            Section("Barre des menus") {
                Toggle("Afficher dans la barre des menus", isOn: $settings.menuBarEnabled)
                Toggle("Afficher l'horaire à côté de l'icône", isOn: $settings.menuBarShowNextCourseText)
                    .disabled(!settings.menuBarEnabled)
                Toggle("Afficher le nom du cours", isOn: $settings.menuBarShowCourseName)
                    .disabled(!settings.menuBarEnabled || !settings.menuBarShowNextCourseText)
                Toggle("Garder dans le Dock quand la fenêtre est fermée", isOn: $settings.keepInDockWhenClosed)
                    .disabled(!settings.menuBarEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private let refreshIntervals: [(Int, String)] = [
        (15, "15 min"),
        (30, "30 min"),
        (45, "45 min"),
        (60, "1 heure"),
        (120, "2 heures")
    ]

    private var nextRefreshLabel: String {
        guard let date = viewModel.nextAutoRefreshDate else { return "—" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "EEE HH:mm"
        return df.string(from: date)
    }

    private var refreshPane: some View {
        Form {
            Section("Actualisation automatique") {
                Toggle("Activer l'actualisation automatique", isOn: $settings.autoRefreshEnabled)

                if settings.autoRefreshEnabled {
                    HStack {
                        Text("Prochaine vérification")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(nextRefreshLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section("Fréquences (minimum 15 min)") {
                Picker("EDT & Vie scolaire", selection: $settings.refreshTimetableNotebookMinutes) {
                    ForEach(refreshIntervals, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }

                Picker("Notes", selection: $settings.refreshGradesMinutes) {
                    ForEach(refreshIntervals, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }

                Picker("Devoirs", selection: $settings.refreshAssignmentsMinutes) {
                    ForEach(refreshIntervals, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }

                Picker("Messages & Infos", selection: $settings.refreshMessagesMinutes) {
                    ForEach(refreshIntervals, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
            }
            .disabled(!settings.autoRefreshEnabled)

            Section {
                Text("Créneaux fixes à partir de 07:01 avec une dernière vérification garantie à 19:55 (pause de 20:00 à 07:00). Les messages ne sont pas actualisés le week-end, et un créneau auto est sauté si une actualisation manuelle vient d'avoir lieu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsPane: some View {
        Form {
            Section {
                Toggle("Activer les notifications", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { enabled in
                        settings.notificationsEnabled = enabled
                        if enabled {
                            Task {
                                _ = await NotificationManager.shared.requestAuthorization()
                                notifStatus = await NotificationManager.shared.authorizationStatus()
                            }
                        }
                    }
                ))

                if notifStatus == .denied {
                    Text("Les notifications sont bloquées dans Réglages Système → Notifications → Pronote Native.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Alertes") {
                Toggle("Changements d'emploi du temps", isOn: $settings.notifyTimetableChanges)
                Toggle("Nouvelles notes", isOn: $settings.notifyNewGrades)
                Toggle("Mode anti-spoiler (masquer la valeur de la note)", isOn: $settings.notifyHideGradeValue)
                    .disabled(!settings.notifyNewGrades)
                Toggle("Nouveaux devoirs", isOn: $settings.notifyNewAssignments)
                Toggle("Nouveaux messages et informations", isOn: $settings.notifyNewMessages)
                Toggle("Nouvelles absences et retards", isOn: $settings.notifyNewAbsences)
            }
            .disabled(!settings.notificationsEnabled)

            Section {
                HStack {
                    Spacer()
                    Button("Envoyer une notification de test") {
                        NotificationManager.shared.sendTestNotification()
                    }
                    .disabled(!settings.notificationsEnabled)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            notifStatus = await NotificationManager.shared.authorizationStatus()
        }
    }

    private var appearancePane: some View {
        Form {
            Section("Thème") {
                Picker("Apparence", selection: $settings.appearanceMode) {
                    Text("Système").tag("system")
                    Text("Clair").tag("light")
                    Text("Sombre").tag("dark")
                }

                Toggle("Fond ambiant Liquid Glass", isOn: $settings.glassBackgroundEnabled)
            }

            Section("Emploi du temps") {
                Picker("Hauteur de la grille", selection: $settings.hourHeightPreset) {
                    Text("Compacte").tag("compact")
                    Text("Normale").tag("normal")
                    Text("Grande").tag("large")
                }

                Toggle("Toujours afficher le samedi", isOn: $settings.alwaysShowSaturday)
            }
        }
        .formStyle(.grouped)
    }

    private var accountPane: some View {
        Form {
            if let creds = viewModel.credentials {
                Section("Profil connecté") {
                    HStack(spacing: 14) {
                        Text(initials(from: creds.studentName))
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Circle()
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(creds.studentName)
                                .font(.headline)
                            if !creds.schoolName.isEmpty {
                                Text(creds.schoolName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(URL(string: creds.baseURL)?.host ?? creds.baseURL)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Se déconnecter de Pronote", role: .destructive) {
                        viewModel.logout()
                    }
                }
            } else {
                Section {
                    Text("Aucun compte connecté")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
    }

    private var aboutPane: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pronote Native")
                            .font(.headline)
                        Text("Version \(appVersion) (build \(appBuild))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Client MacOS natif pour Pronote")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Mises à jour") {
                HStack(spacing: 10) {
                    switch updateState {
                    case .idle:
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                        Text("Vérifier si une nouvelle version est disponible sur GitHub.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                        Text("Recherche de mise à jour…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .upToDate:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Vous utilisez la dernière version (v\(appVersion)).")
                            .font(.callout)
                    case .updateAvailable(let version, let url):
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Nouvelle version disponible : \(version)")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Button("Télécharger") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    case .failed(let msg):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Rechercher les mises à jour") {
                        Task { await checkForUpdates() }
                    }
                    .disabled(updateState == .checking)
                }
            }

            Section("Liens") {
                HStack(spacing: 12) {
                    Button("Dépôt GitHub") {
                        if let url = SafeURL.validatedWebURL("https://github.com/Jellacious/pronote-native", requireHTTPS: true) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Voir les releases") {
                        if let url = SafeURL.validatedWebURL("https://github.com/Jellacious/pronote-native/releases", requireHTTPS: true) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @MainActor
    private func checkForUpdates() async {
        updateState = .checking
        guard let apiURL = SafeURL.validatedWebURL("https://api.github.com/repos/Jellacious/pronote-native/releases/latest", requireHTTPS: true) else {
            updateState = .failed("URL de vérification invalide.")
            return
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("PronoteNative", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                updateState = .failed("Réponse réseau invalide.")
                return
            }
            guard http.statusCode == 200 else {
                switch http.statusCode {
                case 404:
                    updateState = .failed("Aucune release publiée pour le moment.")
                case 403:
                    updateState = .failed("Limite API GitHub atteinte, réessaie plus tard.")
                default:
                    updateState = .failed("Erreur serveur (HTTP \(http.statusCode)).")
                }
                return
            }

            let release = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
            if isVersion(release.tagName, newerThan: appVersion) {
                if let url = SafeURL.validatedWebURL(release.htmlURL, requireHTTPS: true),
                   url.host?.lowercased() == "github.com" {
                    updateState = .updateAvailable(version: release.tagName, url: url)
                } else {
                    updateState = .failed("URL de release GitHub invalide.")
                }
            } else {
                updateState = .upToDate(release.tagName)
            }
        } catch {
            updateState = .failed("Impossible de vérifier les mises à jour (réseau indisponible).")
        }
    }

    private func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let parse: (String) -> [Int] = { raw in
            raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let r = parse(remote)
        let l = parse(local)
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }
        return chars.isEmpty ? "P" : String(chars).uppercased()
    }
}

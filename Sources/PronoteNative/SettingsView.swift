import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Général"
        case .appearance: return "Apparence"
        case .account: return "Compte"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .account: return "person.crop.circle"
        }
    }

    var badgeColor: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .purple
        case .account: return .blue
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
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
            .frame(width: 175)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selectedTab.title)
                        .font(.title2.bold())

                    switch selectedTab {
                    case .general:
                        generalPane
                    case .appearance:
                        appearancePane
                    case .account:
                        accountPane
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 590, height: 390)
    }

    private var generalPane: some View {
        Form {
            Section {
                Picker("Page au démarrage", selection: $settings.startSectionRaw) {
                    ForEach(AppSection.allCases) { section in
                        Text(section.title).tag(section.rawValue)
                    }
                }
            }

            Section("Trackpad & Gestes") {
                Toggle("Retour haptique (vibrations)", isOn: $settings.hapticsEnabled)
                    .onChange(of: settings.hapticsEnabled) { _, enabled in
                        if enabled {
                            Haptics.play(.alignment)
                        }
                    }

                HStack {
                    Text("Tester le retour haptique")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Tester") {
                        Haptics.play(.generic)
                    }
                    .disabled(!settings.hapticsEnabled)
                }

                Toggle("Inverser le sens du swipe dans l'EDT", isOn: $settings.invertTimetableSwipe)
            }
        }
        .formStyle(.grouped)
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

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }
        return chars.isEmpty ? "P" : String(chars).uppercased()
    }
}

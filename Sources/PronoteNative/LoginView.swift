import SwiftUI
import UniformTypeIdentifiers

struct LoginView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var qrPayload: QRCodePayload?
    @State private var pin: String = ""
    @State private var scanStatus: String?
    @State private var isDropTargeted: Bool = false
    @State private var showFileImporter: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Pronote Native")
                    .font(.largeTitle.bold())
                Text("Connexion rapide par QR Code Pronote")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 14) {
                Label("1. Récupère ton QR Code", systemImage: "qrcode")
                    .font(.headline)

                Text("Sur Pronote web : clique sur l'icône QR Code en haut à droite (Mon compte → QR Code), choisis un code à 4 chiffres, puis dépose ou colle le QR code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 2, dash: [6])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
                        )

                    VStack(spacing: 10) {
                        if let payload = qrPayload {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title)
                                .foregroundStyle(.green)
                            Text("QR Code détecté !")
                                .font(.headline)
                            Text(payload.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("Glisse l'image du QR Code ici")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button {
                                pasteFromClipboard()
                            } label: {
                                Label("Coller (⌘V)", systemImage: "doc.on.clipboard")
                            }
                            .keyboardShortcut("v", modifiers: .command)

                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Choisir un fichier…", systemImage: "folder")
                            }
                        }
                    }
                    .padding()
                }
                .frame(height: 155)
                .onDrop(of: [.image, .fileURL, .plainText], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }

                if let scanStatus {
                    Text(scanStatus)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Divider()

                Label("2. Code PIN à 4 chiffres", systemImage: "lock.fill")
                    .font(.headline)

                HStack(spacing: 12) {
                    SecureField("Code PIN (4 chiffres)", text: $pin)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .onSubmit {
                            submit()
                        }

                    Button {
                        submit()
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 12)
                        } else {
                            Text("Se connecter")
                                .padding(.horizontal, 12)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(qrPayload == nil || pin.count != 4 || viewModel.isLoading)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 520)
        }
        .padding(32)
        .frame(minWidth: 620, minHeight: 540)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                decodeFile(url)
            }
        }
    }

    private func submit() {
        guard let qrPayload, pin.count == 4 else { return }
        Task {
            await viewModel.loginWithQRCode(payload: qrPayload, pin: pin)
        }
    }

    private func pasteFromClipboard() {
        scanStatus = nil
        do {
            qrPayload = try QRCodeScanner.decodeFromClipboard()
        } catch {
            scanStatus = error.localizedDescription
        }
    }

    private func decodeFile(_ url: URL) {
        scanStatus = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            qrPayload = try QRCodeScanner.decode(url: url)
        } catch {
            scanStatus = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    Task { @MainActor in
                        decodeFile(url)
                    }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data, let image = NSImage(data: data) {
                    Task { @MainActor in
                        scanStatus = nil
                        do {
                            qrPayload = try QRCodeScanner.decode(image: image)
                        } catch {
                            scanStatus = error.localizedDescription
                        }
                    }
                }
            }
            return true
        }
        return false
    }
}

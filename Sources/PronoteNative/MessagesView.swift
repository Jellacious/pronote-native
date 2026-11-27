import SwiftUI

struct MessagesView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var tab: Int = 0 // 0 = Discussions, 1 = Informations
    @State private var selectedDiscussionID: String?
    @State private var selectedNewsID: String?
    @State private var searchText: String = ""
    @State private var showOnlyUnread: Bool = false
    @State private var replyText: String = ""
    @State private var isSending: Bool = false
    @State private var isSendHovered: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.errorMessage {
                SectionErrorBanner(message: error, viewModel: viewModel) {
                    await viewModel.loadMessages(forceRefresh: true)
                }
            }

            if viewModel.isLoading && viewModel.messages == nil {
                Spacer()
                ProgressView("Chargement des messages…")
                Spacer()
            } else if let snapshot = viewModel.messages {
                HSplitView {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            TextField("Rechercher…", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                            Toggle("Non lus", isOn: $showOnlyUnread)
                                .toggleStyle(.checkbox)
                        }
                        .padding(10)
                        Divider()
                        listPane(snapshot)
                    }
                    .frame(minWidth: 270, idealWidth: 320, maxWidth: 390)

                    detailPane(snapshot)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.easeInOut(duration: 0.18), value: selectedDiscussionID)
                        .animation(.easeInOut(duration: 0.18), value: selectedNewsID)
                }
            } else {
                Spacer()
                Text("Aucun message.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .background(AmbientBackground())
        .navigationTitle("Messages & Infos")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Onglet", selection: $tab) {
                    Text("Discussions").tag(0)
                    Text("Informations").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
    }

    @ViewBuilder
    private func listPane(_ snapshot: MessagesSnapshot) -> some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if tab == 0 {
            let items = snapshot.discussions.filter { disc in
                let matchesUnread = !showOnlyUnread || disc.unreadCount > 0
                let matchesQuery = query.isEmpty ||
                    disc.subject.lowercased().contains(query) ||
                    disc.creator.lowercased().contains(query)
                return matchesUnread && matchesQuery
            }

            if items.isEmpty {
                VStack {
                    Spacer()
                    Text("Aucune discussion")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(items, selection: $selectedDiscussionID) { disc in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(disc.subject)
                                .font(.subheadline.weight(disc.unreadCount > 0 ? .bold : .semibold))
                                .lineLimit(1)
                            Spacer()
                            if disc.unreadCount > 0 {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        HStack {
                            Text(disc.creator)
                            Spacer()
                            Text(shortDate(disc.date))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(disc.id)
                }
                .onChange(of: selectedDiscussionID) { _, newID in
                    if let newID, let disc = snapshot.discussions.first(where: { $0.id == newID }) {
                        Task { await viewModel.openDiscussion(disc) }
                    }
                }
            }
        } else {
            let items = snapshot.news.filter { item in
                let matchesUnread = !showOnlyUnread || !item.read
                let matchesQuery = query.isEmpty ||
                    item.title.lowercased().contains(query) ||
                    item.author.lowercased().contains(query)
                return matchesUnread && matchesQuery
            }

            if items.isEmpty {
                VStack {
                    Spacer()
                    Text("Aucune information")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(items, selection: $selectedNewsID) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.title)
                                .font(.subheadline.weight(item.read ? .semibold : .bold))
                                .lineLimit(1)
                            Spacer()
                            if !item.read {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        HStack {
                            Text(item.author)
                            Spacer()
                            Text(shortDate(item.date))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(item.id)
                }
                .onChange(of: selectedNewsID) { _, newID in
                    if let newID, let item = snapshot.news.first(where: { $0.id == newID }), !item.read {
                        Task { await viewModel.markNewsAsRead(item) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailPane(_ snapshot: MessagesSnapshot) -> some View {
        if tab == 0 {
            if let discID = selectedDiscussionID,
               let disc = snapshot.discussions.first(where: { $0.id == discID }) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(disc.subject)
                            .font(.title3.bold())
                        Text(disc.creator)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)

                    Divider()

                    if viewModel.isLoadingDiscussion {
                        Spacer()
                        HStack {
                            Spacer()
                            ProgressView("Chargement des messages…")
                            Spacer()
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(viewModel.selectedDiscussionMessages) { msg in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(msg.author)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(msg.isMe ? Color.accentColor : Color.primary)
                                            Spacer()
                                            Text(dateTime(msg.date))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(msg.content)
                                            .font(.body)
                                            .textSelection(.enabled)

                                        if !msg.attachments.isEmpty {
                                            FlowAttachmentRow(attachments: msg.attachments)
                                        }
                                    }
                                    .padding(12)
                                    .background(
                                        msg.isMe ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                }
                            }
                            .padding(16)
                        }
                    }

                    if !disc.closed {
                        Divider()
                        let canSend = !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
                        HStack(spacing: 8) {
                            TextField("Répondre à la discussion…", text: $replyText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { sendReply(discID: disc.id) }

                            Button {
                                sendReply(discID: disc.id)
                            } label: {
                                if isSending {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Envoyer", systemImage: "paperplane.fill")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canSend)
                            .scaleEffect(isSendHovered && canSend ? 1.03 : 1.0)
                            .brightness(isSendHovered && canSend ? 0.05 : 0)
                            .animation(.easeOut(duration: 0.15), value: isSendHovered)
                            .onHover { isSendHovered = $0 }
                        }
                        .padding(12)
                        .background(.bar)
                    }
                }
                .id(disc.id)
                .transition(.opacity)
            } else {
                Text("Sélectionne une discussion")
                    .foregroundStyle(.secondary)
            }
        } else {
            if let newsID = selectedNewsID,
               let item = snapshot.news.first(where: { $0.id == newsID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.title)
                            .font(.title3.bold())
                        HStack(spacing: 8) {
                            Text(item.author)
                            Text("·")
                            Text(dateTime(item.date))
                            if let cat = item.category {
                                Text("· \(cat)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Divider()

                        Text(item.content.isEmpty ? "Contenu vide." : item.content)
                            .font(.body)
                            .textSelection(.enabled)

                        if !item.attachments.isEmpty {
                            Divider()
                            FlowAttachmentRow(attachments: item.attachments)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(item.id)
                .transition(.opacity)
            } else {
                Text("Sélectionne une information")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sendReply(discID: String) {
        let content = replyText
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true
        Task {
            let ok = await viewModel.sendReply(discussionID: discID, content: content)
            if ok {
                replyText = ""
            }
            isSending = false
        }
    }

    private func shortDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM"
        return df.string(from: date)
    }

    private func dateTime(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM yyyy · HH:mm"
        return df.string(from: date)
    }
}

struct SectionErrorBanner: View {
    let message: String
    @ObservedObject var viewModel: AppViewModel
    let onRetry: () async -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
            Button("Réessayer") {
                Task { await onRetry() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button("Reconnecter") {
                viewModel.logout()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

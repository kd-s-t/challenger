import SwiftUI

struct JoinNotice: Decodable, Identifiable, Hashable {
  let id: String
  let title: String
  let body: String
  let tournamentId: String
  let readAt: String?
  let createdAt: String
}

struct NoticeBell: View {
  @Binding var path: [AuthRoute]
  @State private var notes: [JoinNotice] = []
  @State private var open = false
  @State private var errorMessage: String?

  private let service = TournamentService()

  var body: some View {
    Button {
      open = true
    } label: {
      Image(systemName: notes.contains(where: { $0.readAt == nil }) ? "bell.badge" : "bell")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(Theme.ink)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Notifications")
    .task {
      await reload()
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        await reload()
      }
    }
    .sheet(isPresented: $open) {
      NavigationStack {
        ScreenColumn(kicker: "", title: "Notifications", subtitle: "Join requests, bracket adds, and when a tournament starts.") {
          VStack(alignment: .leading, spacing: 12) {
            if let errorMessage {
              Notice(text: errorMessage, tone: Theme.danger)
            }
            if notes.isEmpty {
              Text("No notifications yet.")
                .font(.system(size: 16))
                .foregroundStyle(Theme.mute)
            } else {
              ForEach(notes) { note in
                Button {
                  Task { await open(note) }
                } label: {
                  noticeRow(note)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close") { open = false }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Mark all as read") {
              Task { await markAll() }
            }
            .disabled(!notes.contains { $0.readAt == nil })
          }
        }
      }
      .presentationDragIndicator(.visible)
      .task { await reload() }
    }
  }

  private func noticeRow(_ note: JoinNotice) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(note.title)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Spacer()
        if note.readAt == nil {
          Circle()
            .fill(Theme.clay)
            .frame(width: 8, height: 8)
        }
      }
      Text(note.body)
        .font(.system(size: 14))
        .foregroundStyle(Theme.mute)
      if let date = VenueClock.parse(note.createdAt) {
        Text(date.formatted(date: .abbreviated, time: .shortened))
          .font(.system(size: 12))
          .foregroundStyle(Theme.mute)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    }
  }

  private func reload() async {
    do {
      notes = try await service.notices()
      errorMessage = nil
    } catch {
      if isCancel(error) { return }
      errorMessage = error.localizedDescription
    }
  }

  private func markAll() async {
    do {
      try await service.readNotices(all: true, id: nil)
      await reload()
    } catch {
      if isCancel(error) { return }
      errorMessage = error.localizedDescription
    }
  }

  private func open(_ note: JoinNotice) async {
    do {
      if note.readAt == nil {
        try await service.readNotices(all: false, id: note.id)
      }
      open = false
      path.append(.draw(note.tournamentId, true))
      await reload()
    } catch {
      if isCancel(error) { return }
      errorMessage = error.localizedDescription
    }
  }

  private func isCancel(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    let ns = error as NSError
    return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
  }
}

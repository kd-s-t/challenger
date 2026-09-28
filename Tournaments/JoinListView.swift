import SwiftUI

struct JoinListView: View {
  @Environment(AuthStore.self) private var auth
  @Binding var path: [AuthRoute]
  var refreshTick = 0
  @State private var rows: [TournamentItem] = []
  @State private var query = ""
  @State private var year: Int?
  @State private var viewingOwner: OwnerRef?
  @State private var showProfile = false
  @State private var errorMessage: String?
  @State private var loading = true

  private let service = TournamentService()

  var body: some View {
    ScreenColumn(
      kicker: "",
      title: "Join",
      subtitle: "All tournaments.",
      refresh: { await load() }
    ) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(Theme.mute)
          TextField("Search", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        }
        Menu {
          Button {
            year = nil
          } label: {
            if year == nil {
              Label("All", systemImage: "checkmark")
            } else {
              Text("All")
            }
          }
          ForEach(years, id: \.self) { value in
            Button {
              year = value
            } label: {
              if year == value {
                Label(String(value), systemImage: "checkmark")
              } else {
                Text(String(value))
              }
            }
          }
        } label: {
          HStack {
            Text(year.map(String.init) ?? "Year")
              .font(.system(size: 16))
              .foregroundStyle(Theme.ink)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Theme.mute)
          }
          .padding(.horizontal, 14)
          .frame(height: 54)
          .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(Theme.line, lineWidth: 1)
          }
        }
        if loading {
          ProgressView()
            .tint(Theme.clay)
        } else if let errorMessage {
          Notice(text: errorMessage, tone: Theme.danger)
        } else if shown.isEmpty {
          Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && year == nil ? "No tournaments to join." : "No matches.")
            .font(.system(size: 16))
            .foregroundStyle(Theme.mute)
        } else {
          let columns = UIDevice.current.userInterfaceIdiom == .pad
            ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
            : [GridItem(.flexible())]
          LazyVGrid(columns: columns, spacing: 14) {
            ForEach(shown) { item in
              Button {
                path.append(.draw(item.id, false))
              } label: {
                joinRow(item)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle("")
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        NoticeBell(path: $path)
        profileButton
      }
    }
    .sheet(isPresented: $showProfile) {
      NavigationStack {
        AccountView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { showProfile = false }
            }
          }
      }
      .presentationDragIndicator(.visible)
    }
    .onAppear { Task { await load() } }
    .onChange(of: path.isEmpty) { _, empty in
      if empty { Task { await load() } }
    }
    .onChange(of: refreshTick) { _, _ in
      Task { await load() }
    }
    .onChange(of: auth.isBootstrapping) { _, bootstrapping in
      if !bootstrapping {
        Task { await load() }
      }
    }
    .onChange(of: auth.user?.id) { _, _ in
      Task { await load() }
    }
    .sheet(item: $viewingOwner) { owner in
      OwnerSheet(owner: owner)
    }
  }

  private var years: [Int] {
    Set(rows.compactMap(startYear)).sorted(by: >)
  }

  private func startYear(_ item: TournamentItem) -> Int? {
    guard let startsAt = item.startsAt, let date = VenueClock.parse(startsAt) else { return nil }
    return Calendar(identifier: .gregorian).dateComponents(in: VenueClock.zone, from: date).year
  }

  private var profileButton: some View {
    Button {
      showProfile = true
    } label: {
      ZStack {
        if let url = auth.user?.avatarURL {
          AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
          } placeholder: {
            ProgressView()
          }
        } else {
          Image(systemName: "person.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Theme.mute)
        }
      }
      .frame(width: 40, height: 40)
      .background(Theme.card)
      .clipShape(Circle())
      .overlay {
        Circle().stroke(Theme.line, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Profile")
  }

  private var shown: [TournamentItem] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return rows.filter { item in
      if let year, startYear(item) != year { return false }
      if needle.isEmpty { return true }
      if item.name.localizedStandardContains(needle) { return true }
      if let venue = item.venueName, venue.localizedStandardContains(needle) { return true }
      return false
    }
  }

  private func joinRow(_ item: TournamentItem) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Color.clear
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .background { BannerPlate(raw: item.bannerUrl) }
        .clipped()
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 12) {
          PhaseLabel(item: item, color: Theme.mute)
          Spacer(minLength: 8)
          if let venue = item.venueName, !venue.isEmpty {
            Text(venue)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Theme.mute)
              .multilineTextAlignment(.trailing)
          }
        }
        Text(item.titledName)
          .font(.system(size: 22, weight: .regular, design: .serif))
          .foregroundStyle(Theme.ink)
        if let startsAt = item.startsAt {
          Text(VenueClock.label(startsAt))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.ink)
        }
        if VenueClock.phase(item) == "Ongoing", let count = item.spectatorCount {
          Text(count == 1 ? "1 spectating" : "\(count) spectating")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.mute)
        }
        HStack(alignment: .bottom, spacing: 12) {
          prizeLine(item, ink: Theme.ink, mute: Theme.mute)
          Spacer(minLength: 8)
          ownerButton(item, ink: Theme.ink)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
    }
    .background(Theme.card)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    }
  }

  private func ownerButton(_ item: TournamentItem, ink: Color) -> some View {
    Group {
      if let name = item.createdByName, !name.isEmpty, let ownerId = item.createdById {
        Button {
          viewingOwner = OwnerRef(id: ownerId, name: name, picture: item.createdByPictureUrl)
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "person.fill")
              .font(.system(size: 11, weight: .semibold))
            Text(name)
              .font(.system(size: 13, weight: .semibold))
          }
          .foregroundStyle(ink)
        }
        .buttonStyle(.borderless)
      }
    }
  }

  private func prizeLine(_ item: TournamentItem, ink: Color, mute: Color) -> some View {
    Group {
      if let total = PrizeTotal.php(item.prizes) {
        VStack(alignment: .leading, spacing: 1) {
          Text("PRIZE POOL")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(mute)
          Text(total)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
        }
      }
    }
  }

  private func load() async {
    guard !auth.isBootstrapping else { return }
    loading = rows.isEmpty
    errorMessage = nil
    guard auth.user != nil else {
      rows = []
      loading = false
      return
    }
    do {
      let publicRows = try await service.list(managing: false)
      rows = publicRows
        .sorted { left, right in
          let leftDone = VenueClock.phase(left) == "Completed"
          let rightDone = VenueClock.phase(right) == "Completed"
          if leftDone != rightDone { return !leftDone }
          return startTime(left) > startTime(right)
        }
    } catch {
      errorMessage = error.localizedDescription
    }
    loading = false
  }

  private func startTime(_ item: TournamentItem) -> TimeInterval {
    guard let startsAt = item.startsAt, let date = VenueClock.parse(startsAt) else {
      return 0
    }
    return date.timeIntervalSince1970
  }
}

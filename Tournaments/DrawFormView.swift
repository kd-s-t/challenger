import PhotosUI
import SwiftUI

struct DrawFormView: View {
  @Binding var path: [AuthRoute]
  let existingId: String?
  @State private var name = ""
  @State private var size = 8
  @State private var pairing = "shuffle"
  @State private var division = "mens_singles"

  private let divisions: [(id: String, title: String)] = [
    ("mens_singles", "Men's singles"),
    ("womens_singles", "Women's singles"),
    ("mens_doubles", "Men's doubles"),
    ("womens_doubles", "Women's doubles"),
    ("mixed_doubles", "Mixed doubles"),
  ]
  @State private var date = Date()
  @State private var startSlot = ""
  @State private var untilSlot = ""
  @State private var venueName = ""
  @State private var venueLocation: VenueLocation?
  @State private var courtCount = 1
  @State private var fee = ""
  @State private var first = ""
  @State private var second = ""
  @State private var third = ""
  @State private var errorMessage: String?
  @State private var busy = false
  @State private var bannerItem: PhotosPickerItem?
  @State private var bannerData: Data?
  @State private var existingBanner: String?
  @State private var status = ""
  @State private var seats: [DraftSeat] = []
  @State private var singlesLocked = false
  @State private var canRemovePlayers = true
  @State private var adding: DraftSeat?
  @State private var requesters: [AccountHit] = []

  private let sizes = [4, 8, 16, 32]
  private let hours = (0..<24).map { String(format: "%02d:00", $0) }
  private let service = TournamentService()

  var body: some View {
    ScreenColumn(
      kicker: "DRAW",
      title: existingId == nil ? "New tournament" : "Edit tournament",
      subtitle: existingId == nil ? "This stays a draft until you post it." : (status == "draft" ? "Draft. Add players, then post." : "Name, venue, hours, and courts.")
    ) {
      VStack(alignment: .leading, spacing: 16) {
        AuthField(title: "Tournament name", text: $name, content: .name)
        nameAndBanner
        if UIDevice.current.userInterfaceIdiom == .pad, existingId == nil {
          HStack(alignment: .top, spacing: 14) {
            bracketSizeField
              .frame(maxWidth: .infinity, alignment: .leading)
            divisionPicker
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          pairingPicker
        } else {
          if existingId == nil {
            bracketSizeField
          } else {
            Text("\(size) players")
              .font(.system(size: 16))
              .foregroundStyle(Theme.ink)
          }
          pairingPicker
          divisionPicker
        }
        AuthField(title: "Venue name", text: $venueName)
        VenueSearch(markerName: venueName, location: $venueLocation)
        DatePicker("Start day", selection: $date, displayedComponents: .date)
          .datePickerStyle(.compact)
          .tint(Theme.clay)
        if UIDevice.current.userInterfaceIdiom == .pad {
          HStack(alignment: .top, spacing: 14) {
            slotMenu("Begins", selection: $startSlot)
              .frame(maxWidth: .infinity, alignment: .leading)
            slotMenu("Until", selection: $untilSlot)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          slotMenu("Begins", selection: $startSlot)
          slotMenu("Until", selection: $untilSlot)
        }
        if let hours = VenueClock.hoursBetween(start: startSlot, until: untilSlot) {
          Text(hours == 1 ? "1 hour" : "\(hours) hours")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
        }
        Stepper(value: $courtCount, in: 1...30) {
          Text("Courts  \(courtCount)")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
        }
        if let need = VenueClock.hoursRequired(players: size, courts: courtCount) {
          let courtWord = courtCount == 1 ? "court" : "courts"
          let hourWord = need == 1 ? "hour" : "hours"
          Text("\(courtCount) \(courtWord): finishes in \(need) \(hourWord).")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
        }
        AuthField(title: "Fee (PHP, optional)", text: $fee, keyboard: .numberPad)
        AuthField(title: "1st prize", text: $first)
        AuthField(title: "2nd prize", text: $second)
        AuthField(title: "3rd prize", text: $third)
        if existingId != nil {
          players
        }
        if let errorMessage {
          Notice(text: errorMessage, tone: Theme.danger)
        }
        ClayButton(title: status == "active" || status == "completed" ? "Save" : "Save draft", busy: busy) {
          Task { await save() }
        }
        .disabled(busy)
        if existingId != nil, status == "draft" {
          ClayButton(title: "Tournament Ready", busy: busy, fill: Theme.ready) {
            Task { await post() }
          }
          .disabled(busy)
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle("")
    .toolbar {
      if existingId != nil {
        ToolbarItem(placement: .confirmationAction) {
          Button(status == "active" || status == "completed" ? "Save" : "Save draft") {
            Task { await save() }
          }
          .disabled(busy)
        }
      }
    }
    .task { await prepare() }
    .onChange(of: bannerItem) { _, item in
      guard let item else { return }
      Task {
        bannerData = try? await item.loadTransferable(type: Data.self)
      }
    }
    .sheet(item: $adding) { seat in
      playerSearch(seat)
    }
  }

  private var playFormatValue: String {
    if !division.hasSuffix("doubles") { return "singles" }
    return pairing == "fixed" ? "doubles" : "singles"
  }

  private var bracketSizeField: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Bracket size")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.mute)
      Picker("Bracket size", selection: $size) {
        ForEach(sizes, id: \.self) { count in
          Text("\(count) players").tag(count)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .frame(height: 54)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      }
    }
  }

  private var pairingPicker: some View {
    Group {
      if division.hasSuffix("doubles") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Partner")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.mute)
          Picker("Partner", selection: $pairing) {
            Text("Shuffle").tag("shuffle")
            Text("Fixed").tag("fixed")
          }
          .pickerStyle(.segmented)
          Text(pairing == "fixed" ? "Same partner the whole tournament." : "Mixed with other players. No fixed partner.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.mute)
        }
      }
    }
  }

  private var divisionPicker: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Division")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.mute)
      Menu {
        ForEach(divisions, id: \.id) { item in
          Button {
            division = item.id
          } label: {
            if division == item.id {
              Label(item.title, systemImage: "checkmark")
            } else {
              Text(item.title)
            }
          }
          .disabled(singlesLocked && !item.id.hasSuffix("doubles"))
        }
      } label: {
        HStack {
          if let title = divisions.first(where: { $0.id == division })?.title {
            Text(title)
          }
          Spacer()
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.mute)
        }
        .font(.system(size: 16))
        .foregroundStyle(Theme.ink)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .frame(height: 54)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      }
    }
  }

  private var nameAndBanner: some View {
    PhotosPicker(selection: $bannerItem, matching: .images) {
      ZStack {
        bannerFill
        if bannerData == nil && existingBanner == nil {
          VStack(spacing: 8) {
            Image(systemName: "photo")
              .font(.system(size: 22, weight: .semibold))
            Text("Banner")
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundStyle(Theme.mute)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 180)
      .background(Theme.card)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var bannerFill: some View {
    if let bannerData, let image = UIImage(data: bannerData) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipped()
    } else if let existingBanner, let url = mediaURL(existingBanner) {
      AsyncImage(url: url) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          Theme.card
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: 180)
      .clipped()
    } else {
      Theme.card
    }
  }

  private func mediaURL(_ raw: String) -> URL? {
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
      return URL(string: raw)
    }
    return URL(string: raw, relativeTo: APIConfig.baseURL)?.absoluteURL
  }

  private func slotMenu(_ title: String, selection: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.mute)
      Picker(title, selection: selection) {
        Text("Select").tag("")
        ForEach(hours, id: \.self) { slot in
          Text(slot).tag(slot)
        }
      }
      .pickerStyle(.menu)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .frame(height: 54)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      }
    }
  }

  private func prepare() async {
    if let existingId {
      do {
        let item = try await service.detail(id: existingId, managing: true)
        name = item.name
        status = item.status
        pairing = item.playFormat == "doubles" ? "fixed" : "shuffle"
        if let stored = item.division, divisions.contains(where: { $0.id == stored }) {
          division = stored
        }
        let filled = seats(from: item)
        seats = filled
        let rosterPhase = VenueClock.phase(item)
        canRemovePlayers = rosterPhase == "Draft" || rosterPhase == "Upcoming"
        singlesLocked = item.division?.hasSuffix("doubles") == true && filled.contains { seat in
          let name = seat.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          return !name.isEmpty
        }
        requesters = await loadRequesters(existingId)
        existingBanner = item.bannerUrl
        size = item.bracketSize
        first = item.prizes?.first { $0.place == "1st" }?.prize ?? ""
        second = item.prizes?.first { $0.place == "2nd" }?.prize ?? ""
        third = item.prizes?.first { $0.place == "3rd" }?.prize ?? ""
        if let feeAmount = item.registrationFee {
          fee = String(feeAmount)
        }
        if let count = item.courtCount, (1...30).contains(count) {
          courtCount = count
        }
        if let venueName = item.venueName {
          self.venueName = venueName
        }
        if let latitude = item.venueLatitude, let longitude = item.venueLongitude {
          venueLocation = VenueLocation(latitude: latitude, longitude: longitude)
        }
        if let startsAt = item.startsAt, let parts = VenueClock.parts(startsAt),
           let parsed = VenueClock.date(fromDateKey: parts.dateKey) {
          date = parsed
          startSlot = parts.slot
        }
        if let endsAt = item.endsAt, let parts = VenueClock.parts(endsAt) {
          untilSlot = parts.slot
        }
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func loadRequesters(_ id: String) async -> [AccountHit] {
    guard let listed = try? await service.joinRequests(id: id) else { return [] }
    return listed.requests.map {
      AccountHit(id: $0.userId, name: $0.name, email: $0.email, pictureUrl: $0.pictureUrl)
    }
  }

  private func seats(from item: TournamentItem) -> [DraftSeat] {
    let matches = (item.flow?.nodes.compactMap(\.match) ?? []).filter { $0.round == 0 }
    return matches
      .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
      .flatMap { match in
        guard let matchId = match.matchId, let index = match.index else { return [DraftSeat]() }
        return [
          DraftSeat(matchId: matchId, slot: "A", index: index, name: match.playerAName),
          DraftSeat(matchId: matchId, slot: "B", index: index, name: match.playerBName),
        ]
      }
  }

  private var players: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("PLAYERS")
        .font(.system(size: 12, weight: .semibold))
        .tracking(1.2)
        .foregroundStyle(Theme.mute)
      ForEach(seats) { seat in
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Match \(seat.index + 1) · \(seat.slot)")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(Theme.mute)
            if let name = seat.name {
              Text(name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.ink)
            } else {
              Text("Open")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.mute)
            }
          }
          Spacer()
          if seat.name == nil {
            Button("Add") { adding = seat }
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Theme.clay)
          } else if canRemovePlayers {
            Button("Remove") { Task { await clear(seat) } }
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Theme.danger)
          }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        }
      }
    }
  }

  private func playerSearch(_ seat: DraftSeat) -> some View {
    NavigationStack {
      PlayerSearchSheet(requesters: requesters) { account in
        adding = nil
        Task { await assign(seat, account: account) }
      }
    }
    .presentationDragIndicator(.visible)
  }

  private func assign(_ seat: DraftSeat, account: AccountHit) async {
    guard let existingId else { return }
    errorMessage = nil
    busy = true
    defer { busy = false }
    do {
      let item = try await service.assignPlayer(
        tournamentId: existingId,
        matchId: seat.matchId,
        slot: seat.slot,
        name: account.email
      )
      status = item.status
      seats = seats(from: item)
      if requesters.contains(where: { $0.id == account.id }),
         let remaining = try? await service.clearJoinRequest(id: existingId, userId: account.id) {
        requesters = remaining.map {
          AccountHit(id: $0.userId, name: $0.name, email: $0.email, pictureUrl: $0.pictureUrl)
        }
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func clear(_ seat: DraftSeat) async {
    guard let existingId else { return }
    errorMessage = nil
    busy = true
    defer { busy = false }
    do {
      let item = try await service.clearPlayer(
        tournamentId: existingId,
        matchId: seat.matchId,
        slot: seat.slot
      )
      status = item.status
      seats = seats(from: item)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func post() async {
    guard let existingId else { return }
    errorMessage = nil
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      errorMessage = "Name is required"
      return
    }
    guard !startSlot.isEmpty, !untilSlot.isEmpty else {
      errorMessage = "Set when the tournament begins"
      return
    }
    let trimmedVenue = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedVenue.isEmpty, let venueLocation else {
      errorMessage = "Venue name and location are required"
      return
    }
    let key = VenueClock.dateKey(from: date)
    guard let window = VenueClock.hoursBetween(start: startSlot, until: untilSlot),
          let endsAt = VenueClock.endISO(dateKey: key, start: startSlot, until: untilSlot) else {
      errorMessage = "Until must be after the start time"
      return
    }
    if let limit = VenueClock.scheduleLimit(players: size, courts: courtCount, window: window) {
      errorMessage = limit
      return
    }
    busy = true
    defer { busy = false }
    do {
      _ = try await service.update(
        id: existingId,
        name: trimmedName,
        startsAt: "\(key)T\(startSlot):00+08:00",
        endsAt: endsAt,
        courtIds: [],
        fee: parsedFee(),
        prizes: prizes(),
        venueName: trimmedVenue,
        latitude: venueLocation.latitude,
        longitude: venueLocation.longitude,
        courtCount: courtCount,
        playFormat: playFormatValue,
        division: division,
        banner: try bannerFile()
      )
      let item = try await service.post(id: existingId)
      status = item.status
      seats = seats(from: item)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func bannerFile() throws -> (data: Data, mime: String, name: String)? {
    guard let bannerData, !bannerData.isEmpty else { return nil }
    guard let image = UIImage(data: bannerData),
          let jpeg = image.jpegData(compressionQuality: 0.9) else {
      throw APIError.http(status: 400, message: "Banner must be PNG, JPG, or WebP", code: nil)
    }
    return (jpeg, "image/jpeg", "banner.jpg")
  }

  private func prizes() -> [TournamentPrize] {
    [
      TournamentPrize(place: "1st", prize: first.trimmingCharacters(in: .whitespacesAndNewlines)),
      TournamentPrize(place: "2nd", prize: second.trimmingCharacters(in: .whitespacesAndNewlines)),
      TournamentPrize(place: "3rd", prize: third.trimmingCharacters(in: .whitespacesAndNewlines)),
    ]
  }

  private func parsedFee() -> Int? {
    let trimmed = fee.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    return Int(trimmed)
  }

  private func save() async {
    errorMessage = nil
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else {
      errorMessage = "Name is required"
      return
    }
    guard !startSlot.isEmpty, !untilSlot.isEmpty else {
      errorMessage = "Begins and until are required"
      return
    }
    let trimmedVenue = venueName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedVenue.isEmpty else {
      errorMessage = "Venue name is required"
      return
    }
    guard let venueLocation else {
      errorMessage = "Search the map or drop a pin for the venue location"
      return
    }
    guard (1...30).contains(courtCount) else {
      errorMessage = "Courts must be from 1 to 30"
      return
    }
    let trimmedFee = fee.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedFee.isEmpty && Int(trimmedFee) == nil {
      errorMessage = "Registration fee must be a whole number"
      return
    }
    let key = VenueClock.dateKey(from: date)
    guard let window = VenueClock.hoursBetween(start: startSlot, until: untilSlot),
          let endsAt = VenueClock.endISO(dateKey: key, start: startSlot, until: untilSlot) else {
      errorMessage = "Until must be after the start time"
      return
    }
    if let limit = VenueClock.scheduleLimit(players: size, courts: courtCount, window: window) {
      errorMessage = limit
      return
    }
    let startsAt = "\(key)T\(startSlot):00+08:00"
    busy = true
    defer { busy = false }
    do {
      let banner = try bannerFile()
      let savedId: String
      if let existingId {
        _ = try await service.update(
          id: existingId,
          name: trimmedName,
          startsAt: startsAt,
          endsAt: endsAt,
          courtIds: [],
          fee: parsedFee(),
          prizes: prizes(),
          venueName: trimmedVenue,
          latitude: venueLocation.latitude,
          longitude: venueLocation.longitude,
          courtCount: courtCount,
          playFormat: playFormatValue,
          division: division,
          banner: banner
        )
        savedId = existingId
      } else {
        let created = try await service.create(
          name: trimmedName,
          size: size,
          startsAt: startsAt,
          endsAt: endsAt,
          courtIds: [],
          fee: parsedFee(),
          prizes: prizes(),
          venueName: trimmedVenue,
          latitude: venueLocation.latitude,
          longitude: venueLocation.longitude,
          courtCount: courtCount,
          playFormat: playFormatValue,
          division: division,
          banner: banner
        )
        savedId = created.id
      }
      if !path.isEmpty {
        path[path.count - 1] = .drawForm(savedId)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct DraftSeat: Identifiable, Hashable {
  let matchId: String
  let slot: String
  let index: Int
  let name: String?
  var id: String { "\(matchId)-\(slot)" }
}

struct PlayerSearchSheet: View {
  var requesters: [AccountHit] = []
  var title = "Add player"
  let onPick: (AccountHit) -> Void
  @State private var query = ""
  @State private var hits: [AccountHit] = []
  @State private var errorMessage: String?
  @Environment(\.dismiss) private var dismiss

  private let service = TournamentService()

  var body: some View {
    ScreenColumn(
      kicker: "",
      title: title,
      subtitle: "Search a registered account."
    ) {
      VStack(alignment: .leading, spacing: 12) {
        if !requesters.isEmpty {
          Text("REQUESTERS")
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.mute)
          ForEach(requesters) { account in
            accountRow(account)
          }
        }
        AuthField(title: "Name or email", text: $query)
        if let errorMessage {
          Notice(text: errorMessage, tone: Theme.danger)
        }
        ForEach(hits) { account in
          accountRow(account)
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") { dismiss() }
      }
    }
    .onChange(of: query) { _, value in
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.count >= 2 else {
        hits = []
        return
      }
      Task { await search(trimmed) }
    }
  }

  private func accountRow(_ account: AccountHit) -> some View {
    Button {
      onPick(account)
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(account.name)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Text(account.email)
          .font(.system(size: 13))
          .foregroundStyle(Theme.mute)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }

  private func search(_ trimmed: String) async {
    do {
      let found = try await service.accounts(query: trimmed)
      if query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
        hits = found
        errorMessage = nil
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

import SwiftUI
import UIKit

private struct Bone: View {
  var width: CGFloat
  var height: CGFloat
  var onDark = false
  @State private var pulse = false

  var body: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(onDark ? Color.white.opacity(pulse ? 0.55 : 0.22) : Theme.line.opacity(pulse ? 1 : 0.45))
      .frame(width: width, height: height)
      .onAppear {
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
          pulse = true
        }
      }
  }
}

private enum BracketLook {
  static let canvas = Color(red: 1, green: 0.988, blue: 0.969)
  static let gold = Color(red: 0.788, green: 0.635, blue: 0.153)
  static let goldDeep = Color(red: 0.659, green: 0.518, blue: 0.102)
  static let muted = Color(red: 0.961, green: 0.941, blue: 0.902)
  static let ink = Color(red: 0.102, green: 0.102, blue: 0.102)
  static let court = Color(red: 0.184, green: 0.435, blue: 0.373)
  static let courtSoft = Color(red: 0.141, green: 0.357, blue: 0.302)
  static let cardHeight: CGFloat = 127
  static let gap: CGFloat = 28
  static let championHeight: CGFloat = 96
}

private struct BracketJoin: View {
  let matchCount: Int
  let cardHeight: CGFloat
  let gap: CGFloat

  var body: some View {
    Canvas { context, size in
      var path = Path()
      let pairs = matchCount / 2
      for pair in 0..<pairs {
        let y1 = center(pair * 2)
        let y2 = center(pair * 2 + 1)
        let mid = (y1 + y2) / 2
        let bend = min(28, size.width / 2)
        path.move(to: CGPoint(x: 0, y: y1))
        path.addLine(to: CGPoint(x: bend, y: y1))
        path.addLine(to: CGPoint(x: bend, y: y2))
        path.move(to: CGPoint(x: 0, y: y2))
        path.addLine(to: CGPoint(x: bend, y: y2))
        path.move(to: CGPoint(x: bend, y: mid))
        path.addLine(to: CGPoint(x: size.width, y: mid))
      }
      context.stroke(path, with: .color(BracketLook.goldDeep), lineWidth: 1.5)
    }
  }

  private func center(_ index: Int) -> CGFloat {
    CGFloat(index) * (cardHeight + gap) + cardHeight / 2
  }
}

private struct BracketRound {
  let number: Int
  let title: String
  let matches: [BracketMatch]
}

struct DrawDetailView: View {
  @Environment(AuthStore.self) private var auth
  @Binding var path: [AuthRoute]
  let id: String
  let owned: Bool
  @State private var item: TournamentItem?
  @State private var errorMessage: String?
  @State private var loading = true
  @State private var showDelete = false
  @State private var showBracket = false
  @State private var joining = false
  @State private var requests: [JoinRequest] = []
  @State private var viewingOwner: OwnerRef?
  @State private var picker: BracketPicker?
  @State private var posting = false
  @State private var resultPick: ResultPick?
  @State private var scoreA = ""
  @State private var scoreB = ""
  @State private var resultError: String?
  @State private var spectatorCount: Int?
  @State private var spectating = false
  @State private var spectateBusy = false
  @State private var setWinnerMatchId: String?
  @State private var photoPlace: String?
  @State private var uploadingPlace: String?

  private let service = TournamentService()

  var body: some View {
    ScrollView {
      VStack(spacing: -28) {
        banner
        VStack(alignment: .leading, spacing: 16) {
          if loading, item == nil {
            detailSkeleton
          } else if let errorMessage, item == nil {
            Notice(text: errorMessage, tone: Theme.danger)
          } else if let item {
            storyCard(item)
            prizes(item)
            if VenueClock.phase(item) == "Ongoing" {
              bracket(item)
              publicWatch(item.id)
              summary(item)
            } else {
              if VenueClock.phase(item) != "Completed" {
                entranceFee(item)
                requestsList
              }
              summary(item)
              bracket(item)
            }
            if let board = standingBoard(item) {
              standings(board.rows, championId: board.championId)
            }
            if (canManage || owned) && VenueClock.phase(item) != "Ongoing" {
              LineButton(title: "Edit") {
                path.append(.drawForm(id))
              }
            }
            if (canDelete || owned) && VenueClock.phase(item) != "Ongoing" {
              Button("Delete tournament") {
                showDelete = true
              }
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Theme.danger)
            }
            if let errorMessage {
              Notice(text: errorMessage, tone: Theme.danger)
            }
            Color.clear.frame(height: 72)
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
      }
    }
    .background(Theme.paper)
    .ignoresSafeArea(edges: .top)
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle("")
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .task { await load() }
    .refreshable { await load(showingSpinner: false) }
    .onChange(of: path) { _, routes in
      guard case .draw(let drawId, _) = routes.last, drawId == id else { return }
      Task { await load(showingSpinner: false) }
    }
    .sheet(isPresented: $showDelete) {
      deleteSheet
    }
    .sheet(item: $viewingOwner) { owner in
      OwnerSheet(owner: owner)
    }
    .sheet(item: outerPicker) { picker in
      accountPicker(picker)
    }
    .sheet(item: outerResult) { pick in
      resultSheet(pick)
    }
    .fullScreenCover(isPresented: cameraOpen) {
      let place = photoPlace
      WinnerCamera { image in
        photoPlace = nil
        guard let place, let data = image.jpegData(compressionQuality: 0.85) else { return }
        Task { await uploadWinnerPhoto(place, data: data) }
      } onCancel: {
        photoPlace = nil
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let item {
        let completed = VenueClock.phase(item) == "Completed"
        let showSpectate = item.createdById != auth.user?.id && (!completed || spectating)
        if showSpectate || isReadyToPost(item) || canRequestJoin {
        VStack(spacing: 8) {
          if showSpectate {
            ClayButton(title: spectating ? "Unspectate" : "Spectate", busy: spectateBusy, fill: spectating ? Theme.ready : Theme.clay) {
              Task { await toggleSpectate() }
            }
            .disabled(spectateBusy)
          }
          if isReadyToPost(item) {
            ClayButton(title: "Tournament Ready", busy: posting, fill: Theme.ready) {
              Task { await publish() }
            }
            .disabled(posting)
          } else if canRequestJoin {
            ClayButton(title: didRequest ? "Requested" : "Request join", busy: joining) {
              Task { await requestJoin() }
            }
            .disabled(didRequest || joining)
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.paper)
        }
      }
    }
  }

  private var detailSkeleton: some View {
    VStack(alignment: .leading, spacing: 16) {
      skeletonCard(widths: [120, 220, 160])
      skeletonCard(widths: [90, 180])
      skeletonCard(widths: [140, 260, 200, 110])
    }
  }

  private func skeletonCard(widths: [CGFloat]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
        Bone(width: width, height: 14)
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

  private var banner: some View {
    VStack(alignment: .leading, spacing: 4) {
      if loading, item == nil {
        Bone(width: 230, height: 28, onDark: true)
        Bone(width: 150, height: 14, onDark: true)
          .padding(.top, 8)
      } else {
        if let item {
          PhaseLabel(item: item, color: Theme.onFill.opacity(0.8))
        }
        Text(item?.titledName ?? "")
        .font(.system(size: 28, weight: .semibold))
        .foregroundStyle(Theme.onFill)
      }
      if !bannerLine.isEmpty {
      Text(bannerLine)
        .font(.system(size: 15))
        .foregroundStyle(Theme.onFill.opacity(0.82))
      }
      if let owner = item?.createdByName, !owner.isEmpty, let ownerId = item?.createdById {
        Button {
          viewingOwner = OwnerRef(id: ownerId, name: owner, picture: item?.createdByPictureUrl)
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "person.fill")
              .font(.system(size: 12, weight: .semibold))
            Text(owner)
              .font(.system(size: 15, weight: .semibold))
          }
          .foregroundStyle(Theme.onFill)
        }
        .buttonStyle(.plain)
      }
      if let item, hasJoined(item) || (VenueClock.phase(item) == "Ongoing" && spectatorCount != nil) {
        HStack {
          if hasJoined(item) {
            Text("You have joined")
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(Theme.onFill)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Theme.ready, in: Capsule())
          }
          Spacer(minLength: 8)
          if VenueClock.phase(item) == "Ongoing", let spectatorCount {
            HStack(spacing: 6) {
              Image(systemName: "eye.fill")
                .font(.system(size: 14, weight: .semibold))
              Text("\(spectatorCount)")
                .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.onFill.opacity(0.9))
            .accessibilityLabel(spectatorCount == 1 ? "1 spectating" : "\(spectatorCount) spectating")
          }
        }
        .padding(.top, 8)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 88)
    .padding(.bottom, 44)
    .background {
      ZStack(alignment: .bottom) {
        bannerFill
        LinearGradient(
          colors: [Color.white.opacity(0.16), Color.clear],
          startPoint: .top,
          endPoint: .center
        )
      }
    }
  }

  private var bannerLine: String {
    guard let item, let label = formatLabel(item) else { return "" }
    return label
  }

  private func formatLabel(_ item: TournamentItem) -> String? {
    if let division = item.division, let title = divisionTitle(division) {
      return title
    }
    if item.playFormat == "doubles" {
      return "Doubles"
    }
    if item.playFormat == "singles" {
      return "Singles"
    }
    return nil
  }

  private func divisionTitle(_ id: String) -> String? {
    switch id {
    case "mens_singles":
      return "Men's singles"
    case "womens_singles":
      return "Women's singles"
    case "mens_doubles":
      return "Men's doubles"
    case "womens_doubles":
      return "Women's doubles"
    case "mixed_doubles":
      return "Mixed doubles"
    default:
      return nil
    }
  }

  @ViewBuilder
  private var bannerFill: some View {
    if let bannerUrl = item?.bannerUrl, let url = bannerURL(bannerUrl) {
      AsyncImage(url: url) { phase in
        if let image = phase.image {
          image.resizable().scaledToFill()
        } else {
          bannerWash
        }
      }
    } else {
      bannerWash
    }
  }

  private var bannerWash: some View {
    ZStack {
      LinearGradient(
        colors: [Theme.clay, Theme.court, Color(red: 0.03, green: 0.10, blue: 0.28)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      LinearGradient(
        colors: [Color.white.opacity(0.28), Color.clear, Color.clear],
        startPoint: .top,
        endPoint: .center
      )
    }
  }

  private func isReadyToPost(_ item: TournamentItem) -> Bool {
    guard owned || canManage, item.status == "draft" else { return false }
    guard let startsAt = item.startsAt, let endsAt = item.endsAt else { return false }
    guard let venue = item.venueName?.trimmingCharacters(in: .whitespacesAndNewlines), !venue.isEmpty else { return false }
    guard let courts = item.courtCount, courts >= 1 else { return false }
    guard let start = VenueClock.parse(startsAt), let end = VenueClock.parse(endsAt), end > start else { return false }
    let window = Int(end.timeIntervalSince(start) / 3600)
    if let need = VenueClock.hoursRequired(players: item.bracketSize, courts: courts), window < need {
      return false
    }
    return true
  }

  private func publish() async {
    guard let item else { return }
    errorMessage = nil
    posting = true
    defer { posting = false }
    do {
      self.item = try await service.post(id: item.id)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private var canManage: Bool {
    guard let user = auth.user else { return false }
    return DrawAccess.canManage(user)
  }

  private var canScore: Bool {
    guard let item, let userId = auth.user?.id else { return false }
    return item.createdById == userId && VenueClock.phase(item) == "Ongoing"
  }

  private var canDelete: Bool {
    guard let user = auth.user else { return false }
    return DrawAccess.canDelete(user)
  }

  private var canRequestJoin: Bool {
    guard let item, item.createdById != auth.user?.id, !hasJoined(item) else { return false }
    let phase = VenueClock.phase(item)
    return phase == "Upcoming" || phase == "Draft"
  }

  private func hasJoined(_ item: TournamentItem) -> Bool {
    let mine = auth.user?.id
    let myName = auth.user?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    for round in bracketRounds(item) {
      for match in round.matches {
        if let mine, isMe(match.playerAUserId) || isMe(match.playerBUserId) || isMe(match.playerAPartnerUserId) || isMe(match.playerBPartnerUserId) {
          return true
        }
        if let myName, !myName.isEmpty {
          let names = seatNames(match.playerAName) + seatNames(match.playerBName)
          if names.contains(myName) { return true }
        }
      }
    }
    return false
  }

  private func seatNames(_ raw: String?) -> [String] {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if trimmed.isEmpty { return [] }
    return trimmed
      .components(separatedBy: " & ")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
  }

  private var openRequests: [JoinRequest] {
    guard let item else { return requests }
    let ids = seatedUserIds(item)
    let names = seatedNames(item)
    return requests.filter { request in
      if ids.contains(request.userId) { return false }
      let name = request.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      return !names.contains(name)
    }
  }

  private func seatedUserIds(_ item: TournamentItem) -> Set<String> {
    var ids = Set<String>()
    for round in bracketRounds(item) {
      for match in round.matches {
        if let id = match.playerAUserId { ids.insert(id) }
        if let id = match.playerBUserId { ids.insert(id) }
        if let id = match.playerAPartnerUserId { ids.insert(id) }
        if let id = match.playerBPartnerUserId { ids.insert(id) }
      }
    }
    return ids
  }

  private func seatedNames(_ item: TournamentItem) -> Set<String> {
    var names = Set<String>()
    for round in bracketRounds(item) {
      for match in round.matches {
        names.formUnion(seatNames(match.playerAName))
        names.formUnion(seatNames(match.playerBName))
      }
    }
    return names
  }

  private var didRequest: Bool {
    guard let userId = auth.user?.id else { return false }
    return requests.contains { $0.userId == userId }
  }

  private func toggleSpectate() async {
    guard let item else { return }
    spectateBusy = true
    defer { spectateBusy = false }
    do {
      let result = try await service.setSpectating(id: item.id, on: !spectating)
      spectating = result.spectating
      spectatorCount = result.spectatorCount
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func requestJoin() async {
    guard let item else { return }
    errorMessage = nil
    joining = true
    defer { joining = false }
    do {
      let result = try await service.requestToJoin(id: item.id)
      requests = result.requests
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private var requestsList: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("REQUESTS")
        .font(.system(size: 12, weight: .semibold))
        .tracking(1.2)
        .foregroundStyle(Theme.mute)
      if openRequests.isEmpty {
        Text("No one has requested yet.")
          .font(.system(size: 15))
          .foregroundStyle(Theme.mute)
      } else {
        ForEach(openRequests) { request in
          HStack(spacing: 10) {
            requestFace(request.pictureUrl)
            Text(request.name)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(Theme.ink)
            Spacer()
            if request.userId == auth.user?.id {
              Text("You")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.clay)
            }
          }
        }
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

  private func requestFace(_ raw: String?) -> some View {
    Group {
      if let raw, let url = bannerURL(raw) {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            Image(systemName: "person.fill").foregroundStyle(Theme.mute)
          }
        }
      } else {
        Image(systemName: "person.fill").foregroundStyle(Theme.mute)
      }
    }
    .font(.system(size: 14, weight: .semibold))
    .frame(width: 32, height: 32)
    .background(Theme.paper)
    .clipShape(Circle())
  }

  private func bracket(_ item: TournamentItem) -> some View {
    let rounds = bracketRounds(item)
    let gap = BracketLook.gap
    let cardHeight = BracketLook.cardHeight
    return VStack(alignment: .leading, spacing: 10) {
      Text("BRACKET")
        .font(.system(size: 12, weight: .semibold))
        .tracking(1.2)
        .foregroundStyle(Theme.mute)
        .padding(.top, 8)
      ZStack(alignment: .bottomTrailing) {
        ScrollView([.horizontal, .vertical], showsIndicators: false) {
          bracketBoard(rounds, cardHeight: cardHeight, gap: gap)
            .padding(12)
            .padding(.bottom, 36)
        }
        .frame(height: 280)
        HStack(spacing: 14) {
          Text("Drag to view")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.mute)
          Button("View all") {
            showBracket = true
          }
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.clay)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.card.opacity(0.94), in: Capsule())
        .padding(10)
      }
      .background(BracketLook.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(BracketLook.gold.opacity(0.25), lineWidth: 1)
      }
      .sheet(isPresented: $showBracket) {
        NavigationStack {
          ScrollView([.horizontal, .vertical]) {
            bracketBoard(rounds, cardHeight: cardHeight, gap: gap)
              .padding(20)
          }
          .background(BracketLook.canvas)
          .navigationTitle(item.name)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { showBracket = false }
            }
          }
          .sheet(item: $picker) { picker in
            accountPicker(picker)
          }
          .sheet(item: $resultPick) { pick in
            resultSheet(pick)
          }
        }
      }
    }
  }

  private var outerResult: Binding<ResultPick?> {
    Binding(
      get: { showBracket ? nil : resultPick },
      set: { resultPick = $0 }
    )
  }

  private var outerPicker: Binding<BracketPicker?> {
    Binding(
      get: { showBracket ? nil : picker },
      set: { picker = $0 }
    )
  }

  private func accountPicker(_ picker: BracketPicker) -> some View {
    NavigationStack {
      switch picker {
      case .player(let seat):
        PlayerSearchSheet(requesters: requests.map {
          AccountHit(id: $0.userId, name: $0.name, email: $0.email, pictureUrl: $0.pictureUrl)
        }) { account in
          self.picker = nil
          Task { await place(account, in: seat) }
        }
      case .referee(let matchId):
        RefereeNameSheet(initial: currentReferee(matchId)) { name in
          self.picker = nil
          Task { await assignReferee(matchId: matchId, name: name) }
        }
      }
    }
    .presentationDragIndicator(.visible)
  }

  private func bracketBoard(_ rounds: [BracketRound], cardHeight: CGFloat, gap: CGFloat) -> some View {
    let finalDepth = rounds.count - 1
    return HStack(alignment: .top, spacing: 0) {
      ForEach(Array(rounds.enumerated()), id: \.element.number) { index, round in
        bracketColumn(round, depth: index, cardHeight: cardHeight, gap: gap)
        if index < rounds.count - 1 {
          VStack(spacing: 0) {
            Color.clear.frame(height: columnInset(index, cardHeight: cardHeight, gap: gap))
            BracketJoin(matchCount: round.matches.count, cardHeight: cardHeight, gap: columnGap(index, cardHeight: cardHeight, gap: gap))
              .frame(width: 64)
              .frame(height: stackHeight(count: round.matches.count, cardHeight: cardHeight, gap: columnGap(index, cardHeight: cardHeight, gap: gap)))
          }
        }
      }
      if let match = rounds.last?.matches.first, rounds.last?.matches.count == 1 {
        championLink(depth: finalDepth, cardHeight: cardHeight, gap: gap)
        championColumn(match, depth: finalDepth, cardHeight: cardHeight, gap: gap)
      }
    }
  }

  private func championLink(depth: Int, cardHeight: CGFloat, gap: CGFloat) -> some View {
    VStack(spacing: 0) {
      Color.clear.frame(height: columnInset(depth, cardHeight: cardHeight, gap: gap) + cardHeight / 2 - 0.75)
      Rectangle()
        .fill(BracketLook.goldDeep)
        .frame(width: 64, height: 1.5)
    }
  }

  private func championColumn(_ match: BracketMatch, depth: Int, cardHeight: CGFloat, gap: CGFloat) -> some View {
    VStack(spacing: 0) {
      Color.clear.frame(height: columnInset(depth, cardHeight: cardHeight, gap: gap) + (cardHeight - BracketLook.championHeight) / 2)
      championCard(match)
    }
  }

  private func championCard(_ match: BracketMatch) -> some View {
    let seat = championSeat(match)
    let named = seat.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasWinner = !named.isEmpty
    return VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "trophy.fill")
          .font(.system(size: 12, weight: .semibold))
        Text("CHAMPION")
          .font(.system(size: 10, weight: .semibold))
          .tracking(0.8)
      }
      .foregroundStyle(BracketLook.goldDeep)
      .padding(.horizontal, 12)
      .frame(height: 32, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(BracketLook.gold.opacity(0.10))
      .overlay(alignment: .bottom) {
        Rectangle().fill(BracketLook.gold.opacity(0.20)).frame(height: 1)
      }
      HStack(spacing: 12) {
        if hasWinner {
          playerFace(seat.picture, mine: true, lost: false, size: 40, stroke: 2)
          VStack(alignment: .leading, spacing: 2) {
            Text(named)
              .font(.system(size: 16, design: .serif))
              .foregroundStyle(BracketLook.ink)
              .lineLimit(1)
            Text("Champion")
              .font(.system(size: 11))
              .foregroundStyle(BracketLook.ink.opacity(0.7))
          }
        } else {
          Circle()
            .strokeBorder(BracketLook.gold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: 40, height: 40)
            .overlay {
              Image(systemName: "trophy.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BracketLook.goldDeep.opacity(0.6))
            }
          VStack(alignment: .leading, spacing: 2) {
            Text("TBD")
              .font(.system(size: 16, design: .serif))
              .foregroundStyle(BracketLook.ink.opacity(0.55))
            Text("Awaiting final")
              .font(.system(size: 11))
              .foregroundStyle(BracketLook.ink.opacity(0.7))
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12)
      .frame(height: 64, alignment: .leading)
    }
    .frame(width: 220, height: BracketLook.championHeight, alignment: .top)
    .background {
      LinearGradient(
        colors: [BracketLook.muted, Color.white, BracketLook.gold.opacity(0.15)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(hasWinner ? BracketLook.gold : BracketLook.gold.opacity(0.30), lineWidth: hasWinner ? 1.5 : 1)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(BracketLook.gold.opacity(hasWinner ? 0.30 : 0), lineWidth: 3)
        .padding(-3)
    }
  }

  private func championSeat(_ match: BracketMatch) -> (name: String?, picture: String?) {
    guard let winnerId = match.winnerId else {
      return (nil, nil)
    }
    if winnerId == match.playerAId {
      return (match.playerAName, match.playerAPictureUrl)
    }
    if winnerId == match.playerBId {
      return (match.playerBName, match.playerBPictureUrl)
    }
    return (nil, nil)
  }

  private func bracketColumn(_ round: BracketRound, depth: Int, cardHeight: CGFloat, gap: CGFloat) -> some View {
    VStack(spacing: 0) {
      Color.clear.frame(height: columnInset(depth, cardHeight: cardHeight, gap: gap))
      VStack(spacing: columnGap(depth, cardHeight: cardHeight, gap: gap)) {
        ForEach(round.matches) { match in
          matchCard(match, title: round.title)
            .frame(height: cardHeight, alignment: .top)
        }
      }
    }
  }

  private func columnGap(_ depth: Int, cardHeight: CGFloat, gap: CGFloat) -> CGFloat {
    var step = cardHeight + gap
    for _ in 0..<depth {
      step *= 2
    }
    return step - cardHeight
  }

  private func columnInset(_ depth: Int, cardHeight: CGFloat, gap: CGFloat) -> CGFloat {
    var inset: CGFloat = 0
    var step = cardHeight + gap
    for _ in 0..<depth {
      inset += step / 2
      step *= 2
    }
    return inset
  }

  private func stackHeight(count: Int, cardHeight: CGFloat, gap: CGFloat) -> CGFloat {
    if count <= 0 { return 0 }
    return CGFloat(count) * cardHeight + CGFloat(count - 1) * gap
  }

  private func bracketRounds(_ item: TournamentItem) -> [BracketRound] {
    let loaded = item.flow?.nodes.compactMap(\.match) ?? []
    let matches = loaded.isEmpty ? emptyMatches(size: item.bracketSize) : loaded
    let numbers = Set(matches.map(\.round)).sorted()
    let total = numbers.count
    return numbers.map { number in
      let column = matches
        .filter { $0.round == number }
        .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
      return BracketRound(number: number, title: roundTitle(matchCount: column.count, totalRounds: total), matches: column)
    }
  }

  private func roundTitle(matchCount: Int, totalRounds: Int) -> String {
    let players = matchCount * 2
    if players == 2 { return "Final" }
    if players == 4 { return "Semifinal" }
    if players == 8 && totalRounds >= 4 { return "Quarterfinal" }
    return "Round of \(players)"
  }

  private func emptyMatches(size: Int) -> [BracketMatch] {
    var remaining = max(size, 2)
    var round = 1
    var matches: [BracketMatch] = []
    while remaining > 1 {
      let count = remaining / 2
      for index in 0..<count {
        matches.append(.slot(round: round, index: index))
      }
      remaining = count
      round += 1
    }
    return matches
  }

  private func matchCard(_ match: BracketMatch, title: String) -> some View {
    VStack(spacing: 0) {
      matchHeader(match, title: title)
      slotLine(match.playerAName, picture: match.playerAPictureUrl, score: match.scoreA, winner: match.winnerId != nil && match.winnerId == match.playerAId, settled: match.winnerId != nil, mine: isMe(match.playerAUserId) || isMe(match.playerAPartnerUserId), onAdd: addAction(match, slot: "A"), onRemove: removeAction(match, slot: "A"), onPick: pickAction(match, slot: "A"))
      Rectangle().fill(BracketLook.gold.opacity(0.10)).frame(height: 1)
      slotLine(match.playerBName, picture: match.playerBPictureUrl, score: match.scoreB, winner: match.winnerId != nil && match.winnerId == match.playerBId, settled: match.winnerId != nil, mine: isMe(match.playerBUserId) || isMe(match.playerBPartnerUserId), onAdd: addAction(match, slot: "B"), onRemove: removeAction(match, slot: "B"), onPick: pickAction(match, slot: "B"))
    }
    .frame(width: 220, alignment: .top)
    .background(Color.white)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(BracketLook.gold.opacity(0.25), lineWidth: 1)
    }
    .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    .confirmationDialog("Set winner", isPresented: winnerDialogPresented(match), titleVisibility: .visible) {
      let a = match.playerAName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let b = match.playerBName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !a.isEmpty {
        Button(a) { openResult(match, slot: "A", name: a) }
      }
      if !b.isEmpty {
        Button(b) { openResult(match, slot: "B", name: b) }
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private func matchHeader(_ match: BracketMatch, title: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title.uppercased())
          .font(.system(size: 10, weight: .semibold))
          .tracking(0.8)
          .foregroundStyle(BracketLook.goldDeep)
        HStack(spacing: 8) {
          courtControl(match)
          refereeControl(match)
        }
      }
      Spacer(minLength: 4)
      resultControl(match)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .frame(height: 46, alignment: .center)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(BracketLook.muted.opacity(0.7))
    .overlay(alignment: .bottom) {
      Rectangle().fill(BracketLook.gold.opacity(0.15)).frame(height: 1)
    }
  }

  @ViewBuilder
  private func resultControl(_ match: BracketMatch) -> some View {
    if let matchId = match.matchId, match.winnerId != nil, canScore {
      Button("Undo result") {
        Task { await undoResult(matchId) }
      }
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(BracketLook.goldDeep)
      .buttonStyle(.plain)
    } else if canStart(match), let matchId = match.matchId {
      Button("Start") {
        Task { await startGame(matchId) }
      }
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(BracketLook.goldDeep)
      .buttonStyle(.plain)
    } else if canRecord(match) {
      Button("Set winner") {
        setWinnerMatchId = match.matchId
      }
      .font(.system(size: 10, weight: .semibold))
      .foregroundStyle(BracketLook.goldDeep)
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private func courtControl(_ match: BracketMatch) -> some View {
    if owned || canManage, let count = item?.courtCount, (1...30).contains(count), let matchId = match.matchId {
      Menu {
        Button("None") { Task { await setCourt(matchId: matchId, number: nil) } }
        ForEach(1...count, id: \.self) { number in
          Button("Court \(number)") { Task { await setCourt(matchId: matchId, number: number) } }
        }
      } label: {
        Text(match.courtNumber.map { "Court \($0)" } ?? "Assign court")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(match.courtNumber == nil ? BracketLook.courtSoft.opacity(0.8) : BracketLook.court)
          .lineLimit(1)
      }
    } else if let number = match.courtNumber {
      Text("Court \(number)")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(BracketLook.court)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private func refereeControl(_ match: BracketMatch) -> some View {
    if owned || canManage, let matchId = match.matchId {
      Menu {
        Button("Set") { picker = .referee(matchId) }
        if refereeLabel(match) != nil {
          Button("Clear") { Task { await assignReferee(matchId: matchId, name: nil) } }
        }
      } label: {
        Text(refereeLabel(match) ?? "Referee")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(refereeLabel(match) == nil ? BracketLook.courtSoft.opacity(0.8) : BracketLook.court)
          .lineLimit(1)
      }
    } else if let name = refereeLabel(match) {
      Text(name)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(BracketLook.court)
        .lineLimit(1)
    }
  }

  private func canStart(_ match: BracketMatch) -> Bool {
    guard canScore, match.matchId != nil, match.winnerId == nil, match.startedAt == nil else { return false }
    let a = match.playerAName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let b = match.playerBName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !a.isEmpty && !b.isEmpty
  }

  private func canRecord(_ match: BracketMatch) -> Bool {
    guard canScore, match.matchId != nil, match.winnerId == nil, match.startedAt != nil else { return false }
    let a = match.playerAName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let b = match.playerBName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !a.isEmpty && !b.isEmpty
  }

  private func pickAction(_ match: BracketMatch, slot: String) -> (() -> Void)? {
    guard canRecord(match) else { return nil }
    let name = (slot == "A" ? match.playerAName : match.playerBName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !name.isEmpty else { return nil }
    return { openResult(match, slot: slot, name: name) }
  }

  private func openResult(_ match: BracketMatch, slot: String, name: String) {
    guard let matchId = match.matchId else { return }
    scoreA = ""
    scoreB = ""
    resultError = nil
    setWinnerMatchId = nil
    resultPick = ResultPick(matchId: matchId, winnerSlot: slot, winnerName: name)
  }

  private func winnerDialogPresented(_ match: BracketMatch) -> Binding<Bool> {
    Binding(
      get: { setWinnerMatchId != nil && setWinnerMatchId == match.matchId },
      set: { shown in
        if !shown, setWinnerMatchId == match.matchId {
          setWinnerMatchId = nil
        }
      }
    )
  }

  private func startGame(_ matchId: String) async {
    guard let item else { return }
    errorMessage = nil
    do {
      self.item = try await service.startMatch(tournamentId: item.id, matchId: matchId)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func undoResult(_ matchId: String) async {
    guard let item else { return }
    errorMessage = nil
    do {
      self.item = try await service.clearResult(tournamentId: item.id, matchId: matchId)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func resultSheet(_ pick: ResultPick) -> some View {
    NavigationStack {
      ScreenColumn(kicker: "", title: pick.winnerName, subtitle: "Score is required.") {
        VStack(alignment: .leading, spacing: 16) {
          AuthField(title: "Score A", text: $scoreA, keyboard: .numberPad)
          AuthField(title: "Score B", text: $scoreB, keyboard: .numberPad)
          if let resultError {
            Notice(text: resultError, tone: Theme.danger)
          }
          ClayButton(title: "Save") {
            Task { await saveResult(pick) }
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { resultPick = nil }
        }
      }
    }
    .presentationDragIndicator(.visible)
  }

  private func saveResult(_ pick: ResultPick) async {
    guard let item else { return }
    guard let a = Int(scoreA), let b = Int(scoreB), a >= 0, b >= 0 else {
      resultError = "Both scores are required"
      return
    }
    let winnerScore = pick.winnerSlot == "A" ? a : b
    let loserScore = pick.winnerSlot == "A" ? b : a
    guard winnerScore > loserScore else {
      resultError = "Winner score must be higher"
      return
    }
    resultError = nil
    do {
      self.item = try await service.recordResult(
        tournamentId: item.id,
        matchId: pick.matchId,
        winnerSlot: pick.winnerSlot,
        scoreA: a,
        scoreB: b
      )
      resultPick = nil
    } catch {
      resultError = error.localizedDescription
    }
  }

  private func addAction(_ match: BracketMatch, slot: String) -> (() -> Void)? {
    guard owned || canManage, match.round == 0, let matchId = match.matchId else { return nil }
    let name = slot == "A" ? match.playerAName : match.playerBName
    if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
    return { picker = .player(BracketSeat(matchId: matchId, slot: slot)) }
  }

  private func removeAction(_ match: BracketMatch, slot: String) -> (() -> Void)? {
    guard owned || canManage, match.round == 0, match.winnerId == nil, let matchId = match.matchId, let item else { return nil }
    let phase = VenueClock.phase(item)
    guard phase == "Draft" || phase == "Upcoming" else { return nil }
    let name = slot == "A" ? match.playerAName : match.playerBName
    guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return { Task { await clear(matchId: matchId, slot: slot) } }
  }

  private func clear(matchId: String, slot: String) async {
    guard let item else { return }
    errorMessage = nil
    do {
      self.item = try await service.clearPlayer(
        tournamentId: item.id,
        matchId: matchId,
        slot: slot
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refereeLabel(_ match: BracketMatch) -> String? {
    let name = match.refereeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return name.isEmpty ? nil : name
  }

  private func setCourt(matchId: String, number: Int?) async {
    guard let item else { return }
    errorMessage = nil
    do {
      self.item = try await service.setCourt(tournamentId: item.id, matchId: matchId, courtNumber: number)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func currentReferee(_ matchId: String) -> String {
    let loaded = item?.flow?.nodes.compactMap(\.match) ?? []
    return loaded.first { $0.matchId == matchId }?.refereeName ?? ""
  }

  private func assignReferee(matchId: String, name: String?) async {
    guard let item else { return }
    errorMessage = nil
    do {
      self.item = try await service.setReferee(tournamentId: item.id, matchId: matchId, name: name)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func place(_ account: AccountHit, in seat: BracketSeat) async {
    guard let item else { return }
    errorMessage = nil
    do {
      self.item = try await service.assignPlayer(
        tournamentId: item.id,
        matchId: seat.matchId,
        slot: seat.slot,
        name: account.email
      )
      if requests.contains(where: { $0.userId == account.id }) {
        requests = try await service.clearJoinRequest(id: item.id, userId: account.id)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func isMe(_ userId: String?) -> Bool {
    guard let userId, let mine = auth.user?.id else { return false }
    return userId == mine
  }

  @ViewBuilder
  private func slotLine(_ name: String?, picture: String?, score: Int?, winner: Bool, settled: Bool, mine: Bool, onAdd: (() -> Void)?, onRemove: (() -> Void)?, onPick: (() -> Void)?) -> some View {
    let row = slotRow(name, picture: picture, score: score, winner: winner, settled: settled, mine: mine, onAdd: onAdd, onRemove: onRemove)
    if let onPick {
      Button(action: onPick) { row }
        .buttonStyle(.plain)
    } else {
      row
    }
  }

  private func slotRow(_ name: String?, picture: String?, score: Int?, winner: Bool, settled: Bool, mine: Bool, onAdd: (() -> Void)?, onRemove: (() -> Void)?) -> some View {
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let open = trimmed.isEmpty
    let lost = settled && !winner && !open
    return HStack(spacing: 8) {
      if open {
        Circle()
          .strokeBorder(BracketLook.gold.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
          .frame(width: 24, height: 24)
          .overlay {
            Text("+")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(BracketLook.goldDeep.opacity(0.7))
          }
      } else {
          playerFace(picture, mine: mine, lost: lost, size: 24, stroke: mine && !lost ? 1.5 : 1)
      }
      if open, let onAdd {
        Button(action: onAdd) {
          Text("Add")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(BracketLook.goldDeep)
        }
        .buttonStyle(.borderless)
      } else {
        Text(open ? "TBD" : trimmed)
          .font(.system(size: 14, weight: winner ? .semibold : .regular))
          .foregroundStyle(lost ? BracketLook.ink.opacity(0.35) : (open ? BracketLook.ink.opacity(0.55) : BracketLook.ink))
          .strikethrough(lost, color: BracketLook.ink.opacity(0.35))
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      if let onRemove {
        Button("Remove", action: onRemove)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Theme.danger)
          .buttonStyle(.borderless)
      }
      if let score {
        Text("\(score)")
          .font(.system(size: 14))
          .monospacedDigit()
          .foregroundStyle(lost ? BracketLook.ink.opacity(0.30) : BracketLook.ink.opacity(0.55))
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 40)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(winner ? BracketLook.gold.opacity(0.10) : (lost ? BracketLook.ink.opacity(0.03) : Color.clear))
  }

  private func playerFace(_ raw: String?, mine: Bool, lost: Bool, size: CGFloat, stroke: CGFloat) -> some View {
    Group {
      if let raw, let url = bannerURL(raw) {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            faceMark
          }
        }
      } else {
        faceMark
      }
    }
    .frame(width: size, height: size)
    .background(BracketLook.muted)
    .clipShape(Circle())
    .overlay {
      Circle().stroke(mine && !lost ? BracketLook.gold : BracketLook.gold.opacity(0.25), lineWidth: stroke)
    }
    .grayscale(lost ? 1 : 0)
    .opacity(lost ? 0.4 : 1)
  }

  private var faceMark: some View {
    Image(systemName: "person.fill")
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(Theme.mute)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func standingBoard(_ item: TournamentItem) -> (rows: [Standing], championId: String?)? {
    guard let flow = item.flow else { return nil }
    let matches = flow.nodes.compactMap(\.match)
    let rows = ScoreDifferential.standings(matches: matches)
    if rows.isEmpty { return nil }
    return (rows, ScoreDifferential.championId(matches: matches))
  }

  private func standings(_ rows: [Standing], championId: String?) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("STANDINGS")
        .font(.system(size: 12, weight: .semibold))
        .tracking(1.2)
        .foregroundStyle(Theme.mute)
        .padding(.top, 8)
      ForEach(rows) { row in
        VStack(alignment: .leading, spacing: 4) {
          if row.id == championId && row.place == 1 {
            Text("CHAMPION")
              .font(.system(size: 12, weight: .semibold))
              .tracking(1.2)
              .foregroundStyle(Theme.clay)
          }
          Text("\(row.place)")
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.mute)
          Text(row.name)
            .font(.system(size: 22, weight: .regular, design: .serif))
            .foregroundStyle(Theme.ink)
          Text("\(row.record)   \(row.differentialLabel)")
            .font(.system(size: 15))
            .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        }
      }
    }
  }

  private func summary(_ item: TournamentItem) -> some View {
    let placeName = item.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let courtLabel = item.courtName?.trimmingCharacters(in: .whitespacesAndNewlines)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        if let startsAt = item.startsAt, let endsAt = item.endsAt, let line = VenueClock.span(start: startsAt, end: endsAt) {
          Text(line)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
        } else if let startsAt = item.startsAt {
          Text(VenueClock.label(startsAt))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
        }
      }
      if let placeName, !placeName.isEmpty {
        Text(placeName)
          .font(.system(size: 16))
          .foregroundStyle(Theme.ink)
      } else if let courtLabel, !courtLabel.isEmpty {
        Text(courtLabel)
          .font(.system(size: 16))
          .foregroundStyle(Theme.ink)
      }
      if let venueName = item.venueName, !venueName.isEmpty,
         let latitude = item.venueLatitude, let longitude = item.venueLongitude {
        VenueMap(name: venueName, latitude: latitude, longitude: longitude)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    }
  }

  private func entranceFee(_ item: TournamentItem) -> some View {
    Group {
      if let fee = item.registrationFee, let currency = item.registrationFeeCurrency {
        HStack {
          Text("ENTRANCE FEE")
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.mute)
          Spacer()
          Text("\(fee) \(currency)")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.ink)
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

  @ViewBuilder
  private func storyCard(_ item: TournamentItem) -> some View {
    if let text = story(item) {
      Text(text)
        .font(.system(size: 20, weight: .regular, design: .serif))
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
  }

  private func story(_ item: TournamentItem) -> String? {
    guard VenueClock.phase(item) == "Completed",
          let window = playWindow(item),
          let winner = winnerNames(item)["1st"],
          let amount = item.prizes?.first(where: { $0.place.lowercased() == "1st" })?.prize,
          !amount.isEmpty else {
      return nil
    }
    return "Tournament started \(VenueClock.label(VenueClock.stamp(window.start))) and ended \(VenueClock.label(VenueClock.stamp(window.end))). \(winner) takes home \(amount). \(played(from: window.start, until: window.end)) Congratulations!"
  }

  private func playWindow(_ item: TournamentItem) -> (start: Date, end: Date)? {
    let matches = item.flow?.nodes.compactMap(\.match) ?? []
    guard let firstRound = matches.map(\.round).min(),
          let lastRound = matches.map(\.round).max() else {
      return nil
    }
    let starts = matches.filter { $0.round == firstRound }.compactMap { match in
      match.startedAt.flatMap(VenueClock.parse)
    }
    guard let start = starts.min() else { return nil }
    let ends = matches.filter { $0.round == lastRound }.compactMap { match in
      match.endedAt.flatMap(VenueClock.parse)
    }
    guard let end = ends.max(), end >= start else { return nil }
    return (start, end)
  }

  private func played(from start: Date, until end: Date) -> String {
    let minutes = Int(end.timeIntervalSince(start) / 60)
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 {
      return rest == 1 ? "The game took only 1 minute." : "The game took only \(rest) minutes."
    }
    if rest == 0 {
      return hours == 1 ? "The game took only 1 hr." : "The game took only \(hours) hrs."
    }
    let hourWord = hours == 1 ? "1 hr" : "\(hours) hrs"
    let minuteWord = rest == 1 ? "1 minute" : "\(rest) minutes"
    return "The game took only \(hourWord) and \(minuteWord)."
  }

  private var cameraOpen: Binding<Bool> {
    Binding(
      get: { photoPlace != nil && UIImagePickerController.isSourceTypeAvailable(.camera) },
      set: { if !$0 { photoPlace = nil } }
    )
  }

  private func prizes(_ item: TournamentItem) -> some View {
    let filled = (item.prizes ?? []).filter { !$0.prize.isEmpty }
    let names = winnerNames(item)
    return Group {
      if !filled.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(filled.enumerated()), id: \.element.place) { index, prize in
            prizeRow(item, prize: prize, name: names[prize.place.lowercased()])
            if index < filled.count - 1 {
              Rectangle()
                .fill(Theme.line)
                .frame(height: 1)
                .padding(.leading, 48)
            }
          }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.line, lineWidth: 1)
        }
      }
    }
  }

  private func prizeRow(_ item: TournamentItem, prize: TournamentPrize, name: String?) -> some View {
    HStack(spacing: 12) {
      Image(systemName: prizeIcon(prize.place))
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(prizeInk(prize.place))
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(prize.place.uppercased())
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.ink)
        if let name, !name.isEmpty {
          Text(name)
            .font(.system(size: 16, weight: .regular, design: .serif))
            .foregroundStyle(Theme.ink)
        }
      }
      Spacer(minLength: 8)
      if let raw = winnerPhoto(item, place: prize.place), let url = bannerURL(raw) {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      }
      if canPhotograph(item), name != nil {
        Button {
          photoPlace = prize.place.lowercased()
        } label: {
          if uploadingPlace == prize.place.lowercased() {
            ProgressView()
              .frame(width: 28, height: 28)
          } else {
            Image(systemName: "camera.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(Theme.clay)
              .frame(width: 28, height: 28)
          }
        }
        .buttonStyle(.plain)
        .disabled(uploadingPlace != nil)
      }
      Text(prize.prize)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.ink)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  private func publicWatch(_ id: String) -> some View {
    let url = APIConfig.baseURL
      .appending(path: "tournament")
      .appending(path: id)
      .appending(path: "watch")
    return VStack(spacing: 10) {
      WatchQR(url: url.absoluteString)
      Link(destination: url) {
        Text(url.absoluteString)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.clay)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(14)
    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    }
  }

  private func canPhotograph(_ item: TournamentItem) -> Bool {
    if owned { return true }
    guard let ownerId = item.createdById, let userId = auth.user?.id else { return false }
    return ownerId == userId
  }

  private func winnerPhoto(_ item: TournamentItem, place: String) -> String? {
    switch place.lowercased() {
    case "1st":
      return item.firstPlacePhotoUrl
    case "2nd":
      return item.secondPlacePhotoUrl
    case "3rd":
      return item.thirdPlacePhotoUrl
    default:
      return nil
    }
  }

  private func winnerNames(_ item: TournamentItem) -> [String: String] {
    let matches = item.flow?.nodes.compactMap(\.match) ?? []
    guard let maxRound = matches.map(\.round).max(),
          let final = matches.filter({ $0.round == maxRound }).sorted(by: { ($0.index ?? 0) < ($1.index ?? 0) }).first,
          let winnerId = final.winnerId else {
      return [:]
    }
    var names: [String: String] = [:]
    if winnerId == final.playerAId {
      if let name = trimmed(final.playerAName) { names["1st"] = name }
      if let name = trimmed(final.playerBName) { names["2nd"] = name }
    } else if winnerId == final.playerBId {
      if let name = trimmed(final.playerBName) { names["1st"] = name }
      if let name = trimmed(final.playerAName) { names["2nd"] = name }
    }
    if maxRound > 0 {
      let semis = matches
        .filter { $0.round == maxRound - 1 && $0.winnerId != nil }
        .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
      for semi in semis {
        let loser: String?
        if semi.winnerId == semi.playerAId {
          loser = semi.playerBName
        } else if semi.winnerId == semi.playerBId {
          loser = semi.playerAName
        } else {
          loser = nil
        }
        if let name = trimmed(loser) {
          names["3rd"] = name
          break
        }
      }
    }
    return names
  }

  private func trimmed(_ value: String?) -> String? {
    let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? nil : text
  }

  private func uploadWinnerPhoto(_ place: String, data: Data) async {
    guard place == "1st" || place == "2nd" || place == "3rd" else { return }
    uploadingPlace = place
    defer { uploadingPlace = nil }
    errorMessage = nil
    do {
      item = try await service.setWinnerPhoto(id: id, place: place, data: data)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func prizeIcon(_ place: String) -> String {
    switch place.lowercased() {
    case "1st":
      return "trophy.fill"
    case "2nd":
      return "medal.fill"
    default:
      return "star.circle.fill"
    }
  }

  private func prizeInk(_ place: String) -> Color {
    switch place.lowercased() {
    case "1st":
      return Color(red: 0.72, green: 0.52, blue: 0.08)
    case "2nd":
      return Color(red: 0.45, green: 0.50, blue: 0.58)
    default:
      return Color(red: 0.62, green: 0.38, blue: 0.18)
    }
  }

  private func bannerURL(_ raw: String) -> URL? {
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
      return URL(string: raw)
    }
    return URL(string: raw, relativeTo: APIConfig.baseURL)?.absoluteURL
  }

  private var deleteSheet: some View {
    NavigationStack {
      ZStack {
        Theme.paper.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 16) {
          Text("This removes the draw.")
            .font(.system(size: 16))
            .foregroundStyle(Theme.mute)
          if let errorMessage {
            Notice(text: errorMessage, tone: Theme.danger)
          }
          ClayButton(title: "Delete tournament", busy: loading) {
            Task { await remove() }
          }
          Spacer()
        }
        .padding(24)
      }
      .navigationTitle("Delete")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { showDelete = false }
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func load(showingSpinner: Bool = true) async {
    if showingSpinner { loading = true }
    errorMessage = nil
    do {
      item = try await service.detail(id: id, managing: canManage || owned)
      spectatorCount = item?.spectatorCount
      spectating = item?.spectating == true
      let listed = try await service.joinRequests(id: id)
      requests = listed.requests
    } catch {
      errorMessage = error.localizedDescription
    }
    loading = false
  }

  private func remove() async {
    loading = true
    errorMessage = nil
    do {
      try await service.delete(id: id)
      showDelete = false
      path.removeAll { route in
        if case .draw(let drawId, _) = route { return drawId == id }
        if case .drawForm(let formId) = route { return formId == id }
        return false
      }
    } catch {
      errorMessage = error.localizedDescription
      loading = false
    }
  }
}

private struct RefereeNameSheet: View {
  let initial: String
  let onSave: (String?) -> Void
  @State private var name: String
  @Environment(\.dismiss) private var dismiss

  init(initial: String, onSave: @escaping (String?) -> Void) {
    self.initial = initial
    self.onSave = onSave
    _name = State(initialValue: initial)
  }

  var body: some View {
    ScreenColumn(kicker: "", title: "Referee", subtitle: "Type a name.") {
      VStack(alignment: .leading, spacing: 16) {
        AuthField(title: "Name", text: $name)
        ClayButton(title: "Save") {
          let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
          onSave(trimmed.isEmpty ? nil : trimmed)
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close") { dismiss() }
      }
    }
  }
}

struct ResultPick: Identifiable {
  let matchId: String
  let winnerSlot: String
  let winnerName: String
  var id: String { matchId + winnerSlot }
}

enum BracketPicker: Identifiable {
  case player(BracketSeat)
  case referee(String)

  var id: String {
    switch self {
    case .player(let seat):
      return "player-\(seat.id)"
    case .referee(let matchId):
      return "referee-\(matchId)"
    }
  }
}

struct BracketSeat: Identifiable {
  let matchId: String
  let slot: String
  var id: String { "\(matchId)-\(slot)" }
}

struct OwnerRef: Identifiable {
  let id: String
  let name: String
  let picture: String?
}

struct OwnerSheet: View {
  let owner: OwnerRef
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        avatar
        Text(owner.name)
          .font(.system(size: 28, weight: .regular, design: .serif))
          .foregroundStyle(Theme.ink)
        Spacer()
      }
      .padding(.top, 36)
      .frame(maxWidth: .infinity)
      .background(Theme.paper)
      .navigationTitle("Player")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") { dismiss() }
        }
      }
    }
    .presentationDragIndicator(.visible)
  }

  private var avatar: some View {
    Group {
      if let picture = owner.picture, let url = media(picture) {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            person
          }
        }
      } else {
        person
      }
    }
    .frame(width: 96, height: 96)
    .background(Theme.card)
    .clipShape(Circle())
    .overlay {
      Circle().stroke(Theme.line, lineWidth: 1)
    }
  }

  private var person: some View {
    Image(systemName: "person.fill")
      .font(.system(size: 36, weight: .semibold))
      .foregroundStyle(Theme.mute)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func media(_ raw: String) -> URL? {
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
      return URL(string: raw)
    }
    return URL(string: raw, relativeTo: APIConfig.baseURL)?.absoluteURL
  }
}

private struct WinnerCamera: UIViewControllerRepresentable {
  var onShot: (UIImage) -> Void
  var onCancel: () -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.cameraCaptureMode = .photo
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: WinnerCamera

    init(_ parent: WinnerCamera) {
      self.parent = parent
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      if let image = info[.originalImage] as? UIImage {
        parent.onShot(image)
      } else {
        parent.onCancel()
      }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.onCancel()
    }
  }
}

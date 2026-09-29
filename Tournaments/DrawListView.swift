import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct DrawListView: View {
  @Environment(AuthStore.self) private var auth
  @Binding var path: [AuthRoute]
  var refreshTick = 0
  @State private var rows: [DrawEntry] = []
  @State private var errorMessage: String?
  @State private var loading = true
  @State private var showProfile = false
  @State private var viewingOwner: OwnerRef?

  private let service = TournamentService()

  var body: some View {
    ScreenColumn(
      kicker: "",
      title: "Tournaments",
      subtitle: "Ones you made and ones you joined.",
      refresh: { await load() }
    ) {
      VStack(alignment: .leading, spacing: 14) {
        if loading {
          ProgressView()
            .tint(Theme.clay)
        } else if let errorMessage {
          Notice(text: errorMessage, tone: Theme.danger)
        } else if rows.isEmpty {
          Text("No tournaments yet.")
            .font(.system(size: 16))
            .foregroundStyle(Theme.mute)
        } else {
          if let featured {
            Button {
              path.append(.draw(featured.item.id, featured.made))
            } label: {
              upcomingCard(featured)
            }
            .buttonStyle(.plain)
          }
          let rest = rows.filter { $0.id != featured?.id }
          if !rest.isEmpty {
            Text("YOURS")
              .font(.system(size: 12, weight: .semibold))
              .tracking(1.4)
              .foregroundStyle(Theme.mute)
              .padding(.top, 8)
            ForEach(rest) { row in
              Button {
                path.append(.draw(row.item.id, row.made))
              } label: {
                drawRow(row)
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
      if auth.user != nil {
        ToolbarItemGroup(placement: .topBarTrailing) {
          NoticeBell(path: $path)
          profileButton
        }
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
    .onChange(of: auth.isSignedIn) { _, signedIn in
      if !signedIn { showProfile = false }
    }
    .sheet(item: $viewingOwner) { owner in
      OwnerSheet(owner: owner)
    }
  }

  private var profileButton: some View {
    Button {
      if auth.user == nil {
        path.append(.login)
      } else {
        showProfile = true
      }
    } label: {
      profileFace
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Profile")
  }

  private var profileFace: some View {
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

  private var managing: Bool {
    guard let user = auth.user else { return false }
    return DrawAccess.canManage(user)
  }

  private var featured: DrawEntry? {
    let ongoing = rows
      .filter { VenueClock.phase($0.item) == "Ongoing" }
      .sorted { startTime($0.item) < startTime($1.item) }
    if let current = ongoing.first {
      return current
    }
    return rows
      .filter { VenueClock.phase($0.item) == "Upcoming" }
      .sorted { startTime($0.item) < startTime($1.item) }
      .first
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

  private func spectatorLine(_ item: TournamentItem, ink: Color) -> some View {
    Group {
      if VenueClock.phase(item) == "Ongoing", let count = item.spectatorCount {
        Text(count == 1 ? "1 spectating" : "\(count) spectating")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(ink)
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

  private func upcomingCard(_ entry: DrawEntry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Color.clear
        .frame(height: 148)
        .frame(maxWidth: .infinity)
        .background { BannerPlate(raw: entry.item.bannerUrl) }
        .clipped()
      cardFacts(entry, titleSize: 28)
    }
    .background(Theme.card)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    }
  }

  private func drawRow(_ row: DrawEntry) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Color.clear
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .background { BannerPlate(raw: row.item.bannerUrl) }
        .clipped()
      cardFacts(row, titleSize: 22)
    }
    .background(Theme.card)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Theme.line, lineWidth: 1)
    }
  }

  private func cardFacts(_ entry: DrawEntry, titleSize: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        PhaseLabel(item: entry.item, color: Theme.mute)
        Spacer(minLength: 8)
        if let venue = entry.item.venueName, !venue.isEmpty {
          Text(venue)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.mute)
            .multilineTextAlignment(.trailing)
        }
      }
      Text(entry.item.titledName)
        .font(.system(size: titleSize, weight: .regular, design: .serif))
        .foregroundStyle(Theme.ink)
      if let startsAt = entry.item.startsAt {
        Text(VenueClock.label(startsAt))
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.ink)
      }
      spectatorLine(entry.item, ink: Theme.mute)
      HStack(alignment: .bottom) {
        prizeLine(entry.item, ink: Theme.ink, mute: Theme.mute)
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 4) {
          if entry.made {
            Text("Created by you")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Theme.clay)
          }
          ownerButton(entry.item, ink: Theme.ink)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
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
      let mine = try await service.mine()
      var merged: [String: DrawEntry] = [:]
      for item in mine.created {
        merged[item.id] = DrawEntry(item: item, made: true, joined: false, spectating: false, refereeing: false)
      }
      for item in mine.joined {
        if var existing = merged[item.id] {
          existing.joined = true
          merged[item.id] = existing
        } else {
          merged[item.id] = DrawEntry(item: item, made: false, joined: true, spectating: false, refereeing: false)
        }
      }
      for item in mine.spectated {
        if var existing = merged[item.id] {
          existing.spectating = true
          merged[item.id] = existing
        } else {
          merged[item.id] = DrawEntry(item: item, made: false, joined: false, spectating: true, refereeing: false)
        }
      }
      for item in mine.refereed {
        if var existing = merged[item.id] {
          existing.refereeing = true
          merged[item.id] = existing
        } else {
          merged[item.id] = DrawEntry(item: item, made: false, joined: false, spectating: false, refereeing: true)
        }
      }
      rows = merged.values.sorted { left, right in
        let leftDone = VenueClock.phase(left.item) == "Completed"
        let rightDone = VenueClock.phase(right.item) == "Completed"
        if leftDone != rightDone { return !leftDone }
        return startTime(left.item) > startTime(right.item)
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

struct WatchQR: View {
  let image: UIImage

  init(url: String) {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(url.utf8)
    filter.correctionLevel = "M"
    let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
    let cg = Self.context.createCGImage(output, from: output.extent)!
    image = UIImage(cgImage: cg)
  }

  var body: some View {
    Image(uiImage: image)
      .interpolation(.none)
      .resizable()
      .frame(width: 112, height: 112)
      .padding(8)
      .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .accessibilityLabel("Watch QR")
  }

  private static let context = CIContext()
}

private struct RisingLines: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let color = Color(red: 0.79, green: 0.64, blue: 0.15)
  private let tipColor = Color(red: 1.0, green: 0.95, blue: 0.82)

  private static let particles: [Particle] = {
    var rng = SeededRNG(seed: 42)
    return (0..<40).map { _ in
      Particle(
        x: rng.next(),
        phase: rng.next(),
        speed: 0.10 + rng.next() * 0.22,
        length: 0.10 + rng.next() * 0.20,
        width: 0.7 + rng.next() * 1.1,
        opacity: 0.22 + rng.next() * 0.38
      )
    }
  }()

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
      let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
      Canvas { context, size in
        draw(context: context, size: size, time: t)
      }
    }
    .allowsHitTesting(false)
  }

  private func draw(context: GraphicsContext, size: CGSize, time t: TimeInterval) {
    for particle in Self.particles {
      let progress = (t * particle.speed + particle.phase).truncatingRemainder(dividingBy: 1)
      let tipY = size.height * (1.0 - progress)
      let trailLen = size.height * particle.length
      let x = size.width * particle.x
      let edgeFade = min(progress * 3.5, (1 - progress) * 4.5, 1)
      let alpha = particle.opacity * edgeFade
      var trail = Path()
      trail.move(to: CGPoint(x: x, y: tipY))
      trail.addLine(to: CGPoint(x: x, y: min(size.height, tipY + trailLen)))
      context.stroke(
        trail,
        with: .linearGradient(
          Gradient(stops: [
            .init(color: tipColor.opacity(alpha * 0.95), location: 0),
            .init(color: color.opacity(alpha * 0.45), location: 0.22),
            .init(color: color.opacity(alpha * 0.12), location: 0.55),
            .init(color: .clear, location: 1),
          ]),
          startPoint: CGPoint(x: x, y: tipY),
          endPoint: CGPoint(x: x, y: tipY + trailLen)
        ),
        style: StrokeStyle(lineWidth: particle.width, lineCap: .round)
      )
    }
  }

  private struct Particle {
    let x: Double
    let phase: Double
    let speed: Double
    let length: Double
    let width: CGFloat
    let opacity: Double
  }

  private struct SeededRNG {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 1 : seed }
    mutating func next() -> Double {
      state = state &* 6364136223846793005 &+ 1
      return Double((state >> 33) & 0x7FFF_FFFF) / Double(0x7FFF_FFFF)
    }
  }
}

private struct DrawEntry: Identifiable {
  var item: TournamentItem
  var made: Bool
  var joined: Bool
  var spectating: Bool
  var refereeing: Bool

  var id: String { item.id }

  var mark: String {
    if made && joined { return "Made · Joined" }
    if made { return "Made" }
    if joined && refereeing { return "Joined · Referee" }
    if joined { return "Joined" }
    if refereeing { return "Referee" }
    if spectating { return "Spectating" }
    return VenueClock.phaseTitle(item)
  }
}

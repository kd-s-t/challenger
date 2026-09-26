import SwiftUI

enum Theme {
  static let paper = Color(red: 0.945, green: 0.961, blue: 0.980)
  static let ink = Color(red: 0.063, green: 0.118, blue: 0.227)
  static let clay = Color(red: 0.102, green: 0.310, blue: 0.639)
  static let court = Color(red: 0.082, green: 0.275, blue: 0.557)
  static let card = Color.white
  static let line = Color(red: 0.816, green: 0.859, blue: 0.922)
  static let mute = Color(red: 0.361, green: 0.435, blue: 0.545)
  static let danger = Color(red: 0.769, green: 0.188, blue: 0.227)
  static let onFill = Color.white
  static let ready = Color(red: 0.13, green: 0.62, blue: 0.36)
}

struct PhaseLabel: View {
  let item: TournamentItem
  var color: Color

  var body: some View {
    if VenueClock.phase(item) == "Ongoing" {
      LiveBadge()
    } else {
      Text(VenueClock.phaseTitle(item).uppercased())
        .font(.system(size: 12, weight: .semibold))
        .tracking(1.2)
        .foregroundStyle(color)
    }
  }
}

struct LiveBadge: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulse = false

  var body: some View {
    HStack(spacing: 6) {
      ZStack {
        Circle()
          .fill(Color.white.opacity(0.55))
          .frame(width: 8, height: 8)
          .scaleEffect(reduceMotion ? 1 : (pulse ? 1.7 : 1))
          .opacity(reduceMotion ? 0.7 : (pulse ? 0 : 0.8))
        Circle()
          .fill(Color.white)
          .frame(width: 6, height: 6)
      }
      .frame(width: 12, height: 12)
      Text("LIVE NOW")
        .font(.system(size: 11, weight: .bold))
        .tracking(0.3)
    }
    .foregroundStyle(Color.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Theme.ready, in: Capsule())
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeOut(duration: 0.7).repeatForever(autoreverses: false)) {
        pulse = true
      }
    }
  }
}

struct BannerPlate: View {
  let raw: String?
  var dimmed = false

  var body: some View {
    ZStack {
      if let raw, let url = Self.media(raw) {
        AsyncImage(url: url) { phase in
          if let image = phase.image {
            image.resizable().scaledToFill()
          } else {
            wash
          }
        }
      } else {
        wash
      }
      if dimmed {
        Color.white.opacity(0.78)
      } else {
        LinearGradient(
          colors: [Color.black.opacity(0.05), Color.black.opacity(0.45)],
          startPoint: .top,
          endPoint: .bottom
        )
      }
    }
  }

  private var wash: some View {
    ZStack {
      LinearGradient(
        colors: [Theme.clay, Theme.court, Color(red: 0.03, green: 0.10, blue: 0.28)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      LinearGradient(
        colors: [Color.white.opacity(0.28), Color.clear],
        startPoint: .top,
        endPoint: .center
      )
    }
  }

  private static func media(_ raw: String) -> URL? {
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
      return URL(string: raw)
    }
    return URL(string: raw, relativeTo: APIConfig.baseURL)?.absoluteURL
  }
}

struct CourtMark: View {
  var ink: Color = Theme.court

  var body: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .stroke(ink, lineWidth: 1.5)
      .frame(width: 56, height: 76)
      .overlay {
        VStack(spacing: 0) {
          Spacer()
          Rectangle()
            .fill(ink)
            .frame(height: 1.5)
          Spacer()
        }
      }
      .overlay {
        Rectangle()
          .fill(ink)
          .frame(width: 1.5)
      }
  }
}

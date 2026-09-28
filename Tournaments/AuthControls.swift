import SwiftUI

struct ClayButton: View {
  let title: String
  var busy = false
  var fill: Color = Theme.clay
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Text(title)
          .opacity(busy ? 0 : 1)
        if busy {
          ProgressView()
            .tint(Theme.onFill)
        }
      }
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(Theme.onFill)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(busy)
  }
}

struct LineButton: View {
  let title: String
  var busy = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Text(title)
          .opacity(busy ? 0 : 1)
        if busy {
          ProgressView()
            .tint(Theme.ink)
        }
      }
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(Theme.ink)
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .disabled(busy)
  }
}

struct AuthField: View {
  let title: String
  @Binding var text: String
  var secure = false
  var content: UITextContentType?
  var keyboard: UIKeyboardType = .default
  @State private var revealed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.mute)
      HStack(spacing: 8) {
        field
        if secure {
          Button {
            revealed.toggle()
          } label: {
            Image(systemName: revealed ? "eye.slash" : "eye")
              .foregroundStyle(Theme.mute)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 14)
      .frame(height: 54)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(Theme.line, lineWidth: 1)
      }
    }
  }

  @ViewBuilder
  private var field: some View {
    if secure && !revealed {
      SecureField("", text: $text)
        .textContentType(content)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    } else {
      TextField("", text: $text)
        .textContentType(content)
        .keyboardType(keyboard)
        .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
        .autocorrectionDisabled(keyboard == .emailAddress)
    }
  }
}

struct Notice: View {
  let text: String
  var tone: Color = Theme.court

  var body: some View {
    Text(text)
      .font(.system(size: 14))
      .foregroundStyle(tone)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(tone.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct ChallengerLogo: View {
  var height: CGFloat = 120

  var body: some View {
    Image("Logo")
      .resizable()
      .scaledToFit()
      .frame(height: height)
      .frame(maxWidth: .infinity)
      .accessibilityLabel("Challenger")
  }
}

struct ScreenColumn<Content: View>: View {
  let kicker: String
  let title: String
  let subtitle: String
  var logoHeight: CGFloat? = nil
  var refresh: (() async -> Void)? = nil
  @ViewBuilder var content: () -> Content

  var body: some View {
    ZStack {
      Theme.paper.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if let logoHeight {
            ChallengerLogo(height: logoHeight)
              .padding(.bottom, 8)
          }
          if !kicker.isEmpty {
            Text(kicker)
              .font(.system(size: 12, weight: .semibold))
              .tracking(1.6)
              .foregroundStyle(Theme.clay)
          }
          Text(title)
            .font(.system(size: 40, weight: .regular, design: .serif))
            .foregroundStyle(Theme.ink)
            .padding(.top, 10)
          Text(subtitle)
            .font(.system(size: 16))
            .foregroundStyle(Theme.mute)
            .padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true)
          content()
            .padding(.top, 28)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 120)
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshableAction(refresh)
    }
  }
}

private extension View {
  @ViewBuilder
  func refreshableAction(_ action: (() async -> Void)?) -> some View {
    if let action {
      self.refreshable { await action() }
    } else {
      self
    }
  }
}

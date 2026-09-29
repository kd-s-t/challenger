import SwiftUI

struct LoginView: View {
  @Environment(AuthStore.self) private var auth
  @Binding var path: [AuthRoute]
  @State private var email = ""
  @State private var password = ""
  @State private var apple = AppleSignInPresenter()
  @State private var emailBusy = false
  @State private var appleBusy = false
  @State private var googleBusy = false

  var body: some View {
    ScreenColumn(
      kicker: "",
      title: "Challenger",
      subtitle: "",
      logoHeight: 168
    ) {
      VStack(alignment: .leading, spacing: 14) {
        AuthField(title: "Email", text: $email, content: .username, keyboard: .emailAddress)
        AuthField(title: "Password", text: $password, secure: true, content: .password)
        HStack {
          Spacer()
          Button("Forgot password") {
            path.append(.forgot)
          }
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.clay)
        }
        ClayButton(title: "Sign in", busy: emailBusy) {
          Task { await signIn() }
        }
        .disabled(emailBusy || appleBusy || googleBusy)
        if let infoMessage = auth.infoMessage {
          Notice(text: infoMessage)
        }
        if let errorMessage = auth.errorMessage {
          Notice(text: errorMessage, tone: Theme.danger)
          if errorMessage.localizedCaseInsensitiveContains("verify your email") {
            Button("Resend verification email") {
              Task { await resend() }
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.court)
            .disabled(auth.isSubmitting)
          }
        }
        providers
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle("")
    .task {
      auth.clearMessages()
      await auth.adoptExistingSessionIfNeeded()
    }
  }

  private var providers: some View {
    VStack(spacing: 10) {
      Button {
        guard !emailBusy, !appleBusy, !googleBusy else { return }
        appleBusy = true
        apple.onFinish = { result in
          Task { @MainActor in
            await auth.handleAppleCompletion(result)
            appleBusy = false
          }
        }
        apple.start { request in
          auth.prepareAppleRequest(request)
        }
      } label: {
        ZStack {
          HStack(spacing: 10) {
            Image(systemName: "apple.logo")
            Text("Sign in with Apple")
          }
          .opacity(appleBusy ? 0 : 1)
          if appleBusy {
            ProgressView()
              .tint(.white)
          }
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(emailBusy || appleBusy || googleBusy)

      Button {
        Task { await continueWithGoogle() }
      } label: {
        ZStack {
          HStack(spacing: 10) {
            Image("AuthGoogle")
              .resizable()
              .scaledToFit()
              .frame(width: 20, height: 20)
            Text("Continue with Google")
          }
          .opacity(googleBusy ? 0 : 1)
          if googleBusy {
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
      .disabled(emailBusy || appleBusy || googleBusy)
    }
    .padding(.top, 8)
  }

  private func signIn() async {
    emailBusy = true
    defer { emailBusy = false }
    await auth.login(email: email, password: password)
  }

  private func continueWithGoogle() async {
    googleBusy = true
    defer { googleBusy = false }
    await auth.loginWithOAuth(provider: .google)
  }

  private func resend() async {
    let target = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty else { return }
    do {
      auth.infoMessage = try await auth.resendVerification(email: target)
      auth.errorMessage = nil
    } catch {
      auth.errorMessage = error.localizedDescription
    }
  }
}

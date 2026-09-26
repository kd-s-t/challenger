import SwiftUI

struct SignUpView: View {
  @Environment(AuthStore.self) private var auth
  @State private var name = ""
  @State private var email = ""
  @State private var password = ""
  @State private var sent = false

  var body: some View {
    ScreenColumn(
      kicker: "ACCOUNT",
      title: sent ? "Check your email" : "Create account",
      subtitle: sent
        ? "Open the link in the email on this phone. It brings you back here once the address is verified."
        : "Pro player accounts are created here. Admins are assigned on X Court."
    ) {
      if sent, let infoMessage = auth.infoMessage {
        VStack(alignment: .leading, spacing: 14) {
          Notice(text: infoMessage)
          LineButton(title: "Resend email", busy: auth.isSubmitting) {
            Task { await resend() }
          }
          if let errorMessage = auth.errorMessage {
            Notice(text: errorMessage, tone: Theme.danger)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 14) {
          AuthField(title: "Name", text: $name, content: .name)
          AuthField(title: "Email", text: $email, content: .username, keyboard: .emailAddress)
          AuthField(title: "Password", text: $password, secure: true, content: .newPassword)
          Text("At least 8 characters.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.mute)
          ClayButton(title: "Create account", busy: auth.isSubmitting) {
            Task { await submit() }
          }
          .disabled(auth.isSubmitting)
          if let errorMessage = auth.errorMessage {
            Notice(text: errorMessage, tone: Theme.danger)
          }
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle("")
    .task { auth.clearMessages() }
  }

  private func submit() async {
    sent = await auth.register(name: name, email: email, password: password)
  }

  private func resend() async {
    do {
      auth.infoMessage = try await auth.resendVerification(email: email)
      auth.errorMessage = nil
    } catch {
      auth.errorMessage = error.localizedDescription
    }
  }
}

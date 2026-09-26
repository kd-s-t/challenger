import SwiftUI

struct ForgotPasswordView: View {
  @Environment(AuthStore.self) private var auth
  @State private var email = ""
  @State private var sent = false

  var body: some View {
    ScreenColumn(
      kicker: "ACCOUNT",
      title: "Reset password",
      subtitle: "We'll email a reset link for this X Court account."
    ) {
      VStack(alignment: .leading, spacing: 14) {
        if sent, let infoMessage = auth.infoMessage {
          Notice(text: infoMessage)
        } else {
          AuthField(title: "Email", text: $email, content: .username, keyboard: .emailAddress)
          ClayButton(title: "Send reset email", busy: auth.isSubmitting) {
            Task { sent = await auth.forgotPassword(email: email) }
          }
          .disabled(auth.isSubmitting)
        }
        if let errorMessage = auth.errorMessage {
          Notice(text: errorMessage, tone: Theme.danger)
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle("")
    .task { auth.clearMessages() }
  }
}

import SwiftUI

struct AccountView: View {
  @Environment(AuthStore.self) private var auth
  @State private var name = ""
  @State private var email = ""
  @State private var phone = ""
  @State private var profilePicture = ""
  @State private var eligibility = AvatarEligibility.locked
  @State private var loading = true
  @State private var showAvatarPicker = false
  @State private var draftPicture = ""
  @State private var showDelete = false
  @State private var deleteConfirm = ""
  @State private var deletePassword = ""
  @State private var phoneCode = ""
  @State private var verifyingPhone = false

  private let service = AuthService()

  var body: some View {
    Form {
      if loading {
        Section {
          ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
      } else {
        Section {
          HStack(alignment: .center, spacing: 16) {
            Button {
              draftPicture = profilePicture
              showAvatarPicker = true
            } label: {
              avatar(profilePicture, size: 76, selected: true)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 6) {
              TextField("Display name", text: $name)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .textFieldStyle(.plain)
              TextField("Email", text: $email)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.mute)
                .textFieldStyle(.plain)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
              if let user = auth.user {
                Label(
                  user.emailVerified ? "Email verified" : "Email not verified",
                  systemImage: user.emailVerified ? "checkmark.seal.fill" : "exclamationmark.envelope"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(user.emailVerified ? .green : .orange)
              }
            }
          }
          .padding(.vertical, 6)
        }

        Section("Account") {
          TextField("Mobile number", text: $phone)
            .keyboardType(.phonePad)
            .textContentType(.telephoneNumber)
          if let user = auth.user, user.phone != nil {
            Label(
              user.phoneVerified ? "Mobile number verified." : "Phone needs verification",
              systemImage: user.phoneVerified ? "checkmark.seal.fill" : "iphone.badge.play"
            )
            .font(.caption)
            .foregroundStyle(user.phoneVerified ? .green : .orange)
          }
        }

        if auth.user?.phoneVerified == false {
          Section("Verify mobile") {
            Text("We'll send a code by SMS and email when you add or change this.")
              .font(.caption)
              .foregroundStyle(.secondary)
            TextField("Verification code", text: $phoneCode)
              .keyboardType(.numberPad)
              .textContentType(.oneTimeCode)
            Button(verifyingPhone ? "Verifying…" : "Verify mobile") {
              Task { await verifyPhone() }
            }
            .disabled(verifyingPhone || phoneCode.trimmingCharacters(in: .whitespaces).count < 4)
            Button("Resend code") {
              Task { await resendPhone() }
            }
            .disabled(verifyingPhone)
          }
        }

        if let infoMessage = auth.infoMessage {
          Section {
            Text(infoMessage)
              .font(.footnote)
              .foregroundStyle(Theme.ink.opacity(0.7))
          }
        }
        if let errorMessage = auth.errorMessage, !showDelete {
          Section {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }

        Section {
          Button {
            Task { await save() }
          } label: {
            Text(auth.isSubmitting ? "Saving…" : "Save changes")
              .frame(maxWidth: .infinity)
          }
          .disabled(auth.isSubmitting || !canSave)
        }

        Section {
          Button("Sign out", role: .destructive) {
            Task { await auth.logout() }
          }
        }

        Section {
          Button("Delete account", role: .destructive) {
            deleteConfirm = ""
            deletePassword = ""
            auth.clearMessages()
            showDelete = true
          }
        } footer: {
          Text("Permanently removes your account. Booking records may be kept without your personal details.")
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Theme.paper.ignoresSafeArea())
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle("Profile")
    .task { await load() }
    .sheet(isPresented: $showAvatarPicker) {
      avatarSheet
    }
    .sheet(isPresented: $showDelete) {
      deleteSheet
    }
  }

  private var canSave: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !profilePicture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var avatarSheet: some View {
    NavigationStack {
      ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
          ForEach(ProfilePictures.all, id: \.self) { file in
            let unlocked = ProfilePictures.isUnlocked(file, eligibility: eligibility, stored: auth.user?.profilePicture)
            let selected = draftPicture == file
            Button {
              if unlocked { draftPicture = file }
            } label: {
              ZStack {
                avatar(file, size: 64, selected: selected)
                  .opacity(unlocked ? 1 : 0.55)
                  .grayscale(unlocked ? 0 : 1)
                if !unlocked {
                  Image(systemName: "lock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(.black.opacity(0.45)))
                }
              }
            }
            .buttonStyle(.plain)
            .disabled(!unlocked)
          }
        }
        .padding(20)
      }
      .background(Theme.paper.ignoresSafeArea())
      .navigationTitle("Profile picture")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .top) {
        HStack(spacing: 14) {
          avatar(draftPicture, size: 64, selected: true)
          VStack(alignment: .leading, spacing: 4) {
            Text("Choose a picture, then save.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.paper)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { showAvatarPicker = false }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            profilePicture = draftPicture
            showAvatarPicker = false
            Task { await save() }
          }
          .disabled(draftPicture.isEmpty || draftPicture == profilePicture)
        }
      }
    }
    .presentationDetents([.large])
  }

  private func avatar(_ file: String, size: CGFloat, selected: Bool) -> some View {
    let url = ProfilePictures.imageURL(file)
    return AsyncImage(url: url) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFill()
      default:
        Color.gray.opacity(0.15)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay {
      Circle().strokeBorder(selected ? Theme.clay : Theme.line, lineWidth: selected ? 2.5 : 1)
    }
  }

  private func load() async {
    loading = true
    defer { loading = false }
    do {
      let details = try await service.profileDetails()
      auth.applyUser(details.user)
      eligibility = details.avatars
      name = details.user.name ?? ""
      email = details.user.email
      phone = details.user.phone ?? ""
      profilePicture = details.user.profilePicture ?? ""
    } catch {
      if auth.user == nil { return }
      if let user = auth.user {
        name = user.name ?? ""
        email = user.email
        phone = user.phone ?? ""
        profilePicture = user.profilePicture ?? ""
      }
      auth.errorMessage = error.localizedDescription
    }
  }

  private func save() async {
    let ok = await auth.saveAccount(name: name, email: email, phone: phone, picture: profilePicture)
    if ok, let user = auth.user {
      profilePicture = user.profilePicture ?? profilePicture
      phone = user.phone ?? phone
    }
  }

  private func verifyPhone() async {
    verifyingPhone = true
    defer { verifyingPhone = false }
    do {
      try await service.verifyPhone(code: phoneCode.trimmingCharacters(in: .whitespaces))
      phoneCode = ""
      await load()
      auth.infoMessage = "Mobile number verified."
    } catch {
      auth.errorMessage = error.localizedDescription
    }
  }

  private func resendPhone() async {
    verifyingPhone = true
    defer { verifyingPhone = false }
    do {
      try await service.resendPhoneCode()
      auth.infoMessage = "Code sent."
    } catch {
      auth.errorMessage = error.localizedDescription
    }
  }

  private var deleteSheet: some View {
    NavigationStack {
      Form {
        Section {
          Text("This cannot be undone. You will be signed out immediately.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        Section {
          TextField("Type DELETE to confirm", text: $deleteConfirm)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
          if auth.user?.requiresPasswordForDeletion == true {
            SecureField("Password", text: $deletePassword)
          }
        }
        if let errorMessage = auth.errorMessage {
          Section {
            Text(errorMessage).font(.footnote).foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Delete account")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            showDelete = false
            auth.clearMessages()
          }
        }
        ToolbarItem(placement: .destructiveAction) {
          Button("Delete account") {
            Task { await remove() }
          }
          .disabled(!canDelete || auth.isSubmitting)
        }
      }
    }
    .presentationDetents([.medium])
  }

  private var canDelete: Bool {
    let confirmed = deleteConfirm.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "DELETE"
    let needsPassword = auth.user?.requiresPasswordForDeletion == true
    return confirmed && (!needsPassword || !deletePassword.isEmpty)
  }

  private func remove() async {
    let password = auth.user?.requiresPasswordForDeletion == true ? deletePassword : nil
    let ok = await auth.deleteAccount(confirm: deleteConfirm, password: password)
    if ok { showDelete = false }
  }
}

import SwiftUI

enum AuthRoute: Hashable {
  case login
  case signUp
  case forgot
  case account
  case draws
  case draw(String, Bool)
  case drawForm(String?)
}

private enum ShellTab: Hashable {
  case draws
  case join
  case create
}

struct RootView: View {
  @Environment(AuthStore.self) private var auth
  @State private var path: [AuthRoute] = []
  @State private var joinPath: [AuthRoute] = []
  @State private var createPath: [AuthRoute] = []
  @State private var tab: ShellTab = .draws
  @State private var drawsTick = 0
  @State private var joinTick = 0

  var body: some View {
    Group {
      if auth.isBootstrapping {
        Theme.paper.ignoresSafeArea()
      } else if auth.isSignedIn {
        signedIn
      } else {
        signedOut
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.paper.ignoresSafeArea())
    .tint(Theme.clay)
    .preferredColorScheme(.light)
    .task {
      await auth.bootstrap()
    }
    .onOpenURL { url in
      Task { await auth.handleVerifyEmailDeepLink(url) }
    }
    .onChange(of: auth.isSignedIn) { _, signedIn in
      if signedIn {
        path = []
        joinPath = []
        createPath = []
        tab = .draws
      }
    }
  }

  private var signedOut: some View {
    NavigationStack(path: $path) {
      LoginView(path: $path)
        .navigationDestination(for: AuthRoute.self) { route in
          destination(route, path: $path)
        }
    }
  }

  private var signedIn: some View {
    TabView(selection: $tab) {
      Tab("Tournaments", systemImage: "square.grid.2x2", value: ShellTab.draws) {
        NavigationStack(path: $path) {
          DrawListView(path: $path, refreshTick: drawsTick)
            .navigationDestination(for: AuthRoute.self) { route in
              destination(route, path: $path)
            }
        }
      }
      Tab("Join", systemImage: "person.2", value: ShellTab.join) {
        NavigationStack(path: $joinPath) {
          JoinListView(path: $joinPath, refreshTick: joinTick)
            .navigationDestination(for: AuthRoute.self) { route in
              destination(route, path: $joinPath)
            }
        }
      }
      if UIDevice.current.userInterfaceIdiom == .pad {
        Tab("Host a tournament", systemImage: "plus", value: ShellTab.create) {
          NavigationStack(path: $createPath) {
            DrawFormView(path: $createPath, existingId: nil)
              .navigationDestination(for: AuthRoute.self) { route in
                destination(route, path: $createPath)
              }
          }
        }
      } else {
        Tab(value: ShellTab.create, role: .search) {
          Color.clear
        } label: {
          Label("Create", systemImage: "plus")
        }
      }
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .onChange(of: tab) { _, newTab in
      if newTab == .draws { drawsTick += 1 }
      if newTab == .join { joinTick += 1 }
      guard newTab == .create, UIDevice.current.userInterfaceIdiom != .pad else { return }
      tab = .draws
      path.append(.drawForm(nil))
    }
  }

  @ViewBuilder
  private func destination(_ route: AuthRoute, path: Binding<[AuthRoute]>) -> some View {
    switch route {
    case .login:
      LoginView(path: path)
    case .signUp:
      SignUpView()
    case .forgot:
      ForgotPasswordView()
    case .account:
      AccountView()
    case .draws:
      DrawListView(path: path)
    case .draw(let id, let owned):
      DrawDetailView(path: path, id: id, owned: owned)
    case .drawForm(let id):
      DrawFormView(path: path, existingId: id)
        .id(id ?? "new")
    }
  }
}

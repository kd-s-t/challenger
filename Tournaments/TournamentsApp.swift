import SwiftUI

@main
struct TournamentsApp: App {
  @State private var auth = AuthStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(auth)
    }
  }
}

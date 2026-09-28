import SwiftUI

@main
struct TournamentsApp: App {
  @State private var auth = AuthStore()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(auth)
    }
    .defaultSize(width: 1032, height: 1376)
  }
}

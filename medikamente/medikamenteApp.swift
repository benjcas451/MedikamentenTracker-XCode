import SwiftUI

@main
struct MedikamenteApp: App {

  init() {
    NunitoFont.registrieren()
    AppSettings.migrationAusfuehren()
    // Versorgt die Apple Watch mit dem jeweils neuesten Stand.
    WatchSync.shared.activate()
  }

  var body: some Scene {
    WindowGroup {
      HomeView()
    }
  }
}

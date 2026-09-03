import SwiftUI

@main
struct MedikamenteApp: App {

  init() {
    NunitoFont.registrieren()
    AppSettings.migrationAusfuehren()
    // Ohne mindestens eine Datei blendet iOS den App-Ordner in der
    // „Dateien“-App aus – dort liegen aber client.crt/client.key.
    AppOrdner.sichtbarMachen()
    // Versorgt die Apple Watch mit dem jeweils neuesten Stand.
    WatchSync.shared.activate()
  }

  var body: some Scene {
    WindowGroup {
      HomeView()
    }
  }
}

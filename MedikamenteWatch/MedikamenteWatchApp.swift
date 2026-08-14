import SwiftUI

@main
struct MedikamenteWatchApp: App {
  /// Wird beim App-Start erzeugt und aktiviert die WatchConnectivity-Session.
  @StateObject private var store = WatchStore()

  var body: some Scene {
    WindowGroup {
      ContentView().environmentObject(store)
    }
  }
}

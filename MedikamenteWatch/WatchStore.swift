import Foundation
import WatchConnectivity

/// Hält den zuletzt vom iPhone empfangenen Stand und macht ihn für die
/// SwiftUI-Views beobachtbar.
///
/// Der Stand wird in den `UserDefaults` der Uhr gespiegelt, damit die App auch
/// ohne iPhone in Reichweite sofort etwas anzeigen kann statt leer zu starten.
@MainActor
final class WatchStore: NSObject, ObservableObject {
  private static let cacheKey = "last_snapshot"

  @Published private(set) var snapshot = WatchSnapshot()

  override init() {
    super.init()
    if let cached = UserDefaults.standard.dictionary(forKey: Self.cacheKey) {
      snapshot = WatchSnapshot(context: cached)
    }
    activate()
  }

  private func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  /// Übernimmt einen empfangenen Application-Context (auch der beim Start
  /// bereits vorliegende) und legt ihn im Cache ab.
  private func apply(_ context: [String: Any]) {
    guard !context.isEmpty else { return }
    let next = WatchSnapshot(context: context)
    snapshot = next
    UserDefaults.standard.set(next.json, forKey: Self.cacheKey)
  }
}

extension WatchStore: WCSessionDelegate {
  // Die Delegate-Callbacks kommen von beliebigen Threads; die eigentliche
  // Verarbeitung springt auf den MainActor (Wörterbuch bewusst als
  // unstrukturierte Kopie übergeben – [String: Any] ist nicht Sendable).
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    guard activationState == .activated else { return }
    // Beim Start liegt der zuletzt gesendete Stand oft schon bereit.
    nonisolated(unsafe) let context = session.receivedApplicationContext
    Task { @MainActor in self.apply(context) }
  }

  nonisolated func session(
    _ session: WCSession, didReceiveApplicationContext context: [String: Any]
  ) {
    nonisolated(unsafe) let kopie = context
    Task { @MainActor in self.apply(kopie) }
  }
}

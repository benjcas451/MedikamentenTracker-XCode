import Foundation
import WatchConnectivity

/// Schiebt die letzten Einträge auf die Apple Watch (WatchConnectivity).
///
/// Die Uhr bekommt nur eine kompakte Momentaufnahme – sie spricht selbst nicht
/// mit der Server-API. Übertragen wird per `updateApplicationContext`: iOS
/// hält immer nur den *neuesten* Stand vor und stellt ihn zu, sobald die Uhr
/// erreichbar ist. Die Watch-App legt ihn lokal ab und kann ihn daher auch
/// ohne iPhone in Reichweite anzeigen. Payload-Format identisch zur
/// Flutter-App (WatchSyncPlugin), damit die Uhr nahtlos weiterläuft.
///
/// `@unchecked Sendable`: die Klasse hält keinerlei veränderlichen Zustand.
final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {

  static let shared = WatchSync()

  /// Wie viele Einträge die Uhr erhält. Mehr passen kaum auf das Display und
  /// der Application-Context ist auf wenige Kilobyte ausgelegt.
  private static let maxEintraege = 25

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    if session.activationState != .activated {
      session.activate()
    }
  }

  /// Überträgt [eintraege] (neueste zuerst) samt Zählern aus [stats].
  /// Fehler werden bewusst geschluckt: eine fehlende Uhr darf die
  /// Telefon-App nicht stören.
  func push(_ eintraege: [MedEntry], stats: MedStats?) {
    let session = WCSession.default
    guard WCSession.isSupported(),
      session.activationState == .activated,
      session.isPaired, session.isWatchAppInstalled
    else { return }

    var payload: [String: Any] = [
      "updatedAt": IsoZeit.plain.string(from: Date()),
      "todayTotal": stats?.today.total ?? 0,
      "weekTotal": stats?.week.total ?? 0,
    ]
    payload["entries"] = eintraege.prefix(Self.maxEintraege).map { eintrag in
      var json: [String: Any] = ["medikament": eintrag.medikament]
      if let zeit = eintrag.time {
        json["time"] = IsoZeit.plain.string(from: zeit)
      }
      return json
    }
    do {
      try session.updateApplicationContext(payload)
    } catch {
      NSLog("WatchSync: updateApplicationContext fehlgeschlagen: \(error)")
    }
  }

  // MARK: - WCSessionDelegate

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      NSLog("WatchSync: Aktivierung fehlgeschlagen: \(error)")
    }
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  /// Nach einem Wechsel der gekoppelten Uhr muss die Session neu aktiviert werden.
  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
}

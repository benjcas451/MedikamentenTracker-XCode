import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {

  @Published var laedt = true
  @Published var fehler: String?
  @Published var stats: MedStats?
  @Published var eintraege: [MedEntry] = []

  /// Für „Andere Zeit“ gewählter Zeitpunkt; nil = „Jetzt“.
  @Published var eigeneZeit: Date?

  /// Während ein neuer Eintrag gespeichert wird.
  @Published var speichert = false

  /// Kurzmeldungen (Fehler bei Aktionen, Backup-Ergebnisse).
  @Published var meldung: String?

  private var service: MedService = createConfiguredMedService()

  /// Baut die Datenquelle anhand der Einstellung neu auf (z. B. nach dem
  /// Verlassen der Einstellungen) und lädt anschließend neu.
  func datenquelleNeuAufbauen() {
    service = createConfiguredMedService()
    aktualisieren()
  }

  func aktualisieren() {
    laedt = true
    fehler = nil
    Task {
      do {
        async let statsNeu = service.getStats()
        async let eintraegeNeu = service.getEntries(limit: 100)
        let (s, e) = try await (statsNeu, eintraegeNeu)
        stats = s
        eintraege = e
        laedt = false
        // Apple Watch mit dem frischen Stand versorgen (fehlertolerant).
        WatchSync.shared.push(e, stats: s)
      } catch {
        fehler = error.localizedDescription
        laedt = false
      }
    }
  }

  /// Legt einen Eintrag an; `beiErfolg` läuft nach dem Speichern (z. B.
  /// Eingabefeld leeren), bevor neu geladen wird.
  func anlegen(_ medikament: String, beiErfolg: @escaping () -> Void = {}) {
    speichert = true
    Task {
      do {
        try await service.addEntry(medikament: medikament, time: eigeneZeit)
        speichert = false
        eigeneZeit = nil
        beiErfolg()
        meldung = "„\(medikament)“ gespeichert"
        aktualisieren()
      } catch {
        speichert = false
        meldung = "Fehler: \(error.localizedDescription)"
      }
    }
  }

  func loeschen(_ eintrag: MedEntry) {
    guard let id = eintrag.id else { return }
    fuehreAus { [self] in
      try await service.deleteEntry(id: id)
      meldung = "Eintrag gelöscht"
    }
  }

  func letztenRueckgaengig() {
    fuehreAus { [self] in
      let entfernt = try await service.undoLast()
      meldung = entfernt ? "Letzter Eintrag gelöscht" : "Kein Eintrag vorhanden"
    }
  }

  /// Führt eine schreibende Aktion aus und lädt danach neu.
  private func fuehreAus(_ aktion: @escaping () async throws -> Void) {
    Task {
      do {
        try await aktion()
        aktualisieren()
      } catch {
        meldung = "Fehler: \(error.localizedDescription)"
      }
    }
  }
}

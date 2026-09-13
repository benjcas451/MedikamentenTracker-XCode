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

  /// Grund der abgebrochenen Verbindung; nil heisst „online“.
  @Published var offlineGrund: String?
  /// Anzahl der Schreibzugriffe, die noch auf Übertragung warten.
  @Published var ausstehend = 0
  /// IDs, deren Stand noch nicht beim Server ist – die Liste markiert sie.
  @Published var ausstehendeIds: Set<Int64> = []

  private var service: MedService = createConfiguredMedService(offlineFaehig: true)
  private var beobachter: Set<AnyCancellable> = []

  init() {
    // Den Offline-Zustand übernehmen, statt ihn doppelt zu führen.
    let status = OfflineStatus.shared
    status.$grund.assign(to: &$offlineGrund)
    status.$ausstehend.assign(to: &$ausstehend)
    status.$ausstehendeIds.assign(to: &$ausstehendeIds)

    // Sobald wieder ein Netzwerkpfad da ist, die Warteschlange abarbeiten –
    // ohne dass der Nutzer etwas antippen muss.
    Verbindungswache.shared.wiederVerbunden
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.aktualisieren() }
      .store(in: &beobachter)
  }

  /// Baut die Datenquelle anhand der Einstellung neu auf (z. B. nach dem
  /// Verlassen der Einstellungen) und lädt anschließend neu.
  func datenquelleNeuAufbauen() {
    // Der Hinweis des alten Zugangs darf nicht über dem neuen stehen bleiben;
    // die neue Datenquelle meldet ihren eigenen Stand sofort nach.
    OfflineStatus.shared.zuruecksetzen()
    service = createConfiguredMedService(offlineFaehig: true)
    aktualisieren()
  }

  func aktualisieren() {
    laedt = true
    fehler = nil
    Task {
      // Erst das Liegengebliebene loswerden, dann laden: sonst zeigte die
      // Liste einen Serverstand ohne die eigenen Einträge.
      await warteschlangeAbarbeiten()
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

  /// Schickt die offenen Schreibzugriffe zum Server. Verworfene Aktionen
  /// (vom Server inhaltlich zurückgewiesen) meldet sie einmal gesammelt.
  private func warteschlangeAbarbeiten() async {
    guard let offline = service as? OfflineService else { return }
    let verworfen = await offline.nachholen()
    guard !verworfen.isEmpty else { return }
    meldung = verworfen.count == 1
      ? "Eine wartende Änderung wurde vom Server abgelehnt: \(verworfen[0])"
      : "\(verworfen.count) wartende Änderungen wurden vom Server abgelehnt."
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

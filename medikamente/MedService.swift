import Foundation

/// Fehler einer API-/Datenbank-Aktion mit sprechender Meldung.
struct ServiceError: LocalizedError {
  let message: String
  /// HTTP-Status, falls der Fehler von der API kam (404 = „nichts da“).
  var statusCode: Int?
  /// Gesetzt, wenn der Fehler ein Verbindungsproblem war – entscheidet
  /// darüber, ob die Aktion in die Offline-Warteschlange darf.
  var netzfehler: Netzfehler?
  var errorDescription: String? { message }
}

/// Gemeinsame Schnittstelle für Medikamenten-Quellen: die Server-API
/// ([ApiService], mTLS und/oder API-Key) oder die lokale SQLite-Datenbank
/// ([DemoService]). Sendable, damit die Dienste zwischen MainActor (UI) und
/// Hintergrund-Tasks wandern dürfen.
protocol MedService: Sendable {
  /// Vollständige Statistik (heute / Woche / 3 Wochen / Monat + letzter Eintrag).
  func getStats() async throws -> MedStats

  /// Liste der Einträge, neueste zuerst (optional auf `limit` begrenzt).
  func getEntries(limit: Int?) async throws -> [MedEntry]

  /// Neuen Eintrag anlegen (`time` nil = „jetzt“).
  @discardableResult
  func addEntry(medikament: String, time: Date?) async throws -> MedEntry

  /// Eintrag nach ID löschen. Liefert true, wenn etwas entfernt wurde.
  @discardableResult
  func deleteEntry(id: Int64) async throws -> Bool

  /// Letzten Eintrag rückgängig machen.
  /// Liefert true, wenn etwas entfernt wurde, false wenn es keinen gab.
  @discardableResult
  func undoLast() async throws -> Bool
}

/// Erstellt die aktuell konfigurierte Datenquelle.
///
/// `offlineFaehig` legt die Warteschlange darüber, die bei einem
/// Verbindungsabbruch einspringt.
func createConfiguredMedService(offlineFaehig: Bool = false) -> MedService {
  let dienst = createServerOderDemoService()
  guard offlineFaehig, let zugang = aktuellerZugang() else { return dienst }
  return OfflineService(innen: dienst, zugang: zugang)
}

/// Kennung des aktuellen Zugangs (Modus + Basis-URL); nil im Demo-Modus, der
/// ohnehin lokal arbeitet und keine Warteschlange braucht.
private func aktuellerZugang() -> String? {
  switch AppSettings.mode {
  case .api: "api|\(AppSettings.apiBaseUrl)"
  case .apiKey: "apiKey|\(AppSettings.apiKeyBaseUrl)"
  case .cloudflare: "cloudflare|\(AppSettings.cloudflareBaseUrl)"
  case .demo: nil
  }
}

private func createServerOderDemoService() -> MedService {
  switch AppSettings.mode {
  case .api:
    // Der API-Key ist im mTLS-Modus optional und wird nur mitgesendet,
    // wenn hinterlegt (manche Instanzen verlangen beides).
    ApiService(baseURL: AppSettings.apiBaseUrl, certSource: CertSource(), apiKey: AppSettings.apiKey)
  case .apiKey:
    ApiService(baseURL: AppSettings.apiKeyBaseUrl, apiKey: AppSettings.apiKey)
  case .cloudflare:
    // Cloudflare Access sichert den Zugang am Rand; der API-Key geht wie in
    // den anderen Server-Modi mit, sofern hinterlegt.
    ApiService(
      baseURL: AppSettings.cloudflareBaseUrl, apiKey: AppSettings.apiKey,
      cfToken: .ausEinstellungen)
  case .demo:
    DemoService.shared
  }
}

import Foundation

/// Fehler einer API-/Datenbank-Aktion mit sprechender Meldung.
struct ServiceError: LocalizedError {
  let message: String
  /// HTTP-Status, falls der Fehler von der API kam (404 = „nichts da“).
  var statusCode: Int?
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
func createConfiguredMedService() -> MedService {
  switch AppSettings.mode {
  case .api:
    // Der API-Key ist im mTLS-Modus optional und wird nur mitgesendet,
    // wenn hinterlegt (manche Instanzen verlangen beides).
    ApiService(baseURL: AppSettings.apiBaseUrl, certSource: CertSource(), apiKey: AppSettings.apiKey)
  case .apiKey:
    ApiService(baseURL: AppSettings.apiKeyBaseUrl, apiKey: AppSettings.apiKey)
  case .demo:
    DemoService.shared
  }
}

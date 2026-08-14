import Foundation

/// Ein Medikamenten-Eintrag (Freitext-Name + Zeitpunkt).
struct MedEntry: Identifiable, Equatable {
  /// Nil nur bei API-Antworten ohne ID (z. B. Fallback nach `add`).
  let id: Int64?
  let medikament: String
  /// Nil nur bei kaputten API-Antworten; lokale Einträge haben immer eine Zeit.
  let time: Date?
}

/// Zählung eines Medikaments innerhalb eines Zeitraums.
struct MedCount: Identifiable, Equatable {
  let medikament: String
  let anzahl: Int
  var id: String { medikament }
}

/// Statistik eines Zeitraums: Gesamtzahl + Aufschlüsselung je Medikament
/// (so liefert es `GET api.php?action=stats`).
struct PeriodStats: Equatable {
  var total = 0
  var medikamente: [MedCount] = []

  static let leer = PeriodStats()
}

/// Vollständige Statistik-Antwort (`action=stats`): Zeiträume heute / Woche /
/// 3 Wochen / Monat plus letzter Eintrag.
struct MedStats: Equatable {
  var today = PeriodStats.leer
  var week = PeriodStats.leer
  var threeWeeks = PeriodStats.leer
  var month = PeriodStats.leer
  var last: MedEntry?
}

// MARK: - Zeitformate

/// Liest ISO-8601-Zeitstempel tolerant: mit Offset (`+02:00`), mit `Z`,
/// mit 3 oder 6 Nachkommastellen (Dart schrieb Mikrosekunden in die lokale
/// Datenbank!) oder ganz ohne Zeitzone (dann lokale Zeit, wie in Dart).
enum IsoZeit {

  static func parse(_ text: String) -> Date? {
    if let date = fractional.date(from: text) { return date }
    if let date = plain.date(from: text) { return date }
    for formatter in posixFormatter {
      if let date = formatter.date(from: text) { return date }
    }
    return nil
  }

  /// Fürs Schreiben in die lokale Datenbank und an die API: UTC mit
  /// Millisekunden, damit die lexikalische Sortierung der Strings der
  /// zeitlichen entspricht (identisch zu Flutter/Android).
  static func dbString(from date: Date) -> String {
    fractional.string(from: date)
  }

  // (ISO8601-)DateFormatter sind laut Apple-Doku thread-sicher.
  nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static let posixFormatter: [DateFormatter] = [
    // Mikrosekunden (Dart), UTC
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'", utc: true),
    make("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", utc: true),
    // Offset-Formen mit Bruchteilen
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", utc: false),
    // Ohne Zeitzone: als lokale Zeit interpretieren
    make("yyyy-MM-dd'T'HH:mm:ss.SSSSSS", utc: false),
    make("yyyy-MM-dd'T'HH:mm:ss", utc: false),
  ]

  private static func make(_ format: String, utc: Bool) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format
    if utc { formatter.timeZone = TimeZone(identifier: "UTC") }
    return formatter
  }
}

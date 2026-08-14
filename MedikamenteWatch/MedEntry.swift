import Foundation

/// Ein Medikamenten-Eintrag, wie ihn die iPhone-App auf die Uhr schiebt.
struct MedEntry: Identifiable, Hashable {
  let medikament: String
  let time: Date?

  /// Zeitpunkt + Name identifizieren einen Eintrag auf der Uhr ausreichend;
  /// IDs überträgt das iPhone nicht, weil die Uhr nichts löschen kann.
  var id: String { "\(time?.timeIntervalSince1970 ?? 0)-\(medikament)" }

  init(medikament: String, time: Date?) {
    self.medikament = medikament
    self.time = time
  }

  init?(json: [String: Any]) {
    guard let medikament = json["medikament"] as? String, !medikament.isEmpty else { return nil }
    self.medikament = medikament
    self.time = (json["time"] as? String).flatMap(MedEntry.parseDate)
  }

  var json: [String: Any] {
    var out: [String: Any] = ["medikament": medikament]
    if let time = time {
      out["time"] = MedEntry.isoFormatter.string(from: time)
    }
    return out
  }

  /// Das iPhone sendet ISO 8601 in UTC – mit und ohne Sekundenbruchteile.
  static func parseDate(_ raw: String) -> Date? {
    isoFormatter.date(from: raw) ?? isoFormatterWithFraction.date(from: raw)
  }

  // ISO8601DateFormatter ist laut Apple-Doku thread-sicher.
  nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  nonisolated(unsafe) static let isoFormatterWithFraction: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
}

/// Der komplette Stand, den die Uhr vom iPhone kennt.
struct WatchSnapshot {
  var entries: [MedEntry] = []
  var todayTotal: Int = 0
  var weekTotal: Int = 0
  var updatedAt: Date?

  /// Noch nie Daten vom iPhone empfangen.
  var isEmpty: Bool { updatedAt == nil }

  init() {}

  init(context: [String: Any]) {
    entries =
      (context["entries"] as? [[String: Any]] ?? [])
      .compactMap(MedEntry.init(json:))
    todayTotal = context["todayTotal"] as? Int ?? 0
    weekTotal = context["weekTotal"] as? Int ?? 0
    updatedAt = (context["updatedAt"] as? String).flatMap(MedEntry.parseDate)
  }

  var json: [String: Any] {
    var out: [String: Any] = [
      "entries": entries.map(\.json),
      "todayTotal": todayTotal,
      "weekTotal": weekTotal,
    ]
    if let updatedAt = updatedAt {
      out["updatedAt"] = MedEntry.isoFormatter.string(from: updatedAt)
    }
    return out
  }
}

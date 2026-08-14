import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Eine Roh-Zeile der Tabelle `entries` (für Backup-Export/-Restore).
struct EntryRow {
  let id: Int64
  let medikament: String
  let time: String
}

/// Lokaler Modus: nutzt exakt die SQLite-Datenbank weiter, die schon die
/// Flutter-App (sqflite) angelegt hat – gleicher Dateiname im Documents-
/// Ordner, gleiches Schema, gleiche Version (PRAGMA user_version = 1).
/// Bestehende Daten werden beim Umstieg dadurch nahtlos übernommen.
///
/// `@unchecked Sendable`: Das einzige veränderliche Feld (`db`) wird
/// ausschließlich auf der seriellen `queue` gelesen und geschrieben – der
/// Compiler kann das bei der SQLite-C-API (OpaquePointer) nur nicht beweisen.
final class DemoService: MedService, @unchecked Sendable {

  /// Eine Verbindung für die gesamte Prozesslaufzeit: Oberfläche und Backup
  /// dürfen sie sich nicht gegenseitig wegschließen.
  static let shared = DemoService()

  private var db: OpaquePointer?
  private let queue = DispatchQueue(label: "org.dwarftsch.medikamente.demo-db")

  private init() {}

  // MARK: - Öffnen & Schema

  private func datenbank() throws -> OpaquePointer {
    if let db { return db }
    let pfad = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("medikamenten_demo.db").path

    var handle: OpaquePointer?
    guard sqlite3_open(pfad, &handle) == SQLITE_OK, let handle else {
      throw ServiceError(message: "Lokale Datenbank ließ sich nicht öffnen.")
    }
    try migrieren(handle)
    db = handle
    return handle
  }

  /// Identisch zum sqflite-Schema der Flutter-App (Version 1, nie migriert).
  private func migrieren(_ db: OpaquePointer) throws {
    let version = skalarInt(db, "PRAGMA user_version") ?? 0
    if version == 0 {
      try ausfuehren(
        db,
        """
        CREATE TABLE IF NOT EXISTS entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          medikament TEXT NOT NULL,
          time TEXT NOT NULL
        )
        """)
      try ausfuehren(db, "PRAGMA user_version = 1")
    }
  }

  // MARK: - MedService

  func getStats() async throws -> MedStats {
    try await auf { db in
      var stats = MedStats()
      stats.today = try self.periode(db, seit: Self.tagesbeginn())
      stats.week = try self.periode(db, seit: Self.tagesbeginn(tageZurueck: 7))
      stats.threeWeeks = try self.periode(db, seit: Self.tagesbeginn(tageZurueck: 21))
      stats.month = try self.periode(db, seit: Self.tagesbeginn(tageZurueck: 30))
      stats.last = try self.zeilen(db, "SELECT * FROM entries ORDER BY id DESC LIMIT 1", parameter: [])
        .first.flatMap(Self.alsEntry)
      return stats
    }
  }

  /// Statistik für alle Einträge ab `seit`: Gesamtzahl + Zählung je Medikament.
  private func periode(_ db: OpaquePointer, seit: Date) throws -> PeriodStats {
    let rows = try zeilen(
      db, "SELECT * FROM entries WHERE time >= ?",
      parameter: [IsoZeit.dbString(from: seit)])
    var zaehler: [String: Int] = [:]
    for row in rows {
      zaehler[row.medikament, default: 0] += 1
    }
    let medikamente = zaehler
      .map { MedCount(medikament: $0.key, anzahl: $0.value) }
      .sorted { ($0.anzahl, $1.medikament) > ($1.anzahl, $0.medikament) }
    return PeriodStats(total: rows.count, medikamente: medikamente)
  }

  func getEntries(limit: Int?) async throws -> [MedEntry] {
    try await auf { db in
      var sql = "SELECT * FROM entries ORDER BY time DESC, id DESC"
      var parameter: [Any?] = []
      if let limit {
        sql += " LIMIT ?"
        parameter.append(limit)
      }
      return try self.zeilen(db, sql, parameter: parameter).compactMap(Self.alsEntry)
    }
  }

  @discardableResult
  func addEntry(medikament: String, time: Date?) async throws -> MedEntry {
    try await auf { db in
      let zeit = time ?? Date()
      try self.ausfuehren(
        db, "INSERT INTO entries(medikament, time) VALUES(?,?)",
        parameter: [medikament, IsoZeit.dbString(from: zeit)])
      return MedEntry(id: sqlite3_last_insert_rowid(db), medikament: medikament, time: zeit)
    }
  }

  @discardableResult
  func deleteEntry(id: Int64) async throws -> Bool {
    try await auf { db in
      try self.ausfuehren(db, "DELETE FROM entries WHERE id = ?", parameter: [id])
      return sqlite3_changes(db) > 0
    }
  }

  @discardableResult
  func undoLast() async throws -> Bool {
    try await auf { db in
      try self.ausfuehren(
        db, "DELETE FROM entries WHERE id = (SELECT MAX(id) FROM entries)")
      return sqlite3_changes(db) > 0
    }
  }

  // MARK: - Backup

  /// Alle Roh-Zeilen der lokalen Tabelle (für den Backup-Export).
  func exportRows() async throws -> [EntryRow] {
    try await auf { db in
      try self.zeilen(db, "SELECT * FROM entries ORDER BY id", parameter: [])
    }
  }

  /// Ersetzt den gesamten Bestand durch [rows] (Backup-Restore), transaktional.
  func replaceAll(_ rows: [EntryRow]) async throws {
    try await auf { db in
      try self.ausfuehren(db, "BEGIN")
      do {
        try self.ausfuehren(db, "DELETE FROM entries")
        for row in rows {
          try self.ausfuehren(
            db, "INSERT INTO entries(id, medikament, time) VALUES(?,?,?)",
            parameter: [row.id, row.medikament, row.time])
        }
        try self.ausfuehren(db, "COMMIT")
      } catch {
        try? self.ausfuehren(db, "ROLLBACK")
        throw error
      }
    }
  }

  // MARK: - SQLite-Handwerk

  private func auf<T: Sendable>(
    _ arbeit: @Sendable @escaping (OpaquePointer) throws -> T
  ) async throws -> T {
    try await withCheckedThrowingContinuation { fortsetzung in
      queue.async {
        do {
          fortsetzung.resume(returning: try arbeit(try self.datenbank()))
        } catch {
          fortsetzung.resume(throwing: error)
        }
      }
    }
  }

  private func ausfuehren(_ db: OpaquePointer, _ sql: String, parameter: [Any?] = []) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(statement) }
    binden(statement, parameter)
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
  }

  private func zeilen(_ db: OpaquePointer, _ sql: String, parameter: [Any?]) throws -> [EntryRow] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
      throw ServiceError(message: "SQL-Fehler: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(statement) }
    binden(statement, parameter)

    // Spaltenindizes anhand der Namen, damit SELECT * robust bleibt.
    var spalten: [String: Int32] = [:]
    for index in 0..<sqlite3_column_count(statement) {
      spalten[String(cString: sqlite3_column_name(statement, index))] = index
    }
    func text(_ name: String) -> String? {
      guard let index = spalten[name],
        let wert = sqlite3_column_text(statement, index)
      else { return nil }
      return String(cString: wert)
    }
    func zahl(_ name: String) -> Int64? {
      guard let index = spalten[name],
        sqlite3_column_type(statement, index) != SQLITE_NULL
      else { return nil }
      return sqlite3_column_int64(statement, index)
    }

    var ergebnis: [EntryRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      ergebnis.append(
        EntryRow(
          id: zahl("id") ?? 0,
          medikament: text("medikament") ?? "",
          time: text("time") ?? ""))
    }
    return ergebnis
  }

  private func binden(_ statement: OpaquePointer?, _ parameter: [Any?]) {
    for (index, wert) in parameter.enumerated() {
      let position = Int32(index + 1)
      switch wert {
      case nil: sqlite3_bind_null(statement, position)
      case let text as String: sqlite3_bind_text(statement, position, text, -1, SQLITE_TRANSIENT)
      case let zahl as Int: sqlite3_bind_int64(statement, position, Int64(zahl))
      case let zahl as Int64: sqlite3_bind_int64(statement, position, zahl)
      default: sqlite3_bind_null(statement, position)
      }
    }
  }

  private func skalarInt(_ db: OpaquePointer, _ sql: String) -> Int? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return Int(sqlite3_column_int64(statement, 0))
  }

  // MARK: - Helfer

  private static func alsEntry(_ row: EntryRow) -> MedEntry? {
    guard !row.medikament.isEmpty else { return nil }
    return MedEntry(id: row.id, medikament: row.medikament, time: IsoZeit.parse(row.time))
  }

  /// Heutiger Tagesbeginn (lokale Zeit), optional um Tage zurückversetzt.
  private static func tagesbeginn(tageZurueck: Int = 0) -> Date {
    let start = Calendar.current.startOfDay(for: Date())
    return Calendar.current.date(byAdding: .day, value: -tageZurueck, to: start) ?? start
  }
}

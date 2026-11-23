import Foundation

#if DEBUG
/// Nur für die Bildschirmfotos im UI-Test (`ScreenshotTests`): Mit dem
/// Launch-Argument `-MhBildschirmfotos 1` arbeitet der lokale Modus auf einer
/// eigenen, bei jedem Start frisch befüllten Datenbank im temporären Ordner.
/// Die echte Datenbank bleibt unberührt; in Release-Builds fehlt der Teil
/// ganz.
enum Bildschirmfotos {

  static var aktiv: Bool { UserDefaults.standard.bool(forKey: "MhBildschirmfotos") }

  static var datenbankPfad: String {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("medikamenten_bildschirmfotos.db").path
  }

  /// Erfundene Einträge relativ zu `jetzt` (auf 5 Minuten abgerundet), damit
  /// alle Zeiträume der Statistik etwas zeigen.
  static func testdaten(jetzt: Date = Date()) -> [(medikament: String, zeit: Date)] {
    let basis = Date(timeIntervalSince1970: (jetzt.timeIntervalSince1970 / 300).rounded(.down) * 300)
    let minute: TimeInterval = 60
    let stunde = 60 * minute
    let tag = 24 * stunde
    let eintraege: [(String, TimeInterval)] = [
      ("Paracetamol 500 mg", 24 * tag + 3 * stunde),
      ("Zahngel", 15 * tag + 2 * stunde),
      ("Ibuprofen 400 mg", 9 * tag + 5 * stunde),
      ("Vitamin D", 6 * tag),
      ("Nasenspray", 3 * tag + 9 * stunde),
      ("Nasenspray", 3 * tag + 2 * stunde),
      ("Paracetamol 500 mg", 2 * tag + 1 * stunde),
      ("Vitamin D", 1 * tag + 6 * stunde),
      ("Ibuprofen 400 mg", 1 * tag + 1 * stunde),
      ("Nasenspray", 5 * stunde),
      ("Ibuprofen 400 mg", 40 * minute),
    ]
    return eintraege.map { ($0.0, basis.addingTimeInterval(-$0.1)) }
  }
}
#endif

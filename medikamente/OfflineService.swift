import Combine
import Foundation
import Network

// MARK: - Warteschlange

/// Ein Schreibzugriff, der offline erfasst wurde und noch zum Server muss.
///
/// Löschungen beziehen sich immer auf eine **Server-ID**. Trifft eine Löschung
/// einen Eintrag, der selbst noch in der Warteschlange steht, wird dessen
/// `anlegen`-Aktion ersatzlos entfernt — beim Abarbeiten kann also keine noch
/// unbekannte ID auftauchen.
enum Warteaktion: Codable, Equatable {
  case anlegen(Anlegen)
  case loeschen(id: Int64)

  /// Ein offline erfasster neuer Eintrag.
  struct Anlegen: Codable, Equatable {
    /// Negative Kennung, unter der der Eintrag in der Liste auftaucht,
    /// solange er nicht hochgeladen ist.
    let lokaleId: Int64
    let medikament: String
    /// Zeitpunkt der Erfassung, nicht des Hochladens – sonst bekäme der
    /// Eintrag beim Nachholen die falsche Uhrzeit.
    let time: Date
  }
}

/// Die geordnete Liste der offenen Schreibzugriffe eines Zugangs.
struct Warteschlange: Codable, Equatable {

  private(set) var aktionen: [Warteaktion] = []
  /// Zähler für die nächste lokale Kennung (läuft ins Negative).
  private var naechsteLokaleId: Int64 = -1

  var istLeer: Bool { aktionen.isEmpty }
  var anzahl: Int { aktionen.count }

  /// IDs mit noch nicht übertragenem Stand – die Liste markiert sie.
  var ausstehendeIds: Set<Int64> {
    var ids = Set<Int64>()
    for aktion in aktionen {
      switch aktion {
      case .anlegen(let a): ids.insert(a.lokaleId)
      case .loeschen(let id): ids.insert(id)
      }
    }
    return ids
  }

  /// Nimmt einen neuen Eintrag auf und liefert dessen lokale Kennung.
  mutating func lege(medikament: String, time: Date) -> Int64 {
    let id = naechsteLokaleId
    naechsteLokaleId -= 1
    aktionen.append(.anlegen(.init(lokaleId: id, medikament: medikament, time: time)))
    return id
  }

  /// Nimmt eine Löschung auf. Einen Eintrag, der noch gar nicht beim Server
  /// war, wirft sie ersatzlos aus der Warteschlange; der Rückgabewert sagt,
  /// ob das der Fall war.
  @discardableResult
  mutating func loesche(id: Int64) -> Bool {
    if let index = indexDesAnlegens(id) {
      aktionen.remove(at: index)
      return true
    }
    aktionen.append(.loeschen(id: id))
    return false
  }

  /// Nimmt den zuletzt vorgemerkten Eintrag zurück; false, wenn keiner wartet.
  mutating func nimmLetztesAnlegenZurueck() -> Bool {
    guard
      let index = aktionen.lastIndex(where: {
        if case .anlegen = $0 { return true }
        return false
      })
    else { return false }
    aktionen.remove(at: index)
    return true
  }

  mutating func entferneErste() {
    if !aktionen.isEmpty { aktionen.removeFirst() }
  }

  private func indexDesAnlegens(_ id: Int64) -> Int? {
    guard id < 0 else { return nil }
    return aktionen.firstIndex {
      if case .anlegen(let a) = $0 { return a.lokaleId == id }
      return false
    }
  }

  /// Legt die offenen Aktionen über eine Liste vom Server, damit die
  /// Oberfläche den Stand zeigt, den der Nutzer erwartet: neueste zuerst.
  func anwenden(auf eintraege: [MedEntry]) -> [MedEntry] {
    var liste = eintraege
    for aktion in aktionen {
      switch aktion {
      case .anlegen(let a):
        liste.append(MedEntry(id: a.lokaleId, medikament: a.medikament, time: a.time))
      case .loeschen(let id):
        liste.removeAll { $0.id == id }
      }
    }
    return liste.sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
  }

  /// Rechnet die offenen Aktionen in die Statistik ein, damit Kacheln und
  /// Liste nicht auseinanderlaufen. Anders als beim Wickel-Tracker sind das
  /// hier reine Zählungen – die lassen sich vollständig nachführen.
  func anwenden(auf stats: MedStats, jetzt: Date = Date()) -> MedStats {
    guard !aktionen.isEmpty else { return stats }
    var werte = stats
    let kalender = Calendar.current
    for aktion in aktionen {
      guard case .anlegen(let a) = aktion else { continue }
      if kalender.isDate(a.time, inSameDayAs: jetzt) { werte.today.zaehle(a.medikament) }
      if a.time > jetzt.vorTagen(7) { werte.week.zaehle(a.medikament) }
      if a.time > jetzt.vorTagen(21) { werte.threeWeeks.zaehle(a.medikament) }
      if a.time > jetzt.vorTagen(30) { werte.month.zaehle(a.medikament) }
    }
    // Der jüngste wartende Eintrag ist der letzte – sofern er nicht älter ist
    // als der, den der Server kennt.
    let neuester = aktionen.compactMap { aktion -> Warteaktion.Anlegen? in
      if case .anlegen(let a) = aktion { return a }
      return nil
    }.max(by: { $0.time < $1.time })
    if let neuester, (werte.last?.time).map({ neuester.time > $0 }) ?? true {
      werte.last = MedEntry(
        id: neuester.lokaleId, medikament: neuester.medikament, time: neuester.time)
    }
    return werte
  }
}

extension PeriodStats {
  /// Zählt einen wartenden Eintrag mit: Gesamtzahl plus die Aufschlüsselung
  /// des Medikaments.
  fileprivate mutating func zaehle(_ medikament: String) {
    total += 1
    if let index = medikamente.firstIndex(where: { $0.medikament == medikament }) {
      medikamente[index] = MedCount(
        medikament: medikament, anzahl: medikamente[index].anzahl + 1)
    } else {
      medikamente.append(MedCount(medikament: medikament, anzahl: 1))
    }
    medikamente.sort { $0.anzahl > $1.anzahl }
  }
}

extension Date {
  fileprivate func vorTagen(_ tage: Int) -> Date {
    addingTimeInterval(-Double(tage) * 24 * 60 * 60)
  }
}

// MARK: - Ablage

/// Legt Warteschlange und Lesestand je Zugang im App-Verzeichnis ab.
///
/// Der Schlüssel ist Modus plus Basis-URL: Wer zwischen zwei Servern wechselt,
/// bekommt nicht den Stand des anderen zu sehen und lädt auch keine
/// Warteschlange dorthin hoch, wo sie nicht hingehört. Einträge und Statistik
/// liegen getrennt, weil die Oberfläche beide nebenläufig lädt.
struct OfflineSpeicher {

  private let ordner: URL
  private let schluessel: String

  init(zugang: String) {
    schluessel = zugang.map { $0.isLetter || $0.isNumber ? $0 : "_" }.map(String.init).joined()
    let basis = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ordner = basis.appendingPathComponent("Offline", isDirectory: true)
    try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
  }

  private func url(_ name: String) -> URL {
    ordner.appendingPathComponent("\(name)_\(schluessel).json")
  }

  func ladeWarteschlange() -> Warteschlange {
    lade(url("warteschlange"), als: Warteschlange.self) ?? Warteschlange()
  }

  func speichere(_ warteschlange: Warteschlange) {
    speichere(warteschlange, nach: url("warteschlange"))
  }

  func ladeEintraege() -> [MedEntry]? { lade(url("eintraege"), als: [MedEntry].self) }

  func speichere(eintraege: [MedEntry]) { speichere(eintraege, nach: url("eintraege")) }

  func ladeStats() -> MedStats? { lade(url("stats"), als: MedStats.self) }

  func speichere(stats: MedStats) { speichere(stats, nach: url("stats")) }

  private func lade<Inhalt: Codable>(_ url: URL, als: Inhalt.Type) -> Inhalt? {
    guard let daten = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Inhalt.self, from: daten)
  }

  private func speichere<Inhalt: Codable>(_ inhalt: Inhalt, nach url: URL) {
    guard let daten = try? JSONEncoder().encode(inhalt) else { return }
    try? daten.write(to: url, options: .atomic)
  }
}

// MARK: - Zustand

/// Der Offline-Zustand, den die Oberfläche anzeigt.
@MainActor
final class OfflineStatus: ObservableObject {

  static let shared = OfflineStatus()

  /// Grund der letzten gescheiterten Verbindung; nil heisst „online“.
  @Published private(set) var grund: String?
  /// Anzahl der Schreibzugriffe, die noch auf Übertragung warten.
  @Published private(set) var ausstehend = 0
  /// IDs, deren Stand noch nicht beim Server ist (lokale sind negativ).
  @Published private(set) var ausstehendeIds: Set<Int64> = []

  var istOffline: Bool { grund != nil }

  fileprivate func melde(grund: String?) { self.grund = grund }

  fileprivate func melde(warteschlange: Warteschlange) {
    ausstehend = warteschlange.anzahl
    ausstehendeIds = warteschlange.ausstehendeIds
  }

  /// Setzt alles zurück – beim Wechsel der Datenquelle, damit der Hinweis des
  /// alten Zugangs nicht über dem neuen stehen bleibt.
  func zuruecksetzen() {
    grund = nil
    ausstehend = 0
    ausstehendeIds = []
  }
}

// MARK: - Dienst

/// Legt sich über die Server-Quelle und hält die App bei einem
/// Verbindungsabbruch benutzbar.
///
/// Lesen: Bei jedem Netzwerkfehler wird der zuletzt erfolgreiche Stand
/// gezeigt — dabei ist gleich, ob die Anfrage ankam, denn ein Lesevorgang
/// verändert nichts.
///
/// Schreiben: In die Warteschlange darf eine Aktion **nur**, wenn sie den
/// Server nachweislich nie erreicht hat (`Netzfehler.nieGesendet`). Bei einer
/// Zeitüberschreitung oder einem Abbruch mitten in der Übertragung könnte der
/// Server sie bereits ausgeführt haben; ein zweiter Versuch legte dann einen
/// zweiten Eintrag an.
final class OfflineService: MedService {

  private let innen: MedService
  private let speicher: OfflineSpeicher

  private let sperre = NSLock()
  nonisolated(unsafe) private var warteschlange: Warteschlange

  init(innen: MedService, zugang: String) {
    self.innen = innen
    self.speicher = OfflineSpeicher(zugang: zugang)
    self.warteschlange = speicher.ladeWarteschlange()
    meldeStand()
  }

  // MARK: Lesen

  func getStats() async throws -> MedStats {
    do {
      let vomServer = try await innen.getStats()
      speicher.speichere(stats: vomServer)
      await online()
      return aktuelleWarteschlange.anwenden(auf: vomServer)
    } catch let fehler as ServiceError where fehler.netzfehler != nil {
      guard let stand = speicher.ladeStats() else { throw fehler }
      await offline(fehler.message)
      return aktuelleWarteschlange.anwenden(auf: stand)
    }
  }

  func getEntries(limit: Int?) async throws -> [MedEntry] {
    do {
      let vomServer = try await innen.getEntries(limit: limit)
      speicher.speichere(eintraege: vomServer)
      await online()
      return begrenze(aktuelleWarteschlange.anwenden(auf: vomServer), auf: limit)
    } catch let fehler as ServiceError where fehler.netzfehler != nil {
      guard let stand = speicher.ladeEintraege() else { throw fehler }
      await offline(fehler.message)
      return begrenze(aktuelleWarteschlange.anwenden(auf: stand), auf: limit)
    }
  }

  // MARK: Schreiben

  @discardableResult
  func addEntry(medikament: String, time: Date?) async throws -> MedEntry {
    let zeit = time ?? Date()
    // Reihenfolge wahren: Steht schon etwas an, gehört auch das Neue hinten
    // dran, statt es am Stau vorbeizuschicken.
    guard aktuelleWarteschlange.istLeer else {
      return reiheEin(medikament: medikament, time: zeit)
    }
    do {
      let eintrag = try await innen.addEntry(medikament: medikament, time: time)
      await online()
      return eintrag
    } catch let fehler as ServiceError where fehler.netzfehler == .nieGesendet {
      await offline(fehler.message)
      return reiheEin(medikament: medikament, time: zeit)
    }
  }

  @discardableResult
  func deleteEntry(id: Int64) async throws -> Bool {
    // Negative IDs kennt nur die App: der Eintrag wartet noch. Und solange
    // etwas ansteht, bleibt die Reihenfolge gewahrt.
    if id < 0 || !aktuelleWarteschlange.istLeer {
      // Ein lokal wieder entfernter Eintrag war nie beim Server; ein
      // vorgemerkter Löschauftrag zählt für die Oberfläche ebenso als
      // erledigt. Beides meldet deshalb true.
      schreibeWarteschlange { $0.loesche(id: id) }
      return true
    }
    do {
      let entfernt = try await innen.deleteEntry(id: id)
      await online()
      return entfernt
    } catch let fehler as ServiceError where fehler.netzfehler == .nieGesendet {
      await offline(fehler.message)
      schreibeWarteschlange { $0.loesche(id: id) }
      return true
    }
  }

  @discardableResult
  func undoLast() async throws -> Bool {
    // Wartet noch ein Eintrag, ist das der zuletzt erfasste – den nimmt die
    // App direkt zurück, ohne den Server zu behelligen.
    var zurueckgenommen = false
    schreibeWarteschlange { zurueckgenommen = $0.nimmLetztesAnlegenZurueck() }
    if zurueckgenommen { return true }
    // Sonst muss der Server ran. Offline lässt sich das **nicht** vormerken:
    // Die API kennt für `undoLast` keine ID, beim Nachholen träfe es
    // womöglich einen Eintrag, den jemand anders inzwischen angelegt hat.
    return try await innen.undoLast()
  }

  // MARK: Nachholen

  /// Arbeitet die Warteschlange von vorn ab.
  ///
  /// Bricht beim ersten Verbindungsfehler ab — der Rest bleibt in der
  /// Reihenfolge stehen. Weist der Server eine Aktion inhaltlich zurück (etwa
  /// einen längst gelöschten Eintrag), fliegt sie raus und wird gemeldet;
  /// sonst blockierte sie die Warteschlange für immer.
  ///
  /// Liefert die Meldungen zu verworfenen Aktionen.
  @discardableResult
  func nachholen() async -> [String] {
    var verworfen: [String] = []
    while let naechste = aktuelleWarteschlange.aktionen.first {
      do {
        switch naechste {
        case .anlegen(let a):
          _ = try await innen.addEntry(medikament: a.medikament, time: a.time)
        case .loeschen(let id):
          _ = try await innen.deleteEntry(id: id)
        }
        schreibeWarteschlange { $0.entferneErste() }
      } catch let fehler as ServiceError where fehler.netzfehler != nil {
        await offline(fehler.message)
        return verworfen
      } catch {
        schreibeWarteschlange { $0.entferneErste() }
        verworfen.append(error.localizedDescription)
      }
    }
    await online()
    return verworfen
  }

  // MARK: Innere Hilfen

  private var aktuelleWarteschlange: Warteschlange {
    sperre.withLock { warteschlange }
  }

  private func begrenze(_ eintraege: [MedEntry], auf limit: Int?) -> [MedEntry] {
    guard let limit, eintraege.count > limit else { return eintraege }
    return Array(eintraege.prefix(limit))
  }

  private func reiheEin(medikament: String, time: Date) -> MedEntry {
    var id: Int64 = -1
    schreibeWarteschlange { id = $0.lege(medikament: medikament, time: time) }
    return MedEntry(id: id, medikament: medikament, time: time)
  }

  private func schreibeWarteschlange(_ aenderung: (inout Warteschlange) -> Void) {
    let stand: Warteschlange = sperre.withLock {
      aenderung(&warteschlange)
      return warteschlange
    }
    speicher.speichere(stand)
    meldeStand()
  }

  private func meldeStand() {
    let stand = aktuelleWarteschlange
    Task { @MainActor in OfflineStatus.shared.melde(warteschlange: stand) }
  }

  @MainActor private func offline(_ grund: String) {
    OfflineStatus.shared.melde(grund: grund)
  }

  @MainActor private func online() {
    OfflineStatus.shared.melde(grund: nil)
  }
}

// MARK: - Verbindungswache

/// Meldet, sobald wieder ein Netzwerkpfad da ist — damit die Warteschlange
/// nicht erst beim nächsten Antippen abgearbeitet wird.
@MainActor
final class Verbindungswache: ObservableObject {

  static let shared = Verbindungswache()

  /// Feuert bei jedem Wechsel von „kein Pfad“ zu „Pfad da“.
  let wiederVerbunden = PassthroughSubject<Void, Never>()

  private let wache = NWPathMonitor()
  private var warOffline = false

  private init() {
    wache.pathUpdateHandler = { [weak self] pfad in
      let verbunden = pfad.status == .satisfied
      Task { @MainActor in self?.pfadGeaendert(verbunden) }
    }
    wache.start(queue: DispatchQueue(label: "medikamente.verbindungswache"))
  }

  private func pfadGeaendert(_ verbunden: Bool) {
    if verbunden, warOffline { wiederVerbunden.send(()) }
    warOffline = !verbunden
  }
}

import XCTest

/// Bildschirmfotos für Pull Requests (Minze & Honig 2.0).
///
/// Läuft im Workflow „Bildschirmfotos“; hell/dunkel und Schriftgröße stellt
/// der Workflow am Simulator ein und reicht den Namen der Variante als
/// MH_VARIANTE durch (TEST_RUNNER_MH_VARIANTE). Die App startet im lokalen
/// Modus mit einer eigenen Datenbank voller erfundener Einträge
/// (`-MhBildschirmfotos 1`, nur in Debug-Builds), echte Daten bleiben
/// unberührt.
final class ScreenshotTests: XCTestCase {

  override func setUp() {
    continueAfterFailure = true
  }

  @MainActor
  func testAnsichten() throws {
    let app = XCUIApplication()
    app.launchArguments += [
      "-MhBildschirmfotos", "1",
      "-data_source_mode", "demo",
      "-AppleLanguages", "(de)",
      "-AppleLocale", "de_DE",
    ]
    app.launch()

    // Warten, bis die Testdaten geladen sind.
    _ = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Ibuprofen"))
      .firstMatch.waitForExistence(timeout: 15)
    foto(app, "01-start")

    // Ein Wischer geht direkt nach dem Start gelegentlich verloren; so lange
    // wischen (höchstens dreimal), bis der Titel aus dem Bild ist.
    let titel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Medikamente"))
      .firstMatch
    for _ in 0..<3 {
      app.swipeUp()
      sleep(1)
      if !(titel.exists && titel.isHittable) { break }
    }
    foto(app, "02-liste")
    app.swipeDown()
    app.swipeDown()

    if tippe(knopf(app, "Andere Zeit")) {
      foto(app, "03-zeitwahl")
      tippe(knopf(app, "Abbrechen"))
    }

    if einstellungenOeffnen(app) {
      foto(app, "04-einstellungen")
      // Zeigt nur die Felder des Server-Modus; dank `-data_source_mode demo`
      // bleibt die Datenquelle des Laufs trotzdem lokal.
      if tippe(knopf(app, "Server (mTLS-API)")) {
        foto(app, "05-einstellungen-server")
      }
      tippe(knopf(app, "Fertig"))
    }
  }

  // MARK: - Helfer

  /// Knopf, dessen Beschriftung den Text enthält (Symbole davor oder
  /// Untertitel dahinter stören so nicht).
  private func knopf(_ app: XCUIApplication, _ text: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  @discardableResult
  private func tippe(_ element: XCUIElement) -> Bool {
    guard element.waitForExistence(timeout: 5) else { return false }
    element.tap()
    return true
  }

  /// Der Einstellungs-Knopf heißt „Einstellungen“; ältere Fassungen hatten
  /// nur ein Zahnrad-Symbol ganz rechts in der Navigationsleiste.
  private func einstellungenOeffnen(_ app: XCUIApplication) -> Bool {
    if tippe(knopf(app, "Einstellungen")) { return true }
    if tippe(app.buttons["gearshape"]) { return true }
    let leiste = app.navigationBars.buttons
    guard leiste.count > 0 else { return false }
    leiste.element(boundBy: leiste.count - 1).tap()
    return true
  }

  private func foto(_ app: XCUIApplication, _ name: String) {
    sleep(2)
    let variante = ProcessInfo.processInfo.environment["MH_VARIANTE"] ?? "standard"
    let anhang = XCTAttachment(screenshot: app.screenshot())
    anhang.name = "\(variante)-\(name)"
    anhang.lifetime = .keepAlways
    add(anhang)
  }
}

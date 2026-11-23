import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var mode = AppSettings.mode
  @State private var apiUrl = AppSettings.apiBaseUrl
  @State private var apiKeyUrl = AppSettings.apiKeyBaseUrl
  @State private var cloudflareUrl = AppSettings.cloudflareBaseUrl
  @State private var cfClientId = AppSettings.cfAccessClientId
  @State private var cfClientSecret = AppSettings.cfAccessClientSecret
  @State private var apiKey = AppSettings.apiKey
  @State private var certsOk = CertSource().sindVorhanden
  @State private var certOrt = CertSource().locationLabel
  @State private var eigenerCertOrdner = CertSource().eigenerOrdner
  @State private var zeigeOrdnerwahl = false
  @State private var meldung: String?
  @State private var infoTitel: String?
  @State private var infoText: String?
  @State private var restoreBestaetigen = false
  @State private var exportDokument: BackupDokument?
  @State private var zeigeImport = false
  private let certSource = CertSource()

  @FocusState private var urlFokus: Bool
  @FocusState private var keyFokus: Bool
  @FocusState private var cfIdFokus: Bool
  @FocusState private var cfSecretFokus: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        MhKopf("Einstellungen", hauptaktion: {
          Button("Fertig") { dismiss() }
            .buttonStyle(MhHauptButtonStil(klein: true))
        })
        datenquelle
        if mode == .apiKey { apiKeySektion }
        if mode == .api { mtlsSektion }
        if mode == .cloudflare { cloudflareSektion }
        if mode == .demo { backupSektion }
        erklaerung
      }
      .padding(.horizontal, Mh.rand)
      .padding(.top, Mh.abstand5)
      .padding(.bottom, Mh.abstand8)
    }
    .background(Mh.bg.ignoresSafeArea())
    .alert(
      "Hinweis", isPresented: .init(get: { meldung != nil }, set: { if !$0 { meldung = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(meldung ?? "")
    }
    .alert("Backup wiederherstellen?", isPresented: $restoreBestaetigen) {
      Button("Abbrechen", role: .cancel) {}
      Button("Backup auswählen") { zeigeImport = true }
    } message: {
      Text(
        "Alle aktuell lokal gespeicherten Einträge werden durch den Inhalt des "
          + "Backups ersetzt. Dieser Vorgang kann nicht rückgängig gemacht werden.")
    }
    .sheet(
      isPresented: .init(get: { infoText != nil }, set: { if !$0 { infoText = nil } })
    ) {
      InfoSheet(titel: infoTitel ?? "", text: infoText ?? "")
    }
    .fileExporter(
      isPresented: .init(get: { exportDokument != nil }, set: { if !$0 { exportDokument = nil } }),
      document: exportDokument,
      contentType: .json,
      defaultFilename: LocalBackupService.dateiname()
    ) { ergebnis in
      switch ergebnis {
      case .success: meldung = "Backup gespeichert."
      case .failure(let fehler): meldung = "Backup fehlgeschlagen: \(fehler.localizedDescription)"
      }
    }
    .fileImporter(isPresented: $zeigeImport, allowedContentTypes: [.json]) { ergebnis in
      wiederherstellen(ergebnis)
    }
  }

  // MARK: - Sektionen

  private var datenquelle: some View {
    VStack(alignment: .leading, spacing: 0) {
      MhGruppenLabel("Datenquelle")
      ModusZeile(
        gewaehlt: mode == .api, titel: "Server (mTLS-API)",
        untertitel: "Client-Zertifikat, API-Key optional"
      ) { setzeModus(.api) }
      MhTrennlinie()
      ModusZeile(
        gewaehlt: mode == .apiKey, titel: "Server (API-Key)",
        untertitel: "API-Key empfohlen (ohne Zertifikat)"
      ) { setzeModus(.apiKey) }
      MhTrennlinie()
      ModusZeile(
        gewaehlt: mode == .cloudflare, titel: "Server (Cloudflare Access)",
        untertitel: "Service Token, API-Key optional"
      ) { setzeModus(.cloudflare) }
      MhTrennlinie()
      ModusZeile(
        gewaehlt: mode == .demo, titel: "Lokal (SQLite)",
        untertitel: "Einträge bleiben nur auf diesem Gerät"
      ) { setzeModus(.demo) }
    }
  }

  private func setzeModus(_ neu: DataSourceMode) {
    mode = neu
    AppSettings.mode = neu
  }

  /// Der API-Key wird in allen Server-Modi mitgesendet, falls hinterlegt –
  /// manche Instanzen verlangen mTLS bzw. Cloudflare Access UND Key.
  private func apiKeyFeld(hilfe: String?) -> some View {
    MhFeld("API-Key", zusatz: "optional", hinweis: hilfe) {
      GeheimEingabe(wert: $apiKey, platzhalter: "API-Key", fokus: $keyFokus)
        .onChange(of: apiKey) { neu in AppSettings.apiKey = neu }
    }
  }

  private var apiKeySektion: some View {
    VStack(alignment: .leading, spacing: Mh.abstand4) {
      MhGruppenLabel("Server (API-Key)").padding(.bottom, -Mh.abstand4)
      UrlFeld(wert: $apiKeyUrl, fokus: $urlFokus) { AppSettings.apiKeyBaseUrl = $0 }
      apiKeyFeld(hilfe: "Empfohlen. Ohne API-Key nur für interne Testzwecke.")
    }
  }

  /// Cloudflare Access prüft das Service Token am Rand und reicht die
  /// Anfrage erst danach an den Server weiter. Der API-Key ist wie im
  /// mTLS-Modus optional – für Server, die dahinter weiter ihren eigenen
  /// Key verlangen.
  private var cloudflareSektion: some View {
    VStack(alignment: .leading, spacing: Mh.abstand4) {
      MhGruppenLabel("Server (Cloudflare Access)").padding(.bottom, -Mh.abstand4)
      UrlFeld(wert: $cloudflareUrl, fokus: $urlFokus) { AppSettings.cloudflareBaseUrl = $0 }
      GeheimFeld(
        wert: $cfClientId, fokus: $cfIdFokus, titel: "Client-ID",
        hinweis: "Client-ID des Service Tokens, endet üblicherweise auf „.access“."
      ) { AppSettings.cfAccessClientId = $0 }
      GeheimFeld(
        wert: $cfClientSecret, fokus: $cfSecretFokus, titel: "Client-Secret",
        hinweis: "Beide Teile nötig. Service Tokens laufen ab, standardmäßig "
          + "nach einem Jahr."
      ) { AppSettings.cfAccessClientSecret = $0 }
      apiKeyFeld(hilfe: nil)
    }
  }

  private var mtlsSektion: some View {
    VStack(alignment: .leading, spacing: Mh.abstand4) {
      MhGruppenLabel("Server (mTLS-API)").padding(.bottom, -Mh.abstand4)
      UrlFeld(wert: $apiUrl, fokus: $urlFokus) { AppSettings.apiBaseUrl = $0 }
      zertifikatsBlock
      apiKeyFeld(hilfe: nil)
    }
  }

  /// Status der Client-Zertifikate samt Ordnerwahl. Standard bleibt der
  /// App-Ordner in der Dateien-App; alternativ lässt sich ein beliebiger
  /// Ordner auswählen, auf den die App per security-scoped Bookmark
  /// zugreift – dieselbe Bedienung wie in „Hello Baby“.
  private var zertifikatsBlock: some View {
    VStack(alignment: .leading, spacing: Mh.abstand2) {
      MhHinweis(
        zertifikatsText,
        titel: certsOk ? "Zertifikate gefunden" : "Keine Zertifikate gefunden",
        art: certsOk ? .erfolg : .fehler)
      Button {
        zeigeOrdnerwahl = true
      } label: {
        MhButtonInhalt("Zertifikats-Ordner wählen", symbol: "MhFolder")
      }
      .buttonStyle(MhZweitButtonStil(breit: true))
      .padding(.top, Mh.abstand1)
      if eigenerCertOrdner {
        Button {
          certSource.nutzeStandardOrdner()
          pruefeZertifikate()
        } label: {
          MhButtonInhalt("Standard: App-Ordner (Dateien-App)", symbol: "MhFolder")
        }
        .buttonStyle(MhZweitButtonStil(breit: true))
      }
      Button {
        pruefeZertifikate()
        meldung = certsOk ? "Zertifikate gefunden." : "Keine Zertifikate gefunden."
      } label: {
        MhButtonInhalt("Erneut prüfen", symbol: "MhRefresh", symbolGroesse: Mh.symbolKlein)
      }
      .buttonStyle(.mhText)
    }
    // Bewusst hier und nicht am Wurzel-View: dort hängt bereits der Importer
    // für Backups, und zwei fileImporter am selben View vertragen sich nicht.
    .fileImporter(isPresented: $zeigeOrdnerwahl, allowedContentTypes: [.folder]) { ergebnis in
      if case .success(let url) = ergebnis {
        do {
          try certSource.uebernehmeOrdner(url: url)
        } catch {
          meldung = "Ordner konnte nicht übernommen werden: \(error.localizedDescription)"
        }
        pruefeZertifikate()
      }
    }
  }

  private var zertifikatsText: String {
    let ort = "\(CertSource.certFileName) & \(CertSource.keyFileName) – \(certOrt)"
    guard !eigenerCertOrdner else { return ort }
    return ort + "\nPer Dateien-App in den Ordner der App „Medikamenten-Tracker“ kopieren oder "
      + "unten einen eigenen Ordner wählen."
  }

  private func pruefeZertifikate() {
    // Nebenbei: legt die Hinweisdatei an, falls sie fehlt. Damit laesst sich
    // der App-Ordner in der Dateien-App auch ohne Neustart hervorholen.
    AppOrdner.sichtbarMachen()
    certsOk = certSource.sindVorhanden
    certOrt = certSource.locationLabel
    eigenerCertOrdner = certSource.eigenerOrdner
  }

  private var backupSektion: some View {
    VStack(alignment: .leading, spacing: Mh.abstand2) {
      MhGruppenLabel("Backup").padding(.bottom, -Mh.abstand2)
      Button {
        exportieren()
      } label: {
        MhButtonInhalt("In iCloud speichern", symbol: "MhSave")
      }
      .buttonStyle(MhZweitButtonStil(breit: true))
      Button {
        restoreBestaetigen = true
      } label: {
        MhButtonInhalt("Backup wiederherstellen", symbol: "MhUndo")
      }
      .buttonStyle(MhZweitButtonStil(breit: true))
      Text("Im Dateidialog iCloud Drive als Ziel wählen.")
        .mhText(.small)
        .foregroundStyle(Mh.textSecondary)
    }
  }

  private var erklaerung: some View {
    VStack(alignment: .leading, spacing: 0) {
      MhGruppenLabel("Erklärung")
      Button {
        infoTitel = "Aufbau API"
        infoText = SettingsView.apiInfoText
      } label: {
        MhListenZeile("Aufbau API", symbol: "MhCloud", pfeil: true)
      }
      .buttonStyle(.plain)
      MhTrennlinie()
      Button {
        infoTitel = "Aufbau Datenbank"
        infoText = SettingsView.dbInfoText
      } label: {
        MhListenZeile("Aufbau Datenbank", symbol: "MhFile", pfeil: true)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Backup-Logik

  private func exportieren() {
    Task {
      do {
        let rows = try await DemoService.shared.exportRows()
        exportDokument = BackupDokument(daten: try LocalBackupService.exportJson(rows))
      } catch {
        meldung = "Backup fehlgeschlagen: \(error.localizedDescription)"
      }
    }
  }

  private func wiederherstellen(_ ergebnis: Result<URL, Error>) {
    Task {
      do {
        let url = try ergebnis.get()
        guard url.startAccessingSecurityScopedResource() else {
          throw ServiceError(message: "Datei ließ sich nicht öffnen.")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let rows = try LocalBackupService.parseUndValidiere(
          try LocalBackupService.leseBegrenzt(url))
        try await DemoService.shared.replaceAll(rows)
        meldung = "Wiederherstellung erfolgreich: \(rows.count) Einträge."
      } catch {
        meldung = "Wiederherstellung fehlgeschlagen: \(error.localizedDescription)"
      }
    }
  }
}

// MARK: - Bausteine

/// Eine Datenquelle als Listenzeile; die gewählte trägt ein Häkchen.
private struct ModusZeile: View {
  let gewaehlt: Bool
  let titel: String
  let untertitel: String
  let onWahl: () -> Void

  var body: some View {
    Button(action: onWahl) {
      HStack(spacing: Mh.abstand3) {
        VStack(alignment: .leading, spacing: 2) {
          Text(titel)
            .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
            .foregroundStyle(Mh.textStrong)
          Text(untertitel).mhText(.small).foregroundStyle(Mh.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        MhSymbol("MhCheck")
          .foregroundStyle(Mh.textGreen)
          .opacity(gewaehlt ? 1 : 0)
      }
      .padding(.vertical, Mh.abstand3)
      .frame(minHeight: 52)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(gewaehlt ? [.isSelected] : [])
  }
}

/// Verdecktes Feld mit Label und Hinweis – für die beiden Hälften des
/// Cloudflare Service Tokens.
private struct GeheimFeld: View {
  @Binding var wert: String
  var fokus: FocusState<Bool>.Binding
  let titel: String
  let hinweis: String
  let onAenderung: (String) -> Void

  var body: some View {
    MhFeld(titel, hinweis: hinweis) {
      GeheimEingabe(wert: $wert, platzhalter: titel, fokus: fokus)
        .onChange(of: wert) { neu in onAenderung(neu) }
    }
  }
}

private struct UrlFeld: View {
  @Binding var wert: String
  var fokus: FocusState<Bool>.Binding
  let onAenderung: (String) -> Void

  var body: some View {
    MhFeld("API-URL", hinweis: "Basis-URL der API inkl. abschließendem /") {
      TextField("https://…", text: $wert)
        .textFieldStyle(.mh)
        .keyboardType(.URL)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .focused(fokus)
        .onChange(of: wert) { neu in onAenderung(neu) }
        .mhFokus(fokus.wrappedValue)
    }
  }
}

private struct InfoSheet: View {
  let titel: String
  let text: String
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        MhKopf(titel, hauptaktion: {
          Button("Schließen") { dismiss() }
            .buttonStyle(MhHauptButtonStil(klein: true))
        })
        Text(text)
          .mhText(.body)
          .foregroundStyle(Mh.text)
          .textSelection(.enabled)
      }
      .padding(.horizontal, Mh.rand)
      .padding(.top, Mh.abstand5)
      .padding(.bottom, Mh.abstand8)
    }
    .background(Mh.bg.ignoresSafeArea())
  }
}

/// FileDocument-Hülle für den Export-Dialog.
struct BackupDokument: FileDocument {
  static let readableContentTypes: [UTType] = [.json]
  let daten: Data

  init(daten: Data) { self.daten = daten }

  init(configuration: ReadConfiguration) throws {
    daten = configuration.file.regularFileContents ?? Data()
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: daten)
  }
}

// MARK: - Info-Texte (identisch zur Flutter-/Android-App)

extension SettingsView {
  static let apiInfoText = """
    Die App spricht die Medikamenten-Tracker-API unter <Basis-URL>api.php an. Alle Antworten sind JSON.

    Endpunkte:

    • POST <Basis-URL>api.php?action=add
      Neuen Eintrag anlegen, Body: {"medikament": "Ibuprofen 400mg", "time": "<ISO8601, optional>"}
      Antwort: {"ok": true, "id": 42, "medikament": "...", "time": ISO8601}

    • GET <Basis-URL>api.php?action=last
      Letzter Eintrag: {"id": 42, "medikament": "...", "time": ISO8601} oder null

    • GET <Basis-URL>api.php?action=list
      Alle Einträge (optional ?limit=N): {"last": ..., "entries": [...], "total": N}

    • GET <Basis-URL>api.php?action=stats
      Statistik je Zeitraum (today, week, threeWeeks, month) mit total und
      Aufschlüsselung je Medikament, plus "last"

    • POST <Basis-URL>api.php?action=delete
      Eintrag nach ID löschen, Body: {"id": 42}

    • POST <Basis-URL>api.php?action=undo_last
      Letzten Eintrag löschen: {"ok": true, "removed": 42}

    Authentifizierung:
    • Header "X-API-Key: <Key>" wird gesendet, falls hinterlegt. Manche Instanzen \
    verlangen ihn, andere sichern nur über mTLS ab – dann ist der Key optional.
    • Im Modus "Server (mTLS-API)" zusätzlich ein Client-Zertifikat \
    (client.crt + client.key) auf Transport-Ebene.
    • Im Modus "Server (Cloudflare Access)" zusätzlich die Header \
    "CF-Access-Client-Id: <ID>" und "CF-Access-Client-Secret: <Secret>".

    Fehler kommen als {"error": "..."} mit passendem HTTP-Statuscode.
    """

  static let dbInfoText = """
    Im Modus "Lokal (SQLite)" speichert die App alle Einträge in der Datenbank \
    medikamenten_demo.db im app-privaten Speicher. Andere Apps haben keinen Zugriff, \
    es findet keine Synchronisation statt.

    Tabelle "entries":

    • id
      INTEGER, Primärschlüssel (Auto-Increment)

    • medikament
      TEXT, Name des Medikaments (Freitext)

    • time
      TEXT, Zeitpunkt als ISO 8601 in UTC gespeichert (dadurch chronologisch sortierbar), \
    Anzeige in lokaler Zeit

    Die Statistik (heute / 7 Tage / 3 Wochen / 30 Tage) wird lokal aus diesen Einträgen \
    berechnet – mit Aufschlüsselung je Medikament wie die Server-API.

    Sicherung & Gerätewechsel

    Die Einträge liegen in der SQLite-Datei im app-privaten Speicher und werden \
    vom iCloud-Backup mitgesichert – nach einer Wiederherstellung sind sie also wieder da.

    Der API-Key liegt dagegen nicht in den Einstellungen, sondern in der Keychain. \
    Er wandert beim Direkttransfer auf ein neues Gerät (Schnellstart) und im \
    verschlüsselten Backup über den Computer mit, lässt sich aus einem \
    iCloud-Backup aber nicht wiederherstellen. Das ist Absicht: der Schlüssel \
    soll nicht auf fremden Servern liegen. Nach einer Wiederherstellung aus \
    iCloud muss er einmal neu eingetragen werden.

    Client-Zertifikate (client.crt / client.key) liegen im App-Ordner der \
    Dateien-App und sind nach einem Gerätewechsel gegebenenfalls neu abzulegen. \
    Alternativ lässt sich oben ein beliebiger anderer Ordner auswählen; der \
    Zugriff darauf wird als Lesezeichen gespeichert. Nach einer \
    Wiederherstellung auf einem neuen Gerät zeigt das Lesezeichen ins Leere – \
    die App meldet das und bittet darum, den Ordner erneut auszuwählen.

    Unabhängig davon lässt sich hier jederzeit ein eigenes Backup als \
    JSON-Datei sichern und wieder einspielen.
    """
}

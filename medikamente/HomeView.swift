import SwiftUI

/// Startseite wie im Web: Kopf mit Symbolen, Titel, Eingabe mit der einen
/// Hauptaktion „Anlegen“, letzter Eintrag zwischen Haarlinien, Statistik und
/// die Einträge nach Tagen.
struct HomeView: View {
  @StateObject private var model = HomeViewModel()
  @Environment(\.scenePhase) private var szenenPhase

  @State private var medikamentText = ""
  @State private var zeigeEinstellungen = false
  @State private var zeigeZeitwahl = false
  @State private var loeschKandidat: MedEntry?
  @State private var zeigeUndoNachfrage = false
  @FocusState private var eingabeFokussiert: Bool

  var body: some View {
    inhalt
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .background(Mh.bg.ignoresSafeArea())
      .sheet(isPresented: $zeigeEinstellungen, onDismiss: model.datenquelleNeuAufbauen) {
        SettingsView()
      }
      .sheet(isPresented: $zeigeZeitwahl) {
        ZeitwahlSheet(initial: model.eigeneZeit) { neu in
          model.eigeneZeit = neu
        }
      }
      .alert("Eintrag löschen?", isPresented: .init(
        get: { loeschKandidat != nil },
        set: { if !$0 { loeschKandidat = nil } })
      ) {
        Button("Abbrechen", role: .cancel) {}
        Button("Löschen", role: .destructive) {
          if let eintrag = loeschKandidat { model.loeschen(eintrag) }
        }
      } message: {
        if let eintrag = loeschKandidat {
          Text("„\(eintrag.medikament)“ wird entfernt.")
        }
      }
      .alert("Letzten Eintrag löschen?", isPresented: $zeigeUndoNachfrage) {
        Button("Abbrechen", role: .cancel) {}
        Button("Löschen", role: .destructive) { model.letztenRueckgaengig() }
      } message: {
        Text("Der zuletzt angelegte Eintrag wird entfernt.")
      }
      .alert(
        "Hinweis",
        isPresented: .init(get: { model.meldung != nil }, set: { if !$0 { model.meldung = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(model.meldung ?? "")
      }
      .task { model.aktualisieren() }
      // Rückkehr aus dem Hintergrund: nachladen und dabei die Warteschlange
      // abarbeiten – zwischendurch kann die Verbindung wiedergekommen sein,
      // ohne dass die Wache lief.
      .onChange(of: szenenPhase) { neu in
        if neu == .active { model.aktualisieren() }
      }
  }

  // MARK: - Inhalt

  @ViewBuilder
  private var inhalt: some View {
    if model.laedt && model.eintraege.isEmpty && model.fehler == nil {
      VStack(alignment: .leading, spacing: 0) {
        kopf
        MhLaden()
      }
      .padding(.horizontal, Mh.rand)
    } else if let fehler = model.fehler {
      VStack(alignment: .leading, spacing: 0) {
        kopf
        FehlerAnsicht(meldung: fehler) { model.aktualisieren() }
      }
      .padding(.horizontal, Mh.rand)
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          kopf
          // Offline-Hinweis vor allem anderen: Weiterarbeiten geht, der Stand
          // ist aber noch nicht beim Server.
          if model.offlineGrund != nil || model.ausstehend > 0 {
            OfflineHinweis(grund: model.offlineGrund, ausstehend: model.ausstehend)
              .padding(.bottom, Mh.abstand5)
          }
          eingabe
          LetzterEintrag(last: model.stats?.last) { zeigeUndoNachfrage = true }
            .padding(.top, Mh.abstand6)
          if let stats = model.stats {
            statistik(stats).padding(.top, Mh.abstand8)
          }
          eintragsListe.padding(.top, Mh.abstand8)
        }
        .padding(.horizontal, Mh.rand)
        .padding(.bottom, Mh.abstand8)
      }
      .refreshable { model.aktualisieren() }
      // Grund hinter der Statusleiste, damit gescrollter Inhalt nicht unter
      // Uhrzeit und Akku durchscheint.
      .safeAreaInset(edge: .top, spacing: 0) {
        Color.clear.frame(height: 0).background(Mh.bg)
      }
    }
  }

  /// Kopfzeile mit den Symbol-Knöpfen rechts (wie die Web-Kopfzeile), darunter
  /// der Titel linksbündig.
  private var kopf: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Spacer(minLength: 0)
        MhSymbolButton("MhRefresh", beschreibung: "Aktualisieren") { model.aktualisieren() }
        MhSymbolButton("MhSliders", beschreibung: "Einstellungen") { zeigeEinstellungen = true }
      }
      // Symbol bündig mit dem Seitenrand, die Touch-Fläche ragt hinein.
      .padding(.trailing, -Mh.abstand3)
      MhKopf("Medikamenten-Tracker")
    }
  }

  // MARK: - Eingabe

  private var eingabe: some View {
    VStack(alignment: .leading, spacing: Mh.abstand5) {
      MhFeld("Medikament") {
        TextField("z. B. Ibuprofen 400 mg", text: $medikamentText)
          .textFieldStyle(.mh)
          .focused($eingabeFokussiert)
          .submitLabel(.done)
          .onSubmit { anlegen() }
          .mhFokus(eingabeFokussiert)
      }
      MhFeld("Uhrzeit", hinweis: zeitHinweis) {
        MhSegmente(optionen: ["Jetzt", "Andere Zeit"], gewaehlt: zeitWahl)
      }
      Button {
        anlegen()
      } label: {
        if model.speichert {
          ProgressView().tint(Mh.textSecondary)
        } else {
          Text("Anlegen")
        }
      }
      .buttonStyle(MhHauptButtonStil(breit: true))
      .disabled(model.speichert)
    }
  }

  /// „Jetzt“ setzt die eigene Zeit zurück; „Andere Zeit“ öffnet die Auswahl –
  /// auch erneut, wenn schon eine eigene Zeit gewählt ist.
  private var zeitWahl: Binding<Int> {
    Binding(
      get: { model.eigeneZeit == nil ? 0 : 1 },
      set: { neu in
        if neu == 0 {
          model.eigeneZeit = nil
        } else {
          zeigeZeitwahl = true
        }
      })
  }

  private var zeitHinweis: String? {
    model.eigeneZeit.map { "Gewählt: \($0.tagesLabel), \($0.uhrzeit) Uhr" }
  }

  private func anlegen() {
    let name = medikamentText.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else {
      model.meldung = "Bitte ein Medikament eingeben"
      return
    }
    eingabeFokussiert = false
    model.anlegen(name) { medikamentText = "" }
  }

  // MARK: - Statistik

  private func statistik(_ stats: MedStats) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Abschnittstitel("Statistik").padding(.bottom, Mh.abstand2)
      PeriodenZeile(titel: "Heute", periode: stats.today)
      MhTrennlinie()
      PeriodenZeile(titel: "Letzte 7 Tage", periode: stats.week)
      MhTrennlinie()
      PeriodenZeile(titel: "Letzte 3 Wochen", periode: stats.threeWeeks)
      MhTrennlinie()
      PeriodenZeile(titel: "Letzte 30 Tage", periode: stats.month)
    }
  }

  // MARK: - Eintragsliste

  private var eintragsListe: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: Mh.abstand3) {
        Abschnittstitel("Einträge")
        Spacer(minLength: 0)
        if !model.eintraege.isEmpty {
          Text(model.eintraege.count == 1 ? "1 Eintrag" : "\(model.eintraege.count) Einträge")
            .mhText(.small)
            .monospacedDigit()
            .foregroundStyle(Mh.textSecondary)
        }
      }
      if model.eintraege.isEmpty {
        MhLeer("Noch keine Einträge")
      } else {
        let gruppen = Dictionary(grouping: model.eintraege) { $0.time?.tagesUeberschrift ?? "Ohne Datum" }
        let reihenfolge = model.eintraege.map { $0.time?.tagesUeberschrift ?? "Ohne Datum" }.einmalig()
        ForEach(reihenfolge, id: \.self) { tag in
          MhGruppenLabel(tag)
          ForEach(gruppen[tag] ?? [], id: \.selbstId) { eintrag in
            MhTrennlinie()
            EintragsZeile(
              eintrag: eintrag,
              ausstehend: eintrag.id.map(model.ausstehendeIds.contains) ?? false
            ) { loeschKandidat = eintrag }
          }
        }
      }
    }
  }
}

// MARK: - Letzter Eintrag

/// Letzter Eintrag zwischen zwei Haarlinien, „Rückgängig“ als leise
/// Löschaktion rechts.
private struct LetzterEintrag: View {
  let last: MedEntry?
  let onRueckgaengig: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      MhTrennlinie()
      HStack(alignment: .center, spacing: Mh.abstand3) {
        VStack(alignment: .leading, spacing: Mh.abstand1) {
          Text("Letzter Eintrag").mhText(.label).foregroundStyle(Mh.textSecondary)
          if let last {
            Text(last.medikament)
              .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
              .foregroundStyle(Mh.textStrong)
            if let zeit = last.time {
              Text("\(zeit.tagesLabel), \(zeit.uhrzeit) Uhr · \(zeit.relativ)")
                .mhText(.small)
                .monospacedDigit()
                .foregroundStyle(Mh.textSecondary)
            }
          } else {
            Text("Noch kein Eintrag").mhText(.body).foregroundStyle(Mh.textSecondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        if last != nil {
          Button(action: onRueckgaengig) {
            MhButtonInhalt("Rückgängig", symbol: "MhUndo", symbolGroesse: Mh.symbolKlein)
          }
          .buttonStyle(.mhLoeschen)
          .accessibilityLabel("Letzten Eintrag löschen")
        }
      }
      .padding(.vertical, Mh.abstand4)
      MhTrennlinie()
    }
  }
}

// MARK: - Statistik-Zeile

/// Ein Zeitraum als Listenzeile: Titel und Aufschlüsselung je Medikament
/// links, Gesamtzahl groß und dünn in Textfarbe rechts.
private struct PeriodenZeile: View {
  let titel: String
  let periode: PeriodStats

  var body: some View {
    HStack(alignment: .center, spacing: Mh.abstand4) {
      VStack(alignment: .leading, spacing: 2) {
        Text(titel)
          .font(.custom(MhSchrift.medium, size: 16, relativeTo: .body))
          .foregroundStyle(Mh.textStrong)
        Text(aufschluesselung)
          .mhText(.small)
          .monospacedDigit()
          .foregroundStyle(Mh.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Text("\(periode.total)")
        .mhText(.number)
        .foregroundStyle(Mh.textStrong)
    }
    .padding(.vertical, Mh.abstand3)
    .frame(minHeight: 56)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(titel): \(periode.total) gesamt. \(aufschluesselung)")
  }

  private var aufschluesselung: String {
    if periode.medikamente.isEmpty { return "Keine Einträge" }
    return periode.medikamente.map { "\($0.medikament) \($0.anzahl)×" }.joined(separator: " · ")
  }
}

// MARK: - Eintragszeile

/// Eine Zeile wie im Web: Uhrzeit, Medikament, „Löschen“ als roter Text.
private struct EintragsZeile: View {
  let eintrag: MedEntry
  /// Der Eintrag wartet noch auf die Übertragung zum Server.
  let ausstehend: Bool
  let onLoeschen: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: Mh.abstand3) {
      Text(eintrag.time.map { "\($0.uhrzeit) Uhr" } ?? "–")
        .mhText(.small)
        .monospacedDigit()
        .foregroundStyle(Mh.textSecondary)
        .frame(minWidth: 72, alignment: .leading)
      Text(eintrag.medikament)
        .mhText(.body)
        .foregroundStyle(Mh.textStrong)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Mh.abstand2)
      if ausstehend {
        ZStack { MhSymbol("MhClock", groesse: Mh.symbolKlein) }
          .foregroundStyle(Mh.warningFg)
          .accessibilityElement()
          .accessibilityLabel("Wartet auf Übertragung")
      }
      Button("Löschen", action: onLoeschen)
        .buttonStyle(.mhLoeschen)
        .accessibilityLabel("„\(eintrag.medikament)“ löschen")
    }
    .frame(minHeight: 52)
  }
}

// MARK: - Zeitwahl

/// Zeitpunkt für „Andere Zeit“: bis ein Jahr zurück, nicht in der Zukunft
/// (wie in der Flutter-App).
private struct ZeitwahlSheet: View {
  let initial: Date?
  let onUebernehmen: (Date) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var auswahl = Date()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        MhKopf("Uhrzeit wählen", symbole: {
          MhSymbolButton("MhClose", beschreibung: "Abbrechen") { dismiss() }
            .padding(.trailing, -Mh.abstand3)
        })
        DatePicker(
          "Zeitpunkt",
          selection: $auswahl,
          in: Calendar.current.date(byAdding: .year, value: -1, to: Date())!...Date(),
          displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.graphical)
        .tint(Mh.primary)
        // Monat und Wochentage deutsch wie der Rest der App.
        .environment(\.locale, Locale(identifier: "de_DE"))
        Button {
          onUebernehmen(auswahl)
          dismiss()
        } label: {
          Text("Übernehmen")
        }
        .buttonStyle(MhHauptButtonStil(breit: true))
        .padding(.top, Mh.abstand5)
      }
      .padding(.horizontal, Mh.rand)
      .padding(.top, Mh.abstand5)
      .padding(.bottom, Mh.abstand8)
    }
    .background(Mh.bg.ignoresSafeArea())
    .presentationDetents([.large])
    .onAppear { if let initial { auswahl = initial } }
  }
}

// MARK: - Fehleransicht

private struct FehlerAnsicht: View {
  let meldung: String
  let onErneut: () -> Void

  var body: some View {
    VStack(spacing: Mh.abstand4) {
      MhSymbol("MhAlert", groesse: 32).foregroundStyle(Mh.danger)
      Text(meldung)
        .mhText(.body)
        .foregroundStyle(Mh.text)
        .multilineTextAlignment(.center)
      Button {
        onErneut()
      } label: {
        MhButtonInhalt("Erneut versuchen", symbol: "MhRefresh")
      }
      .buttonStyle(.mhHaupt)
      .padding(.top, Mh.abstand2)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Mh.abstand12)
  }
}

// MARK: - Offline-Hinweis

/// Hinweis über dem Inhalt: Verbindung weg, App weiter benutzbar.
private struct OfflineHinweis: View {
  /// Grund der abgebrochenen Verbindung; nil heißt „wieder online, aber es
  /// wartet noch etwas auf die Übertragung“.
  let grund: String?
  let ausstehend: Int

  var body: some View {
    MhHinweis(
      untertitel, titel: titel, art: .warnung,
      symbol: grund == nil ? "MhUpload" : "MhCloudOff")
  }

  private var titel: String {
    guard let grund else { return "Übertragung läuft" }
    return "Offline-Modus – \(grund)"
  }

  private var untertitel: String {
    guard ausstehend > 0 else {
      return "Angezeigt wird der zuletzt geladene Stand."
    }
    if ausstehend == 1 {
      return "Eine Änderung wartet auf die Übertragung und geht raus, sobald die Verbindung steht."
    }
    return
      "\(ausstehend) Änderungen warten auf die Übertragung und gehen raus, sobald die Verbindung steht."
  }
}

// MARK: - Helfer

extension MedEntry {
  /// Stabiler Listen-Schlüssel auch für Einträge ohne Server-ID.
  var selbstId: String {
    if let id { return "id-\(id)" }
    return "\(medikament)-\(time?.timeIntervalSince1970 ?? 0)"
  }
}

extension Array where Element: Hashable {
  /// Reihenfolge-erhaltendes Deduplizieren.
  func einmalig() -> [Element] {
    var gesehen = Set<Element>()
    return filter { gesehen.insert($0).inserted }
  }
}

import SwiftUI

struct HomeView: View {
  @StateObject private var model = HomeViewModel()

  @State private var medikamentText = ""
  @State private var zeigeEinstellungen = false
  @State private var zeigeZeitwahl = false
  @State private var loeschKandidat: MedEntry?
  @State private var zeigeUndoNachfrage = false
  @FocusState private var eingabeFokussiert: Bool

  var body: some View {
    NavigationStack {
      ZStack {
        Mh.grund.ignoresSafeArea()
        inhalt
      }
      .navigationTitle("")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            model.aktualisieren()
          } label: {
            Image(systemName: "arrow.clockwise").foregroundStyle(Mh.gruenText)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            zeigeEinstellungen = true
          } label: {
            Image(systemName: "gearshape").foregroundStyle(Mh.gruenText)
          }
        }
      }
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
    }
  }

  // MARK: - Inhalt

  @ViewBuilder
  private var inhalt: some View {
    if model.laedt && model.eintraege.isEmpty && model.fehler == nil {
      ProgressView().tint(Mh.minze500)
    } else if let fehler = model.fehler {
      FehlerAnsicht(meldung: fehler) { model.aktualisieren() }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // App-Titel im Inhalt statt in der Toolbar: iOS faltet Text-Items
          // dort in ein Überlauf-Menü.
          Text("💊 Medikamente")
            .font(.nunitoExtraBold(26))
            .foregroundStyle(Mh.text)
          eingabeKarte
          LetzterEintragKarte(last: model.stats?.last)
          Button {
            zeigeUndoNachfrage = true
          } label: {
            Label("Letzten rückgängig", systemImage: "arrow.uturn.backward")
              .font(.nunitoSemiBold(15))
          }
          .buttonStyle(MhRandButtonStil())
          if let stats = model.stats { statistik(stats) }
          eintragsListe
        }
        .padding(16)
      }
      .refreshable { model.aktualisieren() }
    }
  }

  // MARK: - Eingabe-Karte

  private var eingabeKarte: some View {
    MhKarte {
      VStack(alignment: .leading, spacing: 12) {
        Text("Neuer Eintrag").font(.nunitoBold(16)).foregroundStyle(Mh.text)
        TextField("z. B. Ibuprofen 400mg", text: $medikamentText)
          .font(.nunito(16))
          .focused($eingabeFokussiert)
          .submitLabel(.done)
          .onSubmit { anlegen() }
          .padding(.horizontal, 12)
          .frame(minHeight: 44)
          .background(Mh.feldFlaeche)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(eingabeFokussiert ? Mh.minze500 : Mh.rand, lineWidth: 1.5)
          )
        HStack(spacing: 8) {
          Chip(text: "Jetzt", aktiv: model.eigeneZeit == nil) {
            model.eigeneZeit = nil
          }
          Chip(
            text: model.eigeneZeit.map { "\($0.tagesLabel) \($0.formatted(date: .omitted, time: .shortened))" }
              ?? "Andere Zeit",
            symbol: model.eigeneZeit == nil ? "clock" : nil,
            aktiv: model.eigeneZeit != nil
          ) {
            zeigeZeitwahl = true
          }
        }
        Button {
          anlegen()
        } label: {
          if model.speichert {
            ProgressView().tint(Mh.minze900).frame(maxWidth: .infinity)
          } else {
            Label("Anlegen", systemImage: "plus").frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(MhButtonStil())
        .disabled(model.speichert)
      }
    }
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
    VStack(alignment: .leading, spacing: 8) {
      Text("Statistik").font(.nunitoBold(16)).foregroundStyle(Mh.text)
      PeriodenKarte(titel: "Heute", periode: stats.today, hervorgehoben: true)
      PeriodenKarte(titel: "Letzte 7 Tage", periode: stats.week)
      PeriodenKarte(titel: "Letzte 3 Wochen", periode: stats.threeWeeks)
      PeriodenKarte(titel: "Letzte 30 Tage", periode: stats.month)
    }
  }

  // MARK: - Eintragsliste

  @ViewBuilder
  private var eintragsListe: some View {
    Text(model.eintraege.isEmpty ? "Einträge" : "Einträge (\(model.eintraege.count))")
      .font(.nunitoBold(16))
      .foregroundStyle(Mh.text)
      .padding(.top, 8)
    if model.eintraege.isEmpty {
      Text("Noch keine Einträge vorhanden")
        .font(.nunito(16))
        .foregroundStyle(Mh.textSekundaer)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    } else {
      let gruppen = Dictionary(grouping: model.eintraege) { $0.time?.tagesLabel ?? "Ohne Datum" }
      let reihenfolge = model.eintraege.map { $0.time?.tagesLabel ?? "Ohne Datum" }.einmalig()
      ForEach(reihenfolge, id: \.self) { tag in
        Text(tag)
          .font(.nunitoBold(14))
          .foregroundStyle(Mh.gruenText)
          .padding(.horizontal, 4)
          .padding(.top, 8)
        ForEach(gruppen[tag] ?? [], id: \.selbstId) { eintrag in
          EintragsKachel(eintrag: eintrag) { loeschKandidat = eintrag }
        }
      }
    }
  }
}

// MARK: - Letzter Eintrag

private struct LetzterEintragKarte: View {
  let last: MedEntry?

  var body: some View {
    MhKarte {
      HStack(spacing: 14) {
        ZStack {
          Circle().fill(Mh.avatarFlaeche).frame(width: 40, height: 40)
          Image(systemName: last == nil ? "clock.arrow.circlepath" : "pills")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Mh.avatarText)
        }
        VStack(alignment: .leading, spacing: 2) {
          if let last {
            Text("Zuletzt: \(last.medikament)").font(.nunito(16)).foregroundStyle(Mh.text)
            if let zeit = last.time {
              Text(
                "\(zeit.tagesLabel) um \(zeit.formatted(date: .omitted, time: .shortened)) · \(zeit.relativ)"
              )
              .font(.nunito(14))
              .foregroundStyle(Mh.textSekundaer)
            }
          } else {
            Text("Noch kein Eintrag").font(.nunito(16)).foregroundStyle(Mh.text)
            Text("Lege oben den ersten Eintrag an.")
              .font(.nunito(14))
              .foregroundStyle(Mh.textSekundaer)
          }
        }
        Spacer(minLength: 0)
      }
    }
  }
}

// MARK: - Perioden-Karte

private struct PeriodenKarte: View {
  let titel: String
  let periode: PeriodStats
  var hervorgehoben = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(titel).font(.nunitoBold(14)).foregroundStyle(Mh.text)
        Spacer()
        Text("\(periode.total) gesamt").font(.nunitoExtraBold(14)).foregroundStyle(Mh.text)
      }
      if periode.medikamente.isEmpty {
        Text("Keine Einträge").font(.nunito(12)).foregroundStyle(Mh.textSekundaer)
      } else {
        ForEach(periode.medikamente) { zeile in
          HStack(spacing: 8) {
            Image(systemName: "pills")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Mh.avatarText)
            Text(zeile.medikament).font(.nunito(15)).foregroundStyle(Mh.text)
            Spacer()
            Text("\(zeile.anzahl)×").font(.nunitoBold(15)).foregroundStyle(Mh.text)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    // "Heute" hervorgehoben als zarte Minze-Fläche (Dark-Äquivalent).
    .background(hervorgehoben ? Mh.avatarFlaeche : Mh.karte)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .shadow(
      color: hervorgehoben ? .clear : Color(UIColor(rgb: 0x22392C)).opacity(0.10),
      radius: 6, y: 2)
  }
}

// MARK: - Chips

/// Pill-Chip nach Guide: aktiv = Minze-300-Fläche mit 900er-Text.
private struct Chip: View {
  let text: String
  var symbol: String?
  let aktiv: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let symbol { Image(systemName: symbol).font(.system(size: 14)) }
        Text(text).font(.nunitoSemiBold(15))
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 36)
      .background(aktiv ? Mh.minze300 : .clear)
      .foregroundStyle(aktiv ? Mh.minze900 : Mh.text)
      .overlay(
        Capsule().strokeBorder(aktiv ? .clear : Mh.rand, lineWidth: 1.5)
      )
      .clipShape(Capsule())
    }
  }
}

// MARK: - Eintrags-Kachel

private struct EintragsKachel: View {
  let eintrag: MedEntry
  let onLoeschen: () -> Void

  var body: some View {
    MhKarte {
      HStack(spacing: 14) {
        ZStack {
          Circle().fill(Mh.avatarFlaeche).frame(width: 40, height: 40)
          Image(systemName: "pills")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Mh.avatarText)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(eintrag.medikament).font(.nunito(16)).foregroundStyle(Mh.text)
          if let zeit = eintrag.time {
            Text("\(zeit.formatted(date: .omitted, time: .shortened)) Uhr")
              .font(.nunito(14))
              .foregroundStyle(Mh.textSekundaer)
          }
        }
        Spacer(minLength: 8)
        Button(action: onLoeschen) {
          Image(systemName: "trash").foregroundStyle(Mh.textSekundaer)
        }
      }
    }
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
    NavigationStack {
      ZStack {
        Mh.grund.ignoresSafeArea()
        VStack {
          DatePicker(
            "Zeitpunkt",
            selection: $auswahl,
            in: Calendar.current.date(byAdding: .year, value: -1, to: Date())!...Date(),
            displayedComponents: [.date, .hourAndMinute]
          )
          .datePickerStyle(.graphical)
          .tint(Mh.minze500)
          .padding(16)
          Spacer()
          Button {
            onUebernehmen(auswahl)
            dismiss()
          } label: {
            Text("Übernehmen").frame(maxWidth: .infinity)
          }
          .buttonStyle(MhButtonStil())
          .padding(16)
        }
      }
      .navigationTitle("Uhrzeit wählen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Abbrechen") { dismiss() }.foregroundStyle(Mh.gruenText)
        }
      }
      .onAppear { if let initial { auswahl = initial } }
    }
    .presentationDetents([.large])
  }
}

// MARK: - Fehleransicht

private struct FehlerAnsicht: View {
  let meldung: String
  let onErneut: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "exclamationmark.circle")
        .font(.system(size: 52))
        .foregroundStyle(Mh.fehlerText)
      Text(meldung)
        .font(.nunito(16))
        .foregroundStyle(Mh.text)
        .multilineTextAlignment(.center)
      Button {
        onErneut()
      } label: {
        Label("Erneut versuchen", systemImage: "arrow.clockwise")
      }
      .buttonStyle(MhButtonStil())
    }
    .padding(32)
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

extension Date {
  var tagesLabel: String {
    if Calendar.current.isDateInToday(self) { return "Heute" }
    if Calendar.current.isDateInYesterday(self) { return "Gestern" }
    return formatted(.dateTime.day(.twoDigits).month(.twoDigits).year())
  }

  /// „vor X min/h/d“ – wie in der Flutter-App.
  var relativ: String {
    let differenz = Int(Date().timeIntervalSince(self))
    let minuten = differenz / 60
    if minuten < 1 { return "gerade eben" }
    if minuten < 60 { return "vor \(minuten) min" }
    let stunden = minuten / 60
    if stunden < 24 { return "vor \(stunden) h" }
    return "vor \(stunden / 24) d"
  }
}

extension Array where Element: Hashable {
  /// Reihenfolge-erhaltendes Deduplizieren.
  func einmalig() -> [Element] {
    var gesehen = Set<Element>()
    return filter { gesehen.insert($0).inserted }
  }
}

/// Sekundär-Button: Rand statt Fläche, grüner Text.
struct MhRandButtonStil: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(Mh.gruenText)
      .padding(.horizontal, 16)
      .frame(minHeight: 40)
      .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(Mh.rand, lineWidth: 1.5)
      )
      .opacity(configuration.isPressed ? 0.6 : 1)
  }
}

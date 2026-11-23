import SwiftUI

// ============================================================================
// App-eigene Bausteine auf Basis von Minze & Honig 2.0 (MhTheme.swift,
// MhBausteine.swift): Abschnittstitel, Fokusrand, verdecktes Eingabefeld und
// die Datumstexte, die Startseite und Einstellungen teilen.
// ============================================================================

/// Abschnittstitel (H2) wie „Einträge“ im Web.
struct Abschnittstitel: View {
  let text: String

  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .mhText(.h2)
      .foregroundStyle(Mh.textStrong)
      .accessibilityAddTraits(.isHeader)
  }
}

extension View {
  /// Fokus eines Eingabefelds: Rand in `focusRing` plus weicher Ring außen.
  func mhFokus(_ aktiv: Bool) -> some View {
    overlay(
      RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
        .stroke(Mh.focusRing, lineWidth: 1)
        .overlay(
          RoundedRectangle(cornerRadius: Mh.radiusMd + 3, style: .continuous)
            .stroke(Mh.focusRing.opacity(0.3), lineWidth: 3)
            .padding(-3)
        )
        .opacity(aktiv ? 1 : 0)
        .allowsHitTesting(false)
    )
  }
}

/// Verdecktes Eingabefeld mit Auge zum Aufdecken (API-Key, Service Token).
/// Gleiche Form wie `.textFieldStyle(.mh)`, das Symbol sitzt im Feld.
struct GeheimEingabe: View {
  @Binding var wert: String
  let platzhalter: String
  var fokus: FocusState<Bool>.Binding

  @State private var sichtbar = false

  var body: some View {
    HStack(spacing: 0) {
      Group {
        if sichtbar {
          TextField(platzhalter, text: $wert)
        } else {
          SecureField(platzhalter, text: $wert)
        }
      }
      .mhText(.body)
      .foregroundStyle(Mh.text)
      .tint(Mh.primary)
      .focused(fokus)
      .autocorrectionDisabled()
      .textInputAutocapitalization(.never)
      MhSymbolButton(
        sichtbar ? "MhEyeOff" : "MhEye",
        beschreibung: sichtbar ? "Verbergen" : "Anzeigen"
      ) { sichtbar.toggle() }
    }
    .padding(.leading, Mh.abstand3)
    .frame(minHeight: Mh.touch)
    .background(RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous).fill(Mh.fieldBg))
    .overlay(
      RoundedRectangle(cornerRadius: Mh.radiusMd, style: .continuous)
        .stroke(Mh.borderStrong, lineWidth: 1)
    )
    .mhFokus(fokus.wrappedValue)
  }
}

// MARK: - Datumstexte (immer deutsch, wie die übrigen Texte der App)

private let deutsch = Locale(identifier: "de_DE")

extension Date {
  /// „Heute“, „Gestern“ oder „21.11.2026“.
  var tagesLabel: String {
    if Calendar.current.isDateInToday(self) { return "Heute" }
    if Calendar.current.isDateInYesterday(self) { return "Gestern" }
    return formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(deutsch))
  }

  /// Überschrift einer Tagesgruppe: „Heute“, „Gestern“ oder „Sa., 21.11.2026“.
  var tagesUeberschrift: String {
    if Calendar.current.isDateInToday(self) { return "Heute" }
    if Calendar.current.isDateInYesterday(self) { return "Gestern" }
    return formatted(
      .dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits).year().locale(deutsch))
  }

  /// Uhrzeit „08:15“ (24 Stunden).
  var uhrzeit: String {
    formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(deutsch))
  }

  /// „gerade eben“, „vor 5 Min.“, „vor 2 Std.“, „vor 3 Tagen“ – wie im Web.
  var relativ: String {
    let minuten = Int(Date().timeIntervalSince(self)) / 60
    if minuten < 1 { return "gerade eben" }
    if minuten < 60 { return "vor \(minuten) Min." }
    let stunden = minuten / 60
    if stunden < 24 { return "vor \(stunden) Std." }
    let tage = stunden / 24
    return tage == 1 ? "vor 1 Tag" : "vor \(tage) Tagen"
  }
}

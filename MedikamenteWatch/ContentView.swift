import SwiftUI

// Minze-&-Honig-Töne für die Uhr (watchOS rendert immer auf dunklem Grund;
// Pastellflächen 300 mit 900er-Text funktionieren dort direkt, Guide 2.8).
enum MhW {
  static let minze300 = Color(red: 0xA8 / 255, green: 0xD5 / 255, blue: 0xBA / 255)
  static let minze900 = Color(red: 0x22 / 255, green: 0x39 / 255, blue: 0x2C / 255)
  static let minzeDunkel = Color(red: 0x26 / 255, green: 0x3B / 255, blue: 0x2F / 255)
  static let karte = Color(red: 0x29 / 255, green: 0x2D / 255, blue: 0x2B / 255)
  static let textHell = Color(red: 0xEC / 255, green: 0xEF / 255, blue: 0xED / 255)
}

extension Font {
  // PostScript-Namen der eingebetteten Nunito-Schnitte (siehe Telefon-App).
  static func nunito(_ groesse: CGFloat) -> Font { .custom("NunitoExtraLight-Regular", size: groesse) }
  static func nunitoSemiBold(_ groesse: CGFloat) -> Font { .custom("NunitoExtraLight-SemiBold", size: groesse) }
  static func nunitoBold(_ groesse: CGFloat) -> Font { .custom("NunitoExtraLight-Bold", size: groesse) }
  static func nunitoExtraBold(_ groesse: CGFloat) -> Font { .custom("NunitoExtraLight-ExtraBold", size: groesse) }
}

/// Übersicht der zuletzt eingenommenen Medikamente.
struct ContentView: View {
  @EnvironmentObject private var store: WatchStore

  private var snapshot: WatchSnapshot { store.snapshot }

  var body: some View {
    NavigationStack {
      Group {
        if snapshot.entries.isEmpty {
          EmptyStateView(neverSynced: snapshot.isEmpty)
        } else {
          List {
            Section {
              TodaySummary(today: snapshot.todayTotal, week: snapshot.weekTotal)
                .listRowBackground(
                  RoundedRectangle(cornerRadius: 12).fill(MhW.minzeDunkel))
            }
            Section("Zuletzt") {
              ForEach(snapshot.entries) { entry in
                EntryRow(entry: entry)
                  .listRowBackground(
                    RoundedRectangle(cornerRadius: 12).fill(MhW.karte))
              }
            }
            if let updatedAt = snapshot.updatedAt {
              Section {
                Text("Stand: \(updatedAt, style: .relative)")
                  .font(.nunito(12))
                  .foregroundStyle(.secondary)
                  .listRowBackground(Color.clear)
              }
            }
          }
        }
      }
      // Ohne Emoji – auf dem schmalen Display bräche der Titel sonst um.
      .navigationTitle("Medikamente")
    }
    .tint(MhW.minze300)
  }
}

/// Tages- und Wochenzähler als Kopfzeile.
private struct TodaySummary: View {
  let today: Int
  let week: Int

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Heute").font(.nunitoSemiBold(12)).foregroundStyle(.secondary)
        Text("\(today)").font(.nunitoExtraBold(22)).foregroundStyle(MhW.minze300)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text("7 Tage").font(.nunitoSemiBold(12)).foregroundStyle(.secondary)
        Text("\(week)").font(.nunitoBold(18)).foregroundStyle(MhW.textHell)
      }
    }
    .padding(.vertical, 2)
  }
}

/// Eine Zeile der Einträgeliste: Name, Zeitpunkt, relativer Abstand.
private struct EntryRow: View {
  let entry: MedEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(entry.medikament)
        .font(.nunitoBold(15))
        .foregroundStyle(MhW.textHell)
        .lineLimit(2)
      if let time = entry.time {
        Text("\(Self.dayLabel(for: time)) · \(time, format: .dateTime.hour().minute())")
          .font(.nunito(12))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
  }

  /// „Heute“ / „Gestern“ / Datum – passend zur Telefon-App.
  private static func dayLabel(for date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Heute" }
    if calendar.isDateInYesterday(date) { return "Gestern" }
    return date.formatted(.dateTime.day().month(.twoDigits).year())
  }
}

private struct EmptyStateView: View {
  /// true, solange die Uhr noch nie Daten vom iPhone bekommen hat.
  let neverSynced: Bool

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: neverSynced ? "iphone.slash" : "tray")
        .font(.largeTitle)
        .foregroundStyle(MhW.minze300)
      Text(neverSynced ? "Noch keine Daten" : "Keine Einträge")
        .font(.nunitoBold(15))
        .foregroundStyle(MhW.textHell)
      Text(
        neverSynced
          ? "Öffne die App auf dem iPhone, damit die Einträge übertragen werden."
          : "Es wurden noch keine Medikamente erfasst."
      )
      .font(.nunito(12))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
    }
    .padding()
  }
}

#Preview {
  ContentView().environmentObject(WatchStore())
}

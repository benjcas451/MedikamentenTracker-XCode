import SwiftUI

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
                  RoundedRectangle(cornerRadius: 12).fill(MhUhr.surface))
            }
            Section {
              ForEach(snapshot.entries) { entry in
                EntryRow(entry: entry)
                  .listRowBackground(
                    RoundedRectangle(cornerRadius: 12).fill(MhUhr.surface))
              }
            } header: {
              Text("Zuletzt")
                .font(.figtreeMedium(13, relativeTo: .footnote))
                .foregroundStyle(MhUhr.textSecondary)
            }
            if let updatedAt = snapshot.updatedAt {
              Section {
                Text("Stand: \(updatedAt, style: .relative)")
                  .font(.figtree(12, relativeTo: .footnote))
                  .foregroundStyle(MhUhr.textSecondary)
                  .listRowBackground(Color.clear)
              }
            }
          }
        }
      }
      // Ohne Emoji – auf dem schmalen Display bräche der Titel sonst um.
      .navigationTitle("Medikamente")
    }
    .tint(MhUhr.primary)
  }
}

/// Tages- und Wochenzähler als Kopfzeile.
private struct TodaySummary: View {
  let today: Int
  let week: Int

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Heute").font(.figtreeMedium(12, relativeTo: .caption)).foregroundStyle(MhUhr.textSecondary)
        // Große Zahlen dünn in Textfarbe (Guide 2.0).
        Text("\(today)").font(.figtree(22, relativeTo: .title3)).foregroundStyle(MhUhr.textStrong)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text("7 Tage").font(.figtreeMedium(12, relativeTo: .caption)).foregroundStyle(MhUhr.textSecondary)
        Text("\(week)").font(.figtree(18, relativeTo: .headline)).foregroundStyle(MhUhr.textStrong)
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
        .font(.figtreeMedium(15, relativeTo: .headline))
        .foregroundStyle(MhUhr.textStrong)
        .lineLimit(2)
      if let time = entry.time {
        Text("\(Self.dayLabel(for: time)) · \(time, format: .dateTime.hour().minute())")
          .font(.figtree(12, relativeTo: .footnote))
          .foregroundStyle(MhUhr.textSecondary)
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
        .foregroundStyle(MhUhr.link)
      Text(neverSynced ? "Noch keine Daten" : "Keine Einträge")
        .font(.figtreeSemiBold(15, relativeTo: .headline))
        .foregroundStyle(MhUhr.textStrong)
      Text(
        neverSynced
          ? "Öffne die App auf dem iPhone, damit die Einträge übertragen werden."
          : "Es wurden noch keine Medikamente erfasst."
      )
      .font(.figtree(12, relativeTo: .footnote))
      .foregroundStyle(MhUhr.textSecondary)
      .multilineTextAlignment(.center)
    }
    .padding()
  }
}

#Preview {
  ContentView().environmentObject(WatchStore())
}

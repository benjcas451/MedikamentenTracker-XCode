# Medikamenten-Tracker (iOS + watchOS)

Native iOS-App zur Erfassung eingenommener Medikamente (Freitext +
Zeitpunkt), mit eingebetteter watchOS-App. Swift, SwiftUI, keine externen
Abhängigkeiten (kein SPM, keine Pods). Portiert von einer Flutter-App —
Bestandsdaten und -einstellungen werden beim App-Store-Update nahtlos
übernommen (Details unten).

Schwester-Repos: **MedikamentenTracker-Android** (gleicher Funktionsumfang,
gleiches Design) und **StillzeitTracker-XCode/-Android** (gleiche
Architektur- und Design-Familie).

---

## Targets

| Target | Was | Bundle-ID |
|---|---|---|
| `medikamente` | iPhone-App (SwiftUI, iOS 16+) | `org.dwarftsch.medikamente` |
| `MedikamenteWatch` | watchOS-App (SwiftUI, watchOS 9+), im App-Bundle eingebettet | `org.dwarftsch.medikamente.watchkitapp` |
| `medikamenteTests` / `medikamenteUITests` | Test-Templates | — |

Alle Targets sind bewusst **auf iOS/watchOS beschränkt**
(`SUPPORTED_PLATFORMS`) — macOS/visionOS wieder zu aktivieren bricht
Xcode-Cloud-Workflows und den WatchConnectivity-Code. Ebenso bleibt
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (der MainActor-Default des
Templates bricht Delegate-Callbacks); der Code ist unter
`SWIFT_STRICT_CONCURRENCY=complete` warnungsfrei.

## Einrichtung auf einem neuen Gerät

1. Repo klonen, `medikamente.xcodeproj` in **Xcode 16 oder neuer** öffnen
   (Projektformat `objectVersion 77` mit synchronisierten Ordner-Gruppen:
   Dateien im Ordner erscheinen automatisch im Target).
2. **Signing:** Automatic Signing; in den Target-Einstellungen das eigene
   Team wählen, falls abweichend. Für Simulator-Builds ist kein
   Zertifikat nötig.
3. Bauen/Starten: Scheme `medikamente` (iPhone) bzw. `MedikamenteWatch`
   (Uhr) auf einem Simulator. Das war's — keine weiteren Setup-Schritte.

```bash
# CLI-Äquivalente
xcodebuild -project medikamente.xcodeproj -scheme medikamente \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project medikamente.xcodeproj -scheme MedikamenteWatch \
  -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build
```

Watch-Test im Simulator: gekoppeltes Paar booten (`xcrun simctl list pairs`),
iPhone-App starten — sie schiebt den aktuellen Stand per
`updateApplicationContext` auf die Uhr.

## Versionierung & Build-Nummern

- `MARKETING_VERSION`: im Projekt gepflegt, **auf App- und Watch-Target
  identisch halten** (Apple verlangt übereinstimmende
  `CFBundleShortVersionString` von Companion und Watch-App).
  **Konvention:** Major/Minor (1.x.x, x.1.x) über alle Plattformen
  (iOS **und** Android) identisch; die Patch-Stelle darf pro Plattform
  divergieren.
- `CURRENT_PROJECT_VERSION` gilt nur für **lokale** Archive.
  **Xcode Cloud überschreibt die Build-Nummer mit seiner eigenen
  fortlaufenden Zählung** — App Store Connect verlangt steigende
  Build-Nummern nur *innerhalb desselben Versions-Strings*. Kollidiert
  ein Cloud-Build mit einer bereits hochgeladenen Nummer: Patch-Version
  anheben oder in ASC → Xcode Cloud → „Next Build Number“ setzen.
- **Generischer TestFlight-Installationsfehler?** Erst Geräte-Logs ziehen
  (`sudo log collect --device-name … --last 5m`) statt raten. Bekannter
  Fall in dieser App-Familie: ein DNS-Filter (NextDNS) blockte
  Apple-Endpunkte (`xp.apple.com`), die TestFlight-ServiceExtension
  crashte daran — Fix ist eine Allowlist-Freigabe, kein Build-Problem.
- Die Flutter-App war zuletzt als 1.2.x (Build ≤ 6) im Store; die native
  App startet als **2.0.0**.

## CI / Releases (`.github/workflows/build-ipa.yml`)

Manuell per *workflow_dispatch*: baut eine **unsignierte IPA**
(inkl. eingebetteter Watch-App) und hängt sie an ein GitHub-Release
(`v<version>-<run_number>`). Unsignierte IPAs sind **nicht**
Transporter-tauglich — App-Store-Uploads laufen über Xcode
(Archive/Organizer) oder Xcode Cloud. Beim Anlegen eines
Xcode-Cloud-Workflows darauf achten, dass nur iOS-Archive-Aktionen
enthalten sind (stale macOS/visionOS-Aktionen manuell entfernen).

## Herkunft & Datenmigration (Flutter → nativ)

Die App ersetzt eine Flutter-App unter derselben Bundle-ID. Beim Update
bleiben alle Nutzerdaten erhalten (im Simulator verifiziert; der
Container-UUID-Wechsel beim Update ist normal, der Inhalt zieht um):

- **SQLite:** identische Datei `medikamenten_demo.db` im Documents-Ordner,
  identisches Schema, `PRAGMA user_version = 1`. Zeitstempel als ISO 8601
  UTC; der Parser (`IsoZeit`) toleriert auch die Mikrosekunden-Präzision
  alter Dart-Einträge (`ISO8601DateFormatter` allein kann das nicht).
- **Einstellungen:** Flutters shared_preferences landet auf iOS in den
  UserDefaults derselben App, nur mit Präfix `flutter.`. Einmalige
  Migration in die nativen Keys, siehe `AppSettings.migrationAusfuehren()`.
- **Watch:** Payload-Format des Application-Context ist identisch zur
  Flutter-App (`WatchSyncPlugin`) — eine bereits installierte Watch-App
  läuft nahtlos weiter.

## Architektur

```
medikamente/                     iPhone-App
  Models.swift                   MedEntry/MedCount/PeriodStats/MedStats, IsoZeit-Parser
  MedService.swift               Protokoll der Datenquellen + Factory
  DemoService.swift              lokale SQLite (sqflite-kompatibel, C-API, serielle Queue)
  ApiService.swift               REST-Client (URLSession; api.php-Actions, mTLS via Delegate)
  Netzfehler.swift               Einordnung: nie gesendet vs. mehrdeutig
  OfflineService.swift           Offline-Hülle, Warteschlange + Lesestand,
                                 Verbindungswache (NWPathMonitor)
  CloudflareServiceToken.swift   Service-Token-Header + Erkennung der
                                 Access-Abweisung (Redirect auf die Login-Seite)
  ClientIdentity.swift           PEM (crt/key) -> SecIdentity (Keychain)
  CertSource.swift               client.crt/client.key: App-Ordner oder frei
                                 gewählter Ordner (security-scoped Bookmark)
  AppOrdner.swift                hält den App-Ordner in der Dateien-App sichtbar
  AppSettings.swift              UserDefaults + Flutter-Migration
  LocalBackupService.swift       JSON-Backup (Format kompatibel zu Android/Flutter)
  WatchSync.swift                schiebt Snapshots an die Uhr (updateApplicationContext)
  MhTheme.swift                  Minze & Honig 2.0: Rollen hell/dunkel, Figtree, Typo-Skala
  MhBausteine.swift              2.0-Bausteine (Kopf, Buttons, Segmente, Listen, Felder …)
  Bausteine.swift                App-eigene Bausteine (Fokusrand, verdecktes Feld, Datumstexte)
  Bildschirmfotos.swift          erfundene Testdaten für die Bildschirmfotos (nur Debug)
  HomeView/HomeViewModel/SettingsView.swift   UI
MedikamenteWatch/                watchOS-App (read-only Anzeige)
  MedEntry.swift                 Eintrag + Snapshot (Payload-Parsing)
  WatchStore.swift               empfängt/cached den Application-Context
  MhUhr.swift                    dunkle 2.0-Rollen + Figtree (über UIAppFonts)
  ContentView.swift              UI
```

**Datenquellen (vom Nutzer wählbar):** Server per mTLS-Client-Zertifikat
(API-Key optional zusätzlich), Server per API-Key (`X-API-Key`-Header),
Server hinter Cloudflare Access per Service Token (API-Key ebenfalls
optional zusätzlich) oder lokale SQLite ohne Sync.

Der Cloudflare-Modus (seit 2.1.0) sendet `CF-Access-Client-Id` und
`CF-Access-Client-Secret`. Beide Hälften liegen in eigenen Keychain-Accounts
(`cf-access-client-id`, `cf-access-client-secret`) und gehen nur gemeinsam
raus — ein halbes Token weist Cloudflare genauso ab wie gar keines.

**Access-Abweisung:** Ohne gültiges Token antwortet Cloudflare nicht mit
einem Fehler, sondern leitet auf die Login-Seite des Teams um. `URLSession`
folgt dem, sodass eine HTML-Seite mit Status 200 ankommt. `ApiService`
erkennt das am Host der finalen Antwort (Subdomain von
`cloudflareaccess.com`) bzw. an einem 403 mit `cf-ray`-Header und meldet es
als Token-Problem. Die Uhr ist davon nicht betroffen: sie spricht nie selbst
mit dem Server.

## Offline-Betrieb

Bricht die Verbindung weg, bleibt die App benutzbar. `OfflineService` legt
sich dafür über die Server-Quelle (nur in den Server-Modi, nicht im Demo).

**Lesen:** Nach jedem erfolgreichen Laden liegen Einträge und Statistik als
JSON in `Application Support/Offline/` (getrennt, weil die Oberfläche beide
nebenläufig lädt). Scheitert das Laden an einem Netzwerkfehler, zeigt die App
diesen Stand statt einer leeren Liste.

**Schreiben:** Was nicht rausging, landet in einer Warteschlange und geht
raus, sobald die Verbindung steht. In die Warteschlange darf eine Aktion
**nur**, wenn sie den Server nachweislich nie erreicht hat (kein Netz, DNS,
Verbindungsaufbau, TLS). Eine Zeitüberschreitung oder ein Abbruch mitten in
der Übertragung ist mehrdeutig — der Server könnte den Eintrag längst haben,
ein zweiter Versuch legte dann einen zweiten an.

**Warteschlange.** Neue Einträge bekommen eine negative lokale ID und
erscheinen sofort in der Liste (mit Uhr-Symbol). Eine Löschung, die einen noch
wartenden Eintrag trifft, entfernt dessen `anlegen`-Aktion ersatzlos — dadurch
beziehen sich alle verbleibenden Löschungen auf echte Server-IDs. Solange
etwas ansteht, geht auch ein neuer Schreibzugriff hinten dran statt am Stau
vorbei.

**`undoLast` wird bewusst nicht vorgemerkt.** Wartet noch ein Eintrag, nimmt
die App ihn direkt aus der Warteschlange. Ist die Warteschlange leer, muss der
Server ran; offline meldet das einen Fehler. Grund: Die API kennt für
`undoLast` keine ID, beim Nachholen träfe es womöglich einen Eintrag, den
jemand anders inzwischen angelegt hat.

**Statistik.** Wartende Einträge werden vollständig eingerechnet, inklusive
der Aufschlüsselung je Medikament — anders als beim Wickel-Tracker sind das
hier reine Zählungen und keine Prozentanteile.

**Abgearbeitet** wird vor jedem Laden, beim Zurückkehren aus dem Hintergrund
und sobald `NWPathMonitor` wieder einen Pfad meldet. Beim ersten
Verbindungsfehler bricht der Durchlauf ab, der Rest bleibt in der Reihenfolge
stehen. Vom Server inhaltlich zurückgewiesene Aktionen fliegen raus und werden
einmal gemeldet.

Die Ablage hängt am Zugang (Modus + Basis-URL).

## Watch-Protokoll (WatchConnectivity)

Reiner **Push** vom iPhone zur Uhr — die Uhr spricht nie selbst mit dem
Server. Nach jedem Laden überträgt `WatchSync.push` per
`updateApplicationContext` (iOS hält nur den neuesten Stand vor und
liefert ihn aus, sobald die Uhr erreichbar ist):

```
{"updatedAt": ISO8601, "todayTotal": n, "weekTotal": n,
 "entries": [{"medikament": "...", "time": ISO8601}, …]}   // max. 25
```

Die Uhr cached den Stand in ihren UserDefaults (`last_snapshot`) und kann
ihn darum auch ohne iPhone in Reichweite anzeigen. **Format identisch zur
abgelösten Flutter-Strecke — Änderungen immer mit der Android-App und
diesem Format abstimmen.**

## REST-API & Datenmodell

Basis-URL konfiguriert der Nutzer in den Einstellungen; alle Endpunkte
liegen unter `<Basis-URL>api.php`. Alle Antworten JSON.

| Endpunkt | Zweck |
|---|---|
| `GET api.php?action=stats` | Statistik je Zeitraum (today, week, threeWeeks, month) mit total + Zählung je Medikament, plus `last` |
| `GET api.php?action=list[&limit=N]` | Einträge, neueste zuerst |
| `GET api.php?action=last` | letzter Eintrag |
| `POST api.php?action=add` | Eintrag anlegen: `{"medikament": "...", "time": "<ISO8601, optional>"}` |
| `POST api.php?action=delete` | Eintrag löschen: `{"id": 42}` |
| `POST api.php?action=undo_last` | letzten Eintrag löschen (404 = keiner vorhanden) |

Eintrag: `id`, `medikament` (Freitext), `time` (ISO 8601). Fehler:
`{"error": "..."}` mit passendem HTTP-Status. Die lokale Tabelle
`entries(id, medikament, time)` spiegelt exakt dieses Modell.

## Sicherung & Gerätewechsel

Auf iOS gibt es kein Gegenstück zu Androids `backup_rules.xml` /
`data_extraction_rules.xml`. Gesteuert wird über die Dateiablage
(`Documents` wird gesichert, `Library/Caches` und `tmp` nicht),
`isExcludedFromBackup` und die Keychain-Attribute.

| | iCloud-Backup | Direkttransfer (Schnellstart) |
|---|---|---|
| Einträge (SQLite) | ✅ | ✅ |
| API-Key & Service Token (Keychain) | ❌ | ✅ |
| Client-Zertifikat | ❌ | ❌ |

Der API-Key und beide Hälften des Cloudflare Service Tokens liegen in der
Keychain, mit `kSecAttrAccessibleAfterFirstUnlock`
und **ohne** `kSecAttrSynchronizable`. Damit sind sie beim Direkttransfer und
im verschlüsselten Finder-Backup dabei, aus einem iCloud-Backup dagegen nicht
wiederherstellbar — die iOS-Entsprechung der Android-Entscheidung
„`<device-transfer>` ja, `<cloud-backup>` nein“. Nach einer Wiederherstellung
aus iCloud ist er einmal neu einzutragen. Die Uhr hält keinen eigenen
Schlüssel: sie bekommt ihren Stand per Push vom iPhone und spricht nie
selbst mit dem Server.

Client-Zertifikate (`client.crt` / `client.key`) liegen im App-Ordner der
Dateien-App und sind nach einem Gerätewechsel gegebenenfalls neu abzulegen.
Dafür müssen zwei Dinge zusammenkommen:

1. **`UIFileSharingEnabled` und `LSSupportsOpeningDocumentsInPlace` im
   Bundle.** `UIFileSharingEnabled` steht in `AppInfo.plist` und **nicht**
   als `INFOPLIST_KEY_UIFileSharingEnabled` im Projekt: diesen Schlüssel
   kennt Xcode als Build-Setting nicht und verwirft ihn kommentarlos. Genau
   daran lag es – der Schlüssel stand im Projekt und kam nie im Binary an.
   `GENERATE_INFOPLIST_FILE` bleibt `YES`; Xcode nimmt `AppInfo.plist` als
   Basis und mergt die `INFOPLIST_KEY_*`-Werte hinein.
2. **Mindestens eine sichtbare Datei in `Documents/`.** iOS blendet den
   Ordner sonst aus. `AppOrdner` hält dafür beim Start eine `README.txt`
   vor und legt sie an, sobald sie fehlt – bewusst ohne Leer-Prüfung:
   `contentsOfDirectory` zählt auch unsichtbare Punkt-Dateien mit, für iOS
   gilt der Ordner damit trotzdem als leer.

Der Build-Check liest beide Schlüssel mit `PlistBuddy` aus dem gebauten
Bundle und schlägt fehl, wenn einer nicht `true` ist. Dass beide ankommen –
einer aus der Datei, einer aus den Build-Settings – belegt zugleich, dass
der Merge greift; `CFBundleShortVersionString` wird als zweiter Beleg
mitgeprüft.

Alternativ lässt sich unter *Einstellungen → Server (mTLS-API)* ein
beliebiger anderer Ordner auswählen. Er wird als security-scoped Bookmark
gespeichert. Nach einer Wiederherstellung auf einem neuen Gerät zeigt das
Bookmark ins Leere; die App meldet das und bittet darum, den Ordner erneut
auszuwählen.

Unabhängig davon gibt es das manuelle Backup unter *Einstellungen → Backup*.

## Design-System „Minze & Honig“ 2.0

Maßgeblich ist der Guide im Repo `DesignGuide` (`DESIGN_GUIDE.md`,
`tokens/design-tokens.json`). Im Code: `medikamente/MhTheme.swift` und
`MhBausteine.swift` (iPhone, aus dem gemeinsamen Bausatz) sowie
`MedikamenteWatch/MhUhr.swift` (Uhr). Kernregeln:

- **Farbe ist Signal, keine Fläche.** Keine Pastell-Buttons, -Kacheln oder
  -Karten. Genau eine Hauptaktion je Ansicht (`Mh.primary`: Minze-700 mit
  weißer Schrift, im Dunkeln Minze-400 mit dunkler Schrift), alles andere
  Haarlinie oder Text.
- **Nur Rollen** (`Mh.bg`, `Mh.text`, `Mh.border` …), nie Skalenwerte.
  Dunkel: Grund `#1F2221`, Flächen `#262A28`, Linien `#343A36`, farbiger
  Text nur aus den Stufen 200/300.
- **Haarlinien und Weißraum** statt Karten mit Schatten.
- **Schrift Figtree** 400/500/600 (keine Kursive), Dynamic Type über
  `.mhText(.h1)` usw. iPhone: `UIAppFonts` in `AppInfo.plist`, zusätzlich
  Registrierung zur Laufzeit in `MhDarstellung.einrichten()`; Uhr:
  `UIAppFonts` in `MedikamenteWatch/Info.plist`. Lizenz:
  `licenses/Figtree-OFL.txt` bzw. `Fonts/OFL_FIGTREE.txt`.
- **Liniensymbole** aus dem Bausatz (`Mh*.imageset`, Vorlagenbilder) statt
  Emojis und SF Symbols. Die Uhr behält ihren Aufbau samt SF Symbols; dort
  sind nur Farben und Schrift umgestellt.
- **Hell/Dunkel** folgt dem System.

**Bildschirmfotos:** Der Workflow `screenshots.yml` (Push auf `claude/**`
oder manuell) startet `ScreenshotTests` im Simulator, hell/dunkel und mit
normaler bzw. großer Schrift, und legt die Bilder als Artefakt
„bildschirmfotos“ ab. Die App läuft dabei mit `-MhBildschirmfotos 1` im
lokalen Modus auf einer eigenen Datenbank mit erfundenen Einträgen (nur
Debug-Builds).

## Sicherheit / was nie ins Repo darf

API-Keys, Server-URLs von Nutzern, Zertifikate/private Schlüssel,
Provisioning-Profile. Die App liest Client-Zertifikate ausschließlich zur
Laufzeit aus ihrem Documents-Ordner.

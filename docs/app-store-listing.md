# App Store – Eintrag, Datenschutz & Prüfung

Stand: 2026-11-01, App 1.2.9, Bundle-ID `com.heizungstrainer.heizungstrainer`,
Apple-ID 6829485327, nur iPhone. Pendant zu `play-store-listing.md`.

Kostenlose Startphase (`freeLaunchPhase = true` in `lib/services/license_service.dart`):
Pro ist für alle frei, der Kauf-Bildschirm erscheint nicht. In-App-Kauf
`heizungstrainer_pro` und der Vertrag für kostenpflichtige Apps sind erst nötig,
wenn die Startphase endet (dann In-App-Kauf mit der Version zur Prüfung einreichen).

---

## 1. App-Informationen

| Feld | Wert |
|---|---|
| Name (max. 30) | `Heizungstrainer` |
| Untertitel (max. 30) | `Heizkurve verstehen & sparen` |
| Primäre Kategorie | Dienstprogramme |
| Sekundäre Kategorie | Lifestyle |
| Primäre Sprache | Deutsch |
| Inhaltsrechte | Enthält keine Inhalte Dritter |
| Altersfreigabe | Fragebogen überall „Keine“ / „Nein“ → 4+ |

## 2. Version 1.2.9 (Deutsch)

**Werbetext** (max. 170, jederzeit ohne Prüfung änderbar):

```
Viele Heizungen laufen wärmer als nötig. Heizungstrainer zeigt, wie deine eingestellt ist – und hilft dir, Heizkurve und Zeitprogramm sparsamer zu machen.
```

**Beschreibung** (max. 4000):

```
Viele Heizungen laufen seit Jahren mit den Werkseinstellungen – und damit oft wärmer als nötig. In Studien war die Heizkurve nur bei einem kleinen Teil der Anlagen passend eingestellt.

Heizungstrainer zeigt dir, wie deine Heizung arbeitet, und hilft dir, sie Schritt für Schritt sparsamer einzustellen. Direkt vom iPhone, im eigenen Heimnetz, ohne Konto.

HEIZKURVE VERSTEHEN UND ANPASSEN
• Deine Heizkurve als Diagramm – mit Richtwert für dein Gebäude und Baujahr.
• Basis-Wärme mit einem Regler verschieben, die Kurve flacher oder steiler stellen oder jeden Punkt einzeln ändern.
• Vorher siehst du genau, welche Vorlauftemperaturen geschrieben werden.
• Jede Änderung wird auf Grenzwerte geprüft, an den Regler gesendet und zurückgelesen.

WARM, WENN DU DA BIST
Das Zeitprogramm deines Reglers als übersichtliche Zeitleiste. Lege fest, wann es warm sein soll und wie stark nachts oder tagsüber abgesenkt wird – oder wähle eine Vorlage wie „Nachts absenken“ oder „Berufstätig“. Die App schätzt, was das spart.

EINSTELLUNGEN PRÜFEN LASSEN
Der Einstellungs-Check findet typische Fehler: Absenkung wärmer als Komfort, Tage ohne warme Zeit, zu hohe Vorlaufgrenze bei Fußbodenheizung oder eine Zirkulationspumpe, die nachts läuft. Mit einem Tipp behebst du sie.

DEINE ANLAGE LIVE
Außen-, Vorlauf-, Rücklauf- und Warmwassertemperatur auf einen Blick. Für unterstützte Danfoss-Anwendungen zeigt das Anlagenbild Pumpen, Ventile und Fühler mit Ist- und Sollwerten.

URLAUB PLANEN
Abreise und Rückkehr eintragen – die Heizung senkt ab und ist rechtzeitig wieder warm. Beim Danfoss ECL wird der Urlaub im Regler gespeichert und läuft ganz ohne App. Die App zeigt, was eine Woche Urlaub je nach Monat spart.

PASST HEIZUNGSTRAINER ZU DEINER ANLAGE?
• Getestet an echter Hardware: Danfoss ECL Comfort 310 über Ethernet (Modbus TCP).
• Beta: Viessmann, Bosch/Buderus, Vaillant, NIBE, Weishaupt und generisches Modbus – je nach System mit Gateway oder Herstellerkonto, noch nicht an echter Hardware verifiziert.
• Verbrauchsvergleich: Brunata Hamburg. Weitere Messdienstleister folgen.
• Kein passender Regler? Im Demo-Modus kannst du alles ausprobieren.

LOKAL UND PRIVAT
Die App spricht direkt mit deinem Regler im Heimnetz. Messwerte und Zugangsdaten bleiben auf deinem iPhone. Von unterwegs geht es über dein eigenes VPN, etwa WireGuard auf der FRITZ!Box.

IN DER STARTPHASE KOSTENLOS
Alle Funktionen sind in der Startphase kostenlos – ohne Werbung und ohne Abo.

Einsparungen sind Schätzungen; sie hängen von Gebäude, Anlage, Wetter und Nutzung ab. Ein Angebot der Navisense GmbH, ohne Verbindung zu den genannten Herstellern und Messdienstleistern.
```

**Keywords** (max. 100, Komma ohne Leerzeichen, Name/Untertitel nicht wiederholen):

```
Heizung,Danfoss,ECL,Fernwärme,Vorlauf,Thermostat,Modbus,Heizkosten,Energie,Brunata,Zeitprogramm
```

| Feld | Wert |
|---|---|
| Support-URL | https://heizungstrainer.de/kontakt.html |
| Marketing-URL | https://heizungstrainer.de/ |
| Datenschutz-URL | https://heizungstrainer.de/datenschutz.html |
| Copyright | 2026 Navisense GmbH |
| Screenshots 6,9″ | `build/app-store/marketing/01–05` (1320 × 2868): `tool/capture_app_store_marketing_test.dart` (App-Widgets mit Demo-Daten) + `tool/compose_app_store_screenshots.py` (Überschrift + Ausschnitt) |
| Build | aus TestFlight wählen (Export-Compliance: Standard-Verschlüsselung, nicht Frankreich) |
| Veröffentlichung | Manuell veröffentlichen |

## 3. App-Prüfung – Informationen für Apple

Anmeldung erforderlich: **Nein**. Kontakt: Name, Telefon, E-Mail des Ansprechpartners.

**Notizen** (Englisch, Apple-Prüfer):

```
No account or login is needed. The app controls a heating controller on the local network (e.g. Danfoss ECL Comfort 310 via Modbus TCP), which reviewers won't have.

To test: on the first screen tap "Ohne Regler ausprobieren (Demo)" (Try without controller). All features then work with simulated values: live values and plant diagram ("Live" tab), heating curve and Basis-Wärme slider, holiday planning ("Urlaub"), backups ("Backup"), comparison ("Vergleich"). No real heating is controlled in demo mode.

Local network access: the app asks for it once, because it searches for and talks to the user's heating controller in the home network (Modbus TCP, port 502). In demo mode nothing is sent to the network.

Pro features are free for everyone during the launch phase; there are no purchases in this version.

Billing portals (e.g. Brunata Hamburg) need the tenant's own credentials; the other providers show clearly labelled example data.
```

## 4. App-Datenschutz (Fragebogen)

„Erfassen Sie Daten?“ → **Ja**, nur diese, jeweils *nicht mit der Identität verknüpft*, *kein Tracking*:

| Datentyp | Zweck | Wann |
|---|---|---|
| Kontaktinfos → E-Mail-Adresse | App-Funktionalität (Antwort auf Feedback) | nur wenn beim Feedback freiwillig angegeben |
| Nutzerinhalte → Sonstige Nutzerinhalte | App-Funktionalität | Feedback-Text, nur beim Absenden |
| Diagnose → Sonstige Diagnosedaten | App-Funktionalität | Diagnosebericht (Protokoll, App-/OS-Version, Reglertyp), nur nach Bestätigung |

Nicht erfasst: Standort, Kennungen, Nutzungsdaten, Kaufdaten (Startphase), Gesundheit, Finanzen.
Regler-Messwerte, Einstellungen und Zugangsdaten zu Abrechnungsportalen bleiben auf dem Gerät
(Portal-Logins gehen direkt vom Gerät an das jeweilige Portal, nicht an Heizungstrainer).
Server: bo.heizungstrainer.de (Feedback/Diagnose).

## 5. Einreichen

1. Version 1.2.9 ausfüllen (oben), Build auswählen, Screenshots hochladen.
2. „Zur Prüfung hinzufügen“ → „Zur Prüfung einreichen“.
3. Nach Freigabe: „Diese Version veröffentlichen“ (manuell).
4. Danach: App-Store-Badge auf heizungstrainer.de (Link `https://apps.apple.com/de/app/id6829485327`).

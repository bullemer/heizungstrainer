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
Heizkurve und Zeitprogramm deines Danfoss ECL verstehen und anpassen – mit Vorschau, Sicherheitsprüfung und Spartipps. In der Startphase kostenlos.
```

**Beschreibung** (max. 4000):

```
Warum läuft die Heizung so warm? Passt die Heizkurve zum Haus? Und was spart eine Woche Urlaub?

Heizungstrainer macht deine Heizungsanlage verständlich. Sieh aktuelle Temperaturen, prüfe Einstellungen und passe sie gezielt an – direkt auf deinem iPhone.

DEINE HEIZUNG AUF EINEN BLICK
• Live-Werte für Außen-, Vorlauf-, Rücklauf- und Warmwassertemperatur, abhängig von Regler und Sensoren.
• Anlagenbild für unterstützte Danfoss-Anwendungen: Temperaturen, Pumpen und Ventile im Zusammenhang.
• Einstellungs-Check: Hinweise auf auffällige Einstellungen und wie du sie behebst.

HEIZKURVE VERSTEHEN UND GEZIELT ANPASSEN
• Heizkurve als Diagramm mit Richtwerten für deinen Gebäudetyp.
• Basis-Wärme verschieben oder die Kurve flacher bzw. steiler stellen – mit Vorschau der neuen Vorlauftemperaturen.
• Jede Änderung wird gegen Grenzwerte geprüft, an den Regler gesendet und zurückgelesen.
• Einstellungen sichern und bei Bedarf wiederherstellen.

WANN SOLL ES WARM SEIN?
Das Zeitprogramm deines Reglers als Zeitleiste: warme Zeiten und Absenkung pro Tag ändern oder eine Vorlage wählen – „Nachts absenken“ oder „Berufstätig“.

URLAUB UND ABWESENHEIT
Plane Absenkung und Rückkehr. Bei unterstützten Danfoss-ECL-Anwendungen wird der Urlaub im Regler gespeichert und läuft ohne App. Die App zeigt, was eine Woche Urlaub je nach Monat spart.

PASST HEIZUNGSTRAINER ZU DEINER ANLAGE?
• An echter Hardware getestet: Danfoss ECL Comfort 310 über Ethernet und Modbus TCP.
• Als Beta vorhanden: Viessmann, Bosch/Buderus, Vaillant, NIBE, Weishaupt und generisches Modbus. Je nach System sind ein Gateway, ein Adapter oder ein Herstellerkonto nötig. Diese Anbindungen sind noch nicht an echter Hardware verifiziert.
• Verbrauchsanalyse: Brunata Hamburg. Weitere Messdienstleister folgen.
• Noch kein passender Regler? Probiere alles im Demo-Modus aus.

LOKAL IM HEIMNETZ
Die App verbindet sich direkt mit deiner Anlage im lokalen Netzwerk – ohne Heizungstrainer-Konto. Dafür fragt iOS einmal nach dem Zugriff auf das lokale Netzwerk. Fernzugriff ist über dein eigenes VPN möglich, etwa WireGuard auf der FRITZ!Box.

IN DER STARTPHASE KOSTENLOS
Alle Funktionen sind während der Startphase kostenlos, ohne Werbung und ohne Abo.

Einsparungen sind Schätzungen; das Ergebnis hängt von Gebäude, Anlage, Wetter und Nutzung ab.

Ein Angebot der Navisense GmbH. Keine Verbindung zu den genannten Geräteherstellern oder Messdienstleistern.
```

**Keywords** (max. 100, Komma ohne Leerzeichen, Name/Untertitel nicht wiederholen):

```
Heizung,Danfoss,ECL,Fernwärme,Vorlauf,Thermostat,Modbus,Heizkosten,Energie,Urlaub,Brunata,Zeitprogramm
```

| Feld | Wert |
|---|---|
| Support-URL | https://heizungstrainer.de/kontakt.html |
| Marketing-URL | https://heizungstrainer.de/ |
| Datenschutz-URL | https://heizungstrainer.de/datenschutz.html |
| Copyright | 2026 Navisense GmbH |
| Screenshots 6,9″ | `~/Downloads/heizungstrainer-appstore/01–04` (1320 × 2868), erzeugt mit `HEIZUNG_SCREENSHOT_TARGET=ios` (siehe `tool/capture_store_screenshots_test.dart`) |
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

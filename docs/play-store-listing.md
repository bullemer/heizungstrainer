# Google Play – Store-Eintrag & Data safety

Stand: 2026-10-07, App 1.1.8 (Build 10), Paket `com.heizungstrainer.heizungstrainer`.
Alles hier entspricht dem, was die App tatsächlich tut (geprüft am Code). Bei
Änderungen an Netzwerkzugriffen oder Berechtigungen diese Datei mit anpassen.

---

## 1. App erstellen

| Feld | Wert |
|---|---|
| App-Name | Heizungstrainer |
| Standardsprache | Deutsch – de-DE |
| App oder Spiel | App |
| Kostenlos oder kostenpflichtig | Kostenlos (In-App-Kauf später möglich) |

## 2. Hauptseite des Store-Eintrags (de-DE)

**App-Name** (max. 30): `Heizungstrainer: Heizkurve`

**Kurzbeschreibung** (max. 80):

```
Heizkurve verstehen und einstellen – direkt am Regler, lokal im Heimnetz.
```

**Vollständige Beschreibung** (max. 4000):

```
Heizungstrainer zeigt dir, was deine Heizung gerade tut – und hilft dir, sie sparsamer einzustellen. Die App verbindet sich direkt im Heimnetz mit deinem Heizungsregler, ohne Cloud und ohne Benutzerkonto.

UNTERSTÜTZTE REGLER
• Danfoss ECL Comfort 310 (Modbus TCP über Ethernet): vollständig unterstützt und an echter Hardware getestet.
• Viessmann (ViCare), Bosch/Buderus (KM200), Vaillant (ebusd), NIBE, Weishaupt und generisches Modbus: als Beta. Diese Regler werden standardmäßig nur gelesen; Schreiben musst du pro Regler ausdrücklich freischalten.
• Ohne passenden Regler kannst du alles im Simulationsmodus ausprobieren.

WAS DIE APP KANN
• Live-Messwerte: Außen-, Vorlauf-, Rücklauf- und Warmwassertemperatur.
• Deine echte Heizkurve als Diagramm – mit Werkseinstellung und Richtwert-Bereich für deinen Gebäudetyp (Heizkörper, Fußbodenheizung, Baujahr).
• Heizkurve einstellen: Komfort-Raumsollwert bzw. Parallelverschiebung vom Sofa aus. Jede Änderung wird gegen Grenzwerte geprüft und anschließend vom Regler zurückgelesen.
• Heizkurven-Simulator: Siehst du, wie sich eine Änderung auswirkt, bevor du sie an den Regler schickst – mit geschätzter Ersparnis in kWh und Euro.
• Optimierungs-Assistent: findet in kleinen Schritten die niedrigste Einstellung, die sich noch angenehm anfühlt.
• Urlaubsmodus: senkt während deiner Abwesenheit ab und stellt rechtzeitig vor der Rückkehr zurück (solange die App läuft und den Regler erreicht).
• Sicherungen: Reglereinstellungen speichern und wiederherstellen.
• Verbrauchsanalyse: Monatswerte aus dem Mieterportal von Brunata Hamburg, mit Vorjahres- und Liegenschaftsvergleich. Weitere Portale sind in Vorbereitung.
• Aktivitätsprotokoll: Jeder Lese- und Schreibbefehl wird lokal protokolliert.

STARTPHASE: ALLES KOSTENLOS
Heizungstrainer ist neu. Deshalb sind in der Startphase alle Funktionen kostenlos – ohne Werbung, ohne Abo. Wer die App jetzt installiert, behält alle Funktionen dauerhaft, auch falls später eine kostenpflichtige Pro-Version kommt.

DATENSCHUTZ
Deine Messwerte und Zugangsdaten bleiben auf deinem Handy (verschlüsselt im Android-Schlüsselspeicher). Die App verbindet sich direkt mit deinem Regler bzw. mit dem Portal deines Messdienstleisters. An uns geht nur etwas, wenn du selbst Feedback oder einen Diagnosebericht schickst.

DEINE MEINUNG ZÄHLT
Sag uns, was gut läuft und was fehlt: in der App unter Einstellungen → Feedback senden oder im Forum auf heizungstrainer.de.

HINWEISE
• Für die Verbindung muss dein Regler im selben Netzwerk erreichbar sein (beim Danfoss ECL 310: Ethernet, Modbus TCP Port 502). Von unterwegs geht das über dein eigenes VPN, z. B. WireGuard auf der FRITZ!Box.
• Android verlangt die Standortberechtigung, damit die App das WLAN erkennen und den Regler im Heimnetz finden kann. Dein Standort wird weder gespeichert noch übertragen. Alternativ kannst du die IP-Adresse des Reglers von Hand eingeben.
• Heizungstrainer ist ein Angebot der Navisense GmbH, Hamburg, und steht in keiner Verbindung zu den genannten Herstellern und Messdienstleistern.
```

**Grafiken** (Pflicht):
- App-Symbol 512×512 PNG (32-bit, Alpha)
- Feature-Grafik 1024×500 JPG/PNG
- Screenshots: assets/branding/screenshots/01–06 (1080×2109, Demo-Modus, Status-/Navigationsleiste abgeschnitten wegen Play-Limit 2:1)
- Icon: assets/branding/play_icon_512.png · Feature-Grafik: assets/branding/play_feature_1024x500.png

## 3. Store-Einstellungen

| Feld | Wert |
|---|---|
| App-Kategorie | Haus & Wohnen |
| Tags | Smart Home, Energie, Werkzeuge (Auswahl in der Console) |
| E-Mail | support@heizungstrainer.de |
| Website | https://heizungstrainer.de/ |
| Telefon | leer lassen (optional) |

## 4. App-Inhalte (Policy → App content)

| Abschnitt | Antwort |
|---|---|
| Datenschutzerklärung | https://heizungstrainer.de/datenschutz.html |
| App-Zugriff | „Alle oder einige Funktionen sind eingeschränkt“ → Anleitung unten |
| Werbung | Nein, enthält keine Werbung |
| Einstufung des Inhalts | siehe 5. |
| Zielgruppe | 18 Jahre und älter (nur diese Altersgruppe) |
| Nachrichten-App | Nein |
| COVID-19-Apps | Nein |
| Behörden-App | Nein |
| Finanzfunktionen | Keine |
| Gesundheit | Keine Gesundheitsfunktionen |
| Data safety | siehe 6. |

**App-Zugriff – Anleitung für die Prüfer:** (Benutzername/Passwort leer lassen – keine eigenen Brunata-Zugangsdaten hinterlegen)

```
Kein Benutzerkonto und kein Login nötig. Die App steuert einen Heizungsregler im lokalen Netzwerk (z. B. Danfoss ECL Comfort 310 per Modbus TCP), den Prüfer nicht haben. Zum Testen auf dem ersten Bildschirm unten „Ohne Regler ausprobieren (Demo)“ tippen (alternativ: Einstellungen → Heizungsregler → beim ausgewählten Regler „Simulation testen“). Danach sind alle Funktionen (Messwerte, Heizkurve, Urlaubsmodus, Sicherungen) mit simulierten Werten nutzbar; es wird keine echte Heizung angesteuert. Das Abrechnungsportal Brunata Hamburg braucht echte Mieter-Zugangsdaten (keine Test-Zugänge vorhanden); die Verbrauchsanalyse lässt sich ohne Zugangsdaten testen: Einstellungen → Messdienstleister & Abrechnung → z. B. „Techem Smart System“ wählen → simulierte Verbrauchsdaten.
```

## 5. Einstufung des Inhalts (IARC-Fragebogen)

- E-Mail: support@heizungstrainer.de
- Kategorie: **Alle anderen App-Typen** (nicht Spiel, nicht Social/Kommunikation)
- Gewalt, Sexualität, Sprache, Drogen, Glücksspiel, Horror: **Nein**
- Können Nutzer miteinander interagieren oder Inhalte austauschen? **Nein** (Feedback geht nur an den Entwickler; das Forum ist eine externe Website)
- Teilt die App den Standort des Nutzers mit anderen? **Nein**
- Digitale Käufe? **Nein** (Stand jetzt; erst ändern, wenn Pro-Kauf kommt)
- Uneingeschränkter Internetzugang/Webbrowser? **Nein**

Erwartetes Ergebnis: USK 0 / PEGI 3.

## 6. Data safety (Datensicherheit)

### Grundfragen

| Frage | Antwort |
|---|---|
| Erhebt oder teilt deine App erforderliche Nutzerdatentypen? | **Ja** |
| Werden alle Daten bei der Übertragung verschlüsselt? | **Ja** (alle Übertragungen an uns per HTTPS) |
| Bietest du eine Möglichkeit an, die Löschung der Daten anzufordern? | **Ja** – per E-Mail an support@heizungstrainer.de oder Kontaktformular |
| Konten | Die App hat keine Benutzerkonten → keine Konto-Lösch-URL nötig |

### Erhobene Datentypen

Alle **„erhoben“ = Ja, „geteilt“ = Nein, „nur vorübergehend verarbeitet“ = Nein,
„optional“ = Ja** (Nutzer entscheidet selbst, ob er sendet).

| Kategorie → Datentyp | Wann | Zwecke |
|---|---|---|
| Personenbezogene Daten → **E-Mail-Adresse** | nur wenn im Feedback-Formular angegeben | App-Funktionen (Antwort auf Feedback) |
| App-Aktivität → **Andere nutzergenerierte Inhalte** | Text einer Feedback-Nachricht | App-Funktionen, Analysen (Verbesserung der App) |
| App-Informationen und -Leistung → **Absturzprotokolle** | Fehlereinträge im Diagnosebericht (nur nach ausdrücklicher Zustimmung im Protokoll-Tab) | App-Funktionen, Analysen |
| App-Informationen und -Leistung → **Diagnosedaten** | Diagnosebericht; App-/Android-Version + Reglertyp beim Feedback | App-Funktionen, Analysen |

Alles andere: **nicht erhoben**. Insbesondere:
- **Standort: nicht erheben.** Die Berechtigung dient nur der WLAN-/Geräteerkennung; nichts verlässt das Gerät.
- **Geräte-IDs, Werbe-ID, Kontakte, Fotos, Finanzdaten: nicht erhoben.**
- **Zugangsdaten für Brunata/Viessmann:** werden nur auf dem Gerät gespeichert und gehen direkt an den Dienst, den der Nutzer selbst ausgewählt hat. Navisense erhält sie nie → keine Erhebung durch uns.
- **Messwerte des Reglers:** bleiben lokal (Modbus im Heimnetz).
- **Energiepreis-Abfrage** (api.energy-charts.info): reine Abfrage öffentlicher Preisdaten, keine Nutzerdaten.

### Vorschau, wie es im Store erscheint

- Keine Daten werden an Dritte weitergegeben
- Erhobene Daten: Personenbezogene Daten, App-Aktivität, App-Informationen und -Leistung
- Daten werden bei der Übertragung verschlüsselt
- Du kannst die Löschung der Daten anfordern

## 7. Release-Hinweise (Interner Test / später Produktion)

```
<de-DE>
Erste Play-Version – in der Startphase mit allen Funktionen kostenlos.
• Heizkurve auslesen, simulieren und einstellen (Danfoss ECL Comfort 310)
• Urlaubsmodus, Sicherungen, Verbrauchsanalyse (Brunata Hamburg)
• Feedback direkt aus der App
</de-DE>
```

## 8. Später, wenn Pro kostenpflichtig wird

- In-App-Produkt `heizungstrainer_pro` anlegen (Einmalkauf).
- Einstufung: „Digitale Käufe“ → Ja; Data safety: Kaufverlauf prüfen (die App speichert die Kauf-ID lokal; Google verarbeitet den Kauf).
- Store-Text „Startphase“ anpassen, Early-Adopter-Zusage beibehalten.

# Google Play – Store-Eintrag & Data safety

Stand: 2026-10-14, App 1.2.1 (Build 32), Paket `com.heizungstrainer.heizungstrainer`.
Store-Texte anhand des Codes aktualisiert. Die Data-safety-Angaben in Abschnitt 6
sind ein Arbeitsentwurf und vor Produktion mit den tatsächlichen Diensten abzugleichen.

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
Heizung verstehen, Heizkurve optimieren und Verbrauch mit Brunata vergleichen.
```

**Vollständige Beschreibung** (max. 4000):

```
Warum läuft die Heizung so warm? Passt die Heizkurve zum Haus? Und wie entwickelt sich dein Verbrauch?

Heizungstrainer macht deine Heizungsanlage verständlich. Sieh aktuelle Temperaturen, prüfe Einstellungen und vergleiche deine Verbrauchswerte – direkt auf deinem Android-Smartphone.

DEINE HEIZUNG AUF EINEN BLICK
• Live-Werte für Außen-, Vorlauf-, Rücklauf- und Warmwassertemperatur, abhängig von Regler und Sensoren.
• Anlagenbild für unterstützte Danfoss-Anwendungen: Temperaturen, Pumpen und Ventile im Zusammenhang sehen.
• Einstellungs-Check: Hinweise auf auffällige Einstellungen und mögliche Verbesserungen.

HEIZKURVE VERSTEHEN UND GEZIELT ANPASSEN
• Heizkurve als Diagramm mit Orientierung für deinen Gebäudetyp.
• Änderungen zuerst im Simulator ausprobieren.
• Bei unterstützten Reglern den Komfort-Raumsollwert oder die Parallelverschiebung anpassen.
• Änderungen werden gegen Grenzwerte geprüft und anschließend vom Regler zurückgelesen.
• Einstellungen sichern und bei Bedarf wiederherstellen.

VERBRAUCH VERGLEICHEN
Verbinde dein Brunata-Hamburg-Konto und behalte deine monatlichen Verbrauchswerte im Blick. Vergleiche sie mit dem Vorjahr und – soweit im Portal verfügbar – mit deiner Liegenschaft. Gemessene Werte und Hochrechnungen werden getrennt dargestellt. Euro-Beträge sind Schätzungen auf Basis des eingestellten Energiepreises, keine Abrechnung.

URLAUB UND ABWESENHEIT PLANEN
Plane die Absenkung und Rückkehr zum normalen Heizbetrieb. Bei unterstützten Danfoss-ECL-Anwendungen wird der Plan im Regler gespeichert. Bei anderen Reglern muss die App laufen und den Regler erreichen.

PASST HEIZUNGSTRAINER ZU DEINER ANLAGE?
• An echter Hardware getestet: Danfoss ECL Comfort 310 über Ethernet und Modbus TCP.
• Als Beta vorhanden: Viessmann, Bosch/Buderus, Vaillant, NIBE, Weishaupt und generisches Modbus. Je nach System sind ein kompatibles Gateway, ein Adapter oder ein Herstellerkonto erforderlich. Diese Anbindungen sind noch nicht an echter Hardware verifiziert.
• Verbrauchsanalyse: Brunata Hamburg. Weitere Abrechnungsportale sind in Vorbereitung.
• Noch kein passender Regler? Lerne die App im Demo-Modus kennen.

LOKAL IM HEIMNETZ
Für lokale Regler verbindet sich die App direkt mit deiner Anlage. Du brauchst kein Heizungstrainer-Konto. Optionale Hersteller-Clouds und Abrechnungsportale benötigen eigene Zugangsdaten. Fernzugriff auf lokale Regler ist über dein eigenes VPN möglich, etwa WireGuard auf der FRITZ!Box.

Android kann für die WLAN-Erkennung eine Standortberechtigung verlangen. Alternativ kannst du die IP-Adresse des Reglers manuell eingeben.

IN DER STARTPHASE KOSTENLOS
Alle Funktionen sind während der Startphase kostenlos nutzbar, ohne Werbung und ohne Abo.

Einsparpotenziale sind Schätzungen. Das Ergebnis hängt unter anderem von Gebäude, Anlage, Wetter und Nutzung ab.

Fragen oder Ideen? Nutze das Feedback in der App oder besuche heizungstrainer.de.

Ein Angebot der Navisense GmbH. Keine Verbindung zu den genannten Geräteherstellern oder Messdienstleistern.
```

**Grafiken**:
- App-Symbol: `assets/branding/play_icon_512.png` (512×512).
- Feature-Grafik: `assets/branding/play_feature_1024x500.png` (1024×500).
- Aktuelle Screenshots: `build/play-release/screenshots/01–05` (1080×1920).
  Direkt aus den Widgets von 1.2.1 mit Demo-Daten gerendert; keine Aufnahme eines Android-Geräts.
  Reihenfolge: Zuhause, Heizkurve, Anlage live, Urlaub, Sicherungen.
- Ältere Hardware-Screenshots unter `assets/branding/screenshots/play/` sind Referenzmaterial,
  nicht als neu aufgenommen kennzeichnen. Keine privaten Mieter-/Abrechnungsdaten veröffentlichen.
- Google erlaubt bis zu acht Bilder je Gerätetyp. Die 9:16-Bilder erfüllen auch die
  Empfehlung für die Bewerbung; das Seitenverhältnis ist nicht die einzige allgemeine Zulassungsbedingung.
  [Offizielle Bildanforderungen](https://support.google.com/googleplay/android-developer/answer/9866151?hl=de).

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

## 6. Data safety – vor Produktion bestätigen

Der bisherige Entwurf setzte „nicht an uns“ mit „nicht erhoben“ gleich. Das ist nicht
korrekt: Google betrachtet auch Übertragungen an Dritte und kontrollierte WebViews.
Lokale Verarbeitung ist ausgenommen. Nutzerinitiierte Weitergabe kann eine Ausnahme
von „geteilt“ sein, ist aber nicht automatisch eine Ausnahme von „erhoben“.
[Google Data-safety-Leitfaden](https://support.google.com/googleplay/android-developer/answer/10787469?hl=de).

Am App-Code bestätigte Datenflüsse:

| Funktion | Daten und Übertragung | Zu prüfen/anzugeben |
|---|---|---|
| Feedback | Freitext, optional E-Mail, App-/OS-Version, Reglertyp per HTTPS an Backoffice | E-Mail, nutzergenerierte Inhalte, Diagnosedaten; optional; Support/App-Funktion |
| Diagnosebericht | Nutzerbestätigter Bericht mit Fehlern und Aktivitäten per HTTPS | Absturz-/Diagnosedaten; tatsächlichen Payload und Server-Aufbewahrung abgleichen |
| Brunata-Portal | Login über gesteuerte WebView; Verbrauch und Abrechnung werden abgerufen | Zugangsdaten/Identifikatoren und Datenverarbeitung beim Dienst nicht pauschal ausnehmen |
| Viessmann/andere Gateways | Zugangstoken bzw. Gateway-Zugangsdaten; je nach Konfiguration Cloud oder LAN | Empfänger und Übertragungsweg pro unterstützter Konfiguration prüfen |
| Lokaler Verlauf | Messwerte in SQLite im privaten App-Verzeichnis | Keine eigene SQLite-Verschlüsselung behaupten |
| WLAN-Erkennung | Standortberechtigung für WLAN-Erkennung; keine GPS-Positionsabfrage im geprüften Code | Berechtigung ist nicht gleich Erhebung von GPS-Daten |
| Energiepreis-Probe | Öffentliche HTTPS-Abfrage; Ergebnis bleibt ein hinterlegter Richtwert | Keine Echtzeit-Tarifdaten versprechen; Anbieter-Serverlogs berücksichtigen |

„Alle Daten bei Übertragung verschlüsselt“ nicht allein aus dem HTTPS-Backoffice
ableiten: Modbus TCP und mehrere lokale HTTP-Gateways sind unverschlüsselt. Die
Ausnahme für vom Nutzer gewählte Dienste gemäß Googles Leitfaden anhand des gesamten
Datenflusses prüfen. „Geteilt: Nein“ und Aufbewahrungs-/Löschangaben ebenfalls mit dem
Backendbetrieb abgleichen. Ohne diese Angaben ist hier keine endgültige Console-Antwort bestätigt.

Öffentliche Datenschutzerklärung: https://heizungstrainer.de/datenschutz.html
(am 14.10.2026 HTTP 200; enthält Abschnitt zur App, Feedback, Diagnose und Drittanbietern).
Löschkontakt: support@heizungstrainer.de. Kein eigenes Heizungstrainer-Benutzerkonto.

## 7. Release-Hinweise (Interner Test / später Produktion)

```
<de-DE>
Verbesserungen für Stabilität und kleine Displays.
• Bessere Darstellung von Einstellungen, Sicherungen und Diagrammen
• Getrennte Verbrauchsdaten je Abrechnungsanbieter
• Zuverlässigeres Trennen und Aktualisieren der Reglerverbindung
• Heizkurven-Simulation im Demo-Modus
• Klarere Verbindungs- und Demo-Anzeigen
</de-DE>
```

## 8. Später, wenn Pro kostenpflichtig wird

- In-App-Produkt `heizungstrainer_pro` anlegen (Einmalkauf).
- Einstufung: „Digitale Käufe“ → Ja; Data safety: Kaufverlauf prüfen (die App speichert die Kauf-ID lokal; Google verarbeitet den Kauf).
- Store-Text „Startphase“ anpassen, Early-Adopter-Zusage beibehalten.

# Heizungstrainer 🌡️🔥

> **Intelligente Heizungsoptimierung, Monitoring & Fail-Safe Steuerung für moderne Heizsysteme.**  
> Offizielle Website & Dokumentation: [heizungstrainer.de](https://heizungstrainer.de)

---

## 📋 Überblick

**Heizungstrainer** ist eine moderne, modulare Flutter-Anwendung zur Optimierung, Analyse und Überwachung von Heizungsanlagen. Die App schlägt die Brücke zwischen professioneller Regelungstechnik im Heizungskeller und intelligenter Verbrauchsdatenanalyse.

### Kernfunktionen:
- 🔌 **Danfoss ECL Comfort 310 Anbindung:** Direkte Kommunikation über Modbus TCP (Ethernet / WLAN) zur Steuerung und Überwachung der Regelungsparameter.
- 🛡️ **Fail-Safe & Auto-Reconnect:** Ausfallsichere Architektur mit automatischem Verbindungs-Wiederaufbau, Watchdog-Schutz und Heartbeat-Erkennung.
- 📈 **Heizkurven-Visualisierung & Simulation:** Interaktive Modellierung der Heizkurve (Steilheit, Parallelverschiebung, Fußpunkt) sowie Spreizungsanalyse ($\Delta T$ Vorlauf/Rücklauf).
- 📊 **Brunata-Integration:** Automatisierter Abruf und Abgleich von Abrechnungs- und Verbrauchsdaten über den integrierten Scraper-Service.
- 💾 **Backup & Restore:** Vollständiges Sichern und Wiederherstellen von Konfigurations-Snapshots der Reglereinstellungen.
- 🔮 **Erweiterbare Architektur:** Zukünftige Unterstützung für weitere Regler (z.B. Buderus Logamatic, Viessmann Vitotronic, Vaillant sensoCOMFORT, Technische Alternative UVR).

---

## 🛠️ Systemarchitektur

```text
[ Heizungstrainer Mobile App ]
      │
      ├─── Modbus TCP (Port 502) ────────► [ Danfoss ECL Comfort 310 ]
      │    - Vorlauf- & Rücklauftemperaturen
      │    - Außentemperatur & Solltemperaturen
      │    - Pumpen- & Mischerstatus
      │    - Betriebsmodi (Auto / Komfort / Absenkung)
      │
      ├─── Secure Web Automation ────────► [ Brunata Online Portal ]
      │    - Zählerstandsabfragen
      │    - Verbrauchsdatenanalyse & Validierung
      │
      └─── Local Storage & Analytics
           - Verschlüsselte Credentials (flutter_secure_storage)
           - Anlagen-Snapshots & Kurvensimulation
```

---

## 📱 Features & Screens

- **Verbindung & Status:** Schnelle Übersicht über Netzwerkstatus, Signalstärke und Controller-Verbindung.
- **Mein Zuhause (Dashboard):** Live-Messwerte, Echtzeit-Temperaturkurven und Schnellwahltasten.
- **Heizkurven-Optimierung:** Feineinstellung von Steilheit und Niveau mit visueller Vorschau der Auswirkungen.
- **Vergleich (Community & Brunata):** Gegenüberstellung eigener Verbrauchswerte mit Referenzdaten.
- **Sicherungen (Backup/Restore):** Versionsverwaltung für Regler-Register und Notfall-Wiederherstellung.

---

## 🚀 Erste Schritte / Entwicklung

### Voraussetzungen
- Flutter SDK (>= 3.0.0)
- Dart SDK (>= 3.0.0)
- Android Studio / VS Code mit Flutter & Dart Plugins
- Für Hardware-Tests: Zugriff auf einen Danfoss ECL Comfort 310 im lokalen Netzwerk (Standard-Port 502)

### Installation

1. **Repository klonen:**
   ```bash
   git clone https://github.com/bullemer/heizungstrainer.git
   cd heizungstrainer
   ```

2. **Dependencies installieren:**
   ```bash
   flutter pub get
   ```

3. **Tests ausführen:**
   ```bash
   flutter test
   ```

4. **App starten (Debug-Modus):**
   ```bash
   flutter run
   ```

---

## 🧪 Tests

Das Projekt verfügt über automatisierte Unit- und Widget-Tests:
```bash
flutter test
```

---

## 📄 Lizenz & Rechtliches

Entwickelt für das Projekt [heizungstrainer.de](https://heizungstrainer.de).  
Alle Rechte vorbehalten.

## Builds

Two Android flavors share the app id `com.heizungstrainer.heizungstrainer`:

| Flavor | Command | Output | Pro unlock | Signing |
|---|---|---|---|---|
| `direct` (default) | `flutter build apk --release` | `build/app/outputs/flutter-apk/app-direct-release.apk` | offline HT2 licence key | debug key (keeps website installs updatable) |
| `play` | `flutter build appbundle --release --flavor play` | `build/app/outputs/bundle/playRelease/app-play-release.aab` | Google Play Billing, product `heizungstrainer_pro` | upload key from `android/key.properties` (gitignored; keystore in `~/.config/heizungstrainer/`) |

Because the signatures differ, the Play version can't be installed over the website APK; users switching have to uninstall first.

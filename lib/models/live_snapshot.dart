/// One live reading of a Danfoss ECL installation for the plant diagram
/// ("Anlagenbild"), modelled on the Danfoss portal's Application view.
///
/// Registers (Danfoss communication description, register = PNU − 1):
/// raw sensors S1–S10 PNU 10201–10210 (×0.01), sensor references ("target"
/// in brackets) PNU 11251+n (circuit 1) / 12251+n (circuit 2) (×0.01),
/// triac outputs PNU 4000–4005, relays PNU 4006–4011, circuit mode PNU 4201+,
/// circuit status PNU 4211+, limiter flags PNU 4220–4223 (circuit 1).
library;

/// Which sensor references an application has, and in which circuit.
class LiveViewSpec {
  const LiveViewSpec({
    required this.application,
    required this.references,
    required this.sensorNames,
    required this.hasDiagram,
  });

  final String application;

  /// Sensor number → circuit whose reference ("target") belongs to it.
  final Map<int, int> references;

  /// Sensor number → function (for the value table).
  final Map<int, String> sensorNames;

  /// A drawn plant diagram exists (otherwise only the value table).
  final bool hasDiagram;

  static int referenceAddress(int circuit, int sensor) => (circuit == 1 ? 11250 : 12250) + sensor - 1;

  /// A247.1 (Danfoss installation guide AN19348647319100, ex. a; checked live
  /// 2026-10-08 against the portal): circuit 1 = heating, circuit 2 = DHW
  /// charging. Outputs: R1 P1, R2 P2, R3 P3, R4 A1; Tr1/Tr2 M1 open/close,
  /// Tr3/Tr4 M2 open/close.
  static const a247 = LiveViewSpec(
    application: 'A247',
    references: {3: 1, 5: 1, 2: 2, 4: 2, 6: 2},
    sensorNames: {
      1: 'Außentemperatur',
      2: 'Rücklauf Fernwärme, Warmwasser',
      3: 'Vorlauf Heizung',
      4: 'Ladevorlauf Warmwasser',
      5: 'Rücklauf Fernwärme, Heizung',
      6: 'Speicher oben',
      8: 'Speicher unten',
    },
    hasDiagram: true,
  );

  /// Generic: all sensors, no references, no diagram.
  static LiveViewSpec generic(String? application) => LiveViewSpec(
        application: application ?? 'unbekannt',
        references: const {},
        sensorNames: const {1: 'Außentemperatur'},
        hasDiagram: false,
      );

  static LiveViewSpec forApplication(String? application) =>
      (application?.startsWith('A247') ?? false) ? a247 : generic(application);
}

enum ValveMotion { opening, closing, idle }

class LiveSnapshot {
  const LiveSnapshot({
    required this.at,
    required this.spec,
    required this.sensors,
    required this.references,
    required this.relays,
    required this.triacs,
    this.circuitMode = const {},
    this.circuitStatus = const {},
    this.limiter = const [],
    this.controllerTime,
    this.simulated = false,
  });

  final DateTime at;
  final LiveViewSpec spec;

  /// Sensor number (1–10) → °C, null if not connected (19200) or unreadable.
  final Map<int, double?> sensors;

  /// Sensor number → controller target value (°C).
  final Map<int, double> references;

  /// R1–R6 and Tr1–Tr6 on/off.
  final List<bool> relays;
  final List<bool> triacs;

  /// Circuit number → mode (PNU 4201+) / status (PNU 4211+).
  final Map<int, int> circuitMode;
  final Map<int, int> circuitStatus;

  /// Limiter words 1–4 of circuit 1.
  final List<int> limiter;

  final DateTime? controllerTime;
  final bool simulated;

  bool relay(int n) => n >= 1 && n <= relays.length && relays[n - 1];
  bool triac(int n) => n >= 1 && n <= triacs.length && triacs[n - 1];

  // ── A247 components ──
  bool get p1 => relay(1);
  bool get p2 => relay(2);
  bool get p3 => relay(3);
  bool get alarmOutput => relay(4);
  ValveMotion get m1 => _valve(1, 2);
  ValveMotion get m2 => _valve(3, 4);

  ValveMotion _valve(int open, int close) =>
      triac(open) ? ValveMotion.opening : (triac(close) ? ValveMotion.closing : ValveMotion.idle);

  /// Sensor value from the 16-bit raw register (×0.01, 19200 = not connected).
  static double? sensorFromRaw(int raw) => raw >= 19200 ? null : raw / 100.0;

  /// What currently influences the circuit-1 reference (limiter flags).
  List<String> get limiterTexts {
    if (limiter.length < 3) return const [];
    String dir(int v) => switch (v) { 1 => 'erhöht', 2 => 'senkt', 3 => 'verändert', _ => '' };
    final out = <String>[];
    void add(int word, int shift, String label, {bool withDirection = true}) {
      final v = (limiter[word] >> shift) & 3;
      if (v == 0) return;
      out.add(withDirection ? '$label ${dir(v)} den Sollwert' : label);
    }

    add(0, 0, 'Rücklaufbegrenzung');
    add(0, 2, 'Raumtemperatur-Einfluss');
    add(0, 14, 'Durchfluss-/Leistungsbegrenzung');
    add(1, 0, 'Urlaubsprogramm', withDirection: false);
    add(1, 14, 'Sommerabschaltung aktiv (Heizgrenze)', withDirection: false);
    add(2, 0, 'Warmwasser-Vorrang', withDirection: false);
    return out;
  }
}

/// ECL circuit status (PNU 4211+), Danfoss table 6-2.
String eclStatusLabel(int? code) => switch (code) {
      0 => 'Spar',
      1 => 'Vor-Komfort',
      2 => 'Komfort',
      3 => 'Vor-Spar',
      4 => 'Urlaub: Komfort',
      5 => 'Urlaub: 7–23 Uhr Komfort',
      6 => 'Urlaub: Spar',
      7 => 'Urlaub: Frostschutz',
      null => '–',
      final c => 'Status $c',
    };

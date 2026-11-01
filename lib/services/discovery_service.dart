/// Local subnet discovery service for finding ECL 310 controllers.
///
/// Scans the device's local /24 WiFi subnet for hosts with open TCP port 502,
/// then verifies each candidate by performing a test Modbus read.
library;

import 'package:heizungstrainer/utils/number_format.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:modbus_client/modbus_client.dart';
import 'package:modbus_client_tcp/modbus_client_tcp.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'package:heizungstrainer/exceptions/modbus_exceptions.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';

/// Service responsible for discovering Danfoss ECL 310 controllers
/// on the local WiFi network.
///
/// ## Discovery Strategy
/// 1. Retrieve the phone's local WiFi IPv4 address.
/// 2. Derive the /24 subnet base (e.g., `192.168.188`).
/// 3. Attempt fast reconnect to previously saved IP first.
/// 4. If that fails, scan all 254 hosts asynchronously with concurrency
///    throttling, checking for open TCP port 502.
/// 5. For each host with port 502 open, perform a Modbus test read
///    on register 411001 (Outdoor Temp) to verify it's an ECL controller.
/// 6. Persist the validated IP in [FlutterSecureStorage].
class DiscoveryService {
  static const String _storageKey = 'ecl_controller_ip';
  static const int _modbusPort = 502;
  static const Duration _socketTimeout = Duration(milliseconds: 500);
  static const Duration _iosSocketTimeout = Duration(milliseconds: 1500);

  /// Maximum concurrent TCP connection attempts during subnet scanning.
  static const int _concurrentScans = 50;

  /// Set once iOS's local-network prompt has been triggered on this install.
  static const String _localNetworkPromptKey = 'ht_ios_local_network_prompted';

  /// A refusal faster than this didn't reach the network (see [_scanLooksBlocked]).
  static const Duration _instantFailure = Duration(milliseconds: 100);

  /// Settings path shown when iOS blocks the local network.
  static const String iosLocalNetworkHint =
      'Auf dem iPhone: Einstellungen → Datenschutz & Sicherheit → Lokales Netzwerk '
      '→ Heizungstrainer einschalten.';

  final NetworkInfo _networkInfo;
  final FlutterSecureStorage _secureStorage;
  final bool _isIOS;
  final Future<void> Function() _awaitPermissionAnswer;

  /// [isIOS] and [awaitPermissionAnswer] are for tests; by default they follow
  /// the platform and watch the app lifecycle.
  DiscoveryService({
    NetworkInfo? networkInfo,
    FlutterSecureStorage? secureStorage,
    bool? isIOS,
    Future<void> Function()? awaitPermissionAnswer,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _isIOS = isIOS ?? (!kIsWeb && Platform.isIOS),
        _awaitPermissionAnswer = awaitPermissionAnswer ?? _awaitSystemAlertAnswer;

  /// Android needs the location permission to read the WiFi IP; iOS doesn't
  /// (it asks for local-network access instead, see [ensureLocalNetworkPrompt]).
  bool get needsLocationPermission => !_isIOS;

  // ──────────────────────────────────────────────────────────────────
  // Secure Storage
  // ──────────────────────────────────────────────────────────────────

  /// Returns the previously saved controller IP, or `null` if none exists.
  Future<String?> getSavedControllerIp() async {
    return _secureStorage.read(key: _storageKey);
  }

  /// Persists a validated controller IP to secure local storage.
  Future<void> saveControllerIp(String ip) async {
    await _secureStorage.write(key: _storageKey, value: ip);
  }

  /// Removes the saved controller IP from storage.
  Future<void> clearSavedIp() async {
    await _secureStorage.delete(key: _storageKey);
  }

  // ──────────────────────────────────────────────────────────────────
  // Network Identification
  // ──────────────────────────────────────────────────────────────────

  /// Retrieves the device's current local WiFi IPv4 address.
  ///
  /// Throws [ControllerNotFoundException] if WiFi is not connected or
  /// the IP address cannot be determined.
  Future<String> getLocalIpAddress() async {
    final wifiIP = await _networkInfo.getWifiIP();
    debugPrint('[Discovery] WiFi IP: $wifiIP');
    if (wifiIP == null || wifiIP.isEmpty) {
      throw ControllerNotFoundException(
        subnet: 'unknown',
        message: 'Lokale WiFi-IP-Adresse konnte nicht ermittelt werden. '
            'Bitte stellen Sie sicher, dass das Gerät mit dem WLAN verbunden ist'
            '${_isIOS ? '.' : ' und die Standortberechtigung erteilt wurde.'}',
      );
    }
    return wifiIP;
  }

  /// Derives the /24 subnet base from a full IP address.
  ///
  /// Example: `'192.168.188.42'` → `'192.168.188'`
  String _getSubnetBase(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      throw ControllerNotFoundException(
        subnet: ip,
        message: 'Ungültige IP-Adresse: $ip',
      );
    }
    return '${parts[0]}.${parts[1]}.${parts[2]}';
  }

  // ──────────────────────────────────────────────────────────────────
  // Port Scanning & Verification
  // ──────────────────────────────────────────────────────────────────

  /// Connects to [host]:502 and classifies the outcome.
  Future<ProbeResult> _probe(String host) async {
    final watch = Stopwatch()..start();
    final timeout = _isIOS ? _iosSocketTimeout : _socketTimeout;
    try {
      final socket = await Socket.connect(
        host,
        _modbusPort,
        timeout: timeout,
      );
      socket.destroy();
      return ProbeResult.open;
    } on SocketException catch (e) {
      // ECONNREFUSED (61 on iOS, 111 on Android/Linux): a host answered.
      final code = e.osError?.errorCode;
      if (code == 61 || code == 111) return ProbeResult.refused;
      if (e.message.contains('timed out') || watch.elapsed >= timeout) {
        return ProbeResult.timeout;
      }
      return watch.elapsed < _instantFailure ? ProbeResult.instantError : ProbeResult.error;
    } catch (_) {
      return ProbeResult.error;
    }
  }

  /// A scan "looks blocked" when nothing answered at all (no open port, no
  /// refusal) and nearly every attempt failed instantly instead of timing out.
  /// On a reachable network, absent hosts time out and the router refuses;
  /// iOS without local-network access fails every connect at once.
  @visibleForTesting
  static bool scanLooksBlocked(Iterable<ProbeResult> results) {
    final list = results.toList();
    if (list.isEmpty) return false;
    if (list.any((r) => r == ProbeResult.open || r == ProbeResult.refused)) return false;
    final instant = list.where((r) => r == ProbeResult.instantError).length;
    return instant >= list.length * 0.9;
  }

  // ──────────────────────────────────────────────────────────────────
  // iOS local-network permission
  // ──────────────────────────────────────────────────────────────────

  /// iOS asks "Allow … to find devices on your local network?" on the first
  /// LAN connection, and fails every connection until the user answers. So
  /// trigger it once with a single connect, wait for the answer, and only
  /// then search. No-op on Android and after the first time.
  Future<void> ensureLocalNetworkPrompt(String subnetBase) async {
    if (!_isIOS) return;
    try {
      if (await _secureStorage.read(key: _localNetworkPromptKey) != null) return;
    } catch (_) {}
    debugPrint('[Discovery] Triggering iOS local-network prompt via $subnetBase.1');
    final answered = _awaitPermissionAnswer();
    await _probe('$subnetBase.1');
    await answered;
    try {
      await _secureStorage.write(key: _localNetworkPromptKey, value: DateTime.now().toIso8601String());
    } catch (_) {}
  }

  /// The system alert makes the app inactive; it is resumed once the user
  /// tapped a button. If no alert shows up (already answered) this returns
  /// after a short grace period.
  static Future<void> _awaitSystemAlertAnswer() async {
    final answered = Completer<void>();
    var alertShown = false;
    final listener = AppLifecycleListener(onStateChange: (state) {
      if (state == AppLifecycleState.inactive) alertShown = true;
      if (state == AppLifecycleState.resumed && alertShown && !answered.isCompleted) {
        answered.complete();
      }
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!alertShown && WidgetsBinding.instance.lifecycleState != AppLifecycleState.inactive) return;
      await answered.future.timeout(const Duration(minutes: 2), onTimeout: () {});
    } finally {
      listener.dispose();
    }
  }

  /// Verifies that a host at [ip] is a genuine ECL 310 controller by
  /// performing a test Modbus read on the Outdoor Temperature register.
  ///
  /// Returns `true` only if the read succeeds and returns a plausible
  /// temperature value (between −50°C and +60°C).
  Future<bool> _verifyECLController(String ip) async {
    ModbusClientTcp? client;
    try {
      client = ModbusClientTcp(ip, unitId: 1);

      // Don't use multiplier in the register — we handle conversion ourselves
      final testRegister = ModbusInt16Register(
        name: 'probe_outdoor_temp',
        type: ModbusElementType.holdingRegister,
        address: ECLRegisters.outdoorTemp.modbusAddress,
      );

      debugPrint('[Discovery] Verifying ECL at $ip (register addr: ${ECLRegisters.outdoorTemp.modbusAddress})...');

      final response = await client
          .send(testRegister.getReadRequest())
          .timeout(const Duration(seconds: 5));

      debugPrint('[Discovery] Modbus response code: $response');

      if (response == ModbusResponseCode.requestSucceed) {
        // register.value is num? (could be int or double depending on multiplier)
        final rawValue = testRegister.value;
        debugPrint('[Discovery] Raw register value: $rawValue (type: ${rawValue.runtimeType})');

        if (rawValue == null) {
          debugPrint('[Discovery] Register value is null — verification failed.');
          return false;
        }

        // Convert to temperature: raw value * 0.01 (Danfoss scale factor)
        final temp = rawValue.toDouble() * 0.01;
        debugPrint('[Discovery] Computed temperature: ${temp.fixed(1)}°C');

        // Sanity check: outdoor temp should be within realistic bounds
        final plausible = temp >= -50.0 && temp <= 60.0;
        debugPrint('[Discovery] Temperature plausible: $plausible');
        return plausible;
      }

      debugPrint('[Discovery] Modbus read failed with code: $response');
      return false;
    } catch (e, stackTrace) {
      debugPrint('[Discovery] ECL verification error for $ip: $e');
      debugPrint('[Discovery] Stack trace: $stackTrace');
      return false;
    } finally {
      try {
        await client?.disconnect();
      } catch (_) {}
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Full Discovery
  // ──────────────────────────────────────────────────────────────────

  /// Discovers an ECL 310 controller on the local /24 WiFi subnet.
  ///
  /// **Fast-path**: A previously connected IP is checked first for a TCP
  /// connection, avoiding a new identification read of a known controller.
  ///
  /// **Full scan**: If fast-path fails, all 254 hosts are scanned in
  /// bounded batches to find a host with port 502 open,
  /// then verified via a Modbus test read.
  ///
  /// [onProgress] reports `(scannedCount, totalCount)` during the scan.
  ///
  /// Returns the IP address of the first verified controller.
  /// Throws [ControllerNotFoundException] if no controller is found.
  Future<String> discoverController({
    void Function(int scanned, int total)? onProgress,
  }) async {
    final localIp = await getLocalIpAddress();
    final subnetBase = _getSubnetBase(localIp);
    debugPrint('[Discovery] Local IP: $localIp, Subnet: $subnetBase.0/24');
    await ensureLocalNetworkPrompt(subnetBase);

    // ── Fast-path: try saved IP first ────────────────────────────
    final savedIp = await getSavedControllerIp();
    if (savedIp != null) {
      debugPrint('[Discovery] Trying saved controller IP: $savedIp');
      final reachable = _isIOS
          ? await _probe(savedIp) == ProbeResult.open
          : await _verifyECLController(savedIp);
      if (reachable) {
        debugPrint('[Discovery] Previously connected controller at $savedIp is reachable.');
        return savedIp;
      }
      debugPrint('[Discovery] Saved IP $savedIp failed verification, starting full scan.');
    }

    // ── Full subnet scan ─────────────────────────────────────────
    String? foundIp;
    int scannedCount = 0;
    const totalHosts = 254;
    final results = <ProbeResult>[];

    final concurrentScans = _isIOS ? 16 : _concurrentScans;
    for (int batchStart = 1;
        batchStart <= totalHosts && foundIp == null;
        batchStart += concurrentScans) {
      final batchEnd = (batchStart + concurrentScans - 1).clamp(1, totalHosts);
      final futures = <Future<void>>[];

      for (int i = batchStart; i <= batchEnd; i++) {
        final candidateIp = '$subnetBase.$i';
        futures.add(() async {
          // Early exit if another future already found the controller
          if (foundIp != null) return;

          final result = await _probe(candidateIp);
          results.add(result);
          if (result == ProbeResult.open) {
            debugPrint('[Discovery] Port 502 open on $candidateIp — verifying…');
            if (await _verifyECLController(candidateIp)) {
              foundIp = candidateIp;
            }
          }
          scannedCount++;
          onProgress?.call(scannedCount, totalHosts);
        }());
      }

      await Future.wait(futures);
    }

    if (foundIp != null) {
      await saveControllerIp(foundIp!);
      debugPrint('[Discovery] ECL 310 controller found and saved: $foundIp');
      return foundIp!;
    }

    if (_isIOS && scanLooksBlocked(results)) {
      debugPrint('[Discovery] All connects failed instantly – local network access looks blocked.');
      throw ControllerNotFoundException(
        subnet: '$subnetBase.0/24',
        localNetworkBlocked: true,
        message: 'Die App darf das lokale Netzwerk offenbar nicht nutzen, '
            'deshalb kann sie den Regler nicht finden. $iosLocalNetworkHint',
      );
    }

    throw ControllerNotFoundException(
      subnet: '$subnetBase.0/24',
      message: 'Kein ECL 310 Controller im Subnetz $subnetBase.0/24 gefunden. '
          'Bitte prüfen Sie, ob der Regler eingeschaltet und im selben '
          'Netzwerk erreichbar ist.'
          '${_isIOS ? ' Falls der Zugriff aufs lokale Netzwerk abgelehnt wurde: $iosLocalNetworkHint' : ''}',
    );
  }

  /// Directly verify and connect to a specific IP (skip subnet scan).
  /// Returns true if the IP hosts a valid ECL controller.
  Future<bool> verifyAndSave(String ip) async {
    debugPrint('[Discovery] Manual verification for $ip');
    final parts = ip.split('.');
    if (parts.length == 4) await ensureLocalNetworkPrompt(parts.take(3).join('.'));
    if (await _verifyECLController(ip)) {
      await saveControllerIp(ip);
      return true;
    }
    return false;
  }
}

/// Outcome of one connection attempt to port 502.
enum ProbeResult {
  /// Port open.
  open,

  /// A host answered with "connection refused".
  refused,

  /// No answer within the timeout.
  timeout,

  /// Failed before reaching the network (typical when iOS blocks the LAN).
  instantError,

  /// Any other failure.
  error,
}

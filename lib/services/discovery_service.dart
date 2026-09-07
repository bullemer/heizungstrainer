/// Local subnet discovery service for finding ECL 310 controllers.
///
/// Scans the device's local /24 WiFi subnet for hosts with open TCP port 502,
/// then verifies each candidate by performing a test Modbus read.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

  /// Maximum concurrent TCP connection attempts during subnet scanning.
  static const int _concurrentScans = 50;

  final NetworkInfo _networkInfo;
  final FlutterSecureStorage _secureStorage;

  DiscoveryService({
    NetworkInfo? networkInfo,
    FlutterSecureStorage? secureStorage,
  })  : _networkInfo = networkInfo ?? NetworkInfo(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

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
      throw const ControllerNotFoundException(
        subnet: 'unknown',
        message: 'Lokale WiFi-IP-Adresse konnte nicht ermittelt werden. '
            'Bitte stellen Sie sicher, dass das Gerät mit dem WLAN verbunden ist '
            'und die Standortberechtigung erteilt wurde.',
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

  /// Tests whether a specific host has TCP port 502 open.
  Future<bool> _isPortOpen(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        _modbusPort,
        timeout: _socketTimeout,
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
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
        debugPrint('[Discovery] Computed temperature: ${temp.toStringAsFixed(1)}°C');

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
  /// **Fast-path**: If a previously saved IP exists and is on the current
  /// subnet, it is tested first for instant reconnection.
  ///
  /// **Full scan**: If fast-path fails, all 254 hosts are scanned in
  /// batches of [_concurrentScans] to find a host with port 502 open,
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

    // ── Fast-path: try saved IP first ────────────────────────────
    final savedIp = await getSavedControllerIp();
    if (savedIp != null && savedIp.startsWith('$subnetBase.')) {
      debugPrint('[Discovery] Trying saved controller IP: $savedIp');
      if (await _verifyECLController(savedIp)) {
        debugPrint('[Discovery] Saved IP $savedIp verified successfully!');
        return savedIp;
      }
      debugPrint('[Discovery] Saved IP $savedIp failed verification, starting full scan.');
    }

    // ── Full subnet scan ─────────────────────────────────────────
    String? foundIp;
    int scannedCount = 0;
    const totalHosts = 254;

    for (int batchStart = 1;
        batchStart <= totalHosts && foundIp == null;
        batchStart += _concurrentScans) {
      final batchEnd = (batchStart + _concurrentScans - 1).clamp(1, totalHosts);
      final futures = <Future<void>>[];

      for (int i = batchStart; i <= batchEnd; i++) {
        final candidateIp = '$subnetBase.$i';
        futures.add(() async {
          // Early exit if another future already found the controller
          if (foundIp != null) return;

          if (await _isPortOpen(candidateIp)) {
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

    throw ControllerNotFoundException(
      subnet: '$subnetBase.0/24',
      message: 'Kein ECL 310 Controller im Subnetz $subnetBase.0/24 gefunden. '
          'Bitte prüfen Sie, ob der Regler eingeschaltet und im selben '
          'Netzwerk erreichbar ist.',
    );
  }

  /// Directly verify and connect to a specific IP (skip subnet scan).
  /// Returns true if the IP hosts a valid ECL controller.
  Future<bool> verifyAndSave(String ip) async {
    debugPrint('[Discovery] Manual verification for $ip');
    if (await _verifyECLController(ip)) {
      await saveControllerIp(ip);
      return true;
    }
    return false;
  }
}

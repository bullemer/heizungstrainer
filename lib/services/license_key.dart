import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Offline Pro licence keys, signed with Ed25519.
///
/// The app only holds the public key, so keys can be verified offline but not
/// created from anything inside the APK. Keys are issued with
/// `heizungstrainer-backoffice/tools/issue_license.py`, which holds the private
/// key; both sides must follow this format:
///
///   payload (10 bytes) = version(1) | licenseId(6) | issuedDay(2, BE) | edition(1)
///   key bytes          = payload | Ed25519 signature over payload (64)
///   key text           = "HT2-" + base32(key bytes, RFC 4648, no padding),
///                        grouped in blocks of 5 joined by "-"
///
/// issuedDay counts days since 2026-01-01 (UTC).
class LicenseKeyData {
  final String licenseId;
  final DateTime issuedAt;
  final int edition;

  const LicenseKeyData({
    required this.licenseId,
    required this.issuedAt,
    required this.edition,
  });
}

class LicenseKeyCodec {
  static const String prefix = 'HT2';
  static const int formatVersion = 1;
  static const int editionProLifetime = 1;

  /// Master licence: Pro for any number of controllers (installers, housing
  /// companies) – lifts the one-controller binding of the normal app.
  static const int editionMaster = 2;
  static const int payloadLength = 10;
  static const int signatureLength = 64;
  static final DateTime epoch = DateTime.utc(2026, 1, 1);

  /// Production verification key (Ed25519, raw 32 bytes).
  static final List<int> productionPublicKey = _hex(
    '2d2a7c589254b66201fea5514d91d01b65a8d57d46ef65895bf177de051c2004',
  );

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// Strips spaces, line breaks, dashes and the "HT2" prefix; uppercases.
  static String normalize(String key) {
    final compact = key.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    return compact.startsWith(prefix) ? compact.substring(prefix.length) : compact;
  }

  /// Verifies [key] against [publicKey]; returns its data, or null if the key
  /// is malformed or the signature doesn't match.
  static Future<LicenseKeyData?> verify(String key, List<int> publicKey) async {
    final bytes = _base32Decode(normalize(key));
    if (bytes == null || bytes.length != payloadLength + signatureLength) return null;

    final payload = bytes.sublist(0, payloadLength);
    final signature = bytes.sublist(payloadLength);
    if (payload[0] != formatVersion) return null;

    final ok = await Ed25519().verify(
      payload,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) return null;

    final days = (payload[7] << 8) | payload[8];
    return LicenseKeyData(
      licenseId: payload
          .sublist(1, 7)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase(),
      issuedAt: epoch.add(Duration(days: days)),
      edition: payload[9],
    );
  }

  /// Formats raw key bytes (payload + signature) as key text. Used by tests;
  /// production keys come from the issuing tool.
  static String format(List<int> keyBytes) {
    final encoded = _base32Encode(keyBytes);
    final groups = <String>[];
    for (var i = 0; i < encoded.length; i += 5) {
      groups.add(encoded.substring(i, i + 5 > encoded.length ? encoded.length : i + 5));
    }
    return '$prefix-${groups.join('-')}';
  }

  static String _base32Encode(List<int> data) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in data) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List? _base32Decode(String text) {
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in text.split('')) {
      final value = _alphabet.indexOf(ch);
      if (value < 0) return null;
      buffer = ((buffer << 5) | value) & 0xFFFF;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 0xFF);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }

  static List<int> _hex(String hex) => [
        for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
      ];
}

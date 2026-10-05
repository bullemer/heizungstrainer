import 'dart:io';

/// Certificate policy for controller HTTP clients.
///
/// Local gateways (Buderus KM200, EMS-ESP, ebusd) often serve HTTPS with a
/// self-signed certificate, so those are accepted — but only for hosts on the
/// home network. Anything public (e.g. a cloud API, or a typo'd hostname that
/// resolves to the internet) always gets normal certificate verification.
class TlsPolicy {
  static bool isLocalNetworkHost(String host) {
    final h = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
    final ip = InternetAddress.tryParse(h);
    if (ip != null) {
      if (ip.isLoopback || ip.isLinkLocal) return true;
      final b = ip.rawAddress;
      if (ip.type == InternetAddressType.IPv4) {
        return b[0] == 10 ||
            (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
            (b[0] == 192 && b[1] == 168);
      }
      return (b[0] & 0xfe) == 0xfc; // IPv6 unique local fc00::/7
    }
    if (!h.contains('.')) return true; // bare LAN name, e.g. "km200"
    return const ['.local', '.lan', '.home', '.home.arpa', '.fritz.box', '.internal']
        .any(h.endsWith);
  }

  /// `badCertificateCallback` for clients that talk to local gateways.
  static bool acceptSelfSignedOnLocalNetwork(X509Certificate cert, String host, int port) =>
      isLocalNetworkHost(host);
}

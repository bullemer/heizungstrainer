import 'dart:async';

import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';

/// Mock or simulated billing provider used for testing and UI development
/// (e.g. simulating Techem, ista, Minol, Kalo).
class MockBillingProvider implements BillingProvider {
  @override
  final String id;
  @override
  final String displayName;
  @override
  final String organization;
  @override
  final BillingAuthType authType;
  @override
  final BillingCapabilities capabilities;

  double _pricePerKwh = 0.12;
  bool _hasCredentials = true;
  String? _username;
  String? _password;
  String _portalUrl;
  final BrunataMeterData? _mockData;

  @override
  final String defaultPortalUrl;

  MockBillingProvider({
    this.id = 'mock_techem',
    this.displayName = 'Techem Smart System (Simuliert)',
    this.organization = 'Techem Energy Services GmbH',
    this.authType = BillingAuthType.restApi,
    this.capabilities = const BillingCapabilities(),
    this.defaultPortalUrl = 'https://example.com/portal',
    String? portalUrl,
    BrunataMeterData? mockData,
  })  : _portalUrl = portalUrl ?? defaultPortalUrl,
        _mockData = mockData;

  @override
  Future<bool> hasCredentials() async => _hasCredentials;

  @override
  Future<String?> getUsername() async => _username;

  @override
  Future<String?> getPassword() async => _password;

  @override
  Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    _hasCredentials = true;
    _username = username;
    _password = password;
  }

  @override
  Future<String> getPortalUrl() async => _portalUrl;

  @override
  Future<void> setPortalUrl(String url) async {
    _portalUrl = url;
  }

  @override
  Future<double> getPricePerKwh() async => _pricePerKwh;

  @override
  Future<void> setPricePerKwh(double price) async {
    _pricePerKwh = price;
  }

  @override
  Future<BillingSyncResult> syncData() async {
    final data = _mockData ?? BrunataMeterData.demo().copyWithPrice(_pricePerKwh);
    return BillingSyncResult.ok(data);
  }
}

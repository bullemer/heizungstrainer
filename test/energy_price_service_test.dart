import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/services/energy_price_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EnergyPriceService Benchmarks & Recommendation Tests', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('defines realistic 2026 heating benchmarks across carriers', () {
      final carriers = EnergyPriceService.knownCarriers;
      expect(carriers.length, greaterThanOrEqualTo(6));

      final hamburg = EnergyPriceService.getCarrierById('district_heating_hamburg');
      expect(hamburg.name, 'Fernwärme Hamburg');
      expect(hamburg.benchmarkPricePerKwh, 0.132);

      final gas = EnergyPriceService.getCarrierById('natural_gas_de');
      expect(gas.name, 'Erdgas Deutschland');
      expect(gas.benchmarkPricePerKwh, 0.118);

      final heatPump = EnergyPriceService.getCarrierById('heat_pump_cop');
      expect(heatPump.name, contains('Wärmepumpe'));
      expect(heatPump.benchmarkPricePerKwh, 0.088);

      final oil = EnergyPriceService.getCarrierById('heating_oil');
      expect(oil.name, 'Heizöl EL');
      expect(oil.benchmarkPricePerKwh, 0.104);

      final pellets = EnergyPriceService.getCarrierById('wood_pellets');
      expect(pellets.name, 'Holzpellets');
      expect(pellets.benchmarkPricePerKwh, 0.076);

      final average = EnergyPriceService.getCarrierById('national_average');
      expect(average.name, 'Bundesweiter Durchschnitt');
      expect(average.benchmarkPricePerKwh, 0.122);
    });

    test('recommends Hamburg district heating for Brunata Hamburg', () {
      final service = EnergyPriceService();
      expect(service.getRecommendedPriceForProvider('brunata_hamburg'), 0.132);
      expect(service.getRecommendedPriceForProvider('other_provider'), 0.128);
      expect(service.getRecommendedPriceForProvider(null), 0.128);
    });

    test('returns recommended realistic benchmark when storage is empty', () async {
      final service = EnergyPriceService();
      final priceBrunata = await service.getEffectivePrice(billingProviderId: 'brunata_hamburg');
      expect(priceBrunata, 0.132);

      final priceOther = await service.getEffectivePrice(billingProviderId: 'generic');
      expect(priceOther, 0.128);
    });

    test('auto-migrates legacy 0.10 placeholder to realistic benchmark when not marked custom', () async {
      FlutterSecureStorage.setMockInitialValues({
        EnergyPriceService.storageKeyPrice: '0.10',
        EnergyPriceService.storageKeyIsCustom: 'false',
      });

      final service = EnergyPriceService();
      final effective = await service.getEffectivePrice(billingProviderId: 'brunata_hamburg');
      // Should upgrade from 0.10 to realistic 0.132
      expect(effective, 0.132);
    });

    test('respects legacy 0.10 if user explicitly marked it as custom', () async {
      FlutterSecureStorage.setMockInitialValues({
        EnergyPriceService.storageKeyPrice: '0.10',
        EnergyPriceService.storageKeyIsCustom: 'true',
      });

      final service = EnergyPriceService();
      final effective = await service.getEffectivePrice(billingProviderId: 'brunata_hamburg');
      // Explicit custom price is respected
      expect(effective, 0.10);
    });

    test('persists user custom price overwrite and reads it back accurately', () async {
      final service = EnergyPriceService();

      // User enters custom contract price of 0.1475 €/kWh
      await service.saveUserPrice(0.1475, carrierId: 'district_heating_hamburg', isCustom: true);

      final effective = await service.getEffectivePrice(billingProviderId: 'brunata_hamburg');
      expect(effective, closeTo(0.1475, 0.0001));

      final isCustom = await service.isCustomPrice();
      expect(isCustom, isTrue);

      final carrierId = await service.getSavedCarrierId();
      expect(carrierId, 'district_heating_hamburg');
    });

    test('synchronizes legacy brunata_price_per_kwh key upon save', () async {
      final mockStorage = const FlutterSecureStorage();
      final service = EnergyPriceService(secureStorage: mockStorage);

      await service.saveUserPrice(0.155, isCustom: true);

      final legacyVal = await mockStorage.read(key: 'brunata_price_per_kwh');
      expect(legacyVal, '0.1550');
    });

    test('fetchDynamicMarketPrice returns carrier profile', () async {
      final service = EnergyPriceService();
      final carrier = await service.fetchDynamicMarketPrice(carrierId: 'natural_gas_de');
      expect(carrier.id, 'natural_gas_de');
      expect(carrier.benchmarkPricePerKwh, 0.118);
    });
  });
}

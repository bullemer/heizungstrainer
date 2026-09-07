import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/billing/brunata_hamburg_billing_provider.dart';
import 'package:heizungstrainer/billing/mock_billing_provider.dart';
import 'package:heizungstrainer/controllers/danfoss_ecl_310_controller.dart';
import 'package:heizungstrainer/controllers/bosch_buderus_ems_controller.dart';
import 'package:heizungstrainer/controllers/viessmann_controller.dart';
import 'package:heizungstrainer/controllers/vaillant_ebusd_controller.dart';
import 'package:heizungstrainer/controllers/weishaupt_wem_controller.dart';
import 'package:heizungstrainer/controllers/nibe_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/controllers/mock_heating_controller.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/device_registry.dart';

void main() {
  group('HeatingController Universal Interface & Danfoss Adapter', () {
    test('DanfossEcl310Controller exposes accurate metadata and capabilities', () {
      final controller = DanfossEcl310Controller();

      expect(controller.id, 'danfoss_ecl_310');
      expect(controller.brandName, 'Danfoss');
      expect(controller.modelName, 'ECL Comfort 310');
      expect(controller.protocol, ConnectionProtocol.modbusTcp);

      final caps = controller.capabilities;
      expect(caps.supportsHeatingCurveShift, isTrue);
      expect(caps.minShift, -15.0);
      expect(caps.maxShift, 15.0);
      expect(caps.supportsRoomTarget, isTrue);
      expect(caps.supportsHotWater, isTrue);
      expect(caps.supportsReturnTemp, isTrue);
      expect(caps.supportsOutdoorTemp, isTrue);
    });

    test('MockHeatingController simulates multi-brand telemetry and controls', () async {
      final mock = MockHeatingController(
        id: 'viessmann_vitotronic',
        brandName: 'Viessmann',
        modelName: 'Vitotronic 200',
        protocol: ConnectionProtocol.restApi,
      );

      expect(mock.isConnected, isFalse);
      await mock.connect(host: '192.168.1.50');
      expect(mock.isConnected, isTrue);

      final telemetry = await mock.readTelemetry();
      expect(telemetry.outdoorTemp, 7.5);
      expect(telemetry.flowTemp, 46.0);
      expect(telemetry.returnTemp, 36.0);
      expect(telemetry.spread, 10.0); // 46 - 36
      expect(telemetry.heatingCurveShift, 0.0);

      // Mutate shift and verify telemetry response
      await mock.setHeatingCurveShift(-2.0);
      final updated = await mock.readTelemetry();
      expect(updated.heatingCurveShift, -2.0);
      expect(updated.flowTemp, 44.0);

      await mock.disconnect();
      expect(mock.isConnected, isFalse);
    });
  });

  group('BillingProvider Universal Interface & Brunata Adapter', () {
    test('BrunataHamburgBillingProvider exposes accurate metadata and capabilities', () {
      final provider = BrunataHamburgBillingProvider();

      expect(provider.id, 'brunata_hamburg');
      expect(provider.displayName, 'Brunata Hamburg');
      expect(provider.organization, 'Brunata Wärmemessdienst Hamburg');
      expect(provider.authType, BillingAuthType.portalScraper);

      final caps = provider.capabilities;
      expect(caps.supportsCommunityComparison, isTrue);
      expect(caps.supportsMonthlyBreakdown, isTrue);
      expect(caps.supportsExtrapolation, isTrue);
      expect(caps.supportsHotWaterSeparation, isTrue);
    });

    test('MockBillingProvider simulates third-party providers (e.g. Techem)', () async {
      final mock = MockBillingProvider(
        id: 'techem_smart',
        displayName: 'Techem Smart System',
        organization: 'Techem Energy Services GmbH',
        mockData: BrunataMeterData.demo(),
      );

      expect(mock.id, 'techem_smart');
      expect(mock.displayName, 'Techem Smart System');
      expect(await mock.hasCredentials(), isTrue);

      final result = await mock.syncData();
      expect(result.success, isTrue);
      expect(result.data, isNotNull);
      expect(result.data!.hasDetail, isTrue);
    });
  });

  group('DeviceRegistry Catalog', () {
    test('contains known controllers with support flags', () {
      final controllers = DeviceRegistry.knownControllers;
      expect(controllers, isNotEmpty);

      final danfoss = controllers.firstWhere((c) => c.id == 'danfoss_ecl_310');
      expect(danfoss.isSupported, isTrue);

      final viessmann = controllers.firstWhere((c) => c.id == 'viessmann_vicare');
      expect(viessmann.isSupported, isTrue);

      final bosch = controllers.firstWhere((c) => c.id == 'bosch_buderus_ems');
      expect(bosch.isSupported, isTrue);

      final vaillant = controllers.firstWhere((c) => c.id == 'vaillant_ebusd');
      expect(vaillant.isSupported, isTrue);

      final weishaupt = controllers.firstWhere((c) => c.id == 'weishaupt_wem');
      expect(weishaupt.isSupported, isTrue);

      final nibe = controllers.firstWhere((c) => c.id == 'nibe_modbus');
      expect(nibe.isSupported, isTrue);
    });

    test('contains known billing providers with support flags', () {
      final providers = DeviceRegistry.knownBillingProviders;
      expect(providers, isNotEmpty);

      final brunata = providers.firstWhere((p) => p.id == 'brunata_hamburg');
      expect(brunata.isSupported, isTrue);

      final techem = providers.firstWhere((p) => p.id == 'techem_smart');
      expect(techem.isSupported, isFalse);

      final ista = providers.firstWhere((p) => p.id == 'ista_ecotrend');
      expect(ista.isSupported, isFalse);
    });

    test('creates default active controller and billing provider', () {
      final controller = DeviceRegistry.createDefaultController();
      expect(controller, isA<DanfossEcl310Controller>());

      final billing = DeviceRegistry.createDefaultBillingProvider();
      expect(billing, isA<BrunataHamburgBillingProvider>());
    });

    test('creates specific controller by ID', () {
      final danfoss = DeviceRegistry.createController('danfoss_ecl_310');
      expect(danfoss, isA<DanfossEcl310Controller>());

      final viessmann = DeviceRegistry.createController('viessmann_vicare');
      expect(viessmann, isA<ViessmannController>());
      expect(viessmann.brandName, 'Viessmann');

      final bosch = DeviceRegistry.createController('bosch_buderus_ems');
      expect(bosch, isA<BoschBuderusEmsController>());
      expect(bosch.brandName, 'Bosch / Buderus');

      final vaillant = DeviceRegistry.createController('vaillant_ebusd');
      expect(vaillant, isA<VaillantEbusdController>());
      expect(vaillant.brandName, 'Vaillant');

      final weishaupt = DeviceRegistry.createController('weishaupt_wem');
      expect(weishaupt, isA<WeishauptWemController>());
      expect(weishaupt.brandName, 'Weishaupt');

      final nibe = DeviceRegistry.createController('nibe_modbus');
      expect(nibe, isA<NibeModbusController>());
      expect(nibe.brandName, 'NIBE');
    });

    test('creates specific billing provider by ID', () {
      final brunata = DeviceRegistry.createBillingProvider('brunata_hamburg');
      expect(brunata, isA<BrunataHamburgBillingProvider>());

      final techem = DeviceRegistry.createBillingProvider('techem_smart');
      expect(techem, isA<MockBillingProvider>());
      expect(techem.displayName, contains('Techem'));
    });
  });

  group('ECLProvider Multi-Controller & Multi-Billing Integration', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    FlutterSecureStorage.setMockInitialValues({});

    test('initializes with default Danfoss and Brunata setup', () {
      final provider = ECLProvider(autoLoadDatabase: false);

      expect(provider.selectedControllerId, 'danfoss_ecl_310');
      expect(provider.selectedBillingId, 'brunata_hamburg');
      expect(provider.isSimulatedController, isFalse);
      expect(provider.isSimulatedBilling, isFalse);
      expect(provider.currentControllerDescriptor.brand, 'Danfoss');
      expect(provider.currentBillingDescriptor.name, 'Brunata Hamburg');
    });

    test('switches controller to Viessmann and runs simulation mode', () async {
      final provider = ECLProvider(autoLoadDatabase: false);

      await provider.setSelectedController('viessmann_vicare');
      expect(provider.selectedControllerId, 'viessmann_vicare');
      expect(provider.isSimulatedController, isFalse);
      expect(provider.currentControllerDescriptor.brand, 'Viessmann');

      // Start simulation
      await provider.startSimulation();
      expect(provider.isConnected, isTrue);
      expect(provider.controllerIp, contains('Simulation'));

      // Verify simulated readings
      expect(provider.hasCachedReadings, isTrue);
      final outdoor = provider.getReading(ECLRegisters.outdoorTemp);
      expect(outdoor, isNotNull);
      expect(outdoor!.displayValue, 7.5);

      final flow = provider.getReading(ECLRegisters.flowTemp);
      expect(flow, isNotNull);
      expect(flow!.displayValue, 46.0);

      // Mutate shift via writeParameter
      await provider.writeParameter(ECLRegisters.heatingCurveShift, 2.0);
      final shift = provider.getReading(ECLRegisters.heatingCurveShift);
      expect(shift, isNotNull);
      expect(shift!.displayValue, 2.0);

      provider.disconnect();
      expect(provider.isConnected, isFalse);
    });

    test('switches billing provider to Techem and syncs simulated data', () async {
      final provider = ECLProvider(autoLoadDatabase: false);

      await provider.setSelectedBillingProvider('techem_smart');
      expect(provider.selectedBillingId, 'techem_smart');
      expect(provider.isSimulatedBilling, isTrue);
      expect(provider.currentBillingDescriptor.name, contains('Techem'));

      await provider.syncBillingData();
      expect(provider.brunataData, isNotNull);
      expect(provider.brunataData!.consumedKwh, greaterThan(0));
      expect(provider.brunataData!.charts, isNotEmpty);
    });
  });
}

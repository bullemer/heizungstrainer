import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/billing/brunata_hamburg_billing_provider.dart';
import 'package:heizungstrainer/billing/brunata_muenchen_billing_provider.dart';
import 'package:heizungstrainer/billing/brunata_huerth_billing_provider.dart';
import 'package:heizungstrainer/billing/kalo_billing_provider.dart';
import 'package:heizungstrainer/billing/techem_billing_provider.dart';
import 'package:heizungstrainer/billing/ista_billing_provider.dart';
import 'package:heizungstrainer/billing/minol_billing_provider.dart';
import 'package:heizungstrainer/billing/mock_billing_provider.dart';
import 'package:heizungstrainer/controllers/danfoss_ecl_310_controller.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/bosch_buderus_ems_controller.dart';
import 'package:heizungstrainer/controllers/viessmann_controller.dart';
import 'package:heizungstrainer/controllers/vaillant_ebusd_controller.dart';
import 'package:heizungstrainer/controllers/weishaupt_wem_controller.dart';
import 'package:heizungstrainer/controllers/nibe_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/controllers/mock_heating_controller.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
import 'package:heizungstrainer/models/bosch_buderus_ems_config.dart';
import 'package:heizungstrainer/models/viessmann_config.dart';
import 'package:heizungstrainer/models/vaillant_ebusd_config.dart';
import 'package:heizungstrainer/models/weishaupt_wem_config.dart';
import 'package:heizungstrainer/models/nibe_modbus_config.dart';
import 'package:heizungstrainer/services/brunata_local_scraper_service.dart';
import 'package:heizungstrainer/services/modbus_service.dart';

/// Metadata entry describing a supported or planned heating controller.
class ControllerDescriptor {
  final String id;
  final String brand;
  final String model;
  final ConnectionProtocol protocol;
  final String description;
  final bool isSupported;
  final IconData icon;

  /// Whether the driver's register map and write path have been verified on
  /// real hardware. Unverified (Beta) drivers are read-only until the user
  /// explicitly allows writes for that controller.
  final bool isHardwareVerified;

  const ControllerDescriptor({
    required this.id,
    required this.brand,
    required this.model,
    required this.protocol,
    required this.description,
    required this.isSupported,
    required this.icon,
    this.isHardwareVerified = false,
  });
}

/// Metadata entry describing a supported or planned billing/metering service.
class BillingProviderDescriptor {
  final String id;
  final String name;
  final String organization;
  final BillingAuthType authType;
  final String description;
  final bool isSupported;
  final IconData icon;

  const BillingProviderDescriptor({
    required this.id,
    required this.name,
    required this.organization,
    required this.authType,
    required this.description,
    required this.isSupported,
    required this.icon,
  });
}

/// Central registry of all heating controller hardware and billing providers.
class DeviceRegistry {
  /// All known controller options.
  static const List<ControllerDescriptor> knownControllers = [
    ControllerDescriptor(
      id: 'danfoss_ecl_310',
      brand: 'Danfoss',
      model: 'ECL Comfort 310 / 210',
      protocol: ConnectionProtocol.modbusTcp,
      description: 'Direkte Modbus-TCP-Abfrage im lokalen Heimnetzwerk (Port 502).',
      isSupported: true,
      isHardwareVerified: true,
      icon: Icons.developer_board_rounded,
    ),
    ControllerDescriptor(
      id: 'viessmann_vicare',
      brand: 'Viessmann',
      model: 'Vitotronic & ViCare',
      protocol: ConnectionProtocol.proprietary,
      description: 'Vollwertiger Betrieb über lokales Optolink (vcontrold) oder ViCare API.',
      isSupported: true,
      icon: Icons.heat_pump_rounded,
    ),
    ControllerDescriptor(
      id: 'bosch_buderus_ems',
      brand: 'Bosch / Buderus',
      model: 'EMS-ESP / KM200',
      protocol: ConnectionProtocol.restApi,
      description: 'Vollwertiger EMS-ESP REST-API Betrieb (BBQKees, Buderus Logamatic, Bosch Condens).',
      isSupported: true,
      icon: Icons.fireplace_rounded,
    ),
    ControllerDescriptor(
      id: 'vaillant_ebusd',
      brand: 'Vaillant',
      model: 'eBUS / eBUSd Gateway',
      protocol: ConnectionProtocol.restApi,
      description: 'Vollwertiger Betrieb über eBUSd HTTP JSON API (sensoCOMFORT, multiMATIC, calorMATIC).',
      isSupported: true,
      icon: Icons.solar_power_rounded,
    ),
    ControllerDescriptor(
      id: 'weishaupt_wem',
      brand: 'Weishaupt',
      model: 'WEM Gateway (Modbus TCP)',
      protocol: ConnectionProtocol.modbusTcp,
      description: 'Direkte Modbus-TCP-Anbindung für WWP LS Split-Wärmepumpen, BiBlock und WTC-GW.',
      isSupported: true,
      icon: Icons.hvac_rounded,
    ),
    ControllerDescriptor(
      id: 'nibe_modbus',
      brand: 'NIBE',
      model: 'S-Serie & F-Serie (Modbus TCP)',
      protocol: ConnectionProtocol.modbusTcp,
      description: 'Natives Modbus TCP für NIBE S-Serie (S1155/S1255/S2125) und F-Serie via Modbus 40.',
      isSupported: true,
      icon: Icons.air_rounded,
    ),
    ControllerDescriptor(
      id: 'generic_modbus',
      brand: 'Generisch',
      model: 'Modbus TCP Heizungsregler',
      protocol: ConnectionProtocol.modbusTcp,
      description: 'Vollwertiger Modbus-TCP-Betrieb für TA UVR16x2, Siemens Synco, Wolf u.a.',
      isSupported: true,
      icon: Icons.settings_input_component_rounded,
    ),
  ];

  /// All known billing and sub-metering providers.
  static const List<BillingProviderDescriptor> knownBillingProviders = [
    BillingProviderDescriptor(
      id: 'brunata_hamburg',
      name: 'Brunata Hamburg',
      organization: 'Brunata Wärmemessdienst Hamburg',
      authType: BillingAuthType.portalScraper,
      description: 'Automatische Monats- und Liegenschafts-Synchronisation über das Mieterportal (portal.brunata-hamburg.de).',
      isSupported: true,
      icon: Icons.apartment_rounded,
    ),
    BillingProviderDescriptor(
      id: 'brunata_muenchen',
      name: 'Brunata München',
      organization: 'BRUNATA Wärmemessdienst München',
      authType: BillingAuthType.portalScraper,
      description: 'uVI-Verbrauchsinformation und Monatsanalyse über das BRUNATA-METRONA Portal München.',
      isSupported: true,
      icon: Icons.location_city_rounded,
    ),
    BillingProviderDescriptor(
      id: 'brunata_huerth',
      name: 'Brunata Hürth',
      organization: 'BRUNATA-METRONA GmbH Hürth',
      authType: BillingAuthType.portalScraper,
      description: 'Verbrauchsauswertung und Liegenschaftsvergleich über das BRUNATA-METRONA Portal West (Hürth/Köln).',
      isSupported: true,
      icon: Icons.domain_rounded,
    ),
    BillingProviderDescriptor(
      id: 'kalo',
      name: 'KALO (Kalorimeta)',
      organization: 'Kalorimeta GmbH (noventic)',
      authType: BillingAuthType.portalScraper,
      description: 'Verbrauchsanalyse für Heizung und Warmwasser über das KALO Mieter- & Bewohnerportal.',
      isSupported: true,
      icon: Icons.speed_rounded,
    ),
    BillingProviderDescriptor(
      id: 'techem_smart',
      name: 'Techem Smart System',
      organization: 'Techem Energy Services GmbH',
      authType: BillingAuthType.restApi,
      description: 'Funk-Heizkostenverteiler & Mieterportal-Integration über Techem Smart Services.',
      isSupported: true,
      icon: Icons.sensors_rounded,
    ),
    BillingProviderDescriptor(
      id: 'ista_ecotrend',
      name: 'ista EcoTrend (Essen)',
      organization: 'ista SE (Essen)',
      authType: BillingAuthType.restApi,
      description: 'Monatliche unterjährige Verbrauchsinformation (uVI) via ista EcoTrend Webportal & API.',
      isSupported: true,
      icon: Icons.eco_rounded,
    ),
    BillingProviderDescriptor(
      id: 'minol_zenner',
      name: 'Minol Messtechnik',
      organization: 'Minol Messtechnik W. Lehmann GmbH & Co. KG',
      authType: BillingAuthType.portalScraper,
      description: 'Monatliche Verbrauchsinformation via Minol e-Service Portal & Abrechnungsimport.',
      isSupported: true,
      icon: Icons.receipt_long_rounded,
    ),
  ];

  /// Factory creating default active controller.
  static HeatingController createDefaultController() {
    return DanfossEcl310Controller();
  }

  /// Factory creating default active billing provider.
  static BillingProvider createDefaultBillingProvider() {
    return BrunataHamburgBillingProvider();
  }

  /// Looks up a controller descriptor by id, falling back to Danfoss.
  static ControllerDescriptor getControllerDescriptor(String id) {
    return knownControllers.firstWhere(
      (c) => c.id == id,
      orElse: () => knownControllers.first,
    );
  }

  /// Looks up a billing provider descriptor by id, falling back to Brunata.
  static BillingProviderDescriptor getBillingProviderDescriptor(String id) {
    return knownBillingProviders.firstWhere(
      (b) => b.id == id,
      orElse: () => knownBillingProviders.first,
    );
  }

  /// Creates a controller instance for the given ID.
  ///
  /// Returns a real adapter for supported hardware (Danfoss, Generic Modbus, Bosch/Buderus,
  /// Viessmann, Vaillant, Weishaupt, NIBE) or a simulated mock adapter for brand previews.
  static HeatingController createController(
    String id, {
    ModbusService? modbusService,
    GenericModbusConfig? genericModbusConfig,
    BoschBuderusEmsConfig? boschBuderusConfig,
    ViessmannConfig? viessmannConfig,
    VaillantEbusdConfig? vaillantConfig,
    WeishauptWemConfig? weishauptConfig,
    NibeModbusConfig? nibeConfig,
  }) {
    if (id == 'danfoss_ecl_310') {
      return DanfossEcl310Controller(modbusService: modbusService);
    }
    if (id == 'generic_modbus') {
      return GenericModbusController(config: genericModbusConfig);
    }
    if (id == 'bosch_buderus_ems') {
      return BoschBuderusEmsController(config: boschBuderusConfig);
    }
    if (id == 'viessmann_vicare') {
      return ViessmannController(config: viessmannConfig);
    }
    if (id == 'vaillant_ebusd') {
      return VaillantEbusdController(config: vaillantConfig);
    }
    if (id == 'weishaupt_wem') {
      return WeishauptWemController(config: weishauptConfig);
    }
    if (id == 'nibe_modbus') {
      return NibeModbusController(config: nibeConfig);
    }
    final desc = getControllerDescriptor(id);
    return MockHeatingController(
      id: desc.id,
      brandName: desc.brand,
      modelName: desc.model,
      protocol: desc.protocol,
    );
  }

  /// Creates a billing provider instance for the given ID.
  ///
  /// Returns a concrete adapter for supported services (Brunata Hamburg,
  /// Brunata München, Brunata Hürth, KALO, Techem, ista, Minol) or a
  /// simulated mock adapter for testing.
  static BillingProvider createBillingProvider(
    String id, {
    BrunataLocalScraperService? scraperService,
    FlutterSecureStorage? secureStorage,
    double? pricePerKwh,
  }) {
    switch (id) {
      case 'brunata_hamburg':
        return BrunataHamburgBillingProvider(scraper: scraperService);
      case 'brunata_muenchen':
        return BrunataMuenchenBillingProvider(secureStorage: secureStorage);
      case 'brunata_huerth':
        return BrunataHuerthBillingProvider(secureStorage: secureStorage);
      case 'kalo':
        return KaloBillingProvider(secureStorage: secureStorage);
      case 'techem_smart':
        return TechemBillingProvider(secureStorage: secureStorage);
      case 'ista_ecotrend':
        return IstaEcoTrendBillingProvider(secureStorage: secureStorage);
      case 'minol_zenner':
        return MinolBillingProvider(secureStorage: secureStorage);
      default:
        final desc = getBillingProviderDescriptor(id);
        return MockBillingProvider(
          id: desc.id,
          displayName: desc.name,
          organization: desc.organization,
          authType: desc.authType,
        );
    }
  }
}

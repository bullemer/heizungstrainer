import 'package:flutter/material.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';
import 'package:heizungstrainer/billing/brunata_hamburg_billing_provider.dart';
import 'package:heizungstrainer/billing/mock_billing_provider.dart';
import 'package:heizungstrainer/controllers/danfoss_ecl_310_controller.dart';
import 'package:heizungstrainer/controllers/generic_modbus_controller.dart';
import 'package:heizungstrainer/controllers/heating_controller.dart';
import 'package:heizungstrainer/controllers/mock_heating_controller.dart';
import 'package:heizungstrainer/models/generic_modbus_config.dart';
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

  const ControllerDescriptor({
    required this.id,
    required this.brand,
    required this.model,
    required this.protocol,
    required this.description,
    required this.isSupported,
    required this.icon,
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
      icon: Icons.developer_board_rounded,
    ),
    ControllerDescriptor(
      id: 'viessmann_vicare',
      brand: 'Viessmann',
      model: 'Vitotronic & ViCare',
      protocol: ConnectionProtocol.restApi,
      description: 'Cloud- und Optolink-Anbindung für Vitodens und Vitocal.',
      isSupported: false,
      icon: Icons.heat_pump_rounded,
    ),
    ControllerDescriptor(
      id: 'bosch_buderus_ems',
      brand: 'Bosch / Buderus',
      model: 'EMS-ESP / KM200',
      protocol: ConnectionProtocol.restApi,
      description: 'Lokale REST- und MQTT-Schnittstelle über das EMS-Bus-Gateway.',
      isSupported: false,
      icon: Icons.fireplace_rounded,
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
      description: 'Automatische Monats- und Liegenschafts-Synchronisation über das Mieterportal.',
      isSupported: true,
      icon: Icons.apartment_rounded,
    ),
    BillingProviderDescriptor(
      id: 'techem_smart',
      name: 'Techem Smart System',
      organization: 'Techem Energy Services GmbH',
      authType: BillingAuthType.restApi,
      description: 'Verbrauchsübermittlung über Techem Funk-Heizkostenverteiler.',
      isSupported: false,
      icon: Icons.sensors_rounded,
    ),
    BillingProviderDescriptor(
      id: 'ista_ecotrend',
      name: 'ista EcoTrend',
      organization: 'ista SE',
      authType: BillingAuthType.restApi,
      description: 'Monatliche unterjährige Verbrauchsinformation (uVI) via ista Portal.',
      isSupported: false,
      icon: Icons.eco_rounded,
    ),
    BillingProviderDescriptor(
      id: 'minol_zenner',
      name: 'Minol Messtechnik',
      organization: 'Minol Messtechnik W. Lehmann GmbH & Co. KG',
      authType: BillingAuthType.fileImport,
      description: 'Direkter Import von Abrechnungsnachweisen und Minol e-Service.',
      isSupported: false,
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
  /// Returns a real adapter for supported hardware (Danfoss) or a
  /// simulated mock adapter for brand previews.
  static HeatingController createController(
    String id, {
    ModbusService? modbusService,
    GenericModbusConfig? genericModbusConfig,
  }) {
    if (id == 'danfoss_ecl_310') {
      return DanfossEcl310Controller(modbusService: modbusService);
    }
    if (id == 'generic_modbus') {
      return GenericModbusController(config: genericModbusConfig);
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
  /// Returns a real scraper adapter for Brunata Hamburg or a
  /// simulated mock adapter for other providers.
  static BillingProvider createBillingProvider(
    String id, {
    BrunataLocalScraperService? scraperService,
    double? pricePerKwh,
  }) {
    if (id == 'brunata_hamburg') {
      return BrunataHamburgBillingProvider(scraper: scraperService);
    }
    final desc = getBillingProviderDescriptor(id);
    return MockBillingProvider(
      id: desc.id,
      displayName: desc.name,
      organization: desc.organization,
      authType: desc.authType,
    );
  }
}

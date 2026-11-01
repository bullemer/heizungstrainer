import 'package:heizungstrainer/billing/base_billing_provider.dart';
import 'package:heizungstrainer/billing/billing_provider.dart';

/// "Kein Messdienstleister": no billing portal. Nothing is synchronised and
/// no consumption data is shown; the tariff price is still used for the
/// savings estimates.
class NoBillingProvider extends BaseBillingProvider {
  NoBillingProvider({super.secureStorage});

  static const providerId = 'none';

  @override
  String get id => providerId;

  @override
  String get displayName => 'Kein Messdienstleister';

  @override
  String get organization => '';

  @override
  BillingAuthType get authType => BillingAuthType.fileImport;

  @override
  String get defaultPortalUrl => '';

  @override
  Future<BillingSyncResult> syncData() async =>
      BillingSyncResult.error('Kein Messdienstleister gewählt – es gibt nichts zu synchronisieren.');
}

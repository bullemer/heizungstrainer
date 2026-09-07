/// Storage key generator for billing service credentials and configurations.
abstract final class BillingStorageKeys {
  /// Secure storage key for a provider's username or customer ID.
  static String username(String providerId) {
    if (providerId == 'brunata_hamburg') return 'brunata_username';
    return '${providerId}_username';
  }

  /// Secure storage key for a provider's password or secret.
  static String password(String providerId) {
    if (providerId == 'brunata_hamburg') return 'brunata_password';
    return '${providerId}_password';
  }

  /// Secure storage key for a provider's custom portal URL.
  static String portalUrl(String providerId) {
    if (providerId == 'brunata_hamburg') return 'brunata_portal_url';
    return '${providerId}_portal_url';
  }

  /// Secure storage key for API bearer tokens (e.g. ista, Techem).
  static String apiToken(String providerId) {
    return '${providerId}_api_token';
  }

  /// Secure storage key for provider-specific price per kWh.
  static String pricePerKwh(String providerId) {
    if (providerId == 'brunata_hamburg') return 'brunata_price_per_kwh';
    return '${providerId}_price_per_kwh';
  }
}

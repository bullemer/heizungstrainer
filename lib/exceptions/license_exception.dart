/// Thrown when a user attempts a Pro-only operation without an active Pro license.
class LicenseRequiredException implements Exception {
  final String message;
  final String? featureName;

  const LicenseRequiredException({
    required this.message,
    this.featureName,
  });

  @override
  String toString() => 'LicenseRequiredException: $message';
}

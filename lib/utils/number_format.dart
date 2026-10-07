/// Decimal text with commercial rounding (.5 away from zero).
///
/// `toStringAsFixed` rounds the binary value: 2645 × 0.01 is stored as
/// 26.4499… and would show as "26.4" while the controller shows 26.45 → 26.5.
extension FixedDecimal on num {
  String fixed(int digits) {
    var f = 1;
    for (var i = 0; i < digits; i++) {
      f *= 10;
    }
    final scaled = this * f;
    final rounded = (scaled + (scaled >= 0 ? 1e-7 : -1e-7)).round();
    return (rounded / f).toStringAsFixed(digits);
  }
}

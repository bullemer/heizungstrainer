import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/utils/number_format.dart';

void main() {
  test('rounds like the controller (.5 away from zero), not by binary artefacts', () {
    expect((2645 * 0.01).fixed(1), '26.5'); // toStringAsFixed gives 26.4
    expect((1305 * 0.01).fixed(1), '13.1');
    expect((2644 * 0.01).fixed(1), '26.4');
    expect((2589 * 0.01).fixed(1), '25.9');
    expect((-15 * 0.01).fixed(1), '-0.2');
    expect(21.fixed(1), '21.0');
    expect(1269.4.fixed(0), '1269');
    expect(0.125.fixed(2), '0.13');
  });

  test('A247 reads S4 and S8 in addition; other applications do not', () {
    expect(ECLRegisters.extraSensorsFor('A247.1 v4.00').map((p) => p.modbusAddress), [10203, 10207, 12189]);
    expect(ECLRegisters.extraSensorsFor('A266.1 v1.08'), isEmpty);
    expect(ECLRegisters.extraSensorsFor(null), isEmpty);
  });
}

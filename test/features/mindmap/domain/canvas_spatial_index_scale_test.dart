import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_spatial_index.dart';

void main() {
  test('spatial index keeps correctness and sub-quadratic scaling at 50k', () {
    final tenThousand = _measureScale(10000);
    final fiftyThousand = _measureScale(50000);

    expect(tenThousand.matches, 100);
    expect(fiftyThousand.matches, 100);
    expect(tenThousand.checksum, 49995000);
    expect(fiftyThousand.checksum, 49995000);
    expect(fiftyThousand.workUnits, lessThan(tenThousand.workUnits * 8));
  });
}

_ScaleResult _measureScale(int count) {
  final index = CanvasSpatialIndex<int>();
  var workUnits = 0;
  for (var value = 0; value < count; value++) {
    final x = (value % 100) * 50.0;
    final y = (value ~/ 100) * 50.0;
    index.insert(value, CanvasBounds.fromLTWH(x, y, 20, 20));
    workUnits++;
  }
  var checksum = 0;
  var matches = 0;
  for (var query = 0; query < 100; query++) {
    final result = index.query(
      CanvasBounds.fromLTWH(
        (query % 10) * 500.0,
        (query ~/ 10) * 500.0,
        500,
        500,
      ),
    );
    matches = result.length;
    checksum += result.fold(0, (sum, value) => sum + value);
    workUnits += result.length;
  }
  return _ScaleResult(
    matches: matches,
    checksum: checksum,
    workUnits: workUnits,
  );
}

final class _ScaleResult {
  const _ScaleResult({
    required this.matches,
    required this.checksum,
    required this.workUnits,
  });

  final int matches;
  final int checksum;
  final int workUnits;
}

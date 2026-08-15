import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/features/mindmap/domain/canvas_connector_router.dart';
import 'package:var_app/features/mindmap/domain/canvas_spatial_index.dart';

void main() {
  test('uniform grid indexes and updates bounds', () {
    final index = CanvasSpatialIndex<String>(cellSize: 100)
      ..insert('near', CanvasBounds.fromLTWH(10, 10, 20, 20))
      ..insert('wide', CanvasBounds.fromLTWH(90, 90, 30, 30));

    expect(index.query(CanvasBounds.fromLTWH(0, 0, 100, 100)), {
      'near',
      'wide',
    });
    index.insert('near', CanvasBounds.fromLTWH(500, 500, 20, 20));
    expect(index.query(CanvasBounds.fromLTWH(0, 0, 100, 100)), {'wide'});
  });

  test('uniform grid handles 10000 objects', () {
    final index = CanvasSpatialIndex<int>();
    for (var value = 0; value < 10000; value++) {
      final x = (value % 100) * 50.0;
      final y = (value ~/ 100) * 50.0;
      index.insert(value, CanvasBounds.fromLTWH(x, y, 20, 20));
    }

    expect(index.length, 10000);
    expect(index.query(CanvasBounds.fromLTWH(0, 0, 500, 500)).length, 100);
  });

  test('nearest attachment selects deterministic cardinal port', () {
    const bounds = CanvasBounds(0, 0, 100, 80);

    expect(
      nearestConnectorAttachment(bounds, const CanvasPoint(180, 45)).port,
      CanvasConnectorPort.right,
    );
    expect(
      nearestConnectorAttachment(bounds, const CanvasPoint(50, -100)).point,
      const CanvasPoint(50, 0),
    );
  });

  test('orthogonal route deterministically avoids obstacle', () {
    final route = routeOrthogonalConnector(
      start: const CanvasPoint(0, 50),
      end: const CanvasPoint(200, 50),
      obstacles: const <CanvasBounds>[CanvasBounds(80, 20, 120, 80)],
      clearance: 10,
    );

    expect(route, <CanvasPoint>[
      const CanvasPoint(0, 50),
      const CanvasPoint(0, 10),
      const CanvasPoint(200, 10),
      const CanvasPoint(200, 50),
    ]);
    expect(
      routeOrthogonalConnector(
        start: const CanvasPoint(0, 50),
        end: const CanvasPoint(200, 50),
        obstacles: const <CanvasBounds>[CanvasBounds(80, 20, 120, 80)],
        clearance: 10,
      ),
      route,
    );
  });
}

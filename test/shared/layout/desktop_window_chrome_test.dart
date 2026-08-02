import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:var_app/core/theme/app_colors.dart';
import 'package:var_app/core/theme/app_theme.dart';
import 'package:var_app/shared/layout/desktop_window_chrome.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  Widget app(_FakeWindowController controller, {bool enabled = true}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: DesktopWindowChrome(
        controller: controller,
        enabled: enabled,
        child: const ColoredBox(
          key: ValueKey('content'),
          color: Colors.transparent,
        ),
      ),
    );
  }

  testWidgets('renders title menus inside app overlay', (tester) async {
    final controller = _FakeWindowController();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => DesktopWindowChrome(
                controller: controller,
                enabled: true,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ],
        ),
        home: const SizedBox.expand(),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('windows-title-bar')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('windows-menu-file')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('windows-menu-quickCapture')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled path leaves child unchanged without native calls', (
    tester,
  ) async {
    final controller = _FakeWindowController();

    await tester.pumpWidget(app(controller, enabled: false));

    expect(find.byKey(const ValueKey('content')), findsOneWidget);
    expect(find.byKey(const ValueKey('windows-title-bar')), findsNothing);
    expect(controller.listener, isNull);
    expect(controller.isMaximizedCalls, 0);
  });

  testWidgets('renders Astryx chrome with accessible 44 px controls', (
    tester,
  ) async {
    final controller = _FakeWindowController();
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(app(controller));
    await tester.pump();

    final context = tester.element(
      find.byKey(const ValueKey('windows-title-bar')),
    );
    final semantic = AppSemanticColors.of(context);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('windows-title-bar')),
                )
                .decoration
            as BoxDecoration;
    final border = decoration.border! as Border;

    expect(decoration.color, semantic.surface);
    expect(border.bottom.color, semantic.border);
    expect(
      tester.getSize(find.byKey(const ValueKey('windows-title-bar'))).height,
      44,
    );
    for (final key in <String>[
      'windows-minimize',
      'windows-maximize',
      'windows-close',
    ]) {
      final finder = find.byKey(ValueKey(key));
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    expect(
      tester.getSemantics(find.byKey(const ValueKey('windows-minimize'))).label,
      contains('Minimize'),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('windows-maximize'))).label,
      contains('Maximize'),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('windows-close'))).label,
      contains('Close'),
    );
    semantics.dispose();
  });

  testWidgets('window buttons call minimize maximize restore and close', (
    tester,
  ) async {
    final controller = _FakeWindowController();
    await tester.pumpWidget(app(controller));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('windows-minimize')));
    await tester.pump();
    expect(controller.minimizeCalls, 1);

    await tester.tap(find.byKey(const ValueKey('windows-maximize')));
    await tester.pump();
    expect(controller.maximizeCalls, 1);
    expect(find.byKey(const ValueKey('windows-restore')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('windows-restore')));
    await tester.pump();
    expect(controller.unmaximizeCalls, 1);
    expect(find.byKey(const ValueKey('windows-maximize')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('windows-close')));
    await tester.pump();
    expect(controller.closeCalls, 1);
  });

  testWidgets('drag region moves window and tracks native maximize events', (
    tester,
  ) async {
    final controller = _FakeWindowController();
    await tester.pumpWidget(app(controller));
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('windows-drag-region'))),
    );
    await gesture.moveBy(const Offset(24, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.startDraggingCalls, 1);

    controller.listener!.onWindowMaximize();
    await tester.pump();
    expect(find.byKey(const ValueKey('windows-restore')), findsOneWidget);

    controller.listener!.onWindowUnmaximize();
    await tester.pump();
    expect(find.byKey(const ValueKey('windows-maximize')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.listener, isNull);
  });

  testWidgets('initial maximized state renders restore control', (
    tester,
  ) async {
    final controller = _FakeWindowController(isMaximized: true);

    await tester.pumpWidget(app(controller));
    await tester.pump();

    expect(find.byKey(const ValueKey('windows-restore')), findsOneWidget);
    expect(find.byKey(const ValueKey('windows-maximize')), findsNothing);
  });
}

class _FakeWindowController implements DesktopWindowController {
  _FakeWindowController({bool isMaximized = false}) : maximized = isMaximized;

  bool maximized;
  WindowListener? listener;
  int isMaximizedCalls = 0;
  int minimizeCalls = 0;
  int maximizeCalls = 0;
  int unmaximizeCalls = 0;
  int closeCalls = 0;
  int startDraggingCalls = 0;
  int popUpWindowMenuCalls = 0;

  @override
  void addListener(WindowListener listener) => this.listener = listener;

  @override
  void removeListener(WindowListener listener) {
    if (identical(this.listener, listener)) this.listener = null;
  }

  @override
  Future<bool> isMaximized() async {
    isMaximizedCalls++;
    return maximized;
  }

  @override
  Future<void> minimize() async => minimizeCalls++;

  @override
  Future<void> maximize() async {
    maximizeCalls++;
    maximized = true;
  }

  @override
  Future<void> unmaximize() async {
    unmaximizeCalls++;
    maximized = false;
  }

  @override
  Future<void> close() async => closeCalls++;

  @override
  Future<void> startDragging() async => startDraggingCalls++;

  @override
  Future<void> popUpWindowMenu() async => popUpWindowMenuCalls++;
}

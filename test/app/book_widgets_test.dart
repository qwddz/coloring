import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/app/widgets/book_button.dart';
import 'package:coloring/app/widgets/book_dialog.dart';
import 'package:coloring/app/widgets/paper_background.dart';
import 'package:coloring/app/widgets/passe_partout.dart';
import 'package:coloring/app/widgets/round_icon_button.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: PaperBackground(child: Center(child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('book button kinds render and respond', (tester) async {
    var taps = 0;
    for (final kind in BookButtonKind.values) {
      await tester.pumpWidget(
        _host(
          BookButton(
            label: 'Go ${kind.name}',
            kind: kind,
            icon: Icons.star,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('Go ${kind.name}'));
      await tester.pump();
    }
    expect(taps, BookButtonKind.values.length);

    await tester.pumpWidget(
      _host(const BookButton(label: 'Off', onPressed: null)),
    );
    await tester.tap(find.text('Off'));
    await tester.pump();
    expect(
      tester.widget<GestureDetector>(find.byType(GestureDetector).first).onTap,
      isNull,
    );
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('labels of all button kinds line up; a press sinks the face', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final kind in BookButtonKind.values)
              BookButton(label: kind.name, kind: kind, onPressed: () {}),
          ],
        ),
      ),
    );
    final centres = [
      for (final kind in BookButtonKind.values)
        tester.getCenter(find.text(kind.name)).dy,
    ];
    expect(centres.toSet(), hasLength(1));

    final before = tester.getCenter(find.text('primary')).dy;
    final g = await tester.startGesture(tester.getCenter(find.text('primary')));
    await tester.pump();
    expect(tester.getCenter(find.text('primary')).dy, greaterThan(before));
    await g.up();
    await tester.pump();
    expect(tester.getCenter(find.text('primary')).dy, before);
  });

  testWidgets('round icon button is at least 48 dp', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        RoundIconButton(
          icon: Icons.settings,
          tooltip: 'Settings',
          onPressed: () => taps++,
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(RoundIconButton)).shortestSide,
      greaterThanOrEqualTo(48),
    );
    expect(find.byTooltip('Settings'), findsOneWidget);
    await tester.tap(find.byType(RoundIconButton));
    expect(taps, 1);
  });

  testWidgets('passe-partout tilt keeps the hit area', (tester) async {
    var taps = 0;
    Widget build(double tilt) => _host(
      PassePartout(
        tiltDegrees: tilt,
        onTap: () => taps++,
        child: const SizedBox(width: 120, height: 80),
      ),
    );
    await tester.pumpWidget(build(0));
    final untilted = tester.getSize(find.byType(PassePartout));
    await tester.pumpWidget(build(4));
    expect(tester.getSize(find.byType(PassePartout)), untilted);
    await tester.tap(find.byType(PassePartout));
    expect(taps, 1);
  });

  testWidgets('passe-partout does not animate with reduced motion', (
    tester,
  ) async {
    Widget build(bool reduced) => _host(
      PassePartout(onTap: () {}, child: const SizedBox(width: 120, height: 80)),
      disableAnimations: reduced,
    );
    await tester.pumpWidget(build(true));
    final g = await tester.startGesture(
      tester.getCenter(find.byType(PassePartout)),
    );
    await tester.pump();
    expect(find.byType(AnimatedScale), findsNothing);
    await g.up();

    await tester.pumpWidget(build(false));
    final g2 = await tester.startGesture(
      tester.getCenter(find.byType(PassePartout)),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0.97,
    );
    await g2.up();
    await tester.pumpAndSettle();
  });

  testWidgets('book dialog shows title, content and actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBookDialog<void>(
              context: context,
              builder: (_) => BookDialog(
                title: 'Title',
                content: const Text('Body'),
                actions: [
                  BookButton(
                    label: 'OK',
                    kind: BookButtonKind.text,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('dialog actions stay visible and tappable on a short screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBookDialog<void>(
              context: context,
              builder: (_) => BookDialog(
                title: 'Title',
                content: Column(
                  children: [for (var i = 0; i < 40; i++) Text('Line $i')],
                ),
                actions: [BookButton(label: 'Go', onPressed: () => taps++)],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.text('Go'));
    expect(rect.bottom, lessThanOrEqualTo(360));
    expect(rect.top, greaterThanOrEqualTo(0));
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('round icon button and tappable passe-partout are buttons', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoundIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () {},
            ),
            PassePartout(
              onTap: () {},
              child: const SizedBox(width: 40, height: 40),
            ),
            const PassePartout(child: SizedBox(width: 40, height: 40)),
          ],
        ),
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Close')),
      matchesSemantics(
        label: 'Close',
        isButton: true,
        hasTapAction: true,
        hasEnabledState: false,
      ),
    );
    expect(
      tester
          .getSemantics(find.byType(PassePartout).first)
          .flagsCollection
          .isButton,
      isTrue,
    );
    expect(
      tester
          .getSemantics(find.byType(PassePartout).last)
          .flagsCollection
          .isButton,
      isFalse,
    );
    handle.dispose();
  });
}

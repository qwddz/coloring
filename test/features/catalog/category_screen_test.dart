import 'dart:io';
import 'dart:typed_data';

import 'package:coloring/app/theme.dart';
import 'package:coloring/features/catalog/category_screen.dart';
import 'package:coloring/features/catalog/data/manifest_provider.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:coloring/features/coloring/model/work.dart';
import 'package:coloring/features/progress/data/progress_store.dart';
import 'package:coloring/features/progress/data/work_repository.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/domain/purchase_service.dart';
import 'package:coloring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/test_manifest.dart';
import '../coloring/fakes.dart';

/// Fails every read of a picture's works, like an unreadable folder.
class _BrokenWorks extends InMemoryWorkRepository {
  @override
  Future<List<Work>> worksFor(String pictureId) async =>
      throw const FileSystemException('works folder unreadable');
}

class _FixedProgress extends ProgressController {
  _FixedProgress(this.ids);

  final Set<String> ids;

  @override
  Future<Set<String>> build() async => ids;
}

void main() {
  late InMemoryWorkRepository works;

  setUp(() => works = InMemoryWorkRepository());

  Future<void> pumpScreen(
    WidgetTester tester, {
    Set<String> completed = const {},
    String categoryId = 'farm',
    bool fullAccess = false,
  }) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => CategoryScreen(categoryId: categoryId),
        ),
        GoRoute(
          path: '/coloring/:id',
          builder: (context, state) =>
              Scaffold(body: Text('stub ${state.uri}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manifestProvider.overrideWith((ref) async => testManifest),
          workRepositoryProvider.overrideWithValue(works),
          progressProvider.overrideWith(() => _FixedProgress(completed)),
          purchaseServiceProvider.overrideWithValue(
            FakePurchaseService(fullAccess: fullAccess),
          ),
        ],
        child: MaterialApp.router(
          theme: buildAppTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Work unfinished(String id, String pictureId, DateTime modified) => Work(
    id: id,
    pictureId: pictureId,
    mode: ColoringMode.free,
    colors: Uint32List(3),
    modified: modified,
  );

  testWidgets('level chips show on free and locked cards', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });

  testWidgets('a star shows only for completed pictures', (tester) async {
    await pumpScreen(tester, completed: {'farm_piglet_picnic'});
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.star_rounded)).semanticLabel,
      'Colored',
    );
    final star = find.ancestor(
      of: find.byIcon(Icons.star_rounded),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: star.first, matching: find.text('Piglet')),
      findsOneWidget,
    );
  });

  testWidgets('no star when nothing is completed', (tester) async {
    await pumpScreen(tester);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('an empty category keeps «coming soon»', (tester) async {
    await pumpScreen(tester, categoryId: 'home');
    expect(
      find.text('New pictures for this category are coming soon'),
      findsOneWidget,
    );
  });

  testWidgets('a tap with no works asks for a mode, then opens it', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Piglet'));
    await tester.pumpAndSettle();
    expect(find.text('How do you want to color?'), findsOneWidget);
    await tester.tap(find.text('By numbers'));
    await tester.pumpAndSettle();
    expect(
      find.text('stub /coloring/farm_piglet_picnic?mode=numbers'),
      findsOneWidget,
    );
  });

  testWidgets('a tap with an unfinished work continues it, no picker', (
    tester,
  ) async {
    await works.save(
      unfinished('w1', 'farm_piglet_picnic', DateTime.utc(2026, 11, 1)),
    );
    await pumpScreen(tester);
    await tester.tap(find.text('Piglet'));
    await tester.pumpAndSettle();
    expect(find.text('How do you want to color?'), findsNothing);
    expect(
      find.text('stub /coloring/farm_piglet_picnic?work=w1'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the picker does not navigate', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Piglet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stub'), findsNothing);
    expect(find.text('On the farm'), findsOneWidget);
  });

  testWidgets('a work saved between two taps changes the second decision', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.text('Piglet'));
    await tester.pumpAndSettle();
    expect(find.text('How do you want to color?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await works.save(
      unfinished('w2', 'farm_piglet_picnic', DateTime.utc(2026, 11, 2)),
    );
    await tester.tap(find.text('Piglet'));
    await tester.pumpAndSettle();
    expect(
      find.text('stub /coloring/farm_piglet_picnic?work=w2'),
      findsOneWidget,
    );
  });

  testWidgets('when the works cannot be read, a tap asks for a mode', (
    tester,
  ) async {
    works = _BrokenWorks();
    await pumpScreen(tester);
    await tester.tap(find.text('Piglet'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('How do you want to color?'), findsOneWidget);
    await tester.tap(find.text('Magic brush'));
    await tester.pumpAndSettle();
    expect(
      find.text('stub /coloring/farm_piglet_picnic?mode=magic'),
      findsOneWidget,
    );
  });

  testWidgets('a paid card opens with the full version too', (tester) async {
    await pumpScreen(tester, fullAccess: true);
    expect(find.byIcon(Icons.lock_rounded), findsNothing);
    await tester.tap(find.text('Goat'));
    await tester.pumpAndSettle();
    expect(find.text('How do you want to color?'), findsOneWidget);
  });
}

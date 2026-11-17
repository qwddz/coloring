import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/features/catalog/domain/content_manifest.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/data/revenuecat_purchase_service.dart';
import 'package:coloring/features/subscription/domain/parental_challenge.dart';
import 'package:coloring/features/subscription/domain/purchase_service.dart';

PictureEntry entry(String id, {required bool free}) => PictureEntry(
  id: id,
  categoryId: 'home',
  title: const LocalizedText({'en': 'x'}),
  level: PictureLevel.simple,
  free: free,
  asset: 'coloring/free/$id/',
);

void main() {
  group('canColor', () {
    test('free pictures always, paid ones only with the full version', () {
      final free = entry('a', free: true);
      final paid = entry('b', free: false);
      expect(canColor(free, fullAccess: false), isTrue);
      expect(canColor(free, fullAccess: true), isTrue);
      expect(canColor(paid, fullAccess: false), isFalse);
      expect(canColor(paid, fullAccess: true), isTrue);
    });
  });

  group('ParentalChallenge', () {
    test('accepts only the product, typed in digits', () {
      const challenge = ParentalChallenge(7, 8);
      expect(challenge.check('56'), isTrue);
      expect(challenge.check(' 56 '), isTrue);
      expect(challenge.check('54'), isFalse);
      expect(challenge.check(''), isFalse);
      expect(challenge.check('fifty-six'), isFalse);
    });

    test('random factors stay in 2..9', () {
      final random = Random(1);
      for (var i = 0; i < 500; i++) {
        final c = ParentalChallenge.random(random);
        expect(c.a, inInclusiveRange(2, 9));
        expect(c.b, inInclusiveRange(2, 9));
      }
    });
  });

  test('release builds need a Google Play RevenueCat key', () {
    expect(
      () => checkRevenueCatConfigured(release: true, apiKey: ''),
      throwsStateError,
    );
    expect(
      () => checkRevenueCatConfigured(release: true, apiKey: 'test_x'),
      throwsStateError,
    );
    checkRevenueCatConfigured(release: true, apiKey: 'goog_x');
    // Debug and profile: no key, or the RevenueCat Test Store.
    checkRevenueCatConfigured(release: false, apiKey: '');
    checkRevenueCatConfigured(release: false, apiKey: 'test_x');
  });

  test('a Test Store key uses the real RevenueCat service', () {
    final container = ProviderContainer(
      overrides: [revenueCatApiKeyProvider.overrideWithValue('test_x')],
    );
    addTearDown(container.dispose);
    expect(
      container.read(purchaseServiceProvider),
      isA<RevenueCatPurchaseService>(),
    );
  });

  test('without a key the fake test store is used', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(purchaseServiceProvider);
    expect(service, isA<FakePurchaseService>());
    expect((service as FakePurchaseService).testStore, isTrue);
  });

  group('PurchaseController', () {
    late FakePurchaseService store;
    late ProviderContainer container;
    final paid = entry('paid', free: false);

    setUp(() {
      store = FakePurchaseService();
      container = ProviderContainer(
        overrides: [purchaseServiceProvider.overrideWithValue(store)],
      );
      container.listen(canColorProvider(paid), (_, _) {});
      container.listen(purchaseControllerProvider, (_, _) {});
    });
    tearDown(() => container.dispose());

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    PurchaseController controller() =>
        container.read(purchaseControllerProvider.notifier);
    PurchaseStatus status() => container.read(purchaseControllerProvider);
    bool canColorPaid() => container.read(canColorProvider(paid));

    test('a purchase unlocks paid pictures at once', () async {
      await settle();
      expect(canColorPaid(), isFalse);
      await controller().purchase();
      await settle();
      expect(status(), PurchaseStatus.purchased);
      expect(canColorPaid(), isTrue);
    });

    test('a cancelled purchase keeps them locked', () async {
      store.purchaseBehavior = FakePurchaseBehavior.cancel;
      await controller().purchase();
      await settle();
      expect(status(), PurchaseStatus.cancelled);
      expect(canColorPaid(), isFalse);
    });

    test('a store error is reported', () async {
      store.purchaseBehavior = FakePurchaseBehavior.fail;
      await controller().purchase();
      await settle();
      expect(status(), PurchaseStatus.failed);
      expect(canColorPaid(), isFalse);
    });

    test('a pending payment is reported as pending', () async {
      store.purchaseBehavior = FakePurchaseBehavior.pending;
      await controller().purchase();
      await settle();
      expect(status(), PurchaseStatus.pending);
      expect(canColorPaid(), isFalse);
    });

    test('an already owned version is restored', () async {
      store
        ..purchaseBehavior = FakePurchaseBehavior.alreadyOwned
        ..restorable = true;
      await controller().purchase();
      await settle();
      expect(status(), PurchaseStatus.purchased);
      expect(canColorPaid(), isTrue);
    });

    test('already owned with nothing to restore fails', () async {
      store.purchaseBehavior = FakePurchaseBehavior.alreadyOwned;
      await controller().purchase();
      await settle();
      expect(status(), PurchaseStatus.failed);
      expect(canColorPaid(), isFalse);
    });

    test('a store error during restore is a restore failure', () async {
      store.restoreFails = true;
      await controller().restore();
      expect(status(), PurchaseStatus.restoreFailed);
    });

    test('restore brings back an earlier purchase', () async {
      await controller().restore();
      expect(status(), PurchaseStatus.nothingToRestore);
      store.restorable = true;
      await controller().restore();
      await settle();
      expect(status(), PurchaseStatus.restored);
      expect(canColorPaid(), isTrue);
    });

    test('a refund locks the paid pictures again', () async {
      await controller().purchase();
      await settle();
      expect(canColorPaid(), isTrue);
      store.setFullAccess(false);
      await settle();
      expect(canColorPaid(), isFalse);
    });
  });
}

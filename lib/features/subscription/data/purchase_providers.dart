import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/domain/content_manifest.dart';
import '../domain/parental_challenge.dart';
import '../domain/purchase_service.dart';
import 'review_access.dart';
import 'revenuecat_purchase_service.dart';

/// RevenueCat public SDK key from `--dart-define=REVENUECAT_API_KEY=goog_…`.
/// Empty switches to the instant "test store"; a `test_…` key uses the
/// RevenueCat Test Store in debug and profile builds. Release builds need a
/// Google Play key, see [checkRevenueCatConfigured].
const revenueCatApiKeyFromEnvironment = String.fromEnvironment(
  'REVENUECAT_API_KEY',
);

final revenueCatApiKeyProvider = Provider<String>(
  (ref) => revenueCatApiKeyFromEnvironment,
);

/// Throws in release builds made without a Google Play `REVENUECAT_API_KEY`:
/// without one the paid pictures could never be bought, and a Test Store
/// `test_…` key must not ship.
void checkRevenueCatConfigured({
  required bool release,
  required String apiKey,
}) {
  if (release && !apiKey.startsWith('goog_')) {
    throw StateError(
      'REVENUECAT_API_KEY must be a Google Play key (goog_…) in release. '
      'Build with --dart-define=REVENUECAT_API_KEY=goog_<key>.',
    );
  }
}

/// RevenueCat with a key, else the fake test store. The RevenueCat SDK is
/// never touched without a key, so tests and keyless debug runs stay local.
final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  final apiKey = ref.watch(revenueCatApiKeyProvider);
  final PurchaseService service = apiKey.isEmpty
      ? FakePurchaseService(testStore: true)
      : RevenueCatPurchaseService(apiKey);
  ref.onDispose(service.dispose);
  return service;
});

/// Whether the full version is unlocked; follows purchases and refunds. The
/// reviewer code ([reviewAccessProvider]) unlocks it without a purchase.
final fullAccessProvider = StreamProvider<bool>(
  (ref) => ref.watch(reviewAccessProvider)
      ? Stream.value(true)
      : ref.watch(purchaseServiceProvider).fullAccess,
);

/// The single access rule: free pictures, or everything with the full version.
bool canColor(PictureEntry entry, {required bool fullAccess}) =>
    entry.free || fullAccess;

/// [canColor] with the current access; paid pictures stay locked while the
/// status loads.
final canColorProvider = Provider.autoDispose.family<bool, PictureEntry>(
  (ref, entry) =>
      canColor(entry, fullAccess: ref.watch(fullAccessProvider).value ?? false),
);

/// The store offer shown on the paywall.
final purchaseOfferProvider = FutureProvider.autoDispose<PurchaseOffer>(
  (ref) => ref.watch(purchaseServiceProvider).fetchOffer(),
);

enum PurchaseStatus {
  idle,
  busy,
  purchased,
  restored,
  nothingToRestore,
  cancelled,
  pending,

  /// The purchase failed.
  failed,
  restoreFailed,
}

/// Runs a purchase or a restore and reports how it ended. Access itself
/// comes from [fullAccessProvider].
class PurchaseController extends Notifier<PurchaseStatus> {
  @override
  PurchaseStatus build() => PurchaseStatus.idle;

  Future<void> purchase() => _run(
    (service) async => switch (await service.purchase()) {
      PurchaseOutcome.purchased => PurchaseStatus.purchased,
      PurchaseOutcome.cancelled => PurchaseStatus.cancelled,
      PurchaseOutcome.pending => PurchaseStatus.pending,
    },
    failure: PurchaseStatus.failed,
  );

  Future<void> restore() => _run(
    (service) async => await service.restore()
        ? PurchaseStatus.restored
        : PurchaseStatus.nothingToRestore,
    failure: PurchaseStatus.restoreFailed,
  );

  Future<void> _run(
    Future<PurchaseStatus> Function(PurchaseService service) action, {
    required PurchaseStatus failure,
  }) async {
    if (state == PurchaseStatus.busy) return;
    final service = ref.read(purchaseServiceProvider);
    state = PurchaseStatus.busy;
    PurchaseStatus result;
    try {
      result = await action(service);
    } catch (_) {
      result = failure;
    }
    if (ref.mounted) state = result;
  }
}

final purchaseControllerProvider =
    NotifierProvider.autoDispose<PurchaseController, PurchaseStatus>(
      PurchaseController.new,
    );

/// Makes the task for the parental gate; tests fix the numbers.
final parentalChallengeProvider = Provider<ParentalChallenge Function()>(
  (ref) => ParentalChallenge.random,
);

enum ParentalGateStatus {
  ready,

  /// A gate is on screen; another tap must not open a second one.
  open,

  /// A wrong answer was given; the gate stays shut for a while.
  coolingDown,
}

/// Whether the parental gate can be opened now.
class ParentalGateController extends Notifier<ParentalGateStatus> {
  static const cooldown = Duration(seconds: 10);

  Timer? _cooldown;

  @override
  ParentalGateStatus build() {
    ref.onDispose(() => _cooldown?.cancel());
    return ParentalGateStatus.ready;
  }

  /// False unless the gate is [ParentalGateStatus.ready]; else marks it open.
  bool open() {
    if (state != ParentalGateStatus.ready) return false;
    state = ParentalGateStatus.open;
    return true;
  }

  /// A wrong answer starts the [cooldown]; a right one or a cancel does not.
  void close({required bool wrongAnswer}) {
    if (!wrongAnswer) {
      state = ParentalGateStatus.ready;
      return;
    }
    state = ParentalGateStatus.coolingDown;
    _cooldown?.cancel();
    _cooldown = Timer(cooldown, () => state = ParentalGateStatus.ready);
  }
}

final parentalGateProvider =
    NotifierProvider<ParentalGateController, ParentalGateStatus>(
      ParentalGateController.new,
    );

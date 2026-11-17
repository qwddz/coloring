import 'dart:async';

/// The "Full version" offer as the store sells it.
class PurchaseOffer {
  const PurchaseOffer({required this.price, this.testStore = false});

  /// Price in the buyer's currency, formatted by the store, like `$4.99`.
  final String price;

  /// True for [FakePurchaseService] in builds without a RevenueCat key:
  /// nothing is charged and the purchase is instant.
  final bool testStore;
}

/// How a purchase ended. [pending]: the payment is waiting (cash, slow
/// card); access arrives through [PurchaseService.fullAccess] once it clears.
enum PurchaseOutcome { purchased, cancelled, pending }

/// The one-time "Full version" purchase. Only the entitlement matters, not
/// the product, so the product or its price can change without code changes.
abstract interface class PurchaseService {
  /// Whether the full version is unlocked: the current value first, then
  /// every change (purchase, restore, refund).
  Stream<bool> get fullAccess;

  Future<PurchaseOffer> fetchOffer();

  /// Throws when the store fails; a cancelled or pending purchase is not an
  /// error.
  Future<PurchaseOutcome> purchase();

  /// Restores earlier purchases; true when the full version is unlocked.
  Future<bool> restore();

  void dispose();
}

enum FakePurchaseBehavior {
  succeed,
  cancel,
  fail,
  pending,

  /// The store says the account already owns the product, like Google Play
  /// does after a reinstall: the purchase falls back to a restore.
  alreadyOwned,
}

/// In-memory store for tests and for debug builds without a RevenueCat key.
class FakePurchaseService implements PurchaseService {
  FakePurchaseService({
    this._fullAccess = false,
    this.price = r'$4.99',
    this.testStore = false,
    this.purchaseBehavior = FakePurchaseBehavior.succeed,
    this.restorable = false,
    this.offerFails = false,
    this.restoreFails = false,
  });

  final String price;
  final bool testStore;
  FakePurchaseBehavior purchaseBehavior;

  /// Whether the store account holds a purchase that [restore] brings back.
  bool restorable;
  bool offerFails;
  bool restoreFails;

  bool _fullAccess;
  final _changes = StreamController<bool>.broadcast();

  @override
  Stream<bool> get fullAccess {
    StreamSubscription<bool>? changes;
    late final StreamController<bool> controller;
    controller = StreamController<bool>(
      onListen: () {
        controller.add(_fullAccess);
        changes = _changes.stream.listen(controller.add);
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  /// Grants or revokes access from outside, like a refund does.
  void setFullAccess(bool value) {
    if (value == _fullAccess) return;
    _fullAccess = value;
    _changes.add(value);
  }

  @override
  Future<PurchaseOffer> fetchOffer() async {
    if (offerFails) throw StateError('No offer');
    return PurchaseOffer(price: price, testStore: testStore);
  }

  @override
  Future<PurchaseOutcome> purchase() async {
    switch (purchaseBehavior) {
      case FakePurchaseBehavior.succeed:
        restorable = true;
        setFullAccess(true);
        return PurchaseOutcome.purchased;
      case FakePurchaseBehavior.cancel:
        return PurchaseOutcome.cancelled;
      case FakePurchaseBehavior.fail:
        throw StateError('Purchase failed');
      case FakePurchaseBehavior.pending:
        return PurchaseOutcome.pending;
      case FakePurchaseBehavior.alreadyOwned:
        if (await restore()) return PurchaseOutcome.purchased;
        throw StateError('Already owned, but nothing to restore');
    }
  }

  @override
  Future<bool> restore() async {
    if (restoreFails) throw StateError('Restore failed');
    if (restorable) setFullAccess(true);
    return _fullAccess;
  }

  @override
  void dispose() => _changes.close();
}

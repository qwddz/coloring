import 'dart:async';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../domain/purchase_service.dart';

/// Google Play purchases through RevenueCat: entitlement `full`, offering
/// `default` with a lifetime package. The SDK caches the customer info, so
/// a bought version works offline.
class RevenueCatPurchaseService implements PurchaseService {
  RevenueCatPurchaseService(this._apiKey);

  static const entitlementId = 'full';
  static const offeringId = 'default';

  final String _apiKey;
  final _changes = StreamController<bool>.broadcast();
  Future<void>? _configured;
  Package? _package;

  /// A failed configure is forgotten, so the next call tries again.
  Future<void> _ready() => _configured ??=
      () async {
        await Purchases.configure(PurchasesConfiguration(_apiKey));
        Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      }().catchError((Object error, StackTrace stackTrace) {
        _configured = null;
        Error.throwWithStackTrace(error, stackTrace);
      });

  void _onCustomerInfo(CustomerInfo info) {
    if (!_changes.isClosed) _changes.add(_hasFullAccess(info));
  }

  static bool _hasFullAccess(CustomerInfo info) =>
      info.entitlements.active.containsKey(entitlementId);

  @override
  Stream<bool> get fullAccess {
    StreamSubscription<bool>? changes;
    late final StreamController<bool> controller;
    controller = StreamController<bool>(
      onListen: () async {
        // Updates first, so none is lost while the current info loads.
        var updated = false;
        changes = _changes.stream.listen((value) {
          updated = true;
          controller.add(value);
        });
        bool current;
        try {
          await _ready();
          current = _hasFullAccess(await Purchases.getCustomerInfo());
        } catch (_) {
          // No cached info and no network: locked until the listener reports.
          current = false;
        }
        if (!updated && !controller.isClosed) controller.add(current);
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  Future<Package> _loadPackage() async {
    await _ready();
    final offerings = await Purchases.getOfferings();
    final offering = offerings.getOffering(offeringId) ?? offerings.current;
    final package =
        offering?.lifetime ?? offering?.availablePackages.firstOrNull;
    if (package == null) {
      throw StateError('RevenueCat offering "$offeringId" has no packages');
    }
    return _package = package;
  }

  @override
  Future<PurchaseOffer> fetchOffer() async =>
      PurchaseOffer(price: (await _loadPackage()).storeProduct.priceString);

  @override
  Future<PurchaseOutcome> purchase() async {
    final package = _package ?? await _loadPackage();
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _onCustomerInfo(result.customerInfo);
      return _hasFullAccess(result.customerInfo)
          ? PurchaseOutcome.purchased
          : throw StateError('Purchase did not unlock "$entitlementId"');
    } on PlatformException catch (e) {
      switch (PurchasesErrorHelper.getErrorCode(e)) {
        case PurchasesErrorCode.purchaseCancelledError:
          return PurchaseOutcome.cancelled;
        case PurchasesErrorCode.paymentPendingError:
          return PurchaseOutcome.pending;
        // Bought earlier, e.g. before a reinstall: bring it back.
        case PurchasesErrorCode.productAlreadyPurchasedError:
          if (await restore()) return PurchaseOutcome.purchased;
          rethrow;
        default:
          rethrow;
      }
    }
  }

  @override
  Future<bool> restore() async {
    await _ready();
    final info = await Purchases.restorePurchases();
    _onCustomerInfo(info);
    return _hasFullAccess(info);
  }

  @override
  void dispose() {
    if (_configured != null) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    }
    _changes.close();
  }
}

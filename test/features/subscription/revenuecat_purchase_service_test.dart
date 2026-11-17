import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/features/subscription/data/revenuecat_purchase_service.dart';
import 'package:coloring/features/subscription/domain/purchase_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

Map<String, Object?> customerInfo({required bool full}) => {
  'originalAppUserId': 'user',
  'entitlements': {
    'all': {if (full) 'full': _fullEntitlement},
    'active': {if (full) 'full': _fullEntitlement},
    'verification': 'NOT_REQUESTED',
  },
  'activeSubscriptions': <String>[],
  'latestExpirationDate': null,
  'allExpirationDates': <String, Object?>{},
  'allPurchasedProductIdentifiers': <String>[],
  'firstSeen': '2026-01-01T00:00:00.000Z',
  'requestDate': '2026-01-01T00:00:00.000Z',
  'allPurchaseDates': <String, Object?>{},
  'originalApplicationVersion': null,
  'nonSubscriptionTransactions': <Object?>[],
};

const _fullEntitlement = {
  'identifier': 'full',
  'isActive': true,
  'willRenew': false,
  'periodType': 'NORMAL',
  'latestPurchaseDateMillis': 1.7e12,
  'latestPurchaseDate': '2026-01-01T00:00:00.000Z',
  'originalPurchaseDateMillis': 1.7e12,
  'originalPurchaseDate': '2026-01-01T00:00:00.000Z',
  'expirationDateMillis': null,
  'expirationDate': null,
  'productIdentifier': 'full_version',
  'isSandbox': true,
  'unsubscribeDetectedAt': null,
  'unsubscribeDetectedAtMillis': null,
  'billingIssueDetectedAt': null,
  'billingIssueDetectedAtMillis': null,
  'store': 'PLAY_STORE',
  'verification': 'NOT_REQUESTED',
};

final _package = {
  'identifier': r'$rc_lifetime',
  'packageType': 'LIFETIME',
  'product': {
    'identifier': 'full_version',
    'description': 'All pictures',
    'title': 'Full version',
    'price': 4.99,
    'priceString': r'$4.99',
    'currencyCode': 'USD',
    'introPrice': null,
    'discounts': null,
    'productCategory': 'NON_SUBSCRIPTION',
    'defaultOption': null,
    'subscriptionOptions': null,
    'presentedOfferingIdentifier': 'default',
    'subscriptionPeriod': null,
  },
  'presentedOfferingContext': {'offeringIdentifier': 'default'},
};

final _offerings = {
  'all': {
    'default': {
      'identifier': 'default',
      'serverDescription': '',
      'metadata': <String, Object?>{},
      'availablePackages': [_package],
      'lifetime': _package,
    },
  },
  'current': null,
};

PlatformException storeError(PurchasesErrorCode code) =>
    PlatformException(code: '${code.index}', message: code.name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  late List<String> calls;
  late Object? Function(String method) respond;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          final response = respond(call.method);
          if (response is PlatformException) throw response;
          return response;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('a failed configure is retried on the next call', () async {
    var configureFails = true;
    respond = (method) => switch (method) {
      'setupPurchases' when configureFails => PlatformException(code: '0'),
      'restorePurchases' => customerInfo(full: true),
      _ => null,
    };
    final service = RevenueCatPurchaseService('test_key');
    addTearDown(service.dispose);
    await expectLater(service.restore(), throwsA(isA<PlatformException>()));
    configureFails = false;
    expect(await service.restore(), isTrue);
    expect(calls.where((m) => m == 'setupPurchases'), hasLength(2));
  });

  group('purchase', () {
    late PlatformException? purchaseError;
    late bool restoredFull;
    late RevenueCatPurchaseService service;

    setUp(() {
      purchaseError = null;
      restoredFull = false;
      respond = (method) => switch (method) {
        'getOfferings' => _offerings,
        'purchasePackage' =>
          purchaseError ??
              {
                'customerInfo': customerInfo(full: true),
                'transaction': {
                  'transactionIdentifier': 't',
                  'productIdentifier': 'full_version',
                  'purchaseDate': '2026-01-01T00:00:00.000Z',
                },
              },
        'restorePurchases' => customerInfo(full: restoredFull),
        _ => null,
      };
      service = RevenueCatPurchaseService('test_key');
    });
    tearDown(() => service.dispose());

    test('succeeds', () async {
      expect(await service.purchase(), PurchaseOutcome.purchased);
    });

    test('a pending payment is pending, not an error', () async {
      purchaseError = storeError(PurchasesErrorCode.paymentPendingError);
      expect(await service.purchase(), PurchaseOutcome.pending);
    });

    test('already purchased restores the full version', () async {
      purchaseError = storeError(
        PurchasesErrorCode.productAlreadyPurchasedError,
      );
      restoredFull = true;
      expect(await service.purchase(), PurchaseOutcome.purchased);
      expect(calls, contains('restorePurchases'));
    });

    test('already purchased without the entitlement fails', () async {
      purchaseError = storeError(
        PurchasesErrorCode.productAlreadyPurchasedError,
      );
      await expectLater(service.purchase(), throwsA(isA<PlatformException>()));
    });
  });
}

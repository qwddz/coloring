import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coloring/features/subscription/data/purchase_providers.dart';
import 'package:coloring/features/subscription/data/review_access.dart';
import 'package:coloring/features/subscription/domain/purchase_service.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final codeHash = hashReviewCode('ABCD-EFGH-2345');

  Future<ProviderContainer> containerWith({
    required String codeSha256,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        reviewCodeSha256Provider.overrideWithValue(codeSha256),
        purchaseServiceProvider.overrideWithValue(FakePurchaseService()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('case, spaces and dashes do not matter', () {
    expect(hashReviewCode(' abcd efgh-2345 '), codeHash);
    expect(hashReviewCode('ABCD-EFGH-2346'), isNot(codeHash));
  });

  test('a wrong code does not unlock', () async {
    final container = await containerWith(codeSha256: codeHash);
    final redeemed = await container
        .read(reviewAccessProvider.notifier)
        .redeem('ABCD-EFGH-2346');
    expect(redeemed, isFalse);
    expect(container.read(reviewAccessProvider), isFalse);
  });

  test('without a code in the build nothing unlocks', () async {
    final container = await containerWith(codeSha256: '');
    expect(
      await container.read(reviewAccessProvider.notifier).redeem(''),
      isFalse,
    );
  });

  test('the right code unlocks the full version and is remembered', () async {
    final container = await containerWith(codeSha256: codeHash);
    final sub = container.listen(fullAccessProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(fullAccessProvider.future);
    expect(sub.read().value, isFalse);
    expect(
      await container
          .read(reviewAccessProvider.notifier)
          .redeem('abcd-efgh-2345'),
      isTrue,
    );
    expect(await container.read(fullAccessProvider.future), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final again = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        reviewCodeSha256Provider.overrideWithValue(codeHash),
      ],
    );
    addTearDown(again.dispose);
    expect(again.read(reviewAccessProvider), isTrue);
  });

  test('a build with a new code locks the old one', () async {
    final container = await containerWith(
      codeSha256: hashReviewCode('NEW-CODE'),
      prefs: {'purchase.reviewCodeSha256': codeHash},
    );
    expect(container.read(reviewAccessProvider), isFalse);
  });
}

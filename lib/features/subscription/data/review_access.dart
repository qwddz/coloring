import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/data/settings_controller.dart';

/// sha256 (hex) of the access code for Google Play reviewers, from
/// `--dart-define=REVIEW_CODE_SHA256=…`. The code itself never ships; empty
/// hides the code entry on the paywall.
const reviewCodeSha256FromEnvironment = String.fromEnvironment(
  'REVIEW_CODE_SHA256',
);

final reviewCodeSha256Provider = Provider<String>(
  (ref) => reviewCodeSha256FromEnvironment.trim().toLowerCase(),
);

/// Letters and digits in upper case: dashes, spaces and case don't matter.
String normalizeReviewCode(String code) =>
    code.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

String hashReviewCode(String code) =>
    sha256.convert(utf8.encode(normalizeReviewCode(code))).toString();

/// Whether this device unlocked the full version with the reviewer code.
/// The hash of the redeemed code is kept, so a build with a new code locks
/// devices that used the old one.
class ReviewAccessController extends Notifier<bool> {
  static const _key = 'purchase.reviewCodeSha256';

  @override
  bool build() {
    final expected = ref.watch(reviewCodeSha256Provider);
    return expected.isNotEmpty &&
        ref.read(sharedPreferencesProvider).getString(_key) == expected;
  }

  /// True and unlocked for the right code; false otherwise.
  Future<bool> redeem(String code) async {
    final expected = ref.read(reviewCodeSha256Provider);
    if (expected.isEmpty || hashReviewCode(code) != expected) return false;
    await ref.read(sharedPreferencesProvider).setString(_key, expected);
    state = true;
    return true;
  }
}

final reviewAccessProvider = NotifierProvider<ReviewAccessController, bool>(
  ReviewAccessController.new,
);

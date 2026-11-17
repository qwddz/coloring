// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Animosaic Colors';

  @override
  String get back => 'Back';

  @override
  String get retry => 'Try again';

  @override
  String get catalogLoadError => 'Couldn\'t load the pictures';

  @override
  String get settings => 'Settings';

  @override
  String get soundEffects => 'Sounds';

  @override
  String get music => 'Music';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'Same as device';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get categoryMissing => 'This category is not available';

  @override
  String get lockedPicture => 'In the full version';

  @override
  String get parentalGateTitle => 'For grown-ups';

  @override
  String parentalGateQuestion(int a, int b) {
    return 'How much is $a × $b? Type the answer in digits.';
  }

  @override
  String get parentalGateAnswer => 'Answer';

  @override
  String get parentalGateCooldown => 'Please wait a few seconds and try again.';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get fullVersionTitle => 'Full version';

  @override
  String fullVersionIncludes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'All $count pictures in every category, and new ones as they arrive',
      one: 'All $count picture in every category, and new ones as they arrive',
    );
    return '$_temp0';
  }

  @override
  String get oneTimePurchase => 'One-time purchase, no subscription';

  @override
  String buyFor(String price) {
    return 'Buy for $price';
  }

  @override
  String get restorePurchases => 'Restore purchases';

  @override
  String get testStore => 'Test store: nothing is charged';

  @override
  String get priceLoadError => 'Couldn\'t reach the store';

  @override
  String get purchaseCancelled => 'Purchase cancelled';

  @override
  String get purchaseFailed => 'The purchase didn\'t go through. Try again.';

  @override
  String get purchasePending =>
      'Payment is pending. The full version opens as soon as it completes.';

  @override
  String get nothingToRestore => 'No purchases to restore';

  @override
  String get purchasesRestored => 'Full version restored';

  @override
  String get restoreFailed => 'Couldn\'t restore purchases. Try again.';

  @override
  String get fullVersionUnlocked => 'Full version unlocked';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get termsOfUse => 'Terms of use';

  @override
  String get about => 'About';

  @override
  String appVersion(String version) {
    return 'Version $version';
  }

  @override
  String get contactUs => 'Contact us';

  @override
  String get credits => 'Credits';

  @override
  String get creditsPictures =>
      'Pictures were created with AI image generation.';

  @override
  String get haveAccessCode => 'I have an access code';

  @override
  String get accessCodeTitle => 'Access code';

  @override
  String get accessCodeField => 'Code';

  @override
  String get accessCodeInvalid => 'This code doesn\'t work';

  @override
  String get vibration => 'Vibration';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get categoryComingSoon =>
      'New pictures for this category are coming soon';

  @override
  String get coloringComingSoon => 'Coloring is coming soon';
}

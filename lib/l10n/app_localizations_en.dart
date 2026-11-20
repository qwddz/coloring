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
  String get coloringUndo => 'Undo';

  @override
  String get coloringEraser => 'Eraser';

  @override
  String get coloringClear => 'Start over';

  @override
  String get coloringClearTitle => 'Start over?';

  @override
  String get coloringClearMessage =>
      'All colors will be removed from this picture.';

  @override
  String get coloringClearConfirm => 'Yes, clear';

  @override
  String get coloringClearCancel => 'No, keep it';

  @override
  String get coloringFind => 'Find the next one';

  @override
  String get coloringDone => 'Done';

  @override
  String get coloringModeFree => 'Free';

  @override
  String get coloringModeNumbers => 'By numbers';

  @override
  String get coloringModeMagic => 'Magic brush';

  @override
  String get coloringModeSwitch => 'Change mode';

  @override
  String get palettePictureColors => 'Picture colors';

  @override
  String get paletteRecent => 'Recent';

  @override
  String get paletteAllColors => 'All colors';

  @override
  String get paletteMagicHint =>
      'Draw with your finger and the picture will color itself!';

  @override
  String paletteColorNumber(int number) {
    return 'Color $number';
  }

  @override
  String get coloringCompleteTitle => 'Great job!';

  @override
  String get coloringKeepColoring => 'Keep coloring';

  @override
  String get coloringBackToPictures => 'Back to pictures';

  @override
  String get coloringLoading => 'Getting the picture ready…';

  @override
  String get coloringLoadError => 'Couldn\'t open the picture';

  @override
  String get coloringNotFound => 'This picture is not available';

  @override
  String get coloringRetry => 'Try again';

  @override
  String get coloringHintTitle => 'Hint';

  @override
  String get myWorks => 'My works';

  @override
  String get myWorksEmpty => 'Your colorings will appear here';

  @override
  String get myWorksToPictures => 'Pick a picture';

  @override
  String get workContinue => 'Continue';

  @override
  String get workNewWork => 'New coloring';

  @override
  String get workSaveToGallery => 'Save to gallery';

  @override
  String get workShare => 'Share';

  @override
  String get workSavedToGallery => 'Saved to the gallery';

  @override
  String get workSaveDenied => 'Allow access to save pictures';

  @override
  String get workExportFailed => 'Could not prepare the picture. Try again';

  @override
  String get workExporting => 'Preparing the picture…';

  @override
  String get workPictureUnavailable => 'This picture is not available';

  @override
  String get workCompleted => 'Finished';

  @override
  String get pictureCompleted => 'Colored';

  @override
  String get levelSimple => 'Simple';

  @override
  String get levelMedium => 'Medium';

  @override
  String get modePickerTitle => 'How do you want to color?';

  @override
  String get modeFreeDescription => 'Choose any colors you like';

  @override
  String get modeNumbersDescription => 'Follow the numbers';

  @override
  String get modeMagicDescription => 'The brush shows the right color';

  @override
  String categoryStars(int completed, int total) {
    return '$completed of $total colored';
  }
}

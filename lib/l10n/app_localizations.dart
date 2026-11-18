import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
    Locale('uk'),
  ];

  /// App name shown in the task switcher and on the home screen
  ///
  /// In en, this message translates to:
  /// **'Animosaic Colors'**
  String get appTitle;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @catalogLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the pictures'**
  String get catalogLoadError;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @soundEffects.
  ///
  /// In en, this message translates to:
  /// **'Sounds'**
  String get soundEffects;

  /// No description provided for @music.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get music;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Same as device'**
  String get languageSystem;

  /// No description provided for @languageUkrainian.
  ///
  /// In en, this message translates to:
  /// **'Українська'**
  String get languageUkrainian;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get languageRussian;

  /// No description provided for @categoryMissing.
  ///
  /// In en, this message translates to:
  /// **'This category is not available'**
  String get categoryMissing;

  /// No description provided for @lockedPicture.
  ///
  /// In en, this message translates to:
  /// **'In the full version'**
  String get lockedPicture;

  /// No description provided for @parentalGateTitle.
  ///
  /// In en, this message translates to:
  /// **'For grown-ups'**
  String get parentalGateTitle;

  /// No description provided for @parentalGateQuestion.
  ///
  /// In en, this message translates to:
  /// **'How much is {a} × {b}? Type the answer in digits.'**
  String parentalGateQuestion(int a, int b);

  /// No description provided for @parentalGateAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get parentalGateAnswer;

  /// No description provided for @parentalGateCooldown.
  ///
  /// In en, this message translates to:
  /// **'Please wait a few seconds and try again.'**
  String get parentalGateCooldown;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @fullVersionTitle.
  ///
  /// In en, this message translates to:
  /// **'Full version'**
  String get fullVersionTitle;

  /// No description provided for @fullVersionIncludes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{All {count} picture in every category, and new ones as they arrive} other{All {count} pictures in every category, and new ones as they arrive}}'**
  String fullVersionIncludes(int count);

  /// No description provided for @oneTimePurchase.
  ///
  /// In en, this message translates to:
  /// **'One-time purchase, no subscription'**
  String get oneTimePurchase;

  /// No description provided for @buyFor.
  ///
  /// In en, this message translates to:
  /// **'Buy for {price}'**
  String buyFor(String price);

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get restorePurchases;

  /// No description provided for @testStore.
  ///
  /// In en, this message translates to:
  /// **'Test store: nothing is charged'**
  String get testStore;

  /// No description provided for @priceLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the store'**
  String get priceLoadError;

  /// No description provided for @purchaseCancelled.
  ///
  /// In en, this message translates to:
  /// **'Purchase cancelled'**
  String get purchaseCancelled;

  /// No description provided for @purchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'The purchase didn\'t go through. Try again.'**
  String get purchaseFailed;

  /// No description provided for @purchasePending.
  ///
  /// In en, this message translates to:
  /// **'Payment is pending. The full version opens as soon as it completes.'**
  String get purchasePending;

  /// No description provided for @nothingToRestore.
  ///
  /// In en, this message translates to:
  /// **'No purchases to restore'**
  String get nothingToRestore;

  /// No description provided for @purchasesRestored.
  ///
  /// In en, this message translates to:
  /// **'Full version restored'**
  String get purchasesRestored;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore purchases. Try again.'**
  String get restoreFailed;

  /// No description provided for @fullVersionUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Full version unlocked'**
  String get fullVersionUnlocked;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get termsOfUse;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersion(String version);

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get contactUs;

  /// No description provided for @credits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get credits;

  /// No description provided for @creditsPictures.
  ///
  /// In en, this message translates to:
  /// **'Pictures were created with AI image generation.'**
  String get creditsPictures;

  /// No description provided for @haveAccessCode.
  ///
  /// In en, this message translates to:
  /// **'I have an access code'**
  String get haveAccessCode;

  /// No description provided for @accessCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Access code'**
  String get accessCodeTitle;

  /// No description provided for @accessCodeField.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get accessCodeField;

  /// No description provided for @accessCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'This code doesn\'t work'**
  String get accessCodeInvalid;

  /// No description provided for @vibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get vibration;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @categoryComingSoon.
  ///
  /// In en, this message translates to:
  /// **'New pictures for this category are coming soon'**
  String get categoryComingSoon;

  /// Undo the last color
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get coloringUndo;

  /// Eraser that removes color from a region
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get coloringEraser;

  /// Button that clears the whole picture
  ///
  /// In en, this message translates to:
  /// **'Start over'**
  String get coloringClear;

  /// Title of the clear confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Start over?'**
  String get coloringClearTitle;

  /// Body of the clear confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'All colors will be removed from this picture.'**
  String get coloringClearMessage;

  /// Confirm button of the clear dialog
  ///
  /// In en, this message translates to:
  /// **'Yes, clear'**
  String get coloringClearConfirm;

  /// Cancel button of the clear dialog
  ///
  /// In en, this message translates to:
  /// **'No, keep it'**
  String get coloringClearCancel;

  /// Button to finish the picture in free mode
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get coloringDone;

  /// Name of the free coloring mode
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get coloringModeFree;

  /// Name of the by-numbers coloring mode
  ///
  /// In en, this message translates to:
  /// **'By numbers'**
  String get coloringModeNumbers;

  /// Name of the magic brush coloring mode
  ///
  /// In en, this message translates to:
  /// **'Magic brush'**
  String get coloringModeMagic;

  /// Tooltip of the mode switch button
  ///
  /// In en, this message translates to:
  /// **'Change mode'**
  String get coloringModeSwitch;

  /// Palette section with the picture's own colors
  ///
  /// In en, this message translates to:
  /// **'Picture colors'**
  String get palettePictureColors;

  /// Palette section with recently used colors
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get paletteRecent;

  /// Palette section with the base colors
  ///
  /// In en, this message translates to:
  /// **'All colors'**
  String get paletteAllColors;

  /// Hint shown instead of swatches in magic brush mode
  ///
  /// In en, this message translates to:
  /// **'Draw with your finger and the picture will color itself!'**
  String get paletteMagicHint;

  /// Semantics label of a palette swatch
  ///
  /// In en, this message translates to:
  /// **'Color {number}'**
  String paletteColorNumber(int number);

  /// Title of the completion overlay
  ///
  /// In en, this message translates to:
  /// **'Great job!'**
  String get coloringCompleteTitle;

  /// Completion overlay button that returns to the picture
  ///
  /// In en, this message translates to:
  /// **'Keep coloring'**
  String get coloringKeepColoring;

  /// Completion overlay button that leaves the coloring screen
  ///
  /// In en, this message translates to:
  /// **'Back to pictures'**
  String get coloringBackToPictures;

  /// Shown while the picture is loading
  ///
  /// In en, this message translates to:
  /// **'Getting the picture ready…'**
  String get coloringLoading;

  /// Shown when the picture fails to load
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the picture'**
  String get coloringLoadError;

  /// Shown when the picture id is unknown
  ///
  /// In en, this message translates to:
  /// **'This picture is not available'**
  String get coloringNotFound;

  /// Retry button on the coloring load error
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get coloringRetry;

  /// Semantics label for the correct-color hint
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get coloringHintTitle;

  /// Title of the screen with the child's saved colorings
  ///
  /// In en, this message translates to:
  /// **'My works'**
  String get myWorks;

  /// Empty state of My works
  ///
  /// In en, this message translates to:
  /// **'Your colorings will appear here'**
  String get myWorksEmpty;

  /// Button on the empty My works screen that opens the catalog
  ///
  /// In en, this message translates to:
  /// **'Pick a picture'**
  String get myWorksToPictures;

  /// Button that reopens an unfinished work
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get workContinue;

  /// Button that starts a fresh work on the same picture
  ///
  /// In en, this message translates to:
  /// **'New coloring'**
  String get workNewWork;

  /// Button that saves the colored picture to the device gallery
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get workSaveToGallery;

  /// Button that shares the colored picture
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get workShare;

  /// Message shown after the picture was saved to the gallery
  ///
  /// In en, this message translates to:
  /// **'Saved to the gallery'**
  String get workSavedToGallery;

  /// Message shown when the gallery permission was denied
  ///
  /// In en, this message translates to:
  /// **'Allow access to save pictures'**
  String get workSaveDenied;

  /// Message shown when rendering the picture for saving or sharing failed
  ///
  /// In en, this message translates to:
  /// **'Could not prepare the picture. Try again'**
  String get workExportFailed;

  /// Progress message while the picture is rendered for saving or sharing
  ///
  /// In en, this message translates to:
  /// **'Preparing the picture…'**
  String get workExporting;

  /// Shown on a work whose picture is no longer in the catalog
  ///
  /// In en, this message translates to:
  /// **'This picture is not available'**
  String get workPictureUnavailable;

  /// Semantics label of the badge on a finished work
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get workCompleted;

  /// Semantics label of the star on a picture the child has finished
  ///
  /// In en, this message translates to:
  /// **'Colored'**
  String get pictureCompleted;

  /// Level badge on a picture card: easy picture
  ///
  /// In en, this message translates to:
  /// **'Simple'**
  String get levelSimple;

  /// Level badge on a picture card: medium picture
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get levelMedium;

  /// Title of the dialog where the child picks a coloring mode
  ///
  /// In en, this message translates to:
  /// **'How do you want to color?'**
  String get modePickerTitle;

  /// Description of the free coloring mode
  ///
  /// In en, this message translates to:
  /// **'Choose any colors you like'**
  String get modeFreeDescription;

  /// Description of the by-numbers coloring mode
  ///
  /// In en, this message translates to:
  /// **'Follow the numbers'**
  String get modeNumbersDescription;

  /// Description of the magic brush coloring mode
  ///
  /// In en, this message translates to:
  /// **'The brush shows the right color'**
  String get modeMagicDescription;

  /// Semantics label of the colored-pictures counter on a category card
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} colored'**
  String categoryStars(int completed, int total);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'Animosaic Розмальовки';

  @override
  String get back => 'Назад';

  @override
  String get retry => 'Спробувати ще';

  @override
  String get catalogLoadError => 'Не вдалося завантажити картинки';

  @override
  String get settings => 'Налаштування';

  @override
  String get soundEffects => 'Звуки';

  @override
  String get music => 'Музика';

  @override
  String get language => 'Мова';

  @override
  String get languageSystem => 'Як на пристрої';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get categoryMissing => 'Ця категорія недоступна';

  @override
  String get lockedPicture => 'У повній версії';

  @override
  String get parentalGateTitle => 'Для дорослих';

  @override
  String parentalGateQuestion(int a, int b) {
    return 'Скільки буде $a × $b? Введіть відповідь цифрами.';
  }

  @override
  String get parentalGateAnswer => 'Відповідь';

  @override
  String get parentalGateCooldown =>
      'Зачекайте кілька секунд і спробуйте ще раз.';

  @override
  String get cancel => 'Скасувати';

  @override
  String get ok => 'OK';

  @override
  String get fullVersionTitle => 'Повна версія';

  @override
  String fullVersionIncludes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Усі $count картинок в усіх категоріях, а також нові, щойно вони з\'являться',
      few:
          'Усі $count картинки в усіх категоріях, а також нові, щойно вони з\'являться',
      one:
          'Усі $count картинка в усіх категоріях, а також нові, щойно вони з\'являться',
    );
    return '$_temp0';
  }

  @override
  String get oneTimePurchase => 'Разова покупка, без підписки';

  @override
  String buyFor(String price) {
    return 'Купити за $price';
  }

  @override
  String get restorePurchases => 'Відновити покупки';

  @override
  String get testStore => 'Тестовий магазин: гроші не списуються';

  @override
  String get priceLoadError => 'Не вдалося зв\'язатися з магазином';

  @override
  String get purchaseCancelled => 'Покупку скасовано';

  @override
  String get purchaseFailed => 'Покупка не вдалася. Спробуйте ще раз.';

  @override
  String get purchasePending =>
      'Оплата очікує підтвердження. Повна версія відкриється, щойно вона завершиться.';

  @override
  String get nothingToRestore => 'Немає покупок для відновлення';

  @override
  String get purchasesRestored => 'Повну версію відновлено';

  @override
  String get restoreFailed => 'Не вдалося відновити покупки. Спробуйте ще раз.';

  @override
  String get fullVersionUnlocked => 'Повну версію відкрито';

  @override
  String get privacyPolicy => 'Політика конфіденційності';

  @override
  String get termsOfUse => 'Умови використання';

  @override
  String get about => 'Про застосунок';

  @override
  String appVersion(String version) {
    return 'Версія $version';
  }

  @override
  String get contactUs => 'Написати нам';

  @override
  String get credits => 'Подяки';

  @override
  String get creditsPictures =>
      'Картинки створено за допомогою генерації зображень штучним інтелектом.';

  @override
  String get haveAccessCode => 'У мене є код доступу';

  @override
  String get accessCodeTitle => 'Код доступу';

  @override
  String get accessCodeField => 'Код';

  @override
  String get accessCodeInvalid => 'Цей код не підходить';

  @override
  String get vibration => 'Вібрація';

  @override
  String get comingSoon => 'Скоро';

  @override
  String get categoryComingSoon =>
      'Нові картинки для цієї категорії скоро з\'являться';

  @override
  String get coloringUndo => 'Скасувати';

  @override
  String get coloringEraser => 'Гумка';

  @override
  String get coloringClear => 'Почати спочатку';

  @override
  String get coloringClearTitle => 'Почати спочатку?';

  @override
  String get coloringClearMessage => 'З картинки зникнуть усі кольори.';

  @override
  String get coloringClearConfirm => 'Так, очистити';

  @override
  String get coloringClearCancel => 'Ні, залишити';

  @override
  String get coloringFind => 'Знайти наступну';

  @override
  String get coloringDone => 'Готово';

  @override
  String get coloringModeFree => 'Вільний';

  @override
  String get coloringModeNumbers => 'За номерами';

  @override
  String get coloringModeMagic => 'Чарівний пензлик';

  @override
  String get coloringModeSwitch => 'Змінити режим';

  @override
  String get palettePictureColors => 'Кольори картинки';

  @override
  String get paletteRecent => 'Останні';

  @override
  String get paletteAllColors => 'Усі кольори';

  @override
  String get paletteMagicHint =>
      'Проведи пальцем, і картинка розфарбується сама!';

  @override
  String paletteColorNumber(int number) {
    return 'Колір $number';
  }

  @override
  String get coloringCompleteTitle => 'Чудова робота!';

  @override
  String get coloringKeepColoring => 'Розмальовувати далі';

  @override
  String get coloringBackToPictures => 'До картинок';

  @override
  String get coloringLoading => 'Готуємо картинку…';

  @override
  String get coloringLoadError => 'Не вдалося відкрити картинку';

  @override
  String get coloringNotFound => 'Цієї картинки немає';

  @override
  String get coloringRetry => 'Спробувати ще раз';

  @override
  String get coloringHintTitle => 'Підказка';

  @override
  String get myWorks => 'Мої роботи';

  @override
  String get myWorksEmpty => 'Тут з\'являться твої розмальовки';

  @override
  String get myWorksToPictures => 'Обрати малюнок';

  @override
  String get workContinue => 'Продовжити';

  @override
  String get workNewWork => 'Нова розмальовка';

  @override
  String get workSaveToGallery => 'Зберегти в галерею';

  @override
  String get workShare => 'Поділитися';

  @override
  String get workSavedToGallery => 'Збережено в галерею';

  @override
  String get workSaveDenied => 'Дозволь доступ, щоб зберігати малюнки';

  @override
  String get workExportFailed =>
      'Не вдалося підготувати малюнок. Спробуй ще раз';

  @override
  String get workExporting => 'Готуємо малюнок…';

  @override
  String get workPictureUnavailable => 'Цього малюнка немає';

  @override
  String get workCompleted => 'Завершено';

  @override
  String get pictureCompleted => 'Розмальовано';

  @override
  String get levelSimple => 'Проста';

  @override
  String get levelMedium => 'Середня';

  @override
  String get modePickerTitle => 'Як будемо розмальовувати?';

  @override
  String get modeFreeDescription => 'Обирай будь-які кольори';

  @override
  String get modeNumbersDescription => 'Фарбуй за цифрами';

  @override
  String get modeMagicDescription => 'Пензлик підкаже правильний колір';

  @override
  String categoryStars(int completed, int total) {
    return 'Розмальовано $completed з $total';
  }

  @override
  String get drawingTileTitle => 'Малювалка';

  @override
  String get drawingLoading => 'Готуємо аркуш…';

  @override
  String get drawingLoadError => 'Аркуш не відкрився';

  @override
  String get drawingToolPencil => 'Олівець';

  @override
  String get drawingToolFelt => 'Фломастер';

  @override
  String get drawingToolMarker => 'Маркер';

  @override
  String get drawingToolEraser => 'Гумка';

  @override
  String get drawingToolRainbow => 'Веселка';

  @override
  String get drawingToolPastel => 'Пастель';

  @override
  String get drawingToolWatercolor => 'Акварель';

  @override
  String get drawingToolAirbrush => 'Аерограф';

  @override
  String get drawingToolNeon => 'Неон';

  @override
  String get drawingToolStars => 'Зірочки';

  @override
  String get drawingToolHearts => 'Сердечка';

  @override
  String get drawingToolFill => 'Заливка';

  @override
  String get drawingUndo => 'Скасувати';

  @override
  String get drawingRedo => 'Повторити';

  @override
  String get drawingClear => 'Очистити аркуш';

  @override
  String get drawingClearTitle => 'Очистити аркуш?';

  @override
  String get drawingClearMessage => 'Увесь малюнок зникне.';

  @override
  String get drawingNewSheet => 'Новий аркуш';

  @override
  String get drawingMirrorOff => 'Дзеркало: вимк.';

  @override
  String get drawingMirrorOn => 'Дзеркало: увімк.';

  @override
  String get drawingBrushSize => 'Розмір пензля';

  @override
  String get drawingSizeSmall => 'Маленький';

  @override
  String get drawingSizeMedium => 'Середній';

  @override
  String get drawingSizeLarge => 'Великий';

  @override
  String get drawingSizeHuge => 'Величезний';

  @override
  String get drawingTools => 'Інструменти';

  @override
  String get drawingColors => 'Кольори';

  @override
  String drawingToolLocked(String tool) {
    return '$tool: у повній версії';
  }

  @override
  String drawingWorkTitle(String date) {
    return 'Малюнок, $date';
  }

  @override
  String get workNewDrawing => 'Новий малюнок';

  @override
  String get fullVersionDrawingTools =>
      'Усі пензлі, штампи, заливка й дзеркало в малювалці';
}

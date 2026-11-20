// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Animosaic Раскраски';

  @override
  String get back => 'Назад';

  @override
  String get retry => 'Попробовать снова';

  @override
  String get catalogLoadError => 'Не удалось загрузить картинки';

  @override
  String get settings => 'Настройки';

  @override
  String get soundEffects => 'Звуки';

  @override
  String get music => 'Музыка';

  @override
  String get language => 'Язык';

  @override
  String get languageSystem => 'Как на устройстве';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get categoryMissing => 'Эта категория недоступна';

  @override
  String get lockedPicture => 'В полной версии';

  @override
  String get parentalGateTitle => 'Для взрослых';

  @override
  String parentalGateQuestion(int a, int b) {
    return 'Сколько будет $a × $b? Введите ответ цифрами.';
  }

  @override
  String get parentalGateAnswer => 'Ответ';

  @override
  String get parentalGateCooldown =>
      'Подождите несколько секунд и попробуйте ещё раз.';

  @override
  String get cancel => 'Отмена';

  @override
  String get ok => 'OK';

  @override
  String get fullVersionTitle => 'Полная версия';

  @override
  String fullVersionIncludes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Все $count картинок во всех категориях, а также новые, как только они появятся',
      few:
          'Все $count картинки во всех категориях, а также новые, как только они появятся',
      one:
          'Все $count картинка во всех категориях, а также новые, как только они появятся',
    );
    return '$_temp0';
  }

  @override
  String get oneTimePurchase => 'Разовая покупка, без подписки';

  @override
  String buyFor(String price) {
    return 'Купить за $price';
  }

  @override
  String get restorePurchases => 'Восстановить покупки';

  @override
  String get testStore => 'Тестовый магазин: деньги не списываются';

  @override
  String get priceLoadError => 'Не удалось связаться с магазином';

  @override
  String get purchaseCancelled => 'Покупка отменена';

  @override
  String get purchaseFailed => 'Покупка не прошла. Попробуйте ещё раз.';

  @override
  String get purchasePending =>
      'Платёж ожидает подтверждения. Полная версия откроется, как только он завершится.';

  @override
  String get nothingToRestore => 'Нет покупок для восстановления';

  @override
  String get purchasesRestored => 'Полная версия восстановлена';

  @override
  String get restoreFailed =>
      'Не удалось восстановить покупки. Попробуйте ещё раз.';

  @override
  String get fullVersionUnlocked => 'Полная версия открыта';

  @override
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get termsOfUse => 'Условия использования';

  @override
  String get about => 'О приложении';

  @override
  String appVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get contactUs => 'Написать нам';

  @override
  String get credits => 'Благодарности';

  @override
  String get creditsPictures =>
      'Картинки созданы с помощью генерации изображений искусственным интеллектом.';

  @override
  String get haveAccessCode => 'У меня есть код доступа';

  @override
  String get accessCodeTitle => 'Код доступа';

  @override
  String get accessCodeField => 'Код';

  @override
  String get accessCodeInvalid => 'Этот код не подходит';

  @override
  String get vibration => 'Вибрация';

  @override
  String get comingSoon => 'Скоро';

  @override
  String get categoryComingSoon =>
      'Новые картинки для этой категории скоро появятся';

  @override
  String get coloringUndo => 'Отменить';

  @override
  String get coloringEraser => 'Ластик';

  @override
  String get coloringClear => 'Начать сначала';

  @override
  String get coloringClearTitle => 'Начать сначала?';

  @override
  String get coloringClearMessage => 'С картинки исчезнут все цвета.';

  @override
  String get coloringClearConfirm => 'Да, очистить';

  @override
  String get coloringClearCancel => 'Нет, оставить';

  @override
  String get coloringFind => 'Найти следующую';

  @override
  String get coloringDone => 'Готово';

  @override
  String get coloringModeFree => 'Свободный';

  @override
  String get coloringModeNumbers => 'По номерам';

  @override
  String get coloringModeMagic => 'Волшебная кисточка';

  @override
  String get coloringModeSwitch => 'Сменить режим';

  @override
  String get palettePictureColors => 'Цвета картинки';

  @override
  String get paletteRecent => 'Недавние';

  @override
  String get paletteAllColors => 'Все цвета';

  @override
  String get paletteMagicHint =>
      'Проведи пальцем, и картинка раскрасится сама!';

  @override
  String paletteColorNumber(int number) {
    return 'Цвет $number';
  }

  @override
  String get coloringCompleteTitle => 'Отличная работа!';

  @override
  String get coloringKeepColoring => 'Раскрашивать дальше';

  @override
  String get coloringBackToPictures => 'К картинкам';

  @override
  String get coloringLoading => 'Готовим картинку…';

  @override
  String get coloringLoadError => 'Не удалось открыть картинку';

  @override
  String get coloringNotFound => 'Такой картинки нет';

  @override
  String get coloringRetry => 'Попробовать ещё раз';

  @override
  String get coloringHintTitle => 'Подсказка';

  @override
  String get myWorks => 'Мои работы';

  @override
  String get myWorksEmpty => 'Здесь появятся твои раскраски';

  @override
  String get myWorksToPictures => 'Выбрать картинку';

  @override
  String get workContinue => 'Продолжить';

  @override
  String get workNewWork => 'Новая раскраска';

  @override
  String get workSaveToGallery => 'Сохранить в галерею';

  @override
  String get workShare => 'Поделиться';

  @override
  String get workSavedToGallery => 'Сохранено в галерею';

  @override
  String get workSaveDenied => 'Разреши доступ, чтобы сохранять картинки';

  @override
  String get workExportFailed =>
      'Не удалось подготовить картинку. Попробуй ещё раз';

  @override
  String get workExporting => 'Готовим картинку…';

  @override
  String get workPictureUnavailable => 'Этой картинки нет';

  @override
  String get workCompleted => 'Завершено';

  @override
  String get pictureCompleted => 'Раскрашено';

  @override
  String get levelSimple => 'Простая';

  @override
  String get levelMedium => 'Средняя';

  @override
  String get modePickerTitle => 'Как будем раскрашивать?';

  @override
  String get modeFreeDescription => 'Выбирай любые цвета';

  @override
  String get modeNumbersDescription => 'Крась по цифрам';

  @override
  String get modeMagicDescription => 'Кисточка подскажет правильный цвет';

  @override
  String categoryStars(int completed, int total) {
    return 'Раскрашено $completed из $total';
  }
}

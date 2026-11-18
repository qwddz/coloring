# Play Console: черновик ответов (Animosaic Colors)

Черновик для разделов «Policy and programs → App content» и «Store settings» в Google Play Console. Адаптирован из `../puzzles/docs/store/play_console.md`. Ответы построены по коду на момент Stage 2 (HEAD после WP0–WP8), `CLAUDE.md` и `docs/store/site/colors/privacy.html`. Каждое действие в Play Console выполняет **пользователь**; агент только готовит тексты. Всё, что зависит от итоговой сборки, помечено **проверить после WP9**, спорные выборы — **проверить**.

Что приложение делает с данными (по коду):

- Зависимости с сетью: `purchases_flutter` (RevenueCat), `dio` (скачивание платных картинок с CDN, адрес задаётся `CDN_BASE_URL`), `url_launcher` (ссылки из «О приложении», за родительской проверкой). Firebase Analytics, рекламных SDK нет. Крэш-репортера в этой сборке нет (Crashlytics разрешён правилами проекта, но не подключён). **проверить после WP9** по `pubspec.yaml` и слитому манифесту.
- RevenueCat работает так же, как в puzzles: `configure`, `getOfferings`, `getCustomerInfo`, `purchase`, `restorePurchases`, без `logIn` со своим ID, атрибутов и device identifiers, то есть с анонимным `$RCAnonymousID`.
- Работы (цвета областей, режим, флаг «готово») и превью лежат только в папке документов приложения. «Сохранить в галерею» (по нажатию пользователя) пишет PNG 2048 × 1536 в `Pictures/Animosaic Colors/` через `gal`. «Поделиться» (за родительской проверкой) передаёт PNG в системное окно «Поделиться» через `share_plus`; куда файл уйдёт дальше, решает человек, мы это не видим.
- Ожидаемые разрешения в слитом релизном манифесте: `INTERNET`, `ACCESS_NETWORK_STATE`, `com.android.vending.BILLING`, `WRITE_EXTERNAL_STORAGE` с `maxSdkVersion="29"` (плюс `requestLegacyExternalStorage="true"`; **проверено в WP9**), служебное `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. Нет `AD_ID`, нет `READ_MEDIA_*`, нет `READ_EXTERNAL_STORAGE`. **Проверено в WP9** на релизной сборке (список снимается из `build/app/intermediates/merged_manifests/release/.../AndroidManifest.xml`).

## Основное

| Поле | Ответ |
|---|---|
| App name | Название из `listing.md` (en-US основной) |
| Default language | English (United States), дальше uk и ru |
| Package name | `app.animosaic.coloring` (после первой загрузки не меняется) |
| Privacy policy URL | https://animosaic.app/colors/privacy (страница должна быть опубликована до заполнения; черновик в `docs/store/site/colors/privacy.html`) |
| Terms (в карточке и на пейволле) | https://animosaic.app/colors/terms |
| Contact e-mail | pirate.dmitry@gmail.com (как в `lib/features/settings/data/about_links.dart`) |
| Website | https://animosaic.app (**проверить**, что открывается; иначе оставить пустым) |
| Phone | не указывать |
| App or game | **проверить**: раскраска не игра в классическом смысле, но в манифесте стоит `appCategory="game"` (нужен для альбомной ориентации на больших экранах Android 16+), а puzzles объявлен как Game. Варианты: App → Art & Design, или Game → Educational/Casual. Склоняюсь к App → Art & Design; решение пользователя |
| Free or paid | Free (с внутриигровой покупкой) |
| Category | **проверить**: Art & Design (если App) или Educational (если Game). Educational включает дополнительные вопросы по педагогике; Art & Design проще для ревью |
| Tags (до 5) | **проверить**: набор фиксирован. Искать ближайшие к «Coloring», «Drawing», «Kids», «Casual», «Family», «Offline» |
| In-app product | `full_version`, разовая (one-time, non-consumable). Цена: по умолчанию US$4.99, как у puzzles (открытый вопрос PLAN.md, **проверить** у пользователя). Должен быть **активен** до отправки на ревью. Создаётся после первой загрузки AAB |
| Countries | Страны с оплатой в Google Play (PLAN.md). **проверить** при выборе |

## App access

- **Да, есть закрытые разделы**: платные картинки открываются покупкой `full_version`.
- Решение как у puzzles: код доступа для ревьюеров. На экране «Полная версия» есть кнопка «У меня есть код доступа» (`lib/features/subscription/data/review_access.dart`). Код `REVIEW_CODE` лежит в `.env`; в сборку попадает только его sha256 (`REVIEW_CODE_SHA256`, см. «Release build» в `CLAUDE.md`). Без этого define кнопка скрыта. **проверить после WP9**: кнопка видна в сборке с `REVIEW_CODE_SHA256`, скрыта без него.
- В форме: имя набора `Full version access code`, логин и пароль пусты, галочка «обеспечивают полный доступ, включая платный» стоит. Инструкция (Any other information, ≤ 500 символов; число бесплатных картинок подставить по фактическому манифесту, **проверить** перед отправкой):

```
No account or login is needed. Some pictures are free. The rest unlock with a one-time
in-app purchase ("Full version"), so we provide an access code that unlocks them
without paying:
1. Open any category and tap a picture with a lock icon.
2. Parental gate: type the product of the two numbers shown (e.g. 7 x 8 = 56), tap OK.
3. On the "Full version" screen tap "I have an access code".
4. Enter the code <REVIEW_CODE из .env> and tap OK. All pictures are now unlocked.
```

- Если на момент закрытого тестирования все картинки бесплатные (в манифесте сейчас 10 бесплатных пробных), раздел можно объявить без закрытого контента. **проверить** по финальному манифесту и `CDN_BASE_URL`.
- При смене кода или сборке без `REVIEW_CODE_SHA256` декларацию нужно обновить вместе с новой сборкой.

## Ads

- **Does your app contain ads? No.**
- Advertising ID declaration: **No**, приложение не использует рекламный идентификатор (`AD_ID` в манифесте нет; проверено в WP9 по слитому релизному манифесту); после любой новой зависимости проверять заново.

## Content rating (IARC)

Категория анкеты: зависит от выбора App/Game выше (**проверить**); ответы одинаковы.

| Вопрос анкеты (суть) | Ответ |
|---|---|
| Violence | No |
| Fear / horror | No. Пауки, змеи и акулы нарисованы дружелюбно в бытовых сценах (`spring_spider_umbrella`, `farm_python_picnic`, `hobbies_shark_guitar`). **проверить** по финальным картинкам: нет оскала, крови, охоты |
| Sexuality / nudity | No |
| Language | No |
| Controlled substances | No |
| Crude humor | No |
| Gambling / simulated gambling, лутбоксы | No |
| Users interact or exchange content? | No (нет чатов, профилей, обмена внутри приложения). Системное «Поделиться» уходит через ОС и не считается обменом в приложении. **проверить** формулировку вопроса при заполнении |
| Shares the user's current physical location? | No |
| Purchase of digital goods? | **Yes** (разовая покупка полной версии) |
| Unrestricted internet access / web browser? | No (ссылки наружу только за родительской проверкой, во внешнем браузере) |
| News / educational reference app? | No |

Ожидаемый результат: IARC 3+, PEGI 3, ESRB Everyone, USK 0, с пометкой «In-App Purchases». **проверить** итог после отправки анкеты.

## Target audience and content

- **Target age groups:** **проверить**. PLAN.md: все возраста, дети входят в целевую аудиторию, значит приложение попадает под **Families Policy**. Предложение: «5 and under», «6–8», «9–12». Возрасты 13+ не отмечать: смешанная аудитория потребует экрана выбора возраста, которого нет. Раскраска «cozy for kids and adults» может привлекать и взрослых; если выбрать только детские группы, карточка не должна быть написана под взрослых.
- Могла ли карточка непреднамеренно привлекать детей: не задаётся, раз дети целевые.
- Как приложение соответствует Families Policy:
  - Реклама отсутствует; AAID, Android ID, IMEI и т. п. не передаются (`AD_ID` нет, RevenueCat без device identifiers).
  - Местоположение, контакты, микрофон, камера не запрашиваются.
  - Покупки, «Поделиться» и ссылки наружу защищены родительской проверкой.
  - Сохранение в галерею не защищено проверкой (решение пользователя S2-D4): это локальное действие, но на Android 7–10 показывается системный запрос на доступ к хранилищу. **проверить**: не возразит ли ревью Families; запасной вариант: поставить проверку и на «Сохранить в галерею» (один вызов перед `saveToGallery`).
  - Политика конфиденциальности описывает обращение с данными детей (раздел «Children» в `privacy.html`).
  - Контент подходит для детей.
  - SDK: RevenueCat как платёжная инфраструктура без таргетинга. **проверить**, не запросит ли ревью дополнительное заявление.
- **Teacher Approved**: по желанию, после релиза.

## Data safety

### Обзор

| Вопрос | Ответ |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** (только Purchase history, см. ниже) |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (RevenueCat и CDN только по HTTPS; **проверить после WP9**, что `CDN_BASE_URL` начинается с `https://`) |
| Do you provide a way for users to request that their data is deleted? | **Yes**: по e-mail pirate.dmitry@gmail.com; удаление клиента делается в дашборде RevenueCat (Customer → Delete customer) |
| Data deletion URL | Не требуется: учётных записей нет. Если Play спросит: https://animosaic.app/colors/privacy (раздел «Your rights») |
| Independent security review | No |
| Committed to Families Policy | Yes |
| Account creation | My app does not allow users to create an account |

### Типы данных

Основание то же, что у puzzles: памятка RevenueCat «Google Play's Data Safety» (https://www.revenuecat.com/docs/platform-resources/google-platform-resources/google-plays-data-safety). Обязательно только **Financial info → Purchase history**.

| Категория → тип | Collected | Shared | Ephemeral | Required | Purposes |
|---|---|---|---|---|---|
| Financial info → **Purchase history** | Yes | No | No | Required | App functionality; Analytics (данные идут в графики дашборда RevenueCat) |
| Device or other IDs | **проверить**: по памятке RevenueCat не объявлять; осторожный вариант: объявить анонимный ID RevenueCat (Collected Yes, Shared No, Ephemeral No, Required, App functionality) | | | | |

Не объявляем, с пояснением:

- **Photos and videos / Files and docs: не собираются.** «Сохранить в галерею» пишет картинку, созданную самим приложением, в галерею устройства по нажатию пользователя; чтение фото и файлов пользователя приложение не делает (нет `READ_MEDIA_*`, `READ_EXTERNAL_STORAGE`). Файл остаётся на устройстве и к нам не попадает. **проверить**: если Play при заполнении настаивает на строке про фото, объявить как «collected: No».
- **Системное «Поделиться» не «sharing» в смысле Data safety.** Файл уходит только туда, куда человек сам его отправит через системное окно, после родительской проверки; на наши серверы и серверы поставщиков данные не передаются. **проверить** формулировку определения «sharing» при заполнении.
- **Работы, превью и звёзды лежат на устройстве и могут попасть в личную резервную копию Android/Google пользователя** (Auto Backup оставлен включённым, `allowBackup` по умолчанию). Копией управляют система и аккаунт Google пользователя; разработчик эти данные не получает, поэтому в Data safety они не «collected». Та же формулировка в `privacy.html` (en/uk/ru).
- **Shared: No** везде: RevenueCat и CDN-хостинг обрабатывают данные от нашего имени как поставщики услуг.
- Технические данные RevenueCat (версия приложения и ОС, страна и валюта для цен) памятка не требует; крэш-логов и диагностики мы не собираем.
- IP-адрес при скачивании картинок с CDN обрабатывает хостинг для доставки файлов; мы его не собираем и не храним. Location не объявляем. **проверить**, если включится аналитика CDN или логирование запросов.
- Personal info, Location, Messages, Audio, Calendar, Contacts, App activity, Web browsing, Health, App info and performance: не собираются.

Разрешение `WRITE_EXTERNAL_STORAGE` (≤ API 29, `maxSdkVersion="29"`, вместе с `requestLegacyExternalStorage`; плагин `gal` проверяет его при сохранении в альбом и на API 29): нужно только для записи сохранённой картинки в публичную папку `Pictures` на Android 7–10; на Android 11+ не используется и не запрашивается. Объяснение для ревью: «Used only on Android 10 and below to save the user's colored picture to the gallery when the user taps Save. Not requested on Android 11 and newer.» Отдельной декларации в Play Console для него нет (в отличие от `MANAGE_EXTERNAL_STORAGE` и `READ_MEDIA_*`). **проверить**, не добавил ли Play предупреждение при загрузке AAB.

Важно: при добавлении Firebase, Crashlytics, аналитики или `Purchases.logIn` раздел нужно пересмотреть.

## Прочие декларации App content

| Раздел | Ответ |
|---|---|
| News app | No |
| COVID-19 contact tracing / status | No |
| Government app | No |
| Financial features | My app doesn't provide any financial features |
| Health apps | No health features |
| Foreground service / exact alarm / другие разрешения-декларации | Не применимо (в манифесте их нет). **проверить после WP9** |

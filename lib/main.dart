import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'features/content/content_config.dart';
import 'features/subscription/data/purchase_providers.dart';
import 'features/settings/data/settings_controller.dart';

Future<void> main() async {
  checkCdnConfigured(release: kReleaseMode, baseUrl: cdnBaseUrlFromEnvironment);
  checkRevenueCatConfigured(
    release: kReleaseMode,
    apiKey: revenueCatApiKeyFromEnvironment,
  );
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const ColoringApp(),
    ),
  );
}

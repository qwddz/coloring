import 'package:coloring/features/palette/data/recent_colors.dart';
import 'package:coloring/features/settings/data/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> container() async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('most recent first, duplicate moves to front', () async {
    final c = await container();
    final n = c.read(recentColorsProvider.notifier);
    n.add(0xFFFF0000);
    n.add(0xFF00FF00);
    n.add(0xFFFF0000);
    expect(c.read(recentColorsProvider), [0xFFFF0000, 0xFF00FF00]);
  });

  test('keeps at most 8', () async {
    final c = await container();
    final n = c.read(recentColorsProvider.notifier);
    for (var i = 1; i <= 10; i++) {
      n.add(0xFF000000 + i);
    }
    final colors = c.read(recentColorsProvider);
    expect(colors.length, 8);
    expect(colors.first, 0xFF00000A);
    expect(colors.last, 0xFF000003);
  });

  test('persists across a new container', () async {
    final first = await container();
    first.read(recentColorsProvider.notifier).add(0xFF112233);
    first.read(recentColorsProvider.notifier).add(0xFF445566);
    final second = await container();
    expect(second.read(recentColorsProvider), [0xFF445566, 0xFF112233]);
  });
}

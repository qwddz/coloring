import 'package:coloring/features/coloring/coloring_route.dart';
import 'package:coloring/features/coloring/model/coloring_mode.dart';
import 'package:flutter_test/flutter_test.dart';

ColoringRequest parse(String location) {
  final uri = Uri.parse(location);
  expect(uri.pathSegments.first, 'coloring');
  return ColoringRequest.fromRoute(uri.pathSegments[1], uri.queryParameters);
}

void main() {
  test('plain route round trips', () {
    final route = coloringRoute('home_fox');
    expect(route, '/coloring/home_fox');
    expect(parse(route), const ColoringRequest('home_fox'));
  });

  test('work route round trips', () {
    final route = coloringRoute('home_fox', workId: 'home_fox-1700');
    expect(route, '/coloring/home_fox?work=home_fox-1700');
    expect(
      parse(route),
      const ColoringRequest('home_fox', workId: 'home_fox-1700'),
    );
  });

  test('mode route round trips for every mode', () {
    for (final mode in ColoringMode.values) {
      final route = coloringRoute('home_fox', newMode: mode);
      expect(route, '/coloring/home_fox?mode=${mode.name}');
      expect(parse(route), ColoringRequest('home_fox', newMode: mode));
    }
  });

  test('an unknown mode is ignored', () {
    expect(
      ColoringRequest.fromRoute('home_fox', {'mode': 'rainbow'}),
      const ColoringRequest('home_fox'),
    );
  });

  test('workId wins over mode', () {
    expect(
      coloringRoute('home_fox', workId: 'w', newMode: ColoringMode.magic),
      '/coloring/home_fox?work=w',
    );
    final request = ColoringRequest.fromRoute('home_fox', {
      'work': 'w',
      'mode': 'magic',
    });
    expect(request.workId, 'w');
    expect(request.newMode, isNull);
    expect(
      const ColoringRequest(
        'home_fox',
        workId: 'w',
        newMode: ColoringMode.magic,
      ).newMode,
      isNull,
    );
  });

  test('a workId that is not a plain file name is ignored', () {
    for (final bad in ['', '.', '..', '../x', 'a/b', r'a\b', 'fox 1', 'ü']) {
      expect(
        ColoringRequest.fromRoute('home_fox', {'work': bad}),
        const ColoringRequest('home_fox'),
        reason: bad,
      );
      expect(
        ColoringRequest.fromRoute('home_fox', {'work': bad, 'mode': 'magic'}),
        const ColoringRequest('home_fox', newMode: ColoringMode.magic),
        reason: bad,
      );
    }
    expect(
      ColoringRequest.fromRoute('home_fox', {'work': 'home_fox-1.v2_a'}),
      const ColoringRequest('home_fox', workId: 'home_fox-1.v2_a'),
    );
  });

  test('equality and hashCode', () {
    const a = ColoringRequest('fox', newMode: ColoringMode.numbers);
    const b = ColoringRequest('fox', newMode: ColoringMode.numbers);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(const ColoringRequest('fox')));
    expect(a, isNot(const ColoringRequest('fox', newMode: ColoringMode.free)));
    expect(
      const ColoringRequest('fox', workId: 'x'),
      isNot(const ColoringRequest('fox', workId: 'y')),
    );
    expect(
      a,
      isNot(const ColoringRequest('cat', newMode: ColoringMode.numbers)),
    );
  });
}

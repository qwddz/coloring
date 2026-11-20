import 'package:coloring/features/drawing/drawing_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime.utc(2032, 3, 4, 5, 6, 7, 8);
  DateTime clock() => t;

  group('fromRoute', () {
    test('no query is the plain request (latest drawing)', () {
      final r = DrawingRequest.fromRoute(const {});
      expect(r, const DrawingRequest());
      expect(r.workId, isNull);
      expect(r.newId, isNull);
    });

    test('work opens that drawing', () {
      expect(
        DrawingRequest.fromRoute(const {'work': 'drawing-1'}),
        const DrawingRequest(workId: 'drawing-1'),
      );
    });

    test('new opens a blank drawing with that id', () {
      expect(
        DrawingRequest.fromRoute(const {'new': 'drawing-2'}),
        const DrawingRequest(newId: 'drawing-2'),
      );
    });

    test('work wins over new', () {
      final r = DrawingRequest.fromRoute(const {
        'work': 'drawing-1',
        'new': 'drawing-2',
      });
      expect(r.workId, 'drawing-1');
      expect(r.newId, isNull);
    });

    test('an invalid work opens a new drawing with a generated id', () {
      final r = DrawingRequest.fromRoute(const {'work': '../evil'}, now: clock);
      expect(r.workId, isNull);
      expect(r.newId, startsWith('drawing-${t.millisecondsSinceEpoch}'));
    });

    test('an invalid new is ignored', () {
      expect(
        DrawingRequest.fromRoute(const {'new': 'a/b'}),
        const DrawingRequest(),
      );
    });
  });

  test('a request never holds both ids', () {
    const r = DrawingRequest(workId: 'a', newId: 'b');
    expect(r.workId, 'a');
    expect(r.newId, isNull);
  });

  test('value equality', () {
    expect(
      const DrawingRequest(newId: 'x'),
      DrawingRequest.fromRoute(const {'new': 'x'}),
    );
    expect(
      const DrawingRequest(newId: 'x').hashCode,
      const DrawingRequest(newId: 'x').hashCode,
    );
    expect(
      const DrawingRequest(newId: 'x'),
      isNot(const DrawingRequest(workId: 'x')),
    );
  });

  group('drawRoute', () {
    test('plain, work and new', () {
      expect(drawRoute(), '/draw');
      expect(drawRoute(workId: 'drawing-9'), '/draw?work=drawing-9');
      expect(
        drawRoute(workId: 'drawing-9', newSheet: true),
        '/draw?work=drawing-9',
      );
      final fresh = drawRoute(newSheet: true, now: clock);
      expect(
        fresh,
        startsWith('/draw?new=drawing-${t.millisecondsSinceEpoch}'),
      );
    });

    test('two new sheets in the same millisecond differ', () {
      final a = drawRoute(newSheet: true, now: clock);
      final b = drawRoute(newSheet: true, now: clock);
      expect(a, isNot(b));
      final ra = DrawingRequest.fromRoute(Uri.parse(a).queryParameters);
      final rb = DrawingRequest.fromRoute(Uri.parse(b).queryParameters);
      expect(ra, isNot(rb));
      expect(ra.newId, isNotNull);
      expect(rb.newId, isNotNull);
    });

    test('routes parse back to the same request', () {
      for (final route in ['/draw', '/draw?work=drawing-3']) {
        final r = DrawingRequest.fromRoute(Uri.parse(route).queryParameters);
        expect(r.toString(), 'DrawingRequest($route)');
      }
    });
  });
}

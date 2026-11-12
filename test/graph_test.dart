import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/models/tree_snapshot.dart';
import 'package:gia_pha_app/services/api_service.dart';
import 'package:gia_pha_app/services/graph_layout_service.dart';
import 'package:gia_pha_app/controllers/graph_controller.dart';

import 'fixtures.dart';
import 'graph_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AccessSession session() => AccessSession.fromJson(accessJson()['session']);
  void verify(TreeSnapshot tree, GraphLayout layout) {
    expect(layout.nodes.keys.toSet(), tree.persons.map((p) => p.id).toSet());
    expect(
      layout.strokes.expand((s) => s.relationships).map((r) => r.id).toSet(),
      tree.relationships.map((r) => r.id).toSet(),
    );
    final rects = layout.nodes.values.toList();
    final bounds = Offset.zero & layout.size;
    for (var i = 0; i < rects.length; i++) {
      expect(bounds.contains(rects[i].topLeft), isTrue);
      expect(bounds.contains(rects[i].bottomRight), isTrue);
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
    for (final s in layout.strokes) {
      for (final p in s.points) {
        expect(bounds.contains(p), isTrue);
      }
    }
    if (!layout.hasParentCycle) {
      for (final r in tree.relationships.where((r) => !r.isSpouse)) {
        expect(
          layout.nodes[r.sourcePersonId]!.bottom,
          lessThan(layout.nodes[r.targetPersonId]!.top),
        );
      }
    }
  }

  test(
    'API16 one authenticated GET, version and all people retained',
    () async {
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls++;
          expect(r.method, 'GET');
          expect(r.url.path, '/families/7/tree');
          expect(r.url.queryParameters, isEmpty);
          expect(r.headers['Authorization'], 'Bearer test-only-token');
          return jsonResponse(treeJson());
        }),
      );
      addTearDown(api.close);
      final tree = await api.getTree(7, session());
      expect(calls, 1);
      expect(tree.version, 4);
      expect(tree.persons.last.name, 'Chưa có thông tin');
      expect(tree.relationships.last.parentKind, 'ADOPTIVE');
    },
  );

  test(
    'API16 rejects cross-family requests before HTTP and malformed scope/edges',
    () async {
      var calls = 0;
      Map<String, dynamic> response = {...treeJson(), 'familyId': 8};
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls++;
          return jsonResponse(response);
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.getTree(8, session()),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 0);
      await expectLater(
        api.getTree(7, session()),
        throwsA(isA<ApiException>()),
      );
      response = treeJson(edges: [edgeJson(1, 11, 999)]);
      await expectLater(
        api.getTree(7, session()),
        throwsA(isA<ApiException>()),
      );
      response = treeJson(people: [personJson(id: 11, familyId: 8)], edges: []);
      await expectLater(
        api.getTree(7, session()),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('layout parents first, unique nodes, isolated blank person, stable ordering', () {
    final tree = TreeSnapshot.fromJson(treeJson());
    final layout = GraphLayoutService().arrange(tree);
    verify(tree, layout);
    expect(layout.hasParentCycle, isFalse);
    final reversed = TreeSnapshot.fromJson(
      treeJson(
        people: (treeJson()['persons'] as List<Map<String, dynamic>>).reversed
            .toList(),
        edges: (treeJson()['relationships'] as List<Map<String, dynamic>>)
            .reversed
            .toList(),
      ),
    );
    expect(GraphLayoutService().arrange(reversed).nodes, layout.nodes);
  });

  test(
    'multiple spouses, two parents without marriage and separate components',
    () {
      final tree = TreeSnapshot.fromJson(
        treeJson(
          people: [for (var i = 1; i <= 10; i++) personJson(id: i)],
          edges: [
            edgeJson(1, 1, 2, spouse: true),
            edgeJson(2, 1, 3, spouse: true),
            edgeJson(3, 1, 4, spouse: true),
            edgeJson(4, 1, 5),
            edgeJson(5, 2, 5, role: 'MOTHER'),
            edgeJson(6, 6, 8),
            edgeJson(7, 7, 8, role: 'MOTHER'),
          ],
        ),
      );
      final layout = GraphLayoutService().arrange(tree);
      verify(tree, layout);
      expect(
        layout.strokes.where((e) => e.kind == StrokeKind.spouse).length,
        3,
      );
    },
  );

  test(
    'spouse across generations does not collapse parent ranks or drop edges',
    () {
      final tree = TreeSnapshot.fromJson(
        treeJson(
          people: [for (var i = 1; i <= 5; i++) personJson(id: i)],
          edges: [
            edgeJson(1, 1, 2),
            edgeJson(2, 2, 3),
            edgeJson(3, 1, 4, spouse: true),
            edgeJson(4, 3, 4, spouse: true),
          ],
        ),
      );
      final layout = GraphLayoutService().arrange(tree);
      verify(tree, layout);
      expect(layout.hasParentCycle, isFalse);
    },
  );

  test(
    'parent cycle has finite warned fallback; spouse cycles remain valid',
    () {
      final tree = TreeSnapshot.fromJson(
        treeJson(
          people: [personJson(id: 1), personJson(id: 2)],
          edges: [edgeJson(1, 1, 2), edgeJson(2, 2, 1)],
        ),
      );
      final layout = GraphLayoutService().arrange(tree);
      verify(tree, layout);
      expect(layout.hasParentCycle, isTrue);
      final spouses = TreeSnapshot.fromJson(
        treeJson(
          people: [personJson(id: 1), personJson(id: 2), personJson(id: 3)],
          edges: [
            edgeJson(1, 1, 2, spouse: true),
            edgeJson(2, 2, 3, spouse: true),
            edgeJson(3, 1, 3, spouse: true),
          ],
        ),
      );
      expect(GraphLayoutService().arrange(spouses).hasParentCycle, isFalse);
    },
  );

  test('empty family is a valid finite scene', () {
    final tree = TreeSnapshot.fromJson(treeJson(people: [], edges: []));
    final layout = GraphLayoutService().arrange(tree);
    verify(tree, layout);
    expect(layout.size.width.isFinite && layout.size.height.isFinite, isTrue);
  });

  test('controller rejects expired session without sending HTTP', () async {
    var calls = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        calls++;
        return jsonResponse(treeJson());
      }),
    );
    addTearDown(api.close);
    final c = GraphController(
      api,
      MemoryStorage(),
      7,
      initialSession: AccessSession.fromJson({
        ...accessJson()['session'] as Map,
        'expiresAt': '2020-01-01T00:00:00Z',
      }),
    );
    addTearDown(c.dispose);
    await c.load();
    expect(c.needsJoin, isTrue);
    expect(calls, 0);
    expect(c.snapshot, isNull);
  });

  test('controller latest request wins, access error clears graph, dispose ignores late result', () async {
    final pending = <Completer<http.Response>>[];
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) {
        final response = Completer<http.Response>();
        pending.add(response);
        return response.future;
      }),
    );
    addTearDown(api.close);
    final c = GraphController(
      api,
      MemoryStorage(),
      7,
      initialSession: session(),
    );
    final first = c.load();
    await Future<void>.delayed(Duration.zero);
    final second = c.load();
    await Future<void>.delayed(Duration.zero);
    pending[1].complete(jsonResponse(treeJson(version: 8)));
    await second;
    pending[0].complete(jsonResponse(treeJson(version: 4)));
    await first;
    expect(c.snapshot!.version, 8);
    final denied = c.load();
    await Future<void>.delayed(Duration.zero);
    pending[2].complete(jsonResponse({}, 403));
    await denied;
    expect(c.snapshot, isNull);
    expect(c.layout, isNull);
    expect(c.error, isNotNull);
    final expired = c.load();
    await Future<void>.delayed(Duration.zero);
    pending[3].complete(jsonResponse({}, 401));
    await expired;
    expect(c.needsJoin, isTrue);
    final late = c.load();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    pending[4].complete(jsonResponse(treeJson()));
    await late;
  });
}

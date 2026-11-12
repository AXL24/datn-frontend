import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gia_pha_app/models/graph_draft.dart';
import 'package:gia_pha_app/models/tree_snapshot.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/controllers/graph_controller.dart';
import 'package:gia_pha_app/controllers/person_edit_controller.dart';
import 'package:gia_pha_app/services/api_service.dart';

import 'fixtures.dart';
import 'graph_fixtures.dart';

GraphDraft fresh() => GraphDraft(
  TreeSnapshot.fromJson(
    treeJson(
      people: [personJson(id: 11), personJson(id: 12), personJson(id: 13)],
      edges: [],
    ),
  ),
);
void child(GraphDraft d, int parent, int person, {String role = 'FATHER'}) =>
    d.add({
      'type': 'ADD_PARENT',
      'parent': d.ref(parent),
      'child': d.ref(person),
      'role': role,
      'kind': 'ADOPTIVE',
    });
AccessSession edit() =>
    AccessSession.fromJson(accessJson(permission: 'EDIT')['session']);
void main() {
  test('four commands use exact tempId-only payload and explicit independent kinds', () {
    final d = fresh(), father = -1, mother = -2;
    expect(d.newPerson(), father);
    expect(d.newPerson(), mother);
    d.add({
      'type': 'ADD_PARENTS',
      'child': d.ref(11),
      'father': d.ref(father),
      'mother': d.ref(mother),
      'fatherKind': 'BIOLOGICAL',
      'motherKind': 'STEP',
    });
    d.add({'type': 'ADD_SPOUSE', 'person': d.ref(11), 'spouse': d.ref(12)});
    final newChild = d.newPerson();
    d.add({
      'type': 'ADD_CHILD',
      'child': d.ref(newChild),
      'parents': [
        {'person': d.ref(11), 'role': 'MOTHER', 'kind': 'ADOPTIVE'},
        {'person': d.ref(12), 'role': 'FATHER', 'kind': 'BIOLOGICAL'},
      ],
    });
    child(d, 11, 13);
    expect(d.validate(), isNull);
    expect(d.snapshot.relationships.length, 6);
    expect(
      d.snapshot.persons
          .where((p) => p.id < 0)
          .every((p) => p.displayName == null && p.gender == 'UNKNOWN'),
      true,
    );
    final payload = d.payload(draftUuid());
    expect(payload.keys.toSet(), {
      'requestId',
      'baseVersion',
      'newPersons',
      'relationCommands',
    });
    for (final p in payload['newPersons']) {
      expect(p.keys.toSet(), {'tempId'});
    }
    expect(d.snapshot.relationships.where((e) => e.isSpouse).length, 1);
  });
  test('no second parent role, self, duplicate spouse, mixed pair or ancestor cycle', () {
    final d = fresh();
    child(d, 11, 12);
    expect(() => child(d, 13, 12), throwsFormatException);
    expect(() => child(d, 11, 11), throwsFormatException);
    expect(() => child(d, 12, 11), throwsFormatException);
    expect(
      () => d.add({
        'type': 'ADD_SPOUSE',
        'person': d.ref(12),
        'spouse': d.ref(11),
      }),
      throwsFormatException,
    );
    d.add({'type': 'ADD_SPOUSE', 'person': d.ref(12), 'spouse': d.ref(13)});
    expect(
      () => d.add({
        'type': 'ADD_SPOUSE',
        'person': d.ref(13),
        'spouse': d.ref(12),
      }),
      throwsFormatException,
    );
    expect(d.commands.length, 2);
  });
  test(
    'removing spouse command cannot silently invalidate common-child command',
    () {
      final d = fresh();
      d.add({'type': 'ADD_SPOUSE', 'person': d.ref(11), 'spouse': d.ref(12)});
      final spouseId = d.commands.first['commandId'];
      final n = d.newPerson();
      d.add({
        'type': 'ADD_CHILD',
        'child': d.ref(n),
        'parents': [
          {'person': d.ref(11), 'role': 'FATHER', 'kind': 'BIOLOGICAL'},
          {'person': d.ref(12), 'role': 'MOTHER', 'kind': 'STEP'},
        ],
      });
      expect(d.removeCommand(spouseId), isNotNull);
      expect(d.commands.length, 2);
      expect(d.removeTemporary(n), isNull);
      expect(d.commands.length, 1);
      expect(d.temporary, isEmpty);
      expect(d.removeCommand(spouseId), isNull);
      expect(d.dirty, false);
      expect(d.baseline.persons.length, 3);
    },
  );
  test('existing people connect with empty newPersons', () {
    final d = fresh();
    child(d, 11, 12);
    expect(d.payload(draftUuid())['newPersons'], isEmpty);
  });
  for (final status in [409, 422, 503]) {
    test(
      'commit $status retains draft, 409/503 block; 422 remains editable',
      () async {
        var posts = 0, gets = 0;
        final api = ApiService(
          baseUrl: 'http://test.invalid',
          client: MockClient((r) async {
            if (r.method == 'POST') {
              posts++;
              return jsonResponse({'code': 'STALE_DRAFT'}, status);
            }
            gets++;
            return jsonResponse(
              treeJson(people: [personJson(id: 11)], edges: []),
            );
          }),
        );
        final g = GraphController(
          api,
          MemoryStorage(),
          7,
          initialSession: edit(),
        );
        await g.load();
        final n = g.draft!.newPerson();
        child(g.draft!, 11, n);
        g.changed();
        expect(await g.commit(), false);
        expect(g.dirty, true);
        expect(g.blocked, status != 422);
        await g.load();
        expect(gets, 1);
        expect(posts, 1);
        if (status != 422) {
          expect(await g.commit(), false);
          expect(posts, 1);
        }
        g.dispose();
        api.close();
      },
    );
  }
  test(
    'confirmed POST then failed GET clears draft; retry reads only',
    () async {
      var posts = 0, gets = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            final j = jsonDecode(r.body);
            return jsonResponse({
              'familyId': 7,
              'requestId': j['requestId'],
              'version': 5,
              'personIdMap': {'tmp-1': 22},
            });
          }
          gets++;
          if (gets == 2) return jsonResponse({}, 503);
          return jsonResponse(
            treeJson(
              people: [personJson(id: 11)],
              edges: [],
              version: gets == 1 ? 4 : 5,
            ),
          );
        }),
      );
      final g = GraphController(
        api,
        MemoryStorage(),
        7,
        initialSession: edit(),
      );
      await g.load();
      final n = g.draft!.newPerson();
      child(g.draft!, 11, n);
      g.changed();
      expect(await g.commit(), true);
      expect(g.dirty, false);
      expect(g.error, isNotNull);
      expect(g.lastIdMap['tmp-1'], 22);
      expect(await g.commit(), false);
      await g.load();
      expect(g.error, isNull);
      expect(posts, 1);
      g.dispose();
      api.close();
    },
  );
  test('API08 updates baseline/version while retaining draft; discard cannot undo profile', () async {
    var version = 4;
    var name = 'An';
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        if (r.method == 'PUT') {
          expect(jsonDecode(r.body)['baseVersion'], 4);
          version = 5;
          name = 'Đã lưu';
          return jsonResponse({
            'familyId': 7,
            'familyVersion': version,
            'person': personJson(id: 11, name: name),
          });
        }
        return jsonResponse(
          treeJson(
            people: [personJson(id: 11, name: name)],
            edges: [],
            version: version,
          ),
        );
      }),
    );
    final g = GraphController(api, MemoryStorage(), 7, initialSession: edit());
    await g.load();
    final n = g.draft!.newPerson();
    child(g.draft!, 11, n);
    g.changed();
    final c = PersonEditController(
      api,
      edit(),
      g.draft!.personWithVersion(11),
      graph: g,
    );
    c.change('displayName', 'Đã lưu');
    expect(await c.save(), true);
    expect(g.dirty, true);
    expect(g.draft!.baseline.version, 5);
    expect(g.draft!.baseline.persons.first.name, 'Đã lưu');
    await g.discardAndReload();
    expect(g.dirty, false);
    expect(g.snapshot!.persons.first.name, 'Đã lưu');
    c.dispose();
    g.dispose();
    api.close();
  });
  test('timeout does not replay and late commit after dispose cannot adopt snapshot', () async {
    final pending = Completer<http.Response>();
    var posts = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((r) async {
        if (r.method == 'POST') {
          posts++;
          return pending.future;
        }
        return jsonResponse(treeJson(people: [personJson(id: 11)], edges: []));
      }),
    );
    final g = GraphController(api, MemoryStorage(), 7, initialSession: edit());
    await g.load();
    final n = g.draft!.newPerson();
    child(g.draft!, 11, n);
    expect(await g.commit(), false);
    expect(g.blocked, true);
    expect(await g.commit(), false);
    expect(posts, 1);
    g.dispose();
    pending.complete(jsonResponse({}));
    api.close();
  });
  test('commit acknowledgement must match request, map and family', () async {
    for (final mode in ['request', 'family', 'mapping']) {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            final j = jsonDecode(r.body);
            return jsonResponse({
              'familyId': mode == 'family' ? 8 : 7,
              'requestId': mode == 'request' ? 'wrong' : j['requestId'],
              'version': 5,
              'personIdMap': mode == 'mapping' ? {'tmp-1': 11} : {'tmp-1': 22},
            });
          }
          return jsonResponse(
            treeJson(people: [personJson(id: 11)], edges: []),
          );
        }),
      );
      final g = GraphController(
        api,
        MemoryStorage(),
        7,
        initialSession: edit(),
      );
      await g.load();
      final n = g.draft!.newPerson();
      child(g.draft!, 11, n);
      expect(await g.commit(), false);
      expect(g.blocked, true);
      expect(g.dirty, true);
      g.dispose();
      api.close();
    }
  });
  test(
    'disposing graph while POST pending ignores response and never fetches',
    () async {
      final pending = Completer<http.Response>();
      var gets = 0;
      String? request;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            request = jsonDecode(r.body)['requestId'];
            return pending.future;
          }
          gets++;
          return jsonResponse(
            treeJson(people: [personJson(id: 11)], edges: []),
          );
        }),
      );
      final g = GraphController(
        api,
        MemoryStorage(),
        7,
        initialSession: edit(),
      );
      await g.load();
      final n = g.draft!.newPerson();
      child(g.draft!, 11, n);
      final saving = g.commit();
      await Future<void>.delayed(Duration.zero);
      g.dispose();
      pending.complete(
        jsonResponse({
          'familyId': 7,
          'requestId': request,
          'version': 5,
          'personIdMap': {'tmp-1': 22},
        }),
      );
      expect(await saving, false);
      expect(gets, 1);
      expect(g.lastIdMap, isEmpty);
      api.close();
    },
  );
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gia_pha_app/controllers/person_controller.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/models/person.dart';
import 'package:gia_pha_app/models/family.dart';
import 'package:gia_pha_app/services/api_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AccessSession session() => AccessSession.fromJson(accessJson()['session']);
  test(
    'API06 sends encoded query, page and bearer for correct Family',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          expect(r.method, 'GET');
          expect(r.url.path, '/families/7/people');
          expect(r.url.queryParameters, {
            'page': '2',
            'size': '20',
            'q': 'Nguyễn & %_',
          });
          expect(r.headers['Authorization'], 'Bearer test-only-token');
          return jsonResponse(peopleJson(page: 2, total: 41, pages: 3));
        }),
      );
      addTearDown(api.close);
      final result = await api.getPeople(
        7,
        session(),
        page: 2,
        q: ' Nguyễn & %_ ',
      );
      expect(result.page, 2);
      expect(result.content.single.name, 'Nguyễn An');
    },
  );
  test(
    'API07 reads actual id and preserves nullable profile and year-only dates',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          expect(r.url.path, '/families/7/people/11');
          return jsonResponse(personJson(name: null));
        }),
      );
      addTearDown(api.close);
      final person = await api.getPerson(7, 11, session());
      expect(person.name, 'Chưa có thông tin');
      expect(person.birthLabel, '1980');
      expect(person.deathLabel, 'Chưa rõ');
      expect(person.lifeStatusLabel, 'Chưa rõ');
      final dated = Person.fromJson({
        ...personJson(),
        'birthDate': '1980-02-03',
        'birthYear': 1980,
        'lifeStatus': 'ALIVE',
      });
      expect(dated.birthLabel, '03/02/1980');
      expect(dated.lifeStatusLabel, 'Còn sống');
    },
  );
  test(
    'cross-family session, temporary id and invalid query never send HTTP',
    () async {
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls++;
          return jsonResponse({});
        }),
      );
      addTearDown(api.close);
      for (final request in [
        api.getPeople(8, session()),
        api.getPerson(7, -1, session()),
        api.getPeople(7, session(), q: 'a' * 151),
        api.getPeople(7, session(), page: -1),
      ]) {
        await expectLater(request, throwsA(isA<ApiException>()));
      }
      expect(calls, 0);
    },
  );
  test(
    'response Family/id mismatch and malformed pages do not expose data',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient(
          (r) async => jsonResponse(
            r.url.path.endsWith('/people')
                ? peopleJson(content: [personJson(familyId: 8)])
                : personJson(id: 12),
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.getPeople(7, session()),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.getPerson(7, 11, session()),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'latest search response wins even if older response finishes later',
    () async {
      final requests = <String, Completer<http.Response>>{};
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) {
          final key = r.url.queryParameters['q']!;
          return (requests[key] = Completer<http.Response>()).future;
        }),
      );
      addTearDown(api.close);
      final c = PersonController(
        api,
        MemoryStorage(),
        7,
        initialSession: session(),
      );
      addTearDown(c.dispose);
      final old = c.loadPeople(q: 'old');
      await Future<void>.delayed(Duration.zero);
      final recent = c.loadPeople(q: 'new');
      await Future<void>.delayed(Duration.zero);
      requests['new']!.complete(
        jsonResponse(peopleJson(content: [personJson(name: 'New')])),
      );
      await recent;
      requests['old']!.complete(
        jsonResponse(peopleJson(content: [personJson(name: 'Old')])),
      );
      await old;
      expect(c.people!.content.single.name, 'New');
      expect(c.query, 'new');
      expect(c.busy, isFalse);
    },
  );
  test(
    'search resets page; refresh preserves applied query; empty page is valid',
    () async {
      final seen = <Map<String, String>>[];
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          seen.add(r.url.queryParameters);
          return jsonResponse(
            peopleJson(
              page: int.parse(r.url.queryParameters['page']!),
              content: [],
              total: 0,
              pages: 0,
            ),
          );
        }),
      );
      addTearDown(api.close);
      final c = PersonController(
        api,
        MemoryStorage(),
        7,
        initialSession: session(),
      );
      addTearDown(c.dispose);
      await c.loadPeople(targetPage: 3);
      await c.loadPeople(q: 'An');
      await c.loadPeople();
      expect(seen.map((p) => p['page']).toList(), ['3', '0', '0']);
      expect(seen.last['q'], 'An');
      expect(c.people!.content, isEmpty);
      expect(c.error, isNull);
    },
  );
  test(
    '401 clears sensitive displayed data and only that family session',
    () async {
      var unauthorized = false;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient(
          (r) async =>
              unauthorized ? jsonResponse({}, 401) : jsonResponse(peopleJson()),
        ),
      );
      addTearDown(api.close);
      final storage = MemoryStorage();
      await storage.saveSession(session());
      await storage.saveSession(
        AccessSession.fromJson(accessJson(id: 8)['session']),
      );
      await storage.saveFamily(Family.fromJson(familyJson()));
      final c = PersonController(api, storage, 7);
      addTearDown(c.dispose);
      await c.loadPeople();
      expect(c.people, isNotNull);
      unauthorized = true;
      await c.loadPeople();
      expect(c.people, isNull);
      expect(c.needsJoin, isTrue);
      expect(storage.sessions.keys, [8]);
      expect(storage.families.keys, [7]);
    },
  );
  test(
    'expired local session requires rejoin without HTTP; 403 is not rejoin',
    () async {
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls++;
          return jsonResponse({}, 403);
        }),
      );
      addTearDown(api.close);
      final expired = PersonController(
        api,
        MemoryStorage(),
        7,
        initialSession: AccessSession(
          familyId: 7,
          accessToken: 'test-only',
          permission: 'VIEW',
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      );
      addTearDown(expired.dispose);
      await expired.loadPeople();
      expect(expired.needsJoin, isTrue);
      expect(calls, 0);
      final forbidden = PersonController(
        api,
        MemoryStorage(),
        7,
        initialSession: session(),
      );
      addTearDown(forbidden.dispose);
      await forbidden.loadPeople();
      expect(forbidden.errorStatus, 403);
      expect(forbidden.needsJoin, isFalse);
    },
  );
  test(
    'missing Person returns actionable 404 instead of family not found',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient(
          (r) async => jsonResponse({'code': 'PERSON_NOT_FOUND'}, 404),
        ),
      );
      addTearDown(api.close);
      final c = PersonController(
        api,
        MemoryStorage(),
        7,
        initialSession: session(),
      );
      addTearDown(c.dispose);
      await c.loadPerson(11);
      expect(c.errorStatus, 404);
      expect(c.error, contains('hồ sơ'));
      expect(c.person, isNull);
    },
  );
  test('dispose prevents updates from pending response', () async {
    final response = Completer<http.Response>();
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) => response.future),
    );
    addTearDown(api.close);
    final c = PersonController(
      api,
      MemoryStorage(),
      7,
      initialSession: session(),
    );
    final result = c.loadPeople();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    response.complete(jsonResponse(peopleJson()));
    await result;
    expect(c.people, isNull);
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gia_pha_app/controllers/family_controller.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/models/family.dart';
import 'package:gia_pha_app/services/api_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'API01 preserves Vietnamese, trims names, sends no credentials',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid/',
        client: MockClient((r) async {
          expect(r.url.path, '/families');
          expect(r.method, 'POST');
          expect(r.headers.containsKey('Authorization'), isFalse);
          final body = jsonDecode(r.body) as Map;
          expect(body['name'], 'Nhà Nguyễn');
          expect(body['firstPerson'], {
            'displayName': 'Nguyễn Văn A',
            'birthYear': 1980,
          });
          expect(body.containsKey('permission'), isFalse);
          return jsonResponse(createdJson(), 201);
        }),
      );
      addTearDown(api.close);
      final result = await api.create(
        name: ' Nhà Nguyễn ',
        personName: ' Nguyễn Văn A ',
        birthYear: 1980,
      );
      expect(result.family.name, 'Gia phả nhà Nguyễn');
      expect(result.session.permission, 'EDIT');
    },
  );
  test(
    'API11 strips code and API02 uses token for exactly its family',
    () async {
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls++;
          if (r.method == 'POST') {
            expect(r.url.path, '/access/join');
            expect(jsonDecode(r.body), {'familyCode': 'test-code'});
            return jsonResponse(accessJson());
          }
          expect(r.url.path, '/families/7');
          expect(r.headers['Authorization'], 'Bearer test-only-token');
          return jsonResponse(familyJson());
        }),
      );
      addTearDown(api.close);
      final result = await api.join(' test-code ');
      await api.getFamily(7, result.session);
      await expectLater(
        api.getFamily(8, result.session),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 2);
    },
  );
  test(
    'unknown create result blocks repeated submission and never auto retries',
    () async {
      var calls = 0;
      final response = Completer<void>();
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        timeout: const Duration(milliseconds: 10),
        client: MockClient((r) async {
          calls++;
          await response.future;
          return jsonResponse(createdJson(), 201);
        }),
      );
      addTearDown(api.close);
      final c = FamilyController(api, MemoryStorage());
      addTearDown(c.dispose);
      final first = c.create(name: 'A', personName: 'B');
      expect(await c.create(name: 'A', personName: 'B'), isNull);
      expect(await first, isNull);
      expect(c.outcomeUnknown, isTrue);
      expect(await c.create(name: 'A', personName: 'B'), isNull);
      expect(calls, 1);
      response.complete();
    },
  );
  test(
    'successful create survives local save failure; local retry never POSTs',
    () async {
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls++;
          return jsonResponse(createdJson(), 201);
        }),
      );
      addTearDown(api.close);
      final storage = MemoryStorage()..failSave = true;
      final c = FamilyController(api, storage);
      addTearDown(c.dispose);
      final result = await c.create(name: 'A', personName: 'B');
      expect(result, isNotNull);
      expect(c.warning, isNotNull);
      storage.failSave = false;
      await c.remember(result!);
      expect(c.warning, isNull);
      expect(storage.sessions.keys, [7]);
      expect(calls, 1);
    },
  );
  test('401 removes only invalid token, preserves recent family and other sessions', () async {
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async => jsonResponse({}, 401)),
    );
    addTearDown(api.close);
    final storage = MemoryStorage();
    for (final id in [7, 8]) {
      await storage.saveSession(
        AccessSession.fromJson(accessJson(id: id)['session']),
      );
      await storage.saveFamily(Family.fromJson(familyJson(id)));
    }
    final c = FamilyController(api, storage);
    addTearDown(c.dispose);
    await c.open(7);
    expect(c.needsJoin, isTrue);
    expect(c.family, isNull);
    expect(storage.sessions.keys, [8]);
    expect(storage.families.length, 2);
  });
  test('expired local session requests rejoin without HTTP; wrong family code not stored', () async {
    var calls = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        calls++;
        return jsonResponse(accessJson(id: 8));
      }),
    );
    addTearDown(api.close);
    final storage = MemoryStorage();
    storage.sessions[7] = AccessSession(
      familyId: 7,
      accessToken: 'test-only',
      permission: 'VIEW',
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    final c = FamilyController(api, storage);
    addTearDown(c.dispose);
    await c.open(7);
    expect(c.needsJoin, isTrue);
    expect(calls, 0);
    expect(await c.join('test-only', expectedFamilyId: 7), isNull);
    expect(storage.sessions.containsKey(8), isFalse);
    expect(c.error, contains('gia phả khác'));
  });
  test(
    'invalid family code is actionable; server response cannot leak into UI',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient(
          (r) async => jsonResponse({
            'code': 'INVALID_FAMILY_CODE',
            'detail': 'private-data',
          }, 403),
        ),
      );
      addTearDown(api.close);
      final c = FamilyController(api, MemoryStorage());
      addTearDown(c.dispose);
      expect(await c.join('test-only'), isNull);
      expect(c.error, contains('Mã gia phả không đúng'));
      expect(c.error, isNot(contains('private-data')));
    },
  );
  test(
    'remove from device does not send request or delete other families',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient(
          (r) async => throw StateError('HTTP must not be called'),
        ),
      );
      addTearDown(api.close);
      final storage = MemoryStorage();
      for (final id in [7, 8]) {
        await storage.saveSession(
          AccessSession.fromJson(accessJson(id: id)['session']),
        );
        await storage.saveFamily(Family.fromJson(familyJson(id)));
      }
      final c = FamilyController(api, storage);
      addTearDown(c.dispose);
      await c.loadRecents();
      await c.remove(7);
      expect(storage.sessions.keys, [8]);
      expect(storage.families.keys, [8]);
      expect(c.recents.single.id, 8);
    },
  );
}

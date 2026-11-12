import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:gia_pha_app/app.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/models/person.dart';
import 'package:gia_pha_app/controllers/person_edit_controller.dart';
import 'package:gia_pha_app/services/api_service.dart';
import 'package:gia_pha_app/views/person_detail_screen.dart';

import 'fixtures.dart';

AccessSession editSession() =>
    AccessSession.fromJson(accessJson(permission: 'EDIT')['session']);
Person baseline() =>
    Person.fromJson({...personJson(), 'version': 42, 'familyVersion': 8});
void main() {
  test(
    'API08 sends Family version, all fields; no-op uses server version',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          expect(r.method, 'PUT');
          final j = jsonDecode(r.body);
          expect(j['baseVersion'], 8);
          expect(j['details'].keys.length, 8);
          expect(j['details']['displayName'], null);
          return jsonResponse({
            'familyId': 7,
            'familyVersion': 8,
            'person': personJson(name: null),
          });
        }),
      );
      final c = PersonEditController(api, editSession(), baseline());
      c.change('displayName', null);
      expect(await c.save(), true);
      expect(c.baseVersion, 8);
      expect(c.dirty, false);
      c.dispose();
      api.close();
    },
  );
  for (final status in [409, 404, 401, 503]) {
    test('write $status preserves form and blocks repeat', () async {
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls++;
          return jsonResponse({'code': 'STALE_VERSION'}, status);
        }),
      );
      final c = PersonEditController(api, editSession(), baseline());
      c.change('displayName', 'Tên mới');
      expect(await c.save(), false);
      expect(c.details['displayName'], 'Tên mới');
      expect(c.baseVersion, 8);
      expect(await c.save(), false);
      expect(calls, 1);
      c.dispose();
      api.close();
    });
  }
  test('DELETE query, no body; success cannot be repeated or undone', () async {
    var calls = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        calls++;
        expect(r.method, 'DELETE');
        expect(r.url.queryParameters['baseVersion'], '8');
        expect(r.body, isEmpty);
        return jsonResponse({
          'familyId': 7,
          'deletedPersonId': 11,
          'version': 9,
        });
      }),
    );
    final c = PersonEditController(api, editSession(), baseline());
    c.change('note', 'chưa lưu');
    expect(await c.remove(), false);
    expect(calls, 0);
    c.discard();
    expect(await c.remove(), true);
    c.discard();
    expect(await c.remove(), false);
    expect(calls, 1);
    c.dispose();
    api.close();
  });
  test('timeout and malformed/scope response are not retried', () async {
    for (final mode in ['timeout', 'scope']) {
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        timeout: const Duration(milliseconds: 5),
        client: MockClient((r) async {
          calls++;
          if (mode == 'timeout') {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          return jsonResponse({
            'familyId': 99,
            'deletedPersonId': 11,
            'version': 9,
          });
        }),
      );
      final c = PersonEditController(api, editSession(), baseline());
      expect(await c.remove(), false);
      expect(c.blocked, true);
      expect(await c.remove(), false);
      expect(calls, 1);
      c.dispose();
      api.close();
    }
  });
  test('date/year validation and no inferred gender or parent role', () {
    final api = ApiService(baseUrl: 'http://test.invalid');
    final c = PersonEditController(api, editSession(), baseline());
    c.change('birthDate', '1980-02-30');
    expect(c.validate(), isNotNull);
    c.change('birthYear', null);
    expect(c.validate(), isNotNull);
    c.change('birthDate', '1980-02-29');
    expect(c.validate(), isNull);
    c.change('deathYear', 1979);
    expect(c.validate(), isNotNull);
    c.change('lifeStatus', 'DECEASED');
    expect(c.validate(), isNotNull);
    c.change('deathYear', 2020);
    expect(c.validate(), isNull);
    expect(c.details['gender'], 'UNKNOWN');
    c.dispose();
    api.close();
  });
  test(
    'family writes share lock; late response cannot change disposed controller',
    () async {
      final pending = Completer<http.Response>();
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) => pending.future),
      );
      final c = PersonEditController(api, editSession(), baseline());
      c.change('displayName', 'Tên mới');
      final saving = c.save();
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        api.updateFamily(7, editSession(), name: 'x', version: 8),
        throwsA(isA<ApiException>()),
      );
      c.dispose();
      pending.complete(
        jsonResponse({
          'familyId': 7,
          'familyVersion': 9,
          'person': personJson(name: 'Tên mới'),
        }),
      );
      expect(await saving, false);
      expect(c.baseline.name, 'Nguyễn An');
      api.close();
    },
  );

  test(
    'changed baseline before confirmation prevents delete without rebasing',
    () async {
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          expect(r.method, 'GET');
          return jsonResponse({...personJson(), 'familyVersion': 9});
        }),
      );
      final c = PersonEditController(api, editSession(), baseline());
      expect(await c.verifyBeforeDelete(), false);
      expect(c.baseVersion, 8);
      expect(c.blocked, true);
      expect(await c.remove(), false);
      c.dispose();
      api.close();
    },
  );
  test('missing familyVersion never falls back to Person version', () async {
    var calls = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        calls++;
        return jsonResponse({});
      }),
    );
    final c = PersonEditController(
      api,
      editSession(),
      Person.fromJson(personJson()),
    );
    expect(await c.save(), false);
    expect(await c.remove(), false);
    expect(calls, 0);
    c.dispose();
    api.close();
  });
  testWidgets(
    'VIEW unlock with storage failure uses new token for detail and update',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var unlocked = false, puts = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            unlocked = true;
            return jsonResponse({
              ...accessJson(permission: 'EDIT')['session']
                  as Map<String, dynamic>,
              'accessToken': 'replacement-test-session',
            });
          }
          if (unlocked) {
            expect(
              r.headers['Authorization'],
              'Bearer replacement-test-session',
            );
          }
          if (r.method == 'PUT') {
            puts++;
            return jsonResponse({
              'familyId': 7,
              'familyVersion': 9,
              'person': personJson(),
            });
          }
          return jsonResponse({...personJson(), 'familyVersion': 8});
        }),
      );
      addTearDown(api.close);
      final storage = MemoryStorage()..failSave = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: PersonDetailScreen(
            api: api,
            storage: storage,
            familyId: 7,
            personId: 11,
            initialSession: AccessSession.fromJson(accessJson()['session']),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập mã chỉnh sửa'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'test-only-edit');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      expect(find.text('Chỉnh sửa hồ sơ'), findsOneWidget);
      await tester.tap(find.text('Lưu hồ sơ'));
      await tester.pumpAndSettle();
      expect(puts, 1);
      expect(tester.takeException(), isNull);
    },
  );
  Future<void> launch(
    WidgetTester tester,
    ApiService api,
    MemoryStorage storage,
  ) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: PersonDetailScreen(
          api: api,
          storage: storage,
          familyId: 7,
          personId: 11,
          initialSession: editSession(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chỉnh sửa'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'MH10 to MH13 dirty Save then MH15 delete uses returned version',
    (tester) async {
      var writes = 0, deletes = 0;
      var version = 8;
      var name = 'Nguyễn An';
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            writes++;
            final j = jsonDecode(r.body);
            expect(j['baseVersion'], 8);
            name = j['details']['displayName'];
            version = 9;
            return jsonResponse({
              'familyId': 7,
              'familyVersion': 9,
              'person': personJson(name: name),
            });
          }
          if (r.method == 'DELETE') {
            deletes++;
            expect(r.url.queryParameters['baseVersion'], '9');
            return jsonResponse({
              'familyId': 7,
              'deletedPersonId': 11,
              'version': 10,
            });
          }
          return jsonResponse({
            ...personJson(name: name),
            'familyVersion': version,
          });
        }),
      );
      await launch(tester, api, MemoryStorage());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'),
        'Tên mới',
      );
      await tester.tap(find.text('Xóa hồ sơ'));
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ có thay đổi chưa lưu'), findsOneWidget);
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(deletes, 0);
      expect(find.text('Xóa Tên mới?'), findsOneWidget);
      await tester.tap(find.text('Xóa hồ sơ'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dirty cancel stops deletion; 409 keeps input and disables delete',
    (tester) async {
      var deletes = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'PUT') {
            return jsonResponse({'code': 'STALE_VERSION'}, 409);
          }
          if (r.method == 'DELETE') deletes++;
          return jsonResponse({...personJson(), 'familyVersion': 8});
        }),
      );
      await launch(tester, api, MemoryStorage());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'),
        'Giữ nội dung',
      );
      await tester.tap(find.text('Xóa hồ sơ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      await tester.tap(find.text('Lưu hồ sơ'));
      await tester.pumpAndSettle();
      expect(find.text('Giữ nội dung'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Xóa hồ sơ'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}

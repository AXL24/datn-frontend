import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gia_pha_app/app.dart';
import 'package:gia_pha_app/controllers/person_edit_controller.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/services/api_service.dart';
import 'package:gia_pha_app/views/people_view.dart';

import 'fixtures.dart';

AccessSession session([String permission = 'EDIT']) =>
    AccessSession.fromJson(accessJson(permission: permission)['session']);
void main() {
  test('create requires name, exact Family version and complete details, no relations', () async {
    var calls = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        calls++;
        expect(r.method, 'POST');
        expect(r.url.path, '/families/7/people');
        final j = jsonDecode(r.body);
        expect(j.keys.toSet(), {'baseVersion', 'details'});
        expect(j['baseVersion'], 8);
        expect(j['details']['displayName'], 'Nguyễn Bình');
        expect(j['details'].keys.length, 8);
        return jsonResponse({
          'familyId': 7,
          'familyVersion': 9,
          'person': personJson(id: 22, name: 'Nguyễn Bình'),
        }, 201);
      }),
    );
    final c = PersonEditController.create(api, session(), 8);
    expect(await c.save(), false);
    expect(calls, 0);
    expect(await c.remove(), false);
    c.change('displayName', '  Nguyễn Bình  ');
    expect(await c.save(), true);
    expect(c.baseline.id, 22);
    expect(c.baseVersion, 9);
    expect(await c.save(), false);
    expect(calls, 1);
    c.dispose();
    api.close();
  });
  for (final status in [409, 503]) {
    test('create $status keeps input and blocks resubmission', () async {
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls++;
          return jsonResponse({'code': 'STALE_VERSION'}, status);
        }),
      );
      final c = PersonEditController.create(api, session(), 8);
      c.change('displayName', 'Giữ nguyên');
      expect(await c.save(), false);
      expect(c.details['displayName'], 'Giữ nguyên');
      expect(c.baseVersion, 8);
      expect(await c.save(), false);
      expect(calls, 1);
      c.dispose();
      api.close();
    });
  }
  test(
    'create timeout or wrong Family response is not automatically repeated',
    () async {
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
              'familyVersion': 9,
              'person': personJson(),
            }, 201);
          }),
        );
        final c = PersonEditController.create(api, session(), 8);
        c.change('displayName', 'An');
        expect(await c.save(), false);
        expect(c.blocked, true);
        expect(await c.save(), false);
        expect(calls, 1);
        c.dispose();
        api.close();
      }
    },
  );
  test('expired EDIT cannot create; input and baseline survive', () async {
    var calls = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        calls++;
        return jsonResponse({});
      }),
    );
    final c = PersonEditController.create(api, session('VIEW'), 8);
    c.change('displayName', 'An');
    expect(await c.save(), false);
    expect(c.needsEdit, true);
    expect(calls, 0);
    expect(c.details['displayName'], 'An');
    c.dispose();
    api.close();
  });
  Future<void> launch(
    WidgetTester tester,
    ApiService api, {
    String permission = 'EDIT',
  }) async {
    tester.view.physicalSize = const Size(430, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: PeopleView(
            api: api,
            storage: MemoryStorage(),
            familyId: 7,
            initialSession: session(permission),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Thêm'));
    await tester.pumpAndSettle();
  }

  testWidgets('MH09 add reuses MH13; cancel sends no write', (tester) async {
    var writes = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        if (r.method != 'GET') writes++;
        return jsonResponse(
          r.url.path.endsWith('/people') ? peopleJson() : familyJson(),
        );
      }),
    );
    await launch(tester, api);
    expect(find.text('Thêm thành viên'), findsOneWidget);
    expect(find.text('Xóa hồ sơ'), findsNothing);
    await tester.tap(find.text('Tạo thành viên'));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng nhập họ tên thành viên.'), findsOneWidget);
    expect(writes, 0);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Họ và tên'),
      'Chưa tạo',
    );
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bỏ'));
    await tester.pumpAndSettle();
    expect(find.text('+ Thêm'), findsOneWidget);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'VIEW unlock then create once; detail read failure retries GET only',
    (tester) async {
      var posts = 0, gets = 0;
      var unlocked = false;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/access/edit')) {
            unlocked = true;
            return jsonResponse({
              ...accessJson(permission: 'EDIT')['session']
                  as Map<String, dynamic>,
              'accessToken': 'test-replacement',
            });
          }
          if (unlocked) {
            expect(r.headers['Authorization'], 'Bearer test-replacement');
          }
          if (r.method == 'POST') {
            posts++;
            expect(jsonDecode(r.body)['baseVersion'], 0);
            return jsonResponse({
              'familyId': 7,
              'familyVersion': 1,
              'person': personJson(id: 22),
            }, 201);
          }
          if (r.url.path.endsWith('/people/22')) {
            gets++;
            return gets == 1
                ? jsonResponse({}, 503)
                : jsonResponse({...personJson(id: 22), 'familyVersion': 1});
          }
          return jsonResponse(
            r.url.path.endsWith('/people') ? peopleJson() : familyJson(),
          );
        }),
      );
      await launch(tester, api, permission: 'VIEW');
      expect(find.text('Nhập mã chỉnh sửa'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'test-only-code');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Họ và tên'),
        'Nguyễn An',
      );
      await tester.tap(find.text('Tạo thành viên'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.text('Chi tiết hồ sơ'), findsOneWidget);
      await tester.tap(find.text('Thử tải lại'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(gets, 2);
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gia_pha_app/app.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/services/api_service.dart';
import 'package:gia_pha_app/views/family_info_screen.dart';
import 'package:gia_pha_app/views/edit_code_screen.dart';

import 'fixtures.dart';

Map<String, dynamic> editSessionJson() => {
  'familyId': 7,
  'accessToken': 'replacement-test-token',
  'permission': 'EDIT',
  'expiresAt': DateTime.now()
      .add(const Duration(days: 7))
      .toUtc()
      .toIso8601String(),
  'editExpiresAt': DateTime.now()
      .add(const Duration(hours: 5))
      .toUtc()
      .toIso8601String(),
};

void main() {
  test('EDIT deadline is separate from readable session; legacy EDIT behaves as VIEW', () {
    final legacy = AccessSession.fromJson(
      accessJson(permission: 'EDIT')['session']..remove('editExpiresAt'),
    );
    expect(legacy.canReadAt(DateTime.now()), isTrue);
    expect(legacy.canEditAt(DateTime.now()), isFalse);
    final current = AccessSession.fromJson(editSessionJson());
    expect(current.canEditAt(DateTime.now()), isTrue);
    final saved = AccessSession.fromJson(current.toJson());
    expect(saved.editExpiresAt, current.editExpiresAt);
    final expiredEdit = AccessSession.fromJson({
      ...editSessionJson(),
      'editExpiresAt': DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toUtc()
          .toIso8601String(),
    });
    expect(expiredEdit.canReadAt(DateTime.now()), isTrue);
    expect(expiredEdit.canEditAt(DateTime.now()), isFalse);
  });

  testWidgets(
    'VIEW opens MH07; new token is stored before editing and PUT uses Family version',
    (t) async {
      t.view.physicalSize = const Size(430, 980);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final storage = MemoryStorage();
      final old = AccessSession.fromJson(accessJson()['session']);
      await storage.saveSession(old);
      var activeToken = old.accessToken;
      var postCalls = 0, putCalls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          expect(r.url.path, startsWith('/families/7'));
          if (r.method == 'GET') {
            expect(r.headers['Authorization'], 'Bearer $activeToken');
            return jsonResponse(familyJson());
          }
          if (r.method == 'POST') {
            postCalls++;
            expect(r.url.path, '/families/7/access/edit');
            expect(r.headers['Authorization'], 'Bearer ${old.accessToken}');
            expect(jsonDecode(r.body), {'editCode': 'ED_test'});
            activeToken = 'replacement-test-token';
            return jsonResponse(editSessionJson());
          }
          putCalls++;
          expect(r.method, 'PUT');
          expect(r.url.path, '/families/7');
          expect(r.headers['Authorization'], 'Bearer replacement-test-token');
          expect(jsonDecode(r.body), {
            'name': 'Gia phả sửa',
            'description': 'Mô tả mới',
            'version': 0,
          });
          return jsonResponse({
            ...familyJson(),
            'name': 'Gia phả sửa',
            'description': 'Mô tả mới',
            'version': 1,
          });
        }),
      );
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: FamilyInfoScreen(api: api, storage: storage, familyId: 7),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Chỉnh sửa'));
      await t.pumpAndSettle();
      expect(find.byType(EditCodeScreen), findsOneWidget);
      await t.enterText(find.byType(TextFormField), ' ED_test ');
      await t.tap(find.text('Xác nhận'));
      await t.pumpAndSettle();
      expect(find.byType(EditCodeScreen), findsNothing);
      expect(storage.sessions[7]!.accessToken, 'replacement-test-token');
      expect(find.text('Chỉnh sửa gia phả'), findsOneWidget);
      await t.enterText(find.byType(TextFormField).at(0), ' Gia phả sửa ');
      await t.enterText(find.byType(TextFormField).at(1), 'Mô tả mới');
      await t.ensureVisible(find.text('Lưu'));
      await t.tap(find.text('Lưu'));
      await t.pumpAndSettle();
      expect(postCalls, 1);
      expect(putCalls, 1);
      expect(find.text('Gia phả sửa'), findsOneWidget);
      expect(storage.families[7]!.name, 'Gia phả sửa');
    },
  );

  testWidgets('bad Edit Code keeps VIEW token and MH07 open', (t) async {
    final storage = MemoryStorage();
    final old = AccessSession.fromJson(accessJson()['session']);
    await storage.saveSession(old);
    var calls = 0;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async {
        if (r.method == 'GET') return jsonResponse(familyJson());
        calls++;
        return jsonResponse({
          'code': 'INVALID_EDIT_CODE',
          'detail': 'private',
        }, 403);
      }),
    );
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: FamilyInfoScreen(api: api, storage: storage, familyId: 7),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Chỉnh sửa'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'wrong');
    await t.tap(find.text('Xác nhận'));
    await t.pumpAndSettle();
    expect(find.byType(EditCodeScreen), findsOneWidget);
    expect(find.textContaining('Mã chỉnh sửa không đúng'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    expect(storage.sessions[7]!.accessToken, old.accessToken);
    expect(calls, 1);
  });

  testWidgets(
    'active EDIT enters form directly; 409 keeps input and never retries',
    (t) async {
      t.view.physicalSize = const Size(430, 980);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final session = AccessSession.fromJson(editSessionJson());
      final storage = MemoryStorage();
      await storage.saveSession(session);
      var posts = 0, puts = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'GET') return jsonResponse(familyJson());
          if (r.method == 'POST') {
            posts++;
            return jsonResponse(editSessionJson());
          }
          puts++;
          return jsonResponse({'code': 'STALE_VERSION'}, 409);
        }),
      );
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: FamilyInfoScreen(api: api, storage: storage, familyId: 7),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Chỉnh sửa'));
      await t.pumpAndSettle();
      expect(find.byType(EditCodeScreen), findsNothing);
      await t.enterText(
        find.byType(TextFormField).first,
        'Bản chỉnh đang viết',
      );
      await t.ensureVisible(find.text('Lưu'));
      await t.tap(find.text('Lưu'));
      await t.pumpAndSettle();
      expect(posts, 0);
      expect(puts, 1);
      expect(find.text('Bản chỉnh đang viết'), findsOneWidget);
      expect(find.textContaining('đã thay đổi'), findsWidgets);
      expect(find.text('Bỏ thay đổi và tải bản mới'), findsOneWidget);
      expect(storage.sessions[7]!.accessToken, session.accessToken);
    },
  );

  test(
    'API12 timeout reports unknown outcome and no automatic retry',
    () async {
      final old = AccessSession.fromJson(accessJson()['session']);
      final pending = Completer<void>();
      var calls = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        timeout: const Duration(milliseconds: 10),
        client: MockClient((r) async {
          calls++;
          await pending.future;
          return jsonResponse(editSessionJson());
        }),
      );
      addTearDown(api.close);
      await expectLater(
        api.unlockEdit(7, old, 'ED_test'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.outcomeUnknown,
            'outcomeUnknown',
            true,
          ),
        ),
      );
      expect(calls, 1);
      pending.complete();
    },
  );
}

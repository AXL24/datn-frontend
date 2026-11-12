import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gia_pha_app/app.dart';
import 'package:gia_pha_app/services/api_service.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/views/family_info_screen.dart';
import 'package:gia_pha_app/views/person_detail_screen.dart';

import 'fixtures.dart';

void main() {
  testWidgets(
    'MH09 from family tab, search/paging, MH10 and back preserve search',
    (t) async {
      t.view.physicalSize = const Size(390, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          requests.add(r.url);
          if (r.url.path.endsWith('/people/11')) {
            return jsonResponse({
              ...personJson(),
              'birthDate': null,
              'birthYear': 1980,
            });
          }
          if (r.url.path.endsWith('/people')) {
            final page = int.parse(r.url.queryParameters['page']!);
            return jsonResponse(peopleJson(page: page, total: 21, pages: 2));
          }
          return jsonResponse(familyJson());
        }),
      );
      addTearDown(api.close);
      await t.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: FamilyInfoScreen(
            api: api,
            storage: MemoryStorage(),
            familyId: 7,
            initialSession: AccessSession.fromJson(accessJson()['session']),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(requests.where((u) => u.path.endsWith('/people')), isEmpty);
      await t.tap(find.text('Thành viên'));
      await t.pumpAndSettle();
      expect(find.text('Nguyễn An'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'An');
      await t.tap(find.text('Tìm kiếm'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byTooltip('Trang sau'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Trang sau'));
      await t.pumpAndSettle();
      expect(find.text('Trang 2 / 2'), findsOneWidget);
      await t.ensureVisible(find.text('Nguyễn An'));
      await t.pumpAndSettle();
      await t.tap(find.text('Nguyễn An'));
      await t.pumpAndSettle();
      expect(find.text('Chi tiết hồ sơ'), findsOneWidget);
      expect(find.text('1980'), findsOneWidget);
      expect(find.text('01/01/1980'), findsNothing);
      expect(find.text('Còn sống'), findsNothing);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.text('Trang 2 / 2'), findsOneWidget);
      expect(requests.last.queryParameters['q'], 'An');
      await t.tap(find.text('Thông tin'));
      await t.pumpAndSettle();
      await t.tap(find.text('Thành viên').last);
      await t.pumpAndSettle();
      expect(find.text('Trang 2 / 2'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'nullable MH10 on narrow screen; error 404 exposes return action',
    (t) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      var missing = false;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient(
          (r) async => missing
              ? jsonResponse({}, 404)
              : jsonResponse({
                  ...personJson(name: null),
                  'birthYear': null,
                  'note': null,
                }),
        ),
      );
      addTearDown(api.close);
      final session = AccessSession.fromJson(accessJson()['session']);
      await t.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: PersonDetailScreen(
            api: api,
            storage: MemoryStorage(),
            familyId: 7,
            personId: 11,
            initialSession: session,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Chưa có thông tin'), findsWidgets);
      expect(find.text('Chưa rõ tình trạng'), findsOneWidget);
      await t.drag(find.byType(ListView), const Offset(0, -600));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      missing = true;
      await t.ensureVisible(find.text('Làm mới hồ sơ'));
      await t.pumpAndSettle();
      await t.tap(find.text('Làm mới hồ sơ'));
      await t.pumpAndSettle();
      expect(find.text('Về danh sách thành viên'), findsOneWidget);
      expect(
        find.text(
          'Không tìm thấy hồ sơ trong gia phả này. Hồ sơ có thể đã bị xóa.',
        ),
        findsOneWidget,
      );
    },
  );
}

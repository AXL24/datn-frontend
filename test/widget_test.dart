import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gia_pha_app/app.dart';
import 'package:gia_pha_app/services/api_service.dart';

import 'fixtures.dart';

void main() {
  testWidgets(
    'create, keep codes masked, confirm, read family and reopen recent',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var creates = 0, reads = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            creates++;
            return jsonResponse(createdJson(), 201);
          }
          reads++;
          return jsonResponse(familyJson());
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(GiaPhaApp(api: api, storage: MemoryStorage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tạo gia phả mới'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Gia phả nhà Nguyễn',
      );
      await tester.enterText(find.byType(TextFormField).at(2), 'Nguyễn Văn A');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Tạo gia phả'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Tạo gia phả'));
      await tester.pumpAndSettle();
      expect(find.text('Đã tạo gia phả'), findsOneWidget);
      expect(find.text('test-only-family-code'), findsNothing);
      expect(find.text('test-only-edit-code'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Vào gia phả'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Vào gia phả'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Vào gia phả'));
      await tester.pumpAndSettle();
      expect(find.text('Thông tin gia phả'), findsOneWidget);
      expect(find.text('Phiên có quyền chỉnh sửa'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Gia phả nhà Nguyễn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gia phả nhà Nguyễn'));
      await tester.pumpAndSettle();
      expect(find.text('Thông tin gia phả'), findsOneWidget);
      expect(creates, 1);
      expect(reads, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'empty join validation then join VIEW on narrow screen with larger text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var joins = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            joins++;
            return jsonResponse(accessJson());
          }
          return jsonResponse(familyJson());
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(GiaPhaApp(api: api, storage: MemoryStorage()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Nhập mã gia phả'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhập mã gia phả'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Mở gia phả'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mở gia phả'));
      await tester.pumpAndSettle();
      expect(joins, 0);
      expect(find.text('Vui lòng nhập mã gia phả.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'test-only');
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Mở gia phả'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mở gia phả'));
      await tester.pumpAndSettle();
      expect(find.text('Quyền xem gia phả'), findsOneWidget);
      expect(joins, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

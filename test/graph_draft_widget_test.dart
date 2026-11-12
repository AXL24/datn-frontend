import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gia_pha_app/app.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/views/family_info_screen.dart';
import 'package:gia_pha_app/widgets/person_node.dart';
import 'package:gia_pha_app/services/api_service.dart';

import 'fixtures.dart';

import 'package:gia_pha_app/controllers/graph_controller.dart';
import 'package:gia_pha_app/views/person_detail_screen.dart';
import 'package:gia_pha_app/views/family_tree_view.dart';

import 'graph_fixtures.dart';

void main() {
  testWidgets(
    'direction buttons open scoped forms, preserve spouse side locally and fit narrow landscape',
    (t) async {
      t.view.physicalSize = const Size(430, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final calls = <String>[];
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          calls.add(r.method);
          return jsonResponse(
            treeJson(people: [personJson(id: 11)], edges: []),
          );
        }),
      );
      final graph = GraphController(
        api,
        MemoryStorage(),
        7,
        initialSession: AccessSession.fromJson(
          accessJson(permission: 'EDIT')['session'],
        ),
      );
      addTearDown(api.close);
      addTearDown(graph.dispose);
      await graph.load();
      graph.editing = true;
      await t.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: FamilyTreeView(
              api: api,
              storage: MemoryStorage(),
              familyId: 7,
              sharedGraph: graph,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('+ Thêm quan hệ'), findsNothing);
      for (final side in ['parents', 'left', 'right', 'child']) {
        expect(find.byKey(ValueKey('add-$side-11')), findsOneWidget);
      }
      await t.tap(find.byKey(const ValueKey('add-child-11')));
      await t.pumpAndSettle();
      expect(find.text('Thêm con'), findsOneWidget);
      expect(find.text('Quan hệ muốn thêm'), findsNothing);
      expect(find.text('Nhánh con'), findsWidgets);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      for (final side in ['right', 'left']) {
        await t.tap(find.byKey(ValueKey('add-$side-11')));
        await t.pumpAndSettle();
        expect(find.text('Thêm vợ/chồng'), findsOneWidget);
        expect(find.text('Quan hệ muốn thêm'), findsNothing);
        await t.tap(find.text('Xem trước quan hệ'));
        await t.pumpAndSettle();
        await t.tap(find.text('Thêm vào bản nháp'));
        await t.pumpAndSettle();
        final target = graph.draft!.temporary.keys.last;
        final x = graph.layout!.nodes[11]!.center.dx;
        final sx = graph.layout!.nodes[target]!.center.dx;
        expect(side == 'left' ? sx < x : sx > x, isTrue);
        expect(find.byKey(ValueKey('add-$side-11')), findsNothing);
      }
      expect(calls, ['GET']);
      final payload = graph.draft!.payload('preview-only');
      expect(payload.toString(), isNot(contains('LEFT')));
      expect(payload.toString(), isNot(contains('RIGHT')));
      expect(find.byKey(const ValueKey('add-child-11')), findsOneWidget);
      t.view.physicalSize = const Size(320, 420);
      t.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byTooltip('Lưu sơ đồ'), findsOneWidget);
      await t.tap(find.byTooltip('Bản nháp (2)'));
      await t.pumpAndSettle();
      expect(find.text('Các thao tác chưa lưu'), findsOneWidget);
      expect(find.text('Lưu / Bỏ / Hủy'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'EDIT add parents stays local across tabs, API05 requires resolving draft, commit once',
    (tester) async {
      tester.view.physicalSize = const Size(650, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var posts = 0;
      var committed = false;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/graph/commit')) {
            posts++;
            final j = jsonDecode(r.body);
            expect(j['baseVersion'], 4);
            expect(j['relationCommands'].single['type'], 'ADD_PARENTS');
            expect(j['newPersons'].length, 2);
            committed = true;
            return jsonResponse({
              'familyId': 7,
              'requestId': j['requestId'],
              'version': 5,
              'personIdMap': {'tmp-1': 22, 'tmp-2': 23},
            });
          }
          if (r.url.path.endsWith('/tree')) {
            return jsonResponse(
              treeJson(
                version: committed ? 5 : 4,
                people: [
                  personJson(id: 11),
                  if (committed) ...[
                    personJson(id: 22, name: null),
                    personJson(id: 23, name: null),
                  ],
                ],
                edges: committed
                    ? [
                        edgeJson(1, 22, 11),
                        edgeJson(2, 23, 11, role: 'MOTHER', kind: 'STEP'),
                      ]
                    : [],
              ),
            );
          }
          if (r.url.path.endsWith('/people')) return jsonResponse(peopleJson());
          return jsonResponse({...familyJson(), 'version': committed ? 5 : 4});
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: FamilyInfoScreen(
            api: api,
            storage: MemoryStorage(),
            familyId: 7,
            initialSession: AccessSession.fromJson(
              accessJson(permission: 'EDIT')['session'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sơ đồ'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      await tester.tap(find.byTooltip('Chỉnh sửa sơ đồ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-parents-11')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bố mẹ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ruột').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kế').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem trước quan hệ'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      await tester.tap(find.text('Thêm vào bản nháp'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonNode), findsNWidgets(3));
      expect(posts, 0);
      await tester.tap(find.text('Thành viên'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ Thêm'));
      await tester.pumpAndSettle();
      expect(find.text('Bản nháp sơ đồ chưa lưu'), findsOneWidget);
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      await tester.tap(find.text('Sơ đồ'));
      await tester.pumpAndSettle();
      expect(find.byType(PersonNode), findsNWidgets(3));
      await tester.tap(find.byTooltip('Lưu sơ đồ'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.byKey(const ValueKey('add-parents-11')), findsNothing);
      expect(find.byKey(const ValueKey('add-child-11')), findsOneWidget);
      expect(find.byTooltip('Bản nháp (0)'), findsOneWidget);
      expect(find.byType(PersonNode), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'delete saved person resolves graph first then reconfirms with committed version',
    (tester) async {
      tester.view.physicalSize = const Size(500, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var version = 4, commits = 0, deletes = 0;
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/graph/commit')) {
            commits++;
            final body = jsonDecode(r.body);
            version = 5;
            return jsonResponse({
              'familyId': 7,
              'requestId': body['requestId'],
              'version': version,
              'personIdMap': {'tmp-1': 22},
            });
          }
          if (r.method == 'DELETE') {
            deletes++;
            expect(r.url.queryParameters['baseVersion'], '5');
            return jsonResponse({
              'familyId': 7,
              'deletedPersonId': 11,
              'version': 6,
            });
          }
          if (r.url.path.endsWith('/tree')) {
            return jsonResponse(
              treeJson(
                version: version,
                people: [
                  personJson(id: 11),
                  if (version == 5) personJson(id: 22, name: null),
                ],
                edges: version == 5 ? [edgeJson(1, 11, 22)] : [],
              ),
            );
          }
          return jsonResponse({
            ...personJson(id: 11),
            'familyVersion': version,
          });
        }),
      );
      addTearDown(api.close);
      final storage = MemoryStorage(),
          session = AccessSession.fromJson(
            accessJson(permission: 'EDIT')['session'],
          );
      final graph = GraphController(api, storage, 7, initialSession: session);
      addTearDown(graph.dispose);
      await graph.load();
      final n = graph.draft!.newPerson();
      graph.draft!.add({
        'type': 'ADD_PARENT',
        'parent': graph.draft!.ref(11),
        'child': graph.draft!.ref(n),
        'role': 'FATHER',
        'kind': 'BIOLOGICAL',
      });
      graph.changed();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: PersonDetailScreen(
            api: api,
            storage: storage,
            familyId: 7,
            personId: 11,
            initialSession: session,
            graph: graph,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xóa hồ sơ'));
      await tester.pumpAndSettle();
      expect(find.text('Bản nháp sơ đồ chưa lưu'), findsOneWidget);
      expect(deletes, 0);
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(commits, 1);
      expect(deletes, 0);
      expect(find.text('Xác nhận xóa hồ sơ'), findsOneWidget);
      await tester.tap(find.text('Xóa hồ sơ'));
      await tester.pumpAndSettle();
      expect(deletes, 1);
      expect(graph.dirty, false);
      expect(tester.takeException(), isNull);
    },
  );
}

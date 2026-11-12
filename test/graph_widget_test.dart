import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gia_pha_app/app.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/services/api_service.dart';
import 'package:gia_pha_app/views/family_info_screen.dart';
import 'package:gia_pha_app/widgets/person_node.dart';

import 'fixtures.dart';

import 'package:gia_pha_app/controllers/graph_controller.dart';
import 'package:gia_pha_app/views/family_tree_view.dart';
import 'package:gia_pha_app/views/add_relationship_screen.dart';

import 'graph_fixtures.dart';

void main() {
  testWidgets(
    'tree tab loads lazily, zoom/pan persist across tabs and detail; refresh errors clear data',
    (t) async {
      t.view.physicalSize = const Size(430, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var treeCalls = 0, status = 200;
      final paths = <String>[];
      final api = ApiService(
        baseUrl: 'http://test.invalid',
        client: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path.endsWith('/tree')) {
            treeCalls++;
            return jsonResponse(treeJson(), status);
          }
          if (r.url.path.endsWith('/people/11')) {
            return jsonResponse(personJson());
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
      expect(treeCalls, 0);
      await t.tap(find.text('Sơ đồ'));
      await t.pumpAndSettle();
      expect(treeCalls, 1);
      expect(find.byType(PersonNode), findsNWidgets(6));
      final canvas = find.byKey(const ValueKey('tree-canvas'));
      final camera = t
          .widget<InteractiveViewer>(canvas)
          .transformationController!;
      final fit = camera.value.clone();
      expect(find.byTooltip('Phóng to'), findsNothing);
      expect(find.byTooltip('Thu nhỏ'), findsNothing);
      await t.sendEventToBinding(
        PointerScrollEvent(
          position: t.getCenter(canvas),
          scrollDelta: const Offset(0, -80),
        ),
      );
      await t.pumpAndSettle();
      expect(
        camera.value.getMaxScaleOnAxis(),
        greaterThan(fit.getMaxScaleOnAxis()),
      );
      await t.drag(canvas, const Offset(-20, 10));
      await t.pumpAndSettle();
      final moved = camera.value.clone();
      await t.tap(find.text('Thông tin'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sơ đồ'));
      await t.pumpAndSettle();
      expect(camera.value, moved);
      expect(treeCalls, 1);
      await t.tap(find.byTooltip('Vừa màn hình'));
      await t.pumpAndSettle();
      expect(camera.value, fit);
      await t.tap(find.text('Nguyễn Văn Bình'));
      await t.pumpAndSettle();
      expect(find.text('Chi tiết hồ sơ'), findsOneWidget);
      expect(paths.last, '/families/7/people/11');
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(camera.value, fit);
      expect(treeCalls, 1);
      final node = find.byKey(const ValueKey('person-node-11'));
      await t.tap(find.descendant(of: node, matching: find.text('Quan hệ')));
      await t.pumpAndSettle();
      expect(find.textContaining('Cha ruột → con'), findsOneWidget);
      Navigator.of(t.element(find.textContaining('Cha ruột → con'))).pop();
      await t.pumpAndSettle();
      status = 401;
      await t.tap(find.byTooltip('Làm mới sơ đồ'));
      await t.pumpAndSettle();
      expect(find.byType(PersonNode), findsNothing);
      expect(find.text('Nhập lại mã gia phả'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('empty tree and narrow view with enlarged text', (t) async {
    t.view.physicalSize = const Size(320, 740);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    var empty = false;
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient(
        (r) async => jsonResponse(
          r.url.path.endsWith('/tree')
              ? (empty ? treeJson(people: [], edges: []) : treeJson())
              : familyJson(),
        ),
      ),
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
    await t.tap(find.text('Sơ đồ'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    empty = true;
    await t.tap(find.byTooltip('Làm mới sơ đồ'));
    await t.pumpAndSettle();
    expect(find.text('Gia phả chưa có thành viên.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('render tree fixture for visual review', (t) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final fontPath = Platform.environment['PREVIEW_FONT_PATH'];
    if (fontPath != null) {
      final bytes = await t.runAsync(() => File(fontPath).readAsBytes());
      await (FontLoader(
        'Preview',
      )..addFont(Future.value(ByteData.sublistView(bytes!)))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    t.view.physicalSize = const Size(430, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient(
        (r) async => jsonResponse(
          r.url.path.endsWith('/tree') ? treeJson() : familyJson(),
        ),
      ),
    );
    addTearDown(api.close);
    final key = GlobalKey();
    await t.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(fontFamily: 'Preview'),
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: FamilyInfoScreen(
            api: api,
            storage: MemoryStorage(),
            familyId: 7,
            initialSession: AccessSession.fromJson(accessJson()['session']),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Sơ đồ'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('test-artifacts/06-tree.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    debugDisableShadows = true;
  }, skip: Platform.environment['GENERATE_PREVIEWS'] != 'true');
  testWidgets('render edit draft and relationship picker', (t) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final fontPath = Platform.environment['PREVIEW_FONT_PATH'];
    if (fontPath != null) {
      final bytes = await t.runAsync(() => File(fontPath).readAsBytes());
      await (FontLoader(
        'Preview',
      )..addFont(Future.value(ByteData.sublistView(bytes!)))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    t.view.physicalSize = const Size(500, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient((r) async => jsonResponse(treeJson())),
    );
    addTearDown(api.close);
    final storage = MemoryStorage(),
        graph = GraphController(
          api,
          MemoryStorage(),
          7,
          initialSession: AccessSession.fromJson(
            accessJson(permission: 'EDIT')['session'],
          ),
        );
    addTearDown(graph.dispose);
    await graph.load();
    graph.editing = true;
    final n = graph.draft!.newPerson();
    graph.draft!.add({
      'type': 'ADD_CHILD',
      'child': graph.draft!.ref(n),
      'parents': [
        {'person': graph.draft!.ref(13), 'role': 'FATHER', 'kind': 'ADOPTIVE'},
      ],
    });
    graph.changed();
    final screens = <String, Widget>{
      '08-tree-draft': Scaffold(
        bottomNavigationBar: NavigationBar(
          selectedIndex: 1,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: 'Thông tin',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_tree_outlined),
              label: 'Sơ đồ',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              label: 'Thành viên',
            ),
          ],
        ),
        body: FamilyTreeView(
          api: api,
          storage: storage,
          familyId: 7,
          sharedGraph: graph,
        ),
      ),
      '11-add-relationship': AddRelationshipScreen(
        graph: graph,
        anchor: graph.snapshot!.persons.first,
        entry: RelationshipEntry.child,
      ),
    };
    for (final entry in screens.entries) {
      final key = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(fontFamily: 'Preview'),
            home: entry.value,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('test-artifacts/${entry.key}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    debugDisableShadows = true;
  }, skip: Platform.environment['GENERATE_PREVIEWS'] != 'true');
}

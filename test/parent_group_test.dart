import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gia_pha_app/app.dart';
import 'package:gia_pha_app/models/tree_snapshot.dart';
import 'package:gia_pha_app/services/graph_layout_service.dart';
import 'package:gia_pha_app/services/parent_group_builder.dart';
import 'package:gia_pha_app/widgets/person_node.dart';
import 'package:gia_pha_app/widgets/relationship_painter.dart';

import 'fixtures.dart';
import 'graph_fixtures.dart';

void main() {
  final tree = TreeSnapshot.fromJson(complexTreeJson());
  test('approved 13-person fixture produces five exact parent sets, retains all 18 edges', () {
    final layout = GraphLayoutService().arrange(tree);
    expect(layout.groups.map((g) => g.key).toSet(), {
      '1:2',
      '3:4',
      '4',
      '4:5',
      '6:7',
    });
    expect(layout.nodes.length, 13);
    expect(
      layout.strokes.expand((s) => s.relationships).map((r) => r.id).toSet(),
      tree.relationships.map((r) => r.id).toSet(),
    );
    expect(layout.strokes.where((s) => s.kind == StrokeKind.child).length, 8);
    expect(layout.hasFallbackRoutes, isFalse);
    for (final r in tree.relationships.where((r) => !r.isSpouse)) {
      expect(
        layout.nodes[r.sourcePersonId]!.bottom,
        lessThan(layout.nodes[r.targetPersonId]!.top),
      );
    }
  });
  test('spouse common children share midpoint trunk and have separate terminal legs', () {
    final l = GraphLayoutService().arrange(tree);
    final spouse = l.strokes.singleWhere((s) => s.key == 'spouse:2');
    final trunk = l.strokes.singleWhere((s) => s.key == 'trunk:3:4');
    expect(trunk.points.first, (spouse.points.first + spouse.points.last) / 2);
    expect(
      l.strokes
          .where((s) => s.groupKey == '3:4' && s.kind == StrokeKind.trunk)
          .length,
      1,
    );
    expect(
      l.strokes
          .where((s) => s.groupKey == '3:4' && s.kind == StrokeKind.child)
          .map(
            (s) => s.relationships.map((r) => r.targetPersonId).toSet().single,
          )
          .toSet(),
      {8, 9},
    );
  });
  test('one known parent starts from its card, never its spouse junction', () {
    final l = GraphLayoutService().arrange(tree);
    final trunk = l.strokes.singleWhere((s) => s.key == 'trunk:4');
    expect(trunk.points.first, l.nodes[4]!.bottomCenter);
    expect(trunk.relationships.map((r) => r.id).toList(), [12]);
    expect(l.groups.singleWhere((g) => g.key == '4').children.keys.toList(), [
      10,
    ]);
  });
  test(
    'co-parents without spouse feed from both bottoms and create no marriage',
    () {
      final l = GraphLayoutService().arrange(tree);
      final feeders = l.strokes
          .where((s) => s.groupKey == '6:7' && s.kind == StrokeKind.feeder)
          .toList();
      expect(feeders.length, 2);
      expect(feeders.map((s) => s.points.first).toSet(), {
        l.nodes[6]!.bottomCenter,
        l.nodes[7]!.bottomCenter,
      });
      expect(feeders.first.points.last, feeders.last.points.last);
      expect(l.strokes.where((s) => s.kind == StrokeKind.spouse).length, 3);
      expect(
        l.strokes.singleWhere((s) => s.key == 'child:13').relationships.length,
        2,
      );
    },
  );
  test(
    'mixed parent kinds are retained; selecting Vy excludes Linh terminal leg',
    () {
      final l = GraphLayoutService().arrange(tree);
      final vy = l.strokes.singleWhere((s) => s.key == 'child:12');
      expect(vy.relationships.map((r) => r.parentKind).toSet(), {
        'BIOLOGICAL',
        'ADOPTIVE',
      });
      expect(vy.touches(12), isTrue);
      expect(
        l.strokes.singleWhere((s) => s.key == 'child:11').touches(12),
        isFalse,
      );
      expect(
        l.strokes.singleWhere((s) => s.key == 'trunk:4:5').touches(12),
        isTrue,
      );
      for (final s in l.strokes.where(
        (s) => s.groupKey == '4:5' && s.kind == StrokeKind.bus,
      )) {
        final otherOnly = s.relationships.every((r) => r.targetPersonId == 11);
        if (otherOnly) expect(s.touches(12), isFalse);
      }
    },
  );
  test(
    'removing one parent in next snapshot regroups child without new edges',
    () {
      final j = complexTreeJson();
      j['persons'] = (j['persons'] as List).where((p) => p['id'] != 5).toList();
      j['relationships'] = (j['relationships'] as List)
          .where((r) => r['sourcePersonId'] != 5 && r['targetPersonId'] != 5)
          .toList();
      final next = TreeSnapshot.fromJson(j);
      final groups = ParentGroupBuilder().build(next);
      expect(groups.singleWhere((g) => g.key == '4').children.keys.toSet(), {
        10,
        11,
        12,
      });
      expect(groups.any((g) => g.key == '4:5'), isFalse);
    },
  );
  test('marriage alone creates no parent group or child trunk', () {
    final t = TreeSnapshot.fromJson(
      treeJson(
        people: [personJson(id: 1), personJson(id: 2)],
        edges: [edgeJson(1, 1, 2, spouse: true)],
      ),
    );
    final l = GraphLayoutService().arrange(t);
    expect(l.groups, isEmpty);
    expect(l.junctions, isEmpty);
    expect(l.strokes.length, 1);
    expect(l.strokes.single.kind, StrokeKind.spouse);
  });
  test(
    'geometry remains finite in bounds for many partners and cyclic parents',
    () {
      for (final cycle in [false, true]) {
        final t = TreeSnapshot.fromJson(
          treeJson(
            people: [for (var i = 1; i <= 12; i++) personJson(id: i)],
            edges: [
              for (var i = 2; i <= 8; i++) edgeJson(i, 1, i, spouse: true),
              edgeJson(20, 1, 9),
              edgeJson(21, 2, 9, role: 'MOTHER'),
              if (cycle) edgeJson(22, 9, 1),
            ],
          ),
        );
        final l = GraphLayoutService().arrange(t);
        final bounds = Offset.zero & l.size;
        expect(l.nodes.length, 12);
        for (final s in l.strokes) {
          for (final p in s.points) {
            expect(bounds.contains(p), isTrue);
          }
        }
        expect(
          l.strokes.expand((s) => s.relationships).map((r) => r.id).toSet(),
          t.relationships.map((r) => r.id).toSet(),
        );
      }
    },
  );
  test(
    'approved fixture has no collinear overlap between different parent groups',
    () {
      final l = GraphLayoutService().arrange(tree);
      final lines = l.strokes.where((s) => s.groupKey != null).toList();
      for (var i = 0; i < lines.length; i++) {
        for (var j = i + 1; j < lines.length; j++) {
          final a = lines[i], b = lines[j];
          if (a.groupKey == b.groupKey) continue;
          for (var ai = 1; ai < a.points.length; ai++) {
            for (var bi = 1; bi < b.points.length; bi++) {
              final a1 = a.points[ai - 1],
                  a2 = a.points[ai],
                  b1 = b.points[bi - 1],
                  b2 = b.points[bi];
              if (a1.dx == a2.dx && b1.dx == b2.dx && a1.dx == b1.dx) {
                final overlap =
                    math.min(math.max(a1.dy, a2.dy), math.max(b1.dy, b2.dy)) -
                    math.max(math.min(a1.dy, a2.dy), math.min(b1.dy, b2.dy));
                expect(
                  overlap,
                  lessThanOrEqualTo(0),
                  reason: '${a.key} / ${b.key}',
                );
              }
              if (a1.dy == a2.dy && b1.dy == b2.dy && a1.dy == b1.dy) {
                final overlap =
                    math.min(math.max(a1.dx, a2.dx), math.max(b1.dx, b2.dx)) -
                    math.max(math.min(a1.dx, a2.dx), math.min(b1.dx, b2.dx));
                expect(
                  overlap,
                  lessThanOrEqualTo(0),
                  reason: '${a.key} / ${b.key}',
                );
              }
            }
          }
        }
      }
    },
  );
  test('approved fixture layout is stable when response order and spouse direction change', () {
    final json = complexTreeJson();
    json['persons'] = (json['persons'] as List).reversed.toList();
    json['relationships'] = (json['relationships'] as List).reversed.map((e) {
      final r = Map<String, dynamic>.from(e);
      if (r['relationshipType'] == 'SPOUSE') {
        final source = r['sourcePersonId'];
        r['sourcePersonId'] = r['targetPersonId'];
        r['targetPersonId'] = source;
      }
      return r;
    }).toList();
    final a = GraphLayoutService().arrange(tree);
    final b = GraphLayoutService().arrange(TreeSnapshot.fromJson(json));
    expect(b.nodes, a.nodes);
    expect(b.groups.map((g) => g.key), a.groups.map((g) => g.key));
    expect(
      b.strokes.map((s) => s.points).toList(),
      a.strokes.map((s) => s.points).toList(),
    );
  });
  testWidgets(
    'render approved complex fixture using production layout and painter',
    (t) async {
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
      final l = GraphLayoutService().arrange(tree);
      t.view.physicalSize = Size(l.size.width, l.size.height);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(fontFamily: 'Preview'),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: RelationshipPainter(l, null)),
                  ),
                  for (final p in tree.persons)
                    Positioned.fromRect(
                      rect: l.nodes[p.id]!,
                      child: PersonNode(
                        person: p,
                        selected: false,
                        onOpen: () {},
                        onRelationships: () {},
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('test-artifacts/06-tree-grouped-complex.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    },
    skip: Platform.environment['GENERATE_PREVIEWS'] != 'true',
  );
}

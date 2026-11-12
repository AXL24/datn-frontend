import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../models/tree_snapshot.dart';
import 'parent_group_builder.dart';

enum StrokeKind { spouse, feeder, trunk, bus, child, fallback }

/// One visible stroke can represent several real relationships.
class GraphStroke {
  final String key;
  final String? groupKey;
  final StrokeKind kind;
  final List<Relationship> relationships;
  final List<Offset> points;
  GraphStroke(
    this.key,
    this.groupKey,
    this.kind,
    Iterable<Relationship> relationships,
    Iterable<Offset> points,
  ) : relationships = List.unmodifiable(relationships),
      points = List.unmodifiable(points);
  bool touches(int id) => relationships.any(
    (r) => r.sourcePersonId == id || r.targetPersonId == id,
  );
}

class GraphJunction {
  final Offset position;
  final List<Relationship> relationships;
  GraphJunction(this.position, Iterable<Relationship> relationships)
    : relationships = List.unmodifiable(relationships);
}

class GraphLayout {
  static const cardSize = Size(160, 148);
  final Map<int, Rect> nodes;
  final List<GraphStroke> strokes;
  final List<GraphJunction> junctions;
  final List<ParentGroup> groups;
  final Size size;
  final bool hasParentCycle, hasFallbackRoutes;
  GraphLayout(
    this.nodes,
    this.strokes,
    this.junctions,
    this.groups,
    this.size,
    this.hasParentCycle,
    this.hasFallbackRoutes,
  );
}

/// Deterministic geometry from one immutable snapshot. No HTTP or persistence.
class GraphLayoutService {
  GraphLayout arrange(
    TreeSnapshot tree, {
    List<int> preferredOrder = const [],
  }) {
    final preferredIndices = {
      for (var i = 0; i < preferredOrder.length; i++) preferredOrder[i]: i,
    };
    int compareDisplay(int a, int b) {
      final oa = preferredIndices[a], ob = preferredIndices[b];
      if (oa != null || ob != null) {
        return (oa ?? preferredIndices.length).compareTo(
          ob ?? preferredIndices.length,
        );
      }
      return a.compareTo(b);
    }

    final groups = ParentGroupBuilder().build(tree);
    final ids = tree.persons.map((p) => p.id).toList()..sort();
    final edges = tree.relationships.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final neighbors = {for (final id in ids) id: <int>{}};
    final parents = {for (final id in ids) id: <int>[]};
    final children = {for (final id in ids) id: <int>[]};
    final partners = {for (final id in ids) id: <int>{}};
    final spouseByPair = <String, Relationship>{};
    String pair(int a, int b) => a < b ? '$a:$b' : '$b:$a';
    for (final r in edges) {
      final a = r.sourcePersonId, b = r.targetPersonId;
      neighbors[a]!.add(b);
      neighbors[b]!.add(a);
      if (r.isSpouse) {
        partners[a]!.add(b);
        partners[b]!.add(a);
        spouseByPair[pair(a, b)] = r;
      } else {
        parents[b]!.add(a);
        children[a]!.add(b);
      }
    }
    // Co-parents may be placed together, but this does NOT create SPOUSE.
    for (final g in groups.where((g) => g.parentIds.length == 2)) {
      final a = g.parentIds[0], b = g.parentIds[1];
      partners[a]!.add(b);
      partners[b]!.add(a);
    }
    final indegree = {for (final id in ids) id: parents[id]!.length};
    final rank = {for (final id in ids) id: 0};
    final queue = Queue<int>.from(ids.where((id) => indegree[id] == 0));
    final order = <int>[];
    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      order.add(id);
      for (final c in children[id]!) {
        rank[c] = math.max(rank[c]!, rank[id]! + 1);
        indegree[c] = indegree[c]! - 1;
        if (indegree[c] == 0) queue.add(c);
      }
    }
    final cycle = order.length != ids.length;
    if (cycle) {
      for (final id in ids) {
        rank[id] = 0;
      }
    } else {
      for (final id in order.reversed) {
        if (partners[id]!.isEmpty) continue;
        final desired = partners[id]!.map((p) => rank[p]!).reduce(math.max);
        final lower = parents[id]!.fold(0, (n, p) => math.max(n, rank[p]! + 1));
        final upper = children[id]!.fold(
          ids.length,
          (n, c) => math.min(n, rank[c]! - 1),
        );
        rank[id] = desired.clamp(lower, upper);
      }
    }
    final groupsPerRank = <int, int>{};
    for (final g in groups) {
      final level = g.parentIds.map((p) => rank[p]!).reduce(math.max);
      groupsPerRank[level] = (groupsPerRank[level] ?? 0) + 1;
    }
    final maxGroups = groupsPerRank.values.fold(0, math.max);
    final extraLanes = math.max(
      0,
      partners.values.fold(0, (n, ps) => math.max(n, ps.length)) - 2,
    );
    final step =
        GraphLayout.cardSize.height + 120 + maxGroups * 24.0 + extraLanes * 10;
    final nodes = <int, Rect>{};
    final strokes = <GraphStroke>[];
    final junctions = <GraphJunction>[];
    final visited = <int>{};
    var left = 60.0, height = 260.0, fallback = cycle;
    for (final root in ids) {
      if (!visited.add(root)) continue;
      final component = <int>[];
      final pending = Queue<int>()..add(root);
      while (pending.isNotEmpty) {
        final id = pending.removeFirst();
        component.add(id);
        final adjacent = neighbors[id]!.toList()..sort();
        for (final n in adjacent) {
          if (visited.add(n)) pending.add(n);
        }
      }
      component.sort();
      final memberIds = component.toSet();
      final componentEdges = edges
          .where((r) => memberIds.contains(r.sourcePersonId))
          .toList();
      final componentGroups = groups
          .where((g) => memberIds.contains(g.parentIds.first))
          .toList();
      final rows = <int, List<int>>{};
      for (final id in component) {
        rows.putIfAbsent(rank[id]!, () => []).add(id);
      }
      final levels = rows.keys.toList()..sort();
      final width = rows.values
          .map((r) => r.length * 216.0 - 56)
          .reduce(math.max);
      for (final level in levels) {
        final row = rows[level]!, remaining = row.toSet(), arranged = <int>[];
        double anchor(int id) {
          final ps = parents[id]!.where(nodes.containsKey).toList();
          return ps.isEmpty
              ? left
              : ps.map((p) => nodes[p]!.center.dx).reduce((a, b) => a + b) /
                    ps.length;
        }

        // Walk chains from their ends: A-B-C keeps B between its two partners.
        while (remaining.isNotEmpty) {
          final candidates = remaining.toList()
            ..sort((a, b) {
              final da = partners[a]!.where(remaining.contains).length;
              final db = partners[b]!.where(remaining.contains).length;
              final endA = da <= 1 ? 0 : 1, endB = db <= 1 ? 0 : 1;
              if (endA != endB) return endA.compareTo(endB);
              if (preferredIndices.containsKey(a) ||
                  preferredIndices.containsKey(b)) {
                return compareDisplay(a, b);
              }
              final c = anchor(a).compareTo(anchor(b));
              return c != 0 ? c : a.compareTo(b);
            });
          var current = candidates.first;
          while (remaining.remove(current)) {
            arranged.add(current);
            final next = partners[current]!.where(remaining.contains).toList()
              ..sort(compareDisplay);
            if (next.isEmpty) break;
            current = next.first;
          }
        }
        for (var i = 0; i < arranged.length; i++) {
          nodes[arranged[i]] = Rect.fromLTWH(
            left + (width - (row.length * 216 - 56)) / 2 + i * 216,
            112 + level * step,
            GraphLayout.cardSize.width,
            GraphLayout.cardSize.height,
          );
        }
      }
      final anchors = <String, Offset>{};
      var lane = 0;
      for (final r in componentEdges.where((r) => r.isSpouse)) {
        final a = nodes[r.sourcePersonId]!, b = nodes[r.targetPersonId]!;
        final first = a.left < b.left ? a : b, last = a.left < b.left ? b : a;
        List<Offset> points;
        Offset? joint;
        if (a.top == b.top && last.left - first.right < 60) {
          points = [first.centerRight, last.centerLeft];
          joint = Offset((first.right + last.left) / 2, first.center.dy);
        } else if (a.top == b.top) {
          fallback = true;
          final y = a.bottom + 18 + (lane++) * 10;
          points = [
            first.bottomCenter,
            Offset(first.center.dx, y),
            Offset(last.center.dx, y),
            last.bottomCenter,
          ];
          joint = Offset((first.center.dx + last.center.dx) / 2, y);
        } else {
          final x = left + width + 28 + (lane++) * 16;
          points = [
            a.centerRight,
            Offset(x, a.center.dy),
            Offset(x, b.center.dy),
            b.centerRight,
          ];
          fallback = true;
        }
        if (joint != null) {
          anchors[pair(r.sourcePersonId, r.targetPersonId)] = joint;
        }
        strokes.add(
          GraphStroke('spouse:${r.id}', null, StrokeKind.spouse, [r], points),
        );
      }
      final groupLanes = <int, int>{};
      final trunkColumns = <int, Set<double>>{};
      for (final g in componentGroups) {
        final level = rank[g.parentIds.first]!;
        final regular =
            !cycle &&
            g.parentIds.length <= 2 &&
            g.parentIds.every((p) => rank[p] == level) &&
            g.children.keys.every((c) => rank[c] == level + 1);
        if (!regular) {
          fallback = true;
          for (final r in g.relationships) {
            final a = nodes[r.sourcePersonId]!, b = nodes[r.targetPersonId]!;
            final x = left + width + 28 + (lane++) * 16;
            final y1 = a.bottom + 14, y2 = b.top - 14;
            strokes.add(
              GraphStroke(
                'fallback:${r.id}',
                g.key,
                StrokeKind.fallback,
                [r],
                [
                  a.bottomCenter,
                  Offset(a.center.dx, y1),
                  Offset(x, y1),
                  Offset(x, y2),
                  Offset(b.center.dx, y2),
                  b.topCenter,
                ],
              ),
            );
          }
          continue;
        }
        final index = groupLanes[level] ?? 0;
        groupLanes[level] = index + 1;
        final bottom = nodes[g.parentIds.first]!.bottom;
        var busY = bottom + 72 + index * 24.0;
        final all = g.relationships;
        Offset source;
        if (g.parentIds.length == 1) {
          source = nodes[g.parentIds.single]!.bottomCenter;
        } else {
          final marriage = spouseByPair[g.key];
          if (marriage != null) {
            source = anchors[g.key]!;
          } else {
            final a = nodes[g.parentIds[0]]!, b = nodes[g.parentIds[1]]!;
            final y = bottom + 24 + index * 10;
            source = Offset((a.center.dx + b.center.dx) / 2, y);
            for (final p in g.parentIds) {
              final start = nodes[p]!.bottomCenter;
              strokes.add(
                GraphStroke(
                  'feeder:${g.key}:$p',
                  g.key,
                  StrokeKind.feeder,
                  all.where((r) => r.sourcePersonId == p),
                  [start, Offset(start.dx, y), source],
                ),
              );
            }
          }
          junctions.add(GraphJunction(source, all));
        }
        // A trunk must not overlap another group's terminal child column.
        // Keep the real pair junction, then dogleg below the cards if needed.
        final otherChildColumns = componentGroups
            .where(
              (other) =>
                  other.key != g.key &&
                  other.parentIds.every((p) => rank[p] == level),
            )
            .expand((other) => other.children.keys)
            .map((c) => nodes[c]!.center.dx)
            .toSet();
        final used = trunkColumns.putIfAbsent(level, () => <double>{});
        final childMean =
            g.children.keys
                .map((c) => nodes[c]!.center.dx)
                .reduce((a, b) => a + b) /
            g.children.length;
        var direction = childMean >= source.dx ? 1.0 : -1.0;
        var trunkX = source.dx;
        while (otherChildColumns.contains(trunkX) || used.contains(trunkX)) {
          if (trunkX + 28 * direction < left + 12) direction = 1;
          trunkX += 28 * direction;
        }
        used.add(trunkX);
        final bendY = math.max(source.dy + 12, bottom + 12);
        busY = math.max(busY, bendY + 24);
        final trunkPoints = trunkX == source.dx
            ? [source, Offset(trunkX, busY)]
            : [
                source,
                Offset(source.dx, bendY),
                Offset(trunkX, bendY),
                Offset(trunkX, busY),
              ];
        strokes.add(
          GraphStroke(
            'trunk:${g.key}',
            g.key,
            StrokeKind.trunk,
            all,
            trunkPoints,
          ),
        );
        final xs = {
          trunkX,
          ...g.children.keys.map((c) => nodes[c]!.center.dx),
        }.toList()..sort();
        for (var i = 0; i + 1 < xs.length; i++) {
          final x1 = xs[i], x2 = xs[i + 1];
          final represented = <Relationship>[];
          for (final entry in g.children.entries) {
            final x = nodes[entry.key]!.center.dx;
            if (math.min(x, trunkX) <= x1 && math.max(x, trunkX) >= x2) {
              represented.addAll(entry.value);
            }
          }
          if (represented.isNotEmpty) {
            strokes.add(
              GraphStroke(
                'bus:${g.key}:$i',
                g.key,
                StrokeKind.bus,
                represented,
                [Offset(x1, busY), Offset(x2, busY)],
              ),
            );
          }
        }
        for (final entry in g.children.entries) {
          final end = nodes[entry.key]!.topCenter;
          strokes.add(
            GraphStroke(
              'child:${entry.key}',
              g.key,
              StrokeKind.child,
              entry.value,
              [Offset(end.dx, busY), end],
            ),
          );
        }
      }
      for (final id in component) {
        height = math.max(height, nodes[id]!.bottom + 120);
      }
      left += width + 120 + lane * 16;
    }
    for (final stroke in strokes) {
      for (final point in stroke.points) {
        height = math.max(height, point.dy + 60);
        left = math.max(left, point.dx + 60);
      }
    }
    return GraphLayout(
      Map.unmodifiable(nodes),
      List.unmodifiable(strokes),
      List.unmodifiable(junctions),
      groups,
      Size(math.max(left, 280), height),
      cycle,
      fallback,
    );
  }
}

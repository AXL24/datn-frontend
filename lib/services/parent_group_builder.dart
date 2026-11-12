import '../models/tree_snapshot.dart';

/// Presentation-only group: the exact set of known parents, never a marriage.
class ParentGroup {
  final String key;
  final List<int> parentIds;
  final Map<int, List<Relationship>> children;
  ParentGroup(this.key, this.parentIds, this.children);
  List<Relationship> get relationships =>
      children.values.expand((edges) => edges).toList(growable: false);
}

class ParentGroupBuilder {
  List<ParentGroup> build(TreeSnapshot tree) {
    final incoming = <int, List<Relationship>>{};
    final edges = tree.relationships.where((r) => !r.isSpouse).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final edge in edges) {
      incoming.putIfAbsent(edge.targetPersonId, () => []).add(edge);
    }
    final grouped = <String, Map<int, List<Relationship>>>{};
    final parents = <String, List<int>>{};
    final childIds = incoming.keys.toList()..sort();
    for (final child in childIds) {
      final ids = incoming[child]!.map((r) => r.sourcePersonId).toSet().toList()
        ..sort();
      final key = ids.join(':');
      parents[key] = ids;
      grouped.putIfAbsent(key, () => {})[child] = List.unmodifiable(
        incoming[child]!,
      );
    }
    final keys = grouped.keys.toList()..sort();
    return List.unmodifiable([
      for (final key in keys)
        ParentGroup(
          key,
          List.unmodifiable(parents[key]!),
          Map.unmodifiable(grouped[key]!),
        ),
    ]);
  }
}

import 'dart:math';

import 'person.dart';
import 'tree_snapshot.dart';

String draftUuid() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Negative IDs are rendering-only. HTTP receives tempId strings, never these IDs.
class GraphDraft {
  TreeSnapshot baseline;
  final Map<int, Person> temporary = {};
  final List<Map<String, dynamic>> commands = [];
  int _next = -1, _command = 0;
  GraphDraft(this.baseline);
  bool get dirty => commands.isNotEmpty;
  Map<String, dynamic> ref(int id) =>
      id > 0 ? {'personId': id} : {'tempId': 'tmp-${-id}'};
  int id(Map<String, dynamic> r) =>
      r['personId'] as int? ?? -int.parse((r['tempId'] as String).substring(4));
  int newPerson() {
    final value = _next--;
    temporary[value] = Person.temporary(value, baseline.familyId);
    return value;
  }

  List<int> spouses(int person) => snapshot.relationships
      .where(
        (e) =>
            e.isSpouse &&
            (e.sourcePersonId == person || e.targetPersonId == person),
      )
      .map(
        (e) => e.sourcePersonId == person ? e.targetPersonId : e.sourcePersonId,
      )
      .toList();
  bool hasRole(int child, String role) => snapshot.relationships.any(
    (e) => !e.isSpouse && e.targetPersonId == child && e.parentRole == role,
  );
  Set<int> references(Map<String, dynamic> command) {
    final result = <int>{};
    void visit(dynamic value) {
      if (value is Map<String, dynamic>) {
        if (value.containsKey('personId') || value.containsKey('tempId')) {
          result.add(id(value));
        } else {
          for (final v in value.values) {
            visit(v);
          }
        }
      } else if (value is List) {
        for (final v in value) {
          visit(v);
        }
      }
    }

    visit(command);
    return result;
  }

  List<Relationship> edges(Map<String, dynamic> c, int start) {
    var edgeId = start;
    Relationship edge(int a, int b, {String? role, String? kind}) =>
        Relationship.fromJson({
          'id': edgeId--,
          'familyId': baseline.familyId,
          'sourcePersonId': a,
          'targetPersonId': b,
          'relationshipType': role == null ? 'SPOUSE' : 'PARENT_CHILD',
          'parentRole': role,
          'parentKind': kind,
        });
    int endpoint(String name) => id(c[name] as Map<String, dynamic>);
    return switch (c['type']) {
      'ADD_SPOUSE' => [edge(endpoint('person'), endpoint('spouse'))],
      'ADD_PARENT' => [
        edge(
          endpoint('parent'),
          endpoint('child'),
          role: c['role'],
          kind: c['kind'],
        ),
      ],
      'ADD_PARENTS' => [
        edge(
          endpoint('father'),
          endpoint('child'),
          role: 'FATHER',
          kind: c['fatherKind'],
        ),
        edge(
          endpoint('mother'),
          endpoint('child'),
          role: 'MOTHER',
          kind: c['motherKind'],
        ),
      ],
      'ADD_CHILD' => [
        for (final p in c['parents'] as List)
          edge(
            id(p['person']),
            endpoint('child'),
            role: p['role'],
            kind: p['kind'],
          ),
      ],
      _ => throw StateError('Unknown command'),
    };
  }

  TreeSnapshot get snapshot => TreeSnapshot.local(
    familyId: baseline.familyId,
    version: baseline.version,
    persons: [...baseline.persons, ...temporary.values],
    relationships: [
      ...baseline.relationships,
      for (var i = 0; i < commands.length; i++)
        ...edges(commands[i], -1 - i * 2),
    ],
  );
  String? validate() {
    if (commands.length > 500 || temporary.length > 500) {
      return 'Mỗi lần lưu tối đa 500 lệnh và 500 người mới.';
    }
    final tree = snapshot, slots = <String>{}, pairs = <String, String>{};
    final ids = tree.persons.map((p) => p.id).toSet();
    final next = <int, List<int>>{};
    for (final e in tree.relationships) {
      final a = e.sourcePersonId, b = e.targetPersonId;
      if (a == b) return 'Không thể nối một hồ sơ với chính nó.';
      if (!ids.contains(a) || !ids.contains(b)) {
        return 'Hồ sơ tham chiếu không còn trong bản nháp.';
      }
      final key = a < b ? '$a:$b' : '$b:$a';
      if (pairs.containsKey(key)) {
        return 'Hai hồ sơ đã có quan hệ trực tiếp hoặc bị nối trùng.';
      }
      pairs[key] = e.relationshipType;
      if (!e.isSpouse) {
        if (!slots.add('$b:${e.parentRole}')) {
          return 'Hồ sơ đã có vai trò cha/mẹ được chọn.';
        }
        (next[a] ??= []).add(b);
      }
    }
    final done = <int>{}, active = <int>{};
    bool cycle(int n) {
      if (active.contains(n)) return true;
      if (done.contains(n)) return false;
      active.add(n);
      for (final m in next[n] ?? <int>[]) {
        if (cycle(m)) return true;
      }
      active.remove(n);
      done.add(n);
      return false;
    }

    if (ids.any(cycle)) return 'Quan hệ này tạo chu trình tổ tiên.';
    for (final c in commands.where((c) => c['type'] == 'ADD_CHILD')) {
      final parents = c['parents'] as List;
      if (parents.length == 2) {
        final a = id(parents[0]['person']), b = id(parents[1]['person']);
        if (!spouses(a).contains(b)) {
          return 'Con chung yêu cầu cặp vợ/chồng trong dữ liệu hoặc bản nháp.';
        }
      }
    }
    return null;
  }

  void add(Map<String, dynamic> fields) {
    final c = <String, dynamic>{'commandId': 'cmd-${++_command}', ...fields};
    commands.add(c);
    final problem = validate();
    if (problem != null) {
      commands.removeLast();
      prune();
      throw FormatException(problem);
    }
  }

  void prune() {
    final used = commands.expand(references).toSet();
    temporary.removeWhere((id, _) => !used.contains(id));
  }

  // Refuse removal if it invalidates another command. Never silently cascade commands.
  String? removeCommand(String commandId) {
    final index = commands.indexWhere((c) => c['commandId'] == commandId);
    if (index < 0) return null;
    final old = commands.removeAt(index);
    final problem = validate();
    if (problem != null) {
      commands.insert(index, old);
      return 'Lệnh khác phụ thuộc quan hệ này. Hãy hủy lệnh phụ thuộc trước. $problem';
    }
    prune();
    return null;
  }

  List<String> commandsFor(int tempId) => commands
      .where((c) => references(c).contains(tempId))
      .map((c) => c['commandId'] as String)
      .toList();
  String? removeTemporary(int tempId) {
    final affected = commands
        .where((c) => references(c).contains(tempId))
        .toList();
    final old = List<Map<String, dynamic>>.of(commands);
    commands.removeWhere(affected.contains);
    final problem = validate();
    if (problem != null) {
      commands
        ..clear()
        ..addAll(old);
      return 'Có lệnh phụ thuộc; hãy hủy lệnh đó trước. $problem';
    }
    prune();
    return null;
  }

  Map<String, dynamic> payload(String requestId) {
    prune();
    return {
      'requestId': requestId,
      'baseVersion': baseline.version,
      'newPersons': [for (final n in temporary.keys) ref(n)],
      'relationCommands': commands,
    };
  }

  Person personWithVersion(int id) => baseline.persons
      .firstWhere((p) => p.id == id)
      .withFamilyVersion(baseline.version);
  void acceptPerson(Person person) {
    baseline = TreeSnapshot.local(
      familyId: baseline.familyId,
      version: person.familyVersion!,
      persons: [
        for (final p in baseline.persons)
          if (p.id == person.id) person else p,
      ],
      relationships: baseline.relationships,
    );
  }
}

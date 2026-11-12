import 'person.dart';

class Relationship {
  final int id, familyId, sourcePersonId, targetPersonId;
  final String relationshipType;
  final String? parentRole, parentKind;
  Relationship.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      familyId = j['familyId'] as int,
      sourcePersonId = j['sourcePersonId'] as int,
      targetPersonId = j['targetPersonId'] as int,
      relationshipType = j['relationshipType'] as String,
      parentRole = j['parentRole'] as String?,
      parentKind = j['parentKind'] as String?;
  bool get isSpouse => relationshipType == 'SPOUSE';
  String get label {
    if (isSpouse) return 'Vợ/chồng';
    final role = parentRole == 'FATHER' ? 'Cha' : 'Mẹ';
    final kind = switch (parentKind) {
      'BIOLOGICAL' => 'ruột',
      'ADOPTIVE' => 'nuôi',
      'STEP' => 'kế',
      _ => '',
    };
    return '$role $kind → con';
  }
}

/// A single API16 snapshot; never assembled from paginated reads.
class TreeSnapshot {
  final int familyId, version;
  final List<Person> persons;
  final List<Relationship> relationships;
  TreeSnapshot.local({
    required this.familyId,
    required this.version,
    required List<Person> persons,
    required List<Relationship> relationships,
  }) : persons = List.unmodifiable(persons),
       relationships = List.unmodifiable(relationships);
  TreeSnapshot.fromJson(Map<String, dynamic> j)
    : familyId = j['familyId'] as int,
      version = j['version'] as int,
      persons = List.unmodifiable(
        (j['persons'] as List).map(
          (p) => Person.fromJson(p as Map<String, dynamic>),
        ),
      ),
      relationships = List.unmodifiable(
        (j['relationships'] as List).map(
          (r) => Relationship.fromJson(r as Map<String, dynamic>),
        ),
      ) {
    final ids = persons.map((p) => p.id).toSet();
    if (familyId <= 0 ||
        version < 0 ||
        ids.length != persons.length ||
        relationships.map((r) => r.id).toSet().length != relationships.length ||
        persons.any((p) => p.id <= 0 || p.familyId != familyId) ||
        relationships.any(
          (r) =>
              r.id <= 0 ||
              r.familyId != familyId ||
              !ids.contains(r.sourcePersonId) ||
              !ids.contains(r.targetPersonId) ||
              r.sourcePersonId == r.targetPersonId ||
              !['SPOUSE', 'PARENT_CHILD'].contains(r.relationshipType) ||
              (!r.isSpouse &&
                  (!['FATHER', 'MOTHER'].contains(r.parentRole) ||
                      ![
                        'BIOLOGICAL',
                        'ADOPTIVE',
                        'STEP',
                      ].contains(r.parentKind))),
        )) {
      throw const FormatException('Invalid tree snapshot');
    }
  }
}

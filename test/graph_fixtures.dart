import 'fixtures.dart';

Map<String, dynamic> edgeJson(
  int id,
  int source,
  int target, {
  bool spouse = false,
  String role = 'FATHER',
  String kind = 'BIOLOGICAL',
}) => {
  'id': id,
  'familyId': 7,
  'sourcePersonId': source,
  'targetPersonId': target,
  'relationshipType': spouse ? 'SPOUSE' : 'PARENT_CHILD',
  'parentRole': spouse ? null : role,
  'parentKind': spouse ? null : kind,
  'createdAt': '2026-10-27T00:00:00Z',
};

Map<String, dynamic> treeJson({
  List<Map<String, dynamic>>? people,
  List<Map<String, dynamic>>? edges,
  int version = 4,
}) => {
  'familyId': 7,
  'version': version,
  'persons':
      people ??
      [
        personJson(id: 11, name: 'Nguyễn Văn Bình'),
        personJson(id: 12, name: 'Trần Thị Lan'),
        personJson(id: 13, name: 'Nguyễn Văn Minh'),
        personJson(id: 14, name: 'Lê Thị Hoa'),
        personJson(id: 15, name: 'Nguyễn Minh Đức'),
        personJson(id: 16, name: null),
      ],
  'relationships':
      edges ??
      [
        edgeJson(1, 11, 12, spouse: true),
        edgeJson(2, 11, 13),
        edgeJson(3, 12, 13, role: 'MOTHER'),
        edgeJson(4, 13, 14, spouse: true),
        edgeJson(5, 13, 15),
        edgeJson(6, 14, 15, role: 'MOTHER', kind: 'ADOPTIVE'),
      ],
};

/// The approved preview: 13 people, 3 spouses, 15 parent edges, 5 parent groups.
Map<String, dynamic> complexTreeJson() {
  final names = [
    'Nguyễn Bình',
    'Trần Lan',
    'Lê Hoa',
    'Nguyễn Minh',
    'Đỗ Mai',
    'Nguyễn Hương',
    'Phạm Quang',
    'Nguyễn An',
    'Nguyễn Bảo',
    'Nguyễn Duy',
    'Nguyễn Linh',
    'Nguyễn Vy',
    'Phạm Khoa',
  ];
  final years = [
    1946,
    1949,
    1975,
    1973,
    1980,
    1976,
    1974,
    1998,
    2002,
    2005,
    2010,
    2013,
    2008,
  ];
  return treeJson(
    people: [
      for (var i = 0; i < names.length; i++)
        {...personJson(id: i + 1, name: names[i]), 'birthYear': years[i]},
    ],
    edges: [
      edgeJson(1, 1, 2, spouse: true),
      edgeJson(2, 3, 4, spouse: true),
      edgeJson(3, 4, 5, spouse: true),
      edgeJson(4, 1, 4),
      edgeJson(5, 2, 4, role: 'MOTHER'),
      edgeJson(6, 1, 6),
      edgeJson(7, 2, 6, role: 'MOTHER'),
      edgeJson(8, 4, 8),
      edgeJson(9, 3, 8, role: 'MOTHER'),
      edgeJson(10, 4, 9),
      edgeJson(11, 3, 9, role: 'MOTHER'),
      edgeJson(12, 4, 10),
      edgeJson(13, 4, 11),
      edgeJson(14, 5, 11, role: 'MOTHER'),
      edgeJson(15, 4, 12),
      edgeJson(16, 5, 12, role: 'MOTHER', kind: 'ADOPTIVE'),
      edgeJson(17, 6, 13, role: 'MOTHER'),
      edgeJson(18, 7, 13),
    ],
  );
}

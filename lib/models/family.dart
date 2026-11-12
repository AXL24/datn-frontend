class Family {
  final int id;
  final String name;
  final String? description;
  final int personCount;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Family({
    required this.id,
    required this.name,
    this.description,
    required this.personCount,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  factory Family.fromJson(Map<String, dynamic> j) => Family(
    id: j['id'] as int,
    name: j['name'] as String,
    description: j['description'] as String?,
    personCount: j['personCount'] as int,
    version: j['version'] as int,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}

class RecentFamily {
  final int id;
  final String name;
  final DateTime lastOpenedAt;
  const RecentFamily(this.id, this.name, this.lastOpenedAt);
  factory RecentFamily.fromJson(Map<String, dynamic> j) => RecentFamily(
    j['id'] as int,
    j['name'] as String,
    DateTime.parse(j['lastOpenedAt'] as String),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lastOpenedAt': lastOpenedAt.toUtc().toIso8601String(),
  };
}

/// Read-only Person DTO. version belongs to Person, not Family.
class Person {
  final int id, familyId, version, generationIndex;
  final String? displayName, birthDate, deathDate, note;
  final int? birthYear, deathYear, familyVersion;
  final String gender, lifeStatus;
  final num? layoutX;
  final DateTime createdAt, updatedAt;
  Person.fromJson(Map<String, dynamic> j)
    : familyVersion = j['familyVersion'] as int?,
      id = j['id'] as int,
      familyId = j['familyId'] as int,
      displayName = j['displayName'] as String?,
      gender = j['gender'] as String,
      lifeStatus = j['lifeStatus'] as String,
      birthDate = j['birthDate'] as String?,
      birthYear = j['birthYear'] as int?,
      deathDate = j['deathDate'] as String?,
      deathYear = j['deathYear'] as int?,
      note = j['note'] as String?,
      generationIndex = j['generationIndex'] as int,
      layoutX = j['layoutX'] as num?,
      version = j['version'] as int,
      createdAt = DateTime.parse(j['createdAt'] as String),
      updatedAt = DateTime.parse(j['updatedAt'] as String);

  Person withFamilyVersion(int value) => Person.fromJson({
    'id': id,
    'familyId': familyId,
    'version': version,
    'familyVersion': value,
    'displayName': displayName,
    'gender': gender,
    'lifeStatus': lifeStatus,
    'birthDate': birthDate,
    'birthYear': birthYear,
    'deathDate': deathDate,
    'deathYear': deathYear,
    'note': note,
    'generationIndex': generationIndex,
    'layoutX': layoutX,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  });
  static Person temporary(int id, int familyId) => Person.fromJson({
    'id': id,
    'familyId': familyId,
    'version': 0,
    'displayName': null,
    'gender': 'UNKNOWN',
    'lifeStatus': 'UNKNOWN',
    'birthDate': null,
    'birthYear': null,
    'deathDate': null,
    'deathYear': null,
    'note': null,
    'generationIndex': 0,
    'layoutX': null,
    'createdAt': '1970-01-01T00:00:00Z',
    'updatedAt': '1970-01-01T00:00:00Z',
  });
  String get name => displayName?.trim().isNotEmpty == true
      ? displayName!
      : 'Chưa có thông tin';
  String get genderLabel => switch (gender) {
    'MALE' => 'Nam',
    'FEMALE' => 'Nữ',
    'OTHER' => 'Khác',
    _ => 'Chưa rõ',
  };
  String get lifeStatusLabel => switch (lifeStatus) {
    'ALIVE' => 'Còn sống',
    'DECEASED' => 'Đã mất',
    _ => 'Chưa rõ',
  };
  String get birthLabel => _dateLabel(birthDate, birthYear);
  String get deathLabel => _dateLabel(deathDate, deathYear);
  // LocalDate is a calendar date, never shift it by the device timezone.
  static String _dateLabel(String? date, int? year) {
    if (date != null) {
      final parts = date.split('-');
      if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
    return year?.toString() ?? 'Chưa rõ';
  }
}

class PeoplePage {
  final List<Person> content;
  final int page, size, totalElements, totalPages;
  PeoplePage.fromJson(Map<String, dynamic> j)
    : content = (j['content'] as List)
          .map((v) => Person.fromJson(v as Map<String, dynamic>))
          .toList(),
      page = j['page'] as int,
      size = j['size'] as int,
      totalElements = j['totalElements'] as int,
      totalPages = j['totalPages'] as int;
}

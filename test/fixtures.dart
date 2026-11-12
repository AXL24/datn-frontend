import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:gia_pha_app/models/family.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/services/storage_service.dart';

Map<String, dynamic> familyJson([int id = 7]) => {
  'id': id,
  'name': 'Gia phả nhà Nguyễn',
  'description': 'Lưu giữ câu chuyện của gia đình qua từng thế hệ.',
  'personCount': 1,
  'version': 0,
  'createdAt': '2026-10-25T02:00:00Z',
  'updatedAt': '2026-10-25T02:00:00Z',
};
Map<String, dynamic> accessJson({int id = 7, String permission = 'VIEW'}) => {
  'family': familyJson(id),
  'session': {
    'familyId': id,
    'accessToken': 'test-only-token',
    'permission': permission,
    if (permission == 'EDIT')
      'editExpiresAt': DateTime.now()
          .add(const Duration(hours: 1))
          .toUtc()
          .toIso8601String(),
    'expiresAt': DateTime.now()
        .add(const Duration(hours: 2))
        .toUtc()
        .toIso8601String(),
  },
};
Map<String, dynamic> createdJson() => {
  ...accessJson(permission: 'EDIT'),
  'familyCode': 'test-only-family-code',
  'editCode': 'test-only-edit-code',
};
http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class MemoryStorage extends StorageService {
  MemoryStorage() : super(server: 'http://test.invalid');
  final sessions = <int, AccessSession>{};
  final families = <int, RecentFamily>{};
  bool failSave = false;
  @override
  Future<void> saveSession(AccessSession session) async {
    if (failSave) throw StateError('storage unavailable');
    sessions[session.familyId] = session;
  }

  @override
  Future<void> saveFamily(Family family) async {
    if (failSave) throw StateError('storage unavailable');
    families[family.id] = RecentFamily(family.id, family.name, DateTime.now());
  }

  @override
  Future<AccessSession?> getSession(int id) async => sessions[id];
  @override
  Future<List<RecentFamily>> getFamilies() async => families.values.toList();
  @override
  Future<void> deleteSession(int id) async {
    sessions.remove(id);
  }

  @override
  Future<void> removeLocalFamily(int id) async {
    sessions.remove(id);
    families.remove(id);
  }
}

Map<String, dynamic> personJson({
  int id = 11,
  int familyId = 7,
  String? name = 'Nguyễn An',
}) => {
  'id': id,
  'familyId': familyId,
  'displayName': name,
  'gender': 'UNKNOWN',
  'lifeStatus': 'UNKNOWN',
  'birthDate': null,
  'birthYear': 1980,
  'deathDate': null,
  'deathYear': null,
  'note': 'Lưu lại câu chuyện của người thân.',
  'generationIndex': 0,
  'layoutX': null,
  'version': 0,
  'createdAt': '2026-10-25T00:00:00Z',
  'updatedAt': '2026-10-25T00:00:00Z',
};
Map<String, dynamic> peopleJson({
  int page = 0,
  List<Map<String, dynamic>>? content,
  int total = 1,
  int pages = 1,
}) => {
  'content': content ?? [personJson()],
  'page': page,
  'size': 20,
  'totalElements': total,
  'totalPages': pages,
};

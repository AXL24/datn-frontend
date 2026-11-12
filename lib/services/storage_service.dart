import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:localstore/localstore.dart';

import '../models/family.dart';
import '../models/access_session.dart';

class StorageService {
  final String scope;
  final Localstore _db;
  final FlutterSecureStorage _secure;
  StorageService({
    required String server,
    Localstore? db,
    FlutterSecureStorage? secure,
  }) : scope = base64Url.encode(utf8.encode(server)),
       _db = db ?? Localstore.instance,
       _secure = secure ?? const FlutterSecureStorage();
  String get _collection => 'families_$scope';
  String _key(int id) => 'session_${scope}_$id';

  Future<List<RecentFamily>> getFamilies() async {
    final docs = await _db.collection(_collection).get();
    final result = <RecentFamily>[];
    for (final value in (docs ?? {}).values) {
      // Skip a damaged record, never clear unrelated families.
      try {
        result.add(
          RecentFamily.fromJson(Map<String, dynamic>.from(value as Map)),
        );
      } catch (_) {
        continue;
      }
    }
    result.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return result;
  }

  Future<void> saveFamily(Family family) => _db
      .collection(_collection)
      .doc('${family.id}')
      .set(RecentFamily(family.id, family.name, DateTime.now()).toJson());
  Future<void> saveSession(AccessSession session) => _secure.write(
    key: _key(session.familyId),
    value: jsonEncode(session.toJson()),
  );
  Future<AccessSession?> getSession(int id) async {
    final raw = await _secure.read(key: _key(id));
    if (raw == null) return null;
    try {
      final session = AccessSession.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      return session.familyId == id ? session : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteSession(int id) => _secure.delete(key: _key(id));
  Future<void> removeLocalFamily(int id) async {
    await deleteSession(id);
    await _db.collection(_collection).doc('$id').delete();
  }
}

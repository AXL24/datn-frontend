import 'package:flutter/foundation.dart';

import '../models/person.dart';
import '../models/access_session.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// One instance per members view/detail route. Latest request wins.
class PersonController extends ChangeNotifier {
  final ApiService api;
  final StorageService storage;
  final int familyId;
  final AccessSession? initialSession;
  PersonController(
    this.api,
    this.storage,
    this.familyId, {
    this.initialSession,
  });
  AccessSession? session;
  PeoplePage? people;
  Person? person;
  bool busy = false, needsJoin = false;
  String? error;
  int? errorStatus;
  String query = '';
  int page = 0;
  int _requestId = 0;
  bool _disposed = false;

  bool _current(int id) => !_disposed && id == _requestId;
  Future<AccessSession> _readSession() async {
    final stored =
        session ?? initialSession ?? await storage.getSession(familyId);
    final value = stored == null ? null : api.resolveSession(stored);
    if (value == null || !value.expiresAt.isAfter(DateTime.now())) {
      throw const ApiException(
        'Phiên đã hết hạn. Vui lòng nhập lại mã gia phả.',
        status: 401,
      );
    }
    if (value.familyId != familyId) {
      throw const ApiException('Phiên không thuộc gia phả này.', status: 403);
    }
    return value;
  }

  Future<void> loadPeople({String? q, int? targetPage}) async {
    query = q ?? query;
    page = targetPage ?? (q != null ? 0 : page);
    final requestedQuery = query, requestedPage = page;
    await _load(() async {
      final result = await api.getPeople(
        familyId,
        session!,
        page: requestedPage,
        q: requestedQuery,
      );
      return result;
    }, detail: false);
  }

  Future<void> loadPerson(int id) =>
      _load(() => api.getPerson(familyId, id, session!), detail: true);

  Future<void> _load(
    Future<Object> Function() fetch, {
    required bool detail,
  }) async {
    final request = ++_requestId;
    busy = true;
    error = null;
    errorStatus = null;
    needsJoin = false;
    if (detail) {
      person = null;
    } else {
      people = null;
    }
    if (!_disposed) notifyListeners();
    try {
      final value = await _readSession();
      if (!_current(request)) return;
      session = value;
      final result = await fetch();
      if (!_current(request)) return;
      if (detail) {
        person = result as Person;
      } else {
        people = result as PeoplePage;
      }
    } on ApiException catch (e) {
      if (!_current(request)) return;
      error = e.message;
      errorStatus = e.status;
      needsJoin = e.status == 401;
      if (needsJoin) {
        try {
          await storage.deleteSession(familyId);
        } catch (_) {
          /* Keep metadata; rejoin can replace token. */
        }
      }
    } catch (_) {
      if (!_current(request)) return;
      error = 'Chưa đọc được dữ liệu trên thiết bị. Vui lòng thử lại.';
    } finally {
      if (_current(request)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _requestId++;
    super.dispose();
  }
}

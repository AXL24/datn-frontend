import 'package:flutter/foundation.dart';

import '../models/family.dart';
import '../models/access_session.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class FamilyController extends ChangeNotifier {
  final ApiService api;
  final StorageService storage;
  FamilyController(this.api, this.storage);
  bool busy = false;
  bool needsJoin = false;
  bool outcomeUnknown = false;
  bool _disposed = false;
  String? error;
  String? warning;
  Family? family;
  AccessSession? session;
  List<RecentFamily> recents = [];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _start() {
    busy = true;
    error = null;
    warning = null;
    needsJoin = false;
    _notify();
  }

  void _finish() {
    busy = false;
    _notify();
  }

  Future<void> remember(FamilyAccess result) async {
    try {
      await storage.saveSession(result.session);
      await storage.saveFamily(result.family);
      warning = null;
    } catch (_) {
      warning = 'Đã nhận dữ liệu từ máy chủ, nhưng chưa lưu được trên thiết bị. Hãy lưu lại mã và thử lưu phiên lần nữa.';
    }
    _notify();
  }

  Future<void> loadRecents() async {
    if (busy) return;
    _start();
    try {
      recents = await storage.getFamilies();
    } catch (_) {
      error = 'Chưa đọc được danh sách trên thiết bị. Hãy thử lại.';
    } finally {
      _finish();
    }
  }

  Future<CreatedFamily?> create({
    required String name,
    String? description,
    required String personName,
    int? birthYear,
  }) async {
    if (busy || outcomeUnknown) return null;
    _start();
    try {
      final result = await api.create(
        name: name,
        description: description,
        personName: personName,
        birthYear: birthYear,
      );
      await remember(result);
      return result;
    } on ApiException catch (e) {
      error = e.message;
      outcomeUnknown = e.outcomeUnknown;
      return null;
    } finally {
      _finish();
    }
  }

  Future<FamilyAccess?> join(String code, {int? expectedFamilyId}) async {
    if (busy) return null;
    _start();
    try {
      final result = await api.join(code);
      if (expectedFamilyId != null && expectedFamilyId != result.family.id) {
        error = 'Mã này thuộc gia phả khác. Hãy nhập mã của gia phả đang mở.';
        return null;
      }
      await remember(result);
      return result;
    } on ApiException catch (e) {
      error = e.message;
      return null;
    } finally {
      _finish();
    }
  }

  Future<void> open(int id, {AccessSession? initialSession}) async {
    if (busy) return;
    _start();
    family = null;
    try {
      session = initialSession ?? await storage.getSession(id);
      if (session != null) session = api.resolveSession(session!);
      if (session == null || !session!.expiresAt.isAfter(DateTime.now())) {
        needsJoin = true;
        error = 'Nhập mã gia phả để tiếp tục xem.';
        return;
      }
      family = await api.getFamily(id, session!);
      outcomeUnknown = false;
      try {
        await storage.saveFamily(family!);
      } catch (_) {
        warning =
            'Đã tải dữ liệu nhưng chưa cập nhật được danh sách trên thiết bị.';
      }
    } on ApiException catch (e) {
      error = e.message;
      if (e.status == 401) {
        needsJoin = true;
        try {
          await storage.deleteSession(id);
        } catch (_) {
          /* Keep recents; rejoin replaces the session. */
        }
      }
    } catch (_) {
      error = 'Chưa đọc được phiên trên thiết bị. Vui lòng nhập lại mã.';
      needsJoin = true;
    } finally {
      _finish();
    }
  }

  void adoptSession(AccessSession value) {
    session = value;
    error = null;
    needsJoin = false;
    _notify();
  }

  Future<Family?> saveMetadata({
    required String name,
    String? description,
    required int baseVersion,
  }) async {
    if (busy || outcomeUnknown || session == null || family == null) {
      return null;
    }
    _start();
    try {
      final result = await api.updateFamily(
        family!.id,
        session!,
        name: name,
        description: description,
        version: baseVersion,
      );
      family = result;
      try {
        await storage.saveFamily(result);
      } catch (_) {
        warning =
            'Đã lưu trên máy chủ nhưng chưa cập nhật danh sách trên thiết bị.';
      }
      return result;
    } on ApiException catch (e) {
      error = e.message;
      outcomeUnknown = e.outcomeUnknown;
      needsJoin = e.status == 401;
      return null;
    } finally {
      _finish();
    }
  }

  Future<void> remove(int id) async {
    if (busy) return;
    _start();
    try {
      await storage.removeLocalFamily(id);
      recents.removeWhere((f) => f.id == id);
    } catch (_) {
      error = 'Chưa bỏ được gia phả khỏi thiết bị. Vui lòng thử lại.';
    } finally {
      _finish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

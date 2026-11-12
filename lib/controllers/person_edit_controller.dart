import 'package:flutter/foundation.dart';

import '../models/person.dart';
import '../models/access_session.dart';
import '../services/api_service.dart';
import 'graph_controller.dart';

/// Owns one saved Person form. Never rebases a dirty form through GET.
class PersonEditController extends ChangeNotifier {
  final GraphController? graph;
  final int? graphEpoch;
  final ApiService api;
  AccessSession session;
  Person? _baseline;
  Person get baseline => _baseline!;
  final bool creating;
  final int? _createVersion;
  bool created = false;
  static Map<String, dynamic> emptyDetails() => {
    'displayName': null,
    'gender': 'UNKNOWN',
    'lifeStatus': 'UNKNOWN',
    'birthDate': null,
    'birthYear': null,
    'deathDate': null,
    'deathYear': null,
    'note': null,
  };
  late Map<String, dynamic> details = _baseline == null
      ? emptyDetails()
      : values(baseline);
  bool busy = false, blocked = false, deleted = false, needsEdit = false;
  bool _disposed = false;
  String? error;
  PersonEditController(this.api, this.session, Person person, {this.graph})
    : graphEpoch = graph?.epoch,
      _baseline = person,
      creating = false,
      _createVersion = null;
  PersonEditController.create(this.api, this.session, int baseVersion)
    : graphEpoch = null,
      graph = null,
      creating = true,
      _createVersion = baseVersion;
  static Map<String, dynamic> values(Person p) => {
    'displayName': p.displayName,
    'gender': p.gender,
    'lifeStatus': p.lifeStatus,
    'birthDate': p.birthDate,
    'birthYear': p.birthYear,
    'deathDate': p.deathDate,
    'deathYear': p.deathYear,
    'note': p.note,
  };
  bool get dirty => !mapEquals(
    details,
    _baseline == null ? emptyDetails() : values(baseline),
  );
  int? get baseVersion => _baseline?.familyVersion ?? _createVersion;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void change(String key, dynamic value) {
    details[key] = value;
    _notify();
  }

  void discard() {
    details = _baseline == null ? emptyDetails() : values(baseline);
    _notify();
  }

  String? validate() {
    final name = details['displayName'] as String?;
    if (creating && (name == null || name.trim().isEmpty)) {
      return 'Vui lòng nhập họ tên thành viên.';
    }
    if (name != null && (name.trim().isEmpty || name.length > 150)) {
      return 'Tên tối đa 150 ký tự; để trống nếu chưa biết.';
    }
    if ((details['note'] as String?)?.length.compareTo(10000) == 1) {
      return 'Ghi chú tối đa 10000 ký tự.';
    }
    DateTime? lower(String prefix, bool upper) {
      final date = details['${prefix}Date'] as String?;
      final year = details['${prefix}Year'] as int?;
      if (date != null && year != null) {
        throw const FormatException('Chọn ngày hoặc năm, không nhập cả hai.');
      }
      if (year != null) {
        if (year < 1 || year > 9999) {
          throw const FormatException('Năm phải từ 1 đến 9999.');
        }
        return DateTime(year, upper ? 12 : 1, upper ? 31 : 1);
      }
      if (date == null) return null;
      final parsed = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.year < 1 ||
          parsed.year > 9999 ||
          parsed.toIso8601String().substring(0, 10) != date) {
        throw const FormatException(
          'Ngày phải hợp lệ theo định dạng YYYY-MM-DD.',
        );
      }
      return parsed;
    }

    try {
      final birth = lower('birth', false), death = lower('death', true);
      if (death != null && details['lifeStatus'] != 'DECEASED') {
        return 'Chỉ nhập ngày/năm mất khi chọn Đã mất.';
      }
      if (birth != null && death != null && death.isBefore(birth)) {
        return 'Thời điểm mất không được trước thời điểm sinh.';
      }
    } on FormatException catch (e) {
      return e.message;
    }
    return null;
  }

  Future<bool> save() async {
    if (busy || blocked || deleted || created || graph?.writeLocked == true) {
      return false;
    }
    error = validate();
    if (error != null) {
      _notify();
      return false;
    }
    return _write(false);
  }

  Future<bool> verifyBeforeDelete() async {
    if (creating || busy || blocked || dirty || deleted) return false;
    busy = true;
    error = null;
    _notify();
    try {
      final current = await api.getPerson(
        baseline.familyId,
        baseline.id,
        api.resolveSession(session),
      );
      if (_disposed) return false;
      if (current.familyVersion != baseVersion ||
          current.version != baseline.version) {
        blocked = true;
        error = 'Hồ sơ hoặc gia phả đã thay đổi. Quay lại để đối chiếu trước khi xác nhận xóa.';
        return false;
      }
      return true;
    } on ApiException catch (e) {
      if (_disposed) return false;
      error = e.message;
      blocked = e.status == 401 || e.status == 404;
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> remove() async {
    if (creating || busy || blocked || deleted || dirty) return false;
    return _write(true);
  }

  Future<bool> _write(bool deleting) async {
    if (baseVersion == null) {
      error = 'Thiếu familyVersion. Hãy cập nhật backend rồi mở lại hồ sơ.';
      _notify();
      return false;
    }
    busy = true;
    error = null;
    needsEdit = false;
    _notify();
    final submittedVersion = baseVersion!;
    try {
      session = api.resolveSession(session);
      if (creating) {
        final result = await api.createPerson(
          session.familyId,
          session,
          baseVersion: baseVersion!,
          details: Map.of(details),
        );
        if (_disposed) return false;
        _baseline = result;
        details = values(result);
        created = true;
      } else if (deleting) {
        await api.deletePerson(
          baseline.familyId,
          baseline.id,
          session,
          baseVersion: baseVersion!,
        );
        if (_disposed) return false;
        deleted = true;
        graph?.invalidateClean();
      } else {
        final result = await api.updatePerson(
          baseline.familyId,
          baseline.id,
          session,
          baseVersion: baseVersion!,
          details: Map.of(details),
        );
        if (_disposed) return false;
        if (graph != null &&
            graph!.dirty &&
            !graph!.acceptPerson(result, graphEpoch!, submittedVersion)) {
          blocked = true;
          error = 'Ngữ cảnh bản nháp đã thay đổi; hãy đối chiếu dữ liệu.';
          return false;
        }
        if (graph != null && !graph!.dirty) graph!.invalidateClean();
        _baseline = result;
        details = values(result);
      }
      return true;
    } on ApiException catch (e) {
      if (_disposed) return false;
      graph?.blockAfterWrite(e);
      error = e.message;
      blocked =
          e.outcomeUnknown ||
          e.status == 409 ||
          e.status == 404 ||
          e.status == 401;
      needsEdit = e.status == 403;
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  void useResolvedBaseline(Person person) {
    if (dirty ||
        busy ||
        blocked ||
        person.id != baseline.id ||
        person.familyId != baseline.familyId) {
      return;
    }
    _baseline = person;
    details = values(person);
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

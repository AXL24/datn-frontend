import 'package:flutter/foundation.dart';

import '../models/access_session.dart';
import '../models/tree_snapshot.dart';
import '../models/graph_draft.dart';
import '../models/person.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/graph_layout_service.dart';

class GraphController extends ChangeNotifier {
  final ApiService api;
  final StorageService storage;
  final int familyId;
  final AccessSession? initialSession;
  GraphController(this.api, this.storage, this.familyId, {this.initialSession});
  AccessSession? session;
  GraphDraft? draft;
  bool editing = false, blocked = false, committing = false, needsEdit = false;
  int epoch = 0, loadedRevision = -1;
  int? confirmedVersion;
  Map<String, int> lastIdMap = {};
  List<int> displayOrder = []; // Presentation only; never sent to API23.
  bool get dirty => draft?.dirty == true;
  bool get writeLocked => busy || committing || blocked;
  TreeSnapshot? snapshot;
  GraphLayout? layout;
  bool busy = false, needsJoin = false, _disposed = false;
  int _request = 0;
  String? error;
  bool _current(int id) => !_disposed && _request == id;

  Future<void> load() async {
    if (_disposed || dirty || blocked || committing) return;
    final request = ++_request;
    busy = true;
    error = null;
    needsJoin = false;
    snapshot = null;
    layout = null;
    notifyListeners();
    try {
      final stored =
          session ?? initialSession ?? await storage.getSession(familyId);
      final value = stored == null ? null : api.resolveSession(stored);
      if (!_current(request)) return;
      if (value == null || !value.expiresAt.isAfter(DateTime.now())) {
        throw const ApiException(
          'Phiên đã hết hạn. Vui lòng nhập lại mã gia phả.',
          status: 401,
        );
      }
      if (value.familyId != familyId) {
        throw const ApiException('Phiên không thuộc gia phả này.', status: 403);
      }
      session = value;
      final result = await api.getTree(familyId, value);
      if (!_current(request)) return;
      if (confirmedVersion != null && result.version < confirmedVersion!) {
        throw const ApiException(
          'Snapshot chưa phản ánh lần lưu đã xác nhận. Chỉ thử tải lại.',
        );
      }
      loadedRevision = api.revision(familyId);
      final arranged = GraphLayoutService().arrange(
        result,
        preferredOrder: displayOrder,
      );
      draft = GraphDraft(result);
      epoch++;
      snapshot = result;
      layout = arranged;
    } on ApiException catch (e) {
      if (!_current(request)) return;
      error = e.message;
      needsJoin = e.status == 401;
      // No old graph remains visible after access fails; rejoin replaces session.
    } catch (_) {
      if (!_current(request)) return;
      error = 'Chưa tải được sơ đồ. Vui lòng thử lại.';
    } finally {
      if (_current(request)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void rebuild() {
    if (_disposed || draft == null) return;
    snapshot = draft!.snapshot;
    layout = GraphLayoutService().arrange(
      snapshot!,
      preferredOrder: displayOrder,
    );
    notifyListeners();
  }

  void placeSpouse(int anchor, int spouse, {required bool left}) {
    if (layout == null) return;
    final ordered = layout!.nodes.keys.toList()
      ..sort((a, b) {
        final x = layout!.nodes[a]!.center.dx.compareTo(
          layout!.nodes[b]!.center.dx,
        );
        return x != 0 ? x : a.compareTo(b);
      });
    ordered.remove(spouse);
    final at = ordered.indexOf(anchor);
    if (at < 0) return;
    ordered.insert(at + (left ? 0 : 1), spouse);
    displayOrder = ordered;
  }

  void changed() {
    error = null;
    rebuild();
  }

  Future<bool> discardAndReload() async {
    if (busy || committing) return false;
    draft = null;
    blocked = false;
    error = null;
    epoch++;
    await load();
    return snapshot != null && error == null;
  }

  void blockAfterWrite(ApiException e) {
    if (_disposed) return;
    if (e.outcomeUnknown ||
        e.status == 409 ||
        e.status == 401 ||
        e.status == 404) {
      blocked = true;
      error = e.message;
      notifyListeners();
    }
  }

  bool acceptPerson(Person p, int expectedEpoch, int expectedVersion) {
    if (_disposed ||
        draft == null ||
        epoch != expectedEpoch ||
        draft!.baseline.version != expectedVersion ||
        p.familyId != familyId) {
      return false;
    }
    draft!.acceptPerson(p);
    rebuild();
    return true;
  }

  void invalidateClean() {
    if (dirty || _disposed) return;
    draft = null;
    snapshot = null;
    layout = null;
    epoch++;
    notifyListeners();
  }

  Future<bool> commit() async {
    if (writeLocked || !dirty || session == null) return false;
    final problem = draft!.validate();
    if (problem != null) {
      error = problem;
      notifyListeners();
      return false;
    }
    final currentDraft = draft!, currentEpoch = epoch;
    final requestId = draftUuid();
    final payload = currentDraft.payload(requestId);
    committing = true;
    error = null;
    needsEdit = false;
    notifyListeners();
    try {
      session = api.resolveSession(session!);
      final result = await api.commitGraph(familyId, session!, payload);
      if (_disposed || epoch != currentEpoch || draft != currentDraft) {
        return false;
      }
      final existingIds = currentDraft.baseline.persons
          .map((p) => p.id)
          .toSet();
      if (result.ids.values.any(existingIds.contains)) {
        throw const ApiException(
          'Ánh xạ hồ sơ mới không hợp lệ. Cần đối chiếu, không gửi lại lệnh.',
          outcomeUnknown: true,
        );
      }
      lastIdMap = result.ids;
      displayOrder = displayOrder
          .map((id) => id < 0 ? result.ids['tmp-${-id}'] ?? id : id)
          .toList();
      confirmedVersion = result.version;
      // A confirmed commit is terminal even if the following GET fails.
      draft = null;
      snapshot = null;
      layout = null;
      epoch++;
      committing = false;
      await load();
      return true;
    } on ApiException catch (e) {
      if (_disposed || epoch != currentEpoch || draft != currentDraft) {
        return false;
      }
      error = e.message;
      blocked =
          e.outcomeUnknown ||
          e.status == 409 ||
          e.status == 401 ||
          e.status == 404;
      needsEdit = e.status == 403;
      needsJoin = e.status == 401;
      return false;
    } finally {
      committing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}

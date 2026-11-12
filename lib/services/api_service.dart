import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/family.dart';
import '../models/person.dart';
import '../models/tree_snapshot.dart';
import '../models/access_session.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final bool outcomeUnknown;
  const ApiException(this.message, {this.status, this.outcomeUnknown = false});
  @override
  String toString() => message;
}

class ApiService {
  // Shared by routes using this API instance; survives secure-storage failures.
  final Map<int, AccessSession> _sessions = {};
  final Map<int, int> _revisions = {};
  int revision(int familyId) => _revisions[familyId] ?? 0;
  final Set<int> _writingFamilies = {};
  AccessSession resolveSession(AccessSession session) =>
      _sessions[session.familyId] ?? session;
  void adoptSession(AccessSession session) {
    _sessions[session.familyId] = session;
  }

  Future<T> _write<T>(int familyId, Future<T> Function() action) async {
    if (!_writingFamilies.add(familyId)) {
      throw const ApiException(
        'Đang có thao tác ghi trong gia phả. Hãy chờ hoàn tất.',
      );
    }
    try {
      return await action();
    } finally {
      _writingFamilies.remove(familyId);
      _revisions[familyId] = revision(familyId) + 1;
    }
  }

  final String baseUrl;
  final http.Client _client;
  final Duration timeout;
  ApiService({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
       _client = client ?? http.Client();

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final writing = method != 'GET';
    try {
      final headers = {
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final uri = Uri.parse('$baseUrl$path');
      final Future<http.Response> pending = switch (method) {
        'POST' => _client.post(uri, headers: headers, body: jsonEncode(body)),
        'PUT' => _client.put(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => _client.get(uri, headers: headers),
      };
      final response = await pending.timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final status = response.statusCode;
        // Do not display or log arbitrary response bodies that could contain private data.
        String? code;
        try {
          code =
              (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['code']
                  as String?;
        } catch (_) {
          /* Generic error below. */
        }
        final message = switch (status) {
          400 => 'Thông tin chưa hợp lệ. Hãy kiểm tra lại các ô nhập.',
          401 => 'Phiên truy cập đã hết hạn. Vui lòng nhập lại mã gia phả.',
          403 when code == 'INVALID_FAMILY_CODE' =>
            'Mã gia phả không đúng. Hãy kiểm tra và thử lại.',
          403 when code == 'INVALID_EDIT_CODE' =>
            'Mã chỉnh sửa không đúng. Hãy kiểm tra và thử lại.',
          403 when code == 'EDIT_REQUIRED' =>
            'Quyền chỉnh sửa đã hết hạn. Hãy nhập lại mã chỉnh sửa.',
          403 => 'Bạn không có quyền truy cập gia phả này.',
          409 when code == 'STALE_VERSION' || code == 'STALE_DRAFT' => 'Thông tin gia phả đã thay đổi. Hãy đối chiếu bản mới trước khi lưu lại.',
          422 => 'Quan hệ chưa hợp lệ. Kiểm tra vai trò cha/mẹ, cạnh trùng, hồ sơ và chu trình; bản nháp chưa được lưu.',
          404 => 'Không tìm thấy dữ liệu. Hồ sơ có thể đã bị xóa.',
          _ =>
            writing
                ? 'Chưa xác nhận được kết quả. Không gửi lại tự động; hãy kiểm tra trước khi thử lại.'
                : 'Chưa tải được dữ liệu. Vui lòng thử lại sau.',
        };
        throw ApiException(
          message,
          status: status,
          outcomeUnknown: writing && status >= 500,
        );
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        writing
            ? 'Yêu cầu quá thời gian. Chưa rõ server đã xử lý hay chưa; không gửi lại tự động.'
            : 'Kết nối quá thời gian. Vui lòng thử tải lại.',
        outcomeUnknown: writing,
      );
    } on http.ClientException {
      throw ApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng và địa chỉ backend.',
        outcomeUnknown: writing,
      );
    } catch (_) {
      throw ApiException(
        'Dữ liệu trả về không hợp lệ. Hãy kiểm tra trước khi thử lại.',
        outcomeUnknown: writing,
      );
    }
  }

  FamilyAccess _access(Map<String, dynamic> j) {
    final family = Family.fromJson(j['family'] as Map<String, dynamic>);
    final session = AccessSession.fromJson(
      j['session'] as Map<String, dynamic>,
    );
    if (family.id != session.familyId) {
      throw const FormatException('Family scope mismatch');
    }
    adoptSession(session);
    return FamilyAccess(family, session);
  }

  Future<CreatedFamily> create({
    required String name,
    String? description,
    required String personName,
    int? birthYear,
  }) async {
    final j = await _request(
      'POST',
      '/families',
      body: {
        'name': name.trim(),
        'description': description,
        'firstPerson': {
          'displayName': personName.trim(),
          'birthYear': birthYear,
        },
      },
    );
    try {
      final result = _access(j);
      final code = j['familyCode'] as String;
      final edit = j['editCode'] as String;
      if (code.isEmpty || edit.isEmpty) {
        throw const FormatException('Missing codes');
      }
      return CreatedFamily(result.family, result.session, code, edit);
    } catch (_) {
      throw const ApiException(
        'Gia phả có thể đã được tạo nhưng phản hồi không đầy đủ. Không gửi tạo lại.',
        outcomeUnknown: true,
      );
    }
  }

  Future<FamilyAccess> join(String code) async {
    final j = await _request(
      'POST',
      '/access/join',
      body: {'familyCode': code.trim()},
    );
    try {
      return _access(j);
    } catch (_) {
      throw const ApiException(
        'Phản hồi phiên không hợp lệ. Vui lòng kiểm tra lại.',
        outcomeUnknown: true,
      );
    }
  }

  Future<Family> getFamily(int id, AccessSession session) async {
    session = resolveSession(session);
    if (session.familyId != id) {
      throw const ApiException('Phiên không thuộc gia phả này.', status: 403);
    }
    final j = await _request(
      'GET',
      '/families/$id',
      token: session.accessToken,
    );
    try {
      final family = Family.fromJson(j);
      if (family.id != id) throw const FormatException('Family scope mismatch');
      return family;
    } catch (_) {
      throw const ApiException('Thông tin gia phả trả về không hợp lệ.');
    }
  }

  Future<AccessSession> unlockEdit(
    int familyId,
    AccessSession current,
    String editCode,
  ) => _write(familyId, () async {
    current = resolveSession(current);
    _checkPeopleScope(familyId, current);
    if (!current.canReadAt(DateTime.now())) {
      throw const ApiException(
        'Phiên truy cập đã hết hạn. Vui lòng nhập lại mã gia phả.',
        status: 401,
      );
    }
    final json = await _request(
      'POST',
      '/families/$familyId/access/edit',
      token: current.accessToken,
      body: {'editCode': editCode.trim()},
    );
    try {
      final next = AccessSession.fromJson(json);
      if (next.familyId != familyId || !next.canEditAt(DateTime.now())) {
        throw const FormatException('Invalid unlocked session');
      }
      adoptSession(next);
      return next;
    } catch (_) {
      throw const ApiException(
        'Chưa xác nhận được phiên chỉnh sửa mới. Hãy mở lại gia phả bằng Family Code.',
        outcomeUnknown: true,
      );
    }
  });

  Future<Family> updateFamily(
    int familyId,
    AccessSession session, {
    required String name,
    String? description,
    required int version,
  }) => _write(familyId, () async {
    session = resolveSession(session);
    _checkPeopleScope(familyId, session);
    if (!session.canEditAt(DateTime.now())) {
      throw const ApiException(
        'Quyền chỉnh sửa đã hết hạn. Hãy nhập lại mã chỉnh sửa.',
        status: 403,
      );
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 150 ||
        (description?.length ?? 0) > 10000 ||
        version < 0) {
      throw const ApiException(
        'Thông tin chưa hợp lệ. Hãy kiểm tra lại các ô nhập.',
        status: 400,
      );
    }
    final json = await _request(
      'PUT',
      '/families/$familyId',
      token: session.accessToken,
      body: {'name': trimmed, 'description': description, 'version': version},
    );
    try {
      final family = Family.fromJson(json);
      if (family.id != familyId || family.version < version) {
        throw const FormatException('Invalid updated family');
      }
      return family;
    } catch (_) {
      throw const ApiException(
        'Chưa xác nhận được kết quả lưu. Hãy tải thông tin gia phả để đối chiếu.',
        outcomeUnknown: true,
      );
    }
  });

  Future<PeoplePage> getPeople(
    int familyId,
    AccessSession session, {
    int page = 0,
    int size = 20,
    String q = '',
  }) async {
    session = resolveSession(session);
    _checkPeopleScope(familyId, session);
    if (page < 0 ||
        size < 1 ||
        size > 100 ||
        page * size > 2147483647 ||
        q.length > 150) {
      throw const ApiException(
        'Tham số tìm kiếm hoặc phân trang chưa hợp lệ.',
        status: 400,
      );
    }
    final query = Uri(
      queryParameters: {
        'page': '$page',
        'size': '$size',
        if (q.trim().isNotEmpty) 'q': q.trim(),
      },
    ).query;
    final json = await _request(
      'GET',
      '/families/$familyId/people?$query',
      token: session.accessToken,
    );
    try {
      final result = PeoplePage.fromJson(json);
      if (result.page != page ||
          result.size != size ||
          result.totalElements < 0 ||
          result.totalPages < 0 ||
          result.content.any((p) => p.familyId != familyId || p.id <= 0)) {
        throw const FormatException('Invalid people page');
      }
      return result;
    } catch (_) {
      throw const ApiException('Danh sách thành viên trả về không hợp lệ.');
    }
  }

  Future<Person> getPerson(
    int familyId,
    int personId,
    AccessSession session,
  ) async {
    session = resolveSession(session);
    _checkPeopleScope(familyId, session);
    if (personId <= 0) {
      throw const ApiException('ID hồ sơ chưa hợp lệ.', status: 400);
    }
    Map<String, dynamic> json;
    try {
      json = await _request(
        'GET',
        '/families/$familyId/people/$personId',
        token: session.accessToken,
      );
    } on ApiException catch (e) {
      if (e.status == 404) {
        throw const ApiException(
          'Không tìm thấy hồ sơ trong gia phả này. Hồ sơ có thể đã bị xóa.',
          status: 404,
        );
      }
      rethrow;
    }
    try {
      final person = Person.fromJson(json);
      if (person.familyId != familyId || person.id != personId) {
        throw const FormatException('Person scope mismatch');
      }
      return person;
    } catch (_) {
      throw const ApiException('Thông tin hồ sơ trả về không hợp lệ.');
    }
  }

  void _checkPeopleScope(int id, AccessSession session) {
    if (id <= 0 || session.familyId != id) {
      throw const ApiException('Phiên không thuộc gia phả này.', status: 403);
    }
  }

  Future<void> checkHealth() async {
    await _request('GET', '/api/status');
  }

  Future<TreeSnapshot> getTree(int familyId, AccessSession session) async {
    session = resolveSession(session);
    _checkPeopleScope(familyId, session);
    final json = await _request(
      'GET',
      '/families/$familyId/tree',
      token: session.accessToken,
    );
    try {
      final tree = TreeSnapshot.fromJson(json);
      if (tree.familyId != familyId) throw const FormatException('Tree scope');
      return tree;
    } catch (_) {
      throw const ApiException(
        'Dữ liệu sơ đồ trả về không hợp lệ. Vui lòng tải lại.',
      );
    }
  }

  void _checkWrite(
    int familyId,
    int personId,
    int baseVersion,
    AccessSession session,
  ) {
    _checkPeopleScope(familyId, session);
    if (personId <= 0 || baseVersion < 0) {
      throw const ApiException('ID hoặc version không hợp lệ.', status: 400);
    }
    if (!session.canReadAt(DateTime.now())) {
      throw const ApiException(
        'Phiên đã hết hạn. Hãy mở lại gia phả.',
        status: 401,
      );
    }
    if (!session.canEditAt(DateTime.now())) {
      throw const ApiException('Cần nhập lại mã chỉnh sửa.', status: 403);
    }
  }

  Future<Person> createPerson(
    int familyId,
    AccessSession session, {
    required int baseVersion,
    required Map<String, dynamic> details,
  }) => _write(familyId, () async {
    session = resolveSession(session);
    _checkPeopleScope(familyId, session);
    if (!session.canReadAt(DateTime.now())) {
      throw const ApiException(
        'Phiên đã hết hạn. Hãy mở lại gia phả.',
        status: 401,
      );
    }
    if (!session.canEditAt(DateTime.now())) {
      throw const ApiException('Cần nhập lại mã chỉnh sửa.', status: 403);
    }
    final name = (details['displayName'] as String?)?.trim();
    if (baseVersion < 0 || name == null || name.isEmpty || name.length > 150) {
      throw const ApiException(
        'Họ tên bắt buộc, tối đa 150 ký tự.',
        status: 400,
      );
    }
    final j = await _request(
      'POST',
      '/families/$familyId/people',
      token: session.accessToken,
      body: {
        'baseVersion': baseVersion,
        'details': {...details, 'displayName': name},
      },
    );
    try {
      final version = j['familyVersion'] as int;
      final person = Person.fromJson({
        ...j['person'] as Map<String, dynamic>,
        'familyVersion': version,
      });
      if (j['familyId'] != familyId ||
          person.familyId != familyId ||
          person.id <= 0 ||
          version != baseVersion + 1) {
        throw const FormatException('Invalid created person');
      }
      return person;
    } catch (_) {
      throw const ApiException(
        'Chưa xác nhận được hồ sơ đã tạo. Hãy đối chiếu danh sách, không tạo lại tự động.',
        outcomeUnknown: true,
      );
    }
  });

  Future<Person> updatePerson(
    int familyId,
    int personId,
    AccessSession session, {
    required int baseVersion,
    required Map<String, dynamic> details,
  }) => _write(familyId, () async {
    session = resolveSession(session);
    _checkWrite(familyId, personId, baseVersion, session);
    final j = await _request(
      'PUT',
      '/families/$familyId/people/$personId',
      token: session.accessToken,
      body: {'baseVersion': baseVersion, 'details': details},
    );
    try {
      final version = j['familyVersion'] as int;
      final person = Person.fromJson({
        ...j['person'] as Map<String, dynamic>,
        'familyVersion': version,
      });
      if (j['familyId'] != familyId ||
          person.familyId != familyId ||
          person.id != personId ||
          version < baseVersion ||
          version > baseVersion + 1) {
        throw const FormatException('Invalid update response');
      }
      return person;
    } catch (_) {
      throw const ApiException(
        'Chưa xác nhận được kết quả lưu. Hãy đối chiếu dữ liệu.',
        outcomeUnknown: true,
      );
    }
  });

  Future<int> deletePerson(
    int familyId,
    int personId,
    AccessSession session, {
    required int baseVersion,
  }) => _write(familyId, () async {
    session = resolveSession(session);
    _checkWrite(familyId, personId, baseVersion, session);
    final j = await _request(
      'DELETE',
      '/families/$familyId/people/$personId?baseVersion=$baseVersion',
      token: session.accessToken,
    );
    try {
      final version = j['version'] as int;
      if (j['familyId'] != familyId ||
          j['deletedPersonId'] != personId ||
          version <= baseVersion) {
        throw const FormatException('Invalid delete response');
      }
      return version;
    } catch (_) {
      throw const ApiException(
        'Chưa xác nhận được kết quả xóa. Hãy đối chiếu dữ liệu.',
        outcomeUnknown: true,
      );
    }
  });

  Future<({int version, Map<String, int> ids})> commitGraph(
    int familyId,
    AccessSession session,
    Map<String, dynamic> payload,
  ) => _write(familyId, () async {
    session = resolveSession(session);
    _checkPeopleScope(familyId, session);
    if (!session.canReadAt(DateTime.now())) {
      throw const ApiException('Phiên truy cập đã hết hạn.', status: 401);
    }
    if (!session.canEditAt(DateTime.now())) {
      throw const ApiException('Cần nhập lại mã chỉnh sửa.', status: 403);
    }
    final j = await _request(
      'POST',
      '/families/$familyId/graph/commit',
      token: session.accessToken,
      body: payload,
    );
    try {
      final ids = Map<String, int>.from(j['personIdMap'] as Map);
      final expected = (payload['newPersons'] as List)
          .map((p) => p['tempId'] as String)
          .toSet();
      if (j['familyId'] != familyId ||
          j['requestId'] != payload['requestId'] ||
          j['version'] != (payload['baseVersion'] as int) + 1 ||
          ids.length != expected.length ||
          !ids.keys.toSet().containsAll(expected) ||
          ids.values.any((v) => v <= 0) ||
          ids.values.toSet().length != ids.length) {
        throw const FormatException('Invalid commit response');
      }
      return (version: j['version'] as int, ids: ids);
    } catch (_) {
      throw const ApiException(
        'Chưa xác nhận được kết quả lưu sơ đồ. Không gửi lại lệnh; hãy đối chiếu.',
        outcomeUnknown: true,
      );
    }
  });

  void close() => _client.close();
}

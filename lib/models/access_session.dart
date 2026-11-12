import 'family.dart';

class AccessSession {
  final int familyId;
  final String accessToken;
  final String permission;
  final DateTime expiresAt;
  final DateTime? editExpiresAt;
  const AccessSession({
    required this.familyId,
    required this.accessToken,
    required this.permission,
    required this.expiresAt,
    this.editExpiresAt,
  });
  factory AccessSession.fromJson(Map<String, dynamic> j) {
    final permission = j['permission'] as String;
    final token = j['accessToken'] as String;
    if (!['VIEW', 'EDIT'].contains(permission) || token.isEmpty) {
      throw const FormatException('Invalid session');
    }
    return AccessSession(
      familyId: j['familyId'] as int,
      accessToken: token,
      permission: permission,
      expiresAt: DateTime.parse(j['expiresAt'] as String),
      editExpiresAt: j['editExpiresAt'] == null
          ? null
          : DateTime.parse(j['editExpiresAt'] as String),
    );
  }
  bool canReadAt(DateTime now) => expiresAt.isAfter(now);
  bool canEditAt(DateTime now) =>
      permission == 'EDIT' &&
      canReadAt(now) &&
      editExpiresAt?.isAfter(now) == true;
  Map<String, dynamic> toJson() => {
    'familyId': familyId,
    'accessToken': accessToken,
    'permission': permission,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'editExpiresAt': editExpiresAt?.toUtc().toIso8601String(),
  };
  @override
  String toString() =>
      'AccessSession(familyId: $familyId, permission: $permission, token: REDACTED)';
}

class FamilyAccess {
  final Family family;
  final AccessSession session;
  const FamilyAccess(this.family, this.session);
}

class CreatedFamily extends FamilyAccess {
  final String familyCode;
  final String editCode;
  const CreatedFamily(
    super.family,
    super.session,
    this.familyCode,
    this.editCode,
  );
  @override
  String toString() => 'CreatedFamily(codes: REDACTED)';
}

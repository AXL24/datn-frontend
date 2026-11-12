import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/models/family.dart';
import 'package:gia_pha_app/services/storage_service.dart';

import 'fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real localstore persists metadata, scopes servers, deletes only selected family', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final fixtureServer =
        'http://storage-test-${DateTime.now().microsecondsSinceEpoch}.invalid';
    final stores = [
      StorageService(server: fixtureServer),
      StorageService(server: '$fixtureServer/other'),
    ];
    addTearDown(() async {
      for (final store in stores) {
        final dir = Directory(
          '${Directory.current.path}/families_${store.scope}',
        );
        // Only the unique directories this test owns, directly under test cwd.
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    });
    for (final id in [7, 8]) {
      await stores[0].saveFamily(Family.fromJson(familyJson(id)));
      await stores[0].saveSession(
        AccessSession.fromJson(accessJson(id: id)['session']),
      );
    }
    final reloaded = StorageService(server: fixtureServer);
    expect((await reloaded.getFamilies()).map((f) => f.id).toSet(), {7, 8});
    expect((await reloaded.getSession(7))?.permission, 'VIEW');
    expect(await stores[1].getFamilies(), isEmpty);
    expect(await stores[1].getSession(7), isNull);
    final raw = jsonDecode(
      await File('${Directory.current.path}/families_${stores[0].scope}/7')
          .readAsString(),
    ) as Map;
    expect(raw.keys.toSet(), {'id', 'name', 'lastOpenedAt'});
    await reloaded.removeLocalFamily(7);
    expect((await reloaded.getFamilies()).map((f) => f.id), [8]);
    expect(await reloaded.getSession(7), isNull);
    expect(await reloaded.getSession(8), isNotNull);
  });
  test('localstore write failure reaches caller instead of premature success', () async {
    final store = StorageService(
      server:
          'http://write-failure-${DateTime.now().microsecondsSinceEpoch}.invalid',
    );
    final collision = File('${Directory.current.path}/families_${store.scope}');
    await collision.writeAsString('test fixture preventing directory creation');
    addTearDown(() async {
      if (collision.existsSync()) await collision.delete();
    });
    await expectLater(
      store.saveFamily(Family.fromJson(familyJson())),
      throwsA(isA<FileSystemException>()),
    );
  });
}

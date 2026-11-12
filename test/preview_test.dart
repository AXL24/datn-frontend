import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:gia_pha_app/models/access_session.dart';
import 'package:gia_pha_app/models/family.dart';
import 'package:gia_pha_app/services/api_service.dart';
import 'package:gia_pha_app/views/home_screen.dart';
import 'package:gia_pha_app/views/create_family_screen.dart';
import 'package:gia_pha_app/views/join_family_screen.dart';
import 'package:gia_pha_app/views/family_codes_screen.dart';
import 'package:gia_pha_app/views/family_info_screen.dart';
import 'package:gia_pha_app/views/edit_code_screen.dart';
import 'package:gia_pha_app/app.dart';

import 'fixtures.dart';

import 'package:gia_pha_app/models/person.dart';
import 'package:gia_pha_app/controllers/person_edit_controller.dart';
import 'package:gia_pha_app/views/person_edit_screen.dart';
import 'package:gia_pha_app/views/delete_person_screen.dart';

import 'package:gia_pha_app/views/person_detail_screen.dart';

void main() {
  testWidgets('render twelve screens for visual review', (tester) async {
    final fontPath = Platform.environment['PREVIEW_FONT_PATH'];
    if (fontPath != null) {
      final bytes = await tester.runAsync(() => File(fontPath).readAsBytes());
      await (FontLoader(
        'Preview',
      )..addFont(Future.value(ByteData.sublistView(bytes!)))).load();
    }
    if (fontPath != null) {
      final fontBytes = await tester.runAsync(
        () => File(fontPath).readAsBytes(),
      );
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(fontBytes!)))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = ApiService(
      baseUrl: 'http://test.invalid',
      client: MockClient(
        (r) async => jsonResponse(
          r.url.path.endsWith('/people')
              ? peopleJson(
                  content: [
                    personJson(),
                    personJson(id: 12, name: 'Trần Thị Lan'),
                    personJson(id: 13, name: null),
                  ],
                  total: 3,
                )
              : r.url.path.endsWith('/people/11')
              ? personJson()
              : familyJson(),
        ),
      ),
    );
    addTearDown(api.close);
    final storage = MemoryStorage();
    final family = Family.fromJson(familyJson());
    final session = AccessSession.fromJson(accessJson()['session']);
    await storage.saveSession(session);
    await storage.saveFamily(family);
    final screens = <String, Widget>{
      '01-home': HomeScreen(api: api, storage: storage),
      '02-create': CreateFamilyScreen(api: api, storage: storage),
      '03-join': JoinFamilyScreen(api: api, storage: storage),
      '04-codes': FamilyCodesScreen(
        api: api,
        storage: storage,
        result: CreatedFamily(
          family,
          session,
          'test-only-family-code',
          'test-only-edit-code',
        ),
      ),
      '05-info': FamilyInfoScreen(api: api, storage: storage, familyId: 7),
      '05-edit': FamilyInfoScreen(
        api: api,
        storage: storage,
        familyId: 7,
        initialSession: AccessSession.fromJson(
          accessJson(permission: 'EDIT')['session'],
        ),
      ),
      '07-edit-code': EditCodeScreen(
        api: api,
        storage: storage,
        familyId: 7,
        session: session,
      ),
    };
    screens['09-members'] = FamilyInfoScreen(
      api: api,
      storage: storage,
      familyId: 7,
    );
    screens['10-person'] = PersonDetailScreen(
      api: api,
      storage: storage,
      familyId: 7,
      personId: 11,
    );
    final editSession = AccessSession.fromJson(
      accessJson(permission: 'EDIT')['session'],
    );
    final person = Person.fromJson({...personJson(), 'familyVersion': 0});
    final deleteController = PersonEditController(api, editSession, person);
    addTearDown(deleteController.dispose);
    screens['13-create-person'] = PersonEditScreen.create(
      api: api,
      storage: storage,
      session: editSession,
      baseVersion: 0,
    );
    screens['13-edit-person'] = PersonEditScreen(
      api: api,
      storage: storage,
      person: person,
      session: editSession,
    );
    screens['15-delete-person'] = DeletePersonScreen(
      controller: deleteController,
    );
    for (final entry in screens.entries) {
      tester.view.physicalSize = Size(
        430,
        entry.key.startsWith('13-') ? 1300 : 1100,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('vi'),
            supportedLocales: const [Locale('vi')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildAppTheme(
              fontFamily: fontPath == null ? null : 'Preview',
            ),
            home: entry.value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (entry.key == '05-edit') {
        await tester.tap(find.text('Chỉnh sửa'));
        await tester.pumpAndSettle();
      }
      if (entry.key == '09-members') {
        await tester.tap(find.text('Thành viên'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('test-artifacts/${entry.key}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  }, skip: Platform.environment['GENERATE_PREVIEWS'] != 'true');
}

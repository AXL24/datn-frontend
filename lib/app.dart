import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'views/home_screen.dart';
import 'widgets/app_widgets.dart';

class GiaPhaApp extends StatelessWidget {
  final ApiService api;
  final StorageService storage;
  const GiaPhaApp({super.key, required this.api, required this.storage});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Cây Gia Phả',
    debugShowCheckedModeBanner: false,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildAppTheme(),
    home: HomeScreen(api: api, storage: storage),
  );
}

ThemeData buildAppTheme({String? fontFamily}) => ThemeData(
  fontFamily: fontFamily,
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: forest,
    primary: forest,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: const Color(0xFFF4F9F5),
  appBarTheme: AppBarTheme(
    backgroundColor: Color(0xFFF4F9F5),
    foregroundColor: ink,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      fontFamily: fontFamily,
      color: ink,
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF8FBF9),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFDCE7DF)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFDCE7DF)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
);

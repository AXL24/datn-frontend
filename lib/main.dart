import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = ApiService(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: kIsWeb ? 'http://localhost:8080' : 'http://10.0.2.2:8080',
    ),
  );
  runApp(
    GiaPhaApp(
      api: api,
      storage: StorageService(server: api.baseUrl),
    ),
  );
}

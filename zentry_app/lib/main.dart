import 'package:flutter/material.dart';
import 'zentry_api_service.dart';
import 'zentry_login.dart';
import 'zentry_normal.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ZentryApiService.restoreSession();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
home: !ZentryApiService.isLoggedIn
    ? const ZentryLogin()
    : ZentryApiService.account?['must_change_password'] == true
        ? const ZentryLogin()
        : const ZentryNormal(),
    );
  }
}
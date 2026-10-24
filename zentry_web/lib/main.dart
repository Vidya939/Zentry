
import 'package:flutter/material.dart';

import 'web_api_service.dart';
import 'web_home.dart';
import 'web_login.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SessionGate(),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  late final Future<bool> _sessionFuture = _restoreSession();

  Future<bool> _restoreSession() async {
    try {
      await WebApiService.restoreSession();

      if (WebApiService.accessToken == null ||
          WebApiService.accessToken!.isEmpty) {
        return false;
      }

      // Validate the saved token against the backend.
      await WebApiService.getOfficerProfile();
      return true;
    } catch (_) {
      await WebApiService.logout();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _sessionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.data == true) {
          return const WebHome();
        }

        return const WebLogin();
      },
    );
  }
}

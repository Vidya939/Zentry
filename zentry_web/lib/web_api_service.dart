import 'dart:convert';

import 'package:http/http.dart' as http;

class WebApiService {
  // Local development URL.
  // Change this when you deploy your backend.
  static const String baseUrl = 'http://127.0.0.1:8000';

  // Holds the logged-in officer's token for the current app session.
  static String? accessToken;

  static Map<String, String> get authHeaders {
    final token = accessToken;

    if (token == null || token.isEmpty) {
      throw Exception('Please log in first.');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> officerLogin({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/officer/login');

    final http.Response response;

    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw Exception(
        'Cannot connect to Zentry server. Check that the backend is running.',
      );
    }

    Map<String, dynamic> data;

    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('The server returned an invalid response.');
    }

    if (response.statusCode == 200) {
      final token = data['access_token'];

      if (token is! String || token.isEmpty) {
        throw Exception('The server did not return an access token.');
      }

      accessToken = token;
      return data;
    }

    if (response.statusCode == 401) {
      throw Exception('Invalid email or password.');
    }

    if (response.statusCode == 403) {
      throw Exception(
        'Access denied. Verify your email and account permissions.',
      );
    }

    throw Exception(
      data['detail']?.toString() ?? 'Login failed. Please try again.',
    );
  }

  static void logout() {
    accessToken = null;
  }
}
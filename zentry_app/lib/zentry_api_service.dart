import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ZentryApiService {
  static Future<Map<String, dynamic>?> getLastDrill() async {
  final endpoint = isVisitor
      ? '/incidents/last-drill/visitor'
      : '/incidents/last-drill/employee';

  final response = await http
      .get(
        Uri.parse('$baseUrl$endpoint'),
        headers: authHeaders,
      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(_errorMessage(response));
  }

  if (response.statusCode == 204 || response.body.trim().isEmpty) {
    return null;
  }

  final decoded = jsonDecode(response.body);

  if (decoded == null) return null;

  if (decoded is Map<String, dynamic>) {
    return decoded;
  }

  throw Exception('Invalid last-drill response from server.');
}


  // Must point to the active tunnel forwarding to your FastAPI backend.
static const String baseUrl =
    'https://lives-cheaper-hello-perform.trycloudflare.com';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _tokenKey = 'zentry_access_token';
  static const String _accountKey = 'zentry_account';

  static String? accessToken;
  static Map<String, dynamic>? account;

  static bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;

  static bool get isVisitor =>
      account?['account_type']?.toString().toLowerCase() == 'visitor';

  static Map<String, String> get authHeaders {
    final token = accessToken;

    if (token == null || token.isEmpty) {
      throw Exception('Please log in again.');
    }

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // A useful exception is raised below.
    }

    throw Exception(
      'The server returned an invalid response (${response.statusCode}).',
    );
  }

  static String _errorMessage(http.Response response) {
    try {
      final data = jsonDecode(response.body);

      if (data is Map && data['detail'] != null) {
        final detail = data['detail'];

        if (detail is String) return detail;

        if (detail is List) {
          return detail
              .map(
                (item) => item is Map
                    ? item['msg']?.toString() ?? item.toString()
                    : item.toString(),
              )
              .join('\n');
        }

        return detail.toString();
      }
    } catch (_) {
      // Use the fallback message for non-JSON responses.
    }

    return 'Server request failed (${response.statusCode}).';
  }

  static Future<Map<String, dynamic>> _postJson({
    required String path,
    required Map<String, dynamic> body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers:
              headers ??
              const {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(response));
    }

    return _decodeObject(response);
  }

  static Future<Map<String, dynamic>> _saveAuthenticatedAccount(
    Map<String, dynamic> result, {
    required String accountType,
  }) async {
    final token = result['access_token']?.toString();
    final rawAccount = result['account'];

    if (token == null || token.isEmpty) {
      throw Exception('The server did not return an access token.');
    }

    if (rawAccount is! Map) {
      throw Exception('The server did not return account details.');
    }

    final returnedAccount = Map<String, dynamic>.from(rawAccount);
    returnedAccount['account_type'] ??= accountType;

    returnedAccount['must_change_password'] ??=
        result['must_change_password'] ?? false;

    // Persist the session securely before marking login complete.
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _accountKey, value: jsonEncode(returnedAccount));

    accessToken = token;
    account = returnedAccount;

    return returnedAccount;
  }

  // --------------------------------------------------
  // EMPLOYEE LOGIN
  // --------------------------------------------------

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final result = await _postJson(
      path: '/auth/employee/login',
      body: {'email': email.trim().toLowerCase(), 'password': password},
      timeout: const Duration(seconds: 45),
    );

    await _saveAuthenticatedAccount(result, accountType: 'employee');
    return result;
  }

  // --------------------------------------------------
  // VISITOR REGISTRATION
  // --------------------------------------------------

  static Future<Map<String, dynamic>> registerVisitor({
    required String fullName,
    required String email,
  }) async {
    final result = await _postJson(
      path: '/auth/visitor/register',
      body: {'full_name': fullName.trim(), 'email': email.trim().toLowerCase()},
      timeout: const Duration(seconds: 30),
    );

    final vrfId = result['vrf_id']?.toString();

    if (vrfId == null || vrfId.isEmpty) {
      throw Exception('The server did not return a visitor VRF ID.');
    }

    return result;
  }

  // --------------------------------------------------
  // VERIFY VISITOR REGISTRATION EMAIL OTP
  // --------------------------------------------------

  static Future<Map<String, dynamic>> verifyVisitorEmail({
    required String vrfId,
    required String email,
    required String otp,
  }) async {
    final result = await _postJson(
      path: '/auth/visitor/verify-email',
      body: {
        'vrf_id': vrfId.trim().toUpperCase(),
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
      },
    );

    await _saveAuthenticatedAccount(result, accountType: 'visitor');
    return result;
  }

  // --------------------------------------------------
  // REQUEST OTP FOR AN EXISTING VISITOR
  // --------------------------------------------------

  static Future<Map<String, dynamic>> requestVisitorLoginOtp({
    required String email,
  }) {
    return _postJson(
      path: '/auth/visitor/login/request-otp',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  // --------------------------------------------------
  // VERIFY EXISTING VISITOR LOGIN OTP
  // --------------------------------------------------

  static Future<Map<String, dynamic>> verifyVisitorLoginOtp({
    required String email,
    required String otp,
  }) async {
    final result = await _postJson(
      path: '/auth/visitor/login/verify-otp',
      body: {'email': email.trim().toLowerCase(), 'otp': otp.trim()},
    );

    await _saveAuthenticatedAccount(result, accountType: 'visitor');
    return result;
  }

  // --------------------------------------------------
  // SUBMIT SAFETY RESPONSE: EMPLOYEE OR VISITOR
  // --------------------------------------------------

  // --------------------------------------------------
  // SUBMIT SAFETY RESPONSE: EMPLOYEE OR VISITOR
  // --------------------------------------------------

  static Future<Map<String, dynamic>> submitResponse({
    required int incidentId,
    required String status,
    String? message,
    String? locationDetails,
    String? conditionStatus,
    String? evacuationStatus,
  }) async {
    final endpoint = isVisitor ? 'visitor-responses' : 'responses';

    final body = <String, dynamic>{'response_status': status};

    if (message != null) {
      body['message'] = message;
    }

    // Location must be saved for both employees and visitors.
    if (locationDetails != null) {
      body['location_details'] = locationDetails;
    }

    if (conditionStatus != null) {
      body['condition_status'] = conditionStatus;
    }

    if (evacuationStatus != null) {
      body['evacuation_status'] = evacuationStatus;
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/incidents/$incidentId/$endpoint'),
          headers: authHeaders,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_errorMessage(response));
    }

    return _decodeObject(response);
  }


  // --------------------------------------------------
  // EMPLOYEE FORGOT PASSWORD: REQUEST EMAIL OTP
  // --------------------------------------------------

  static Future<Map<String, dynamic>> requestEmployeePasswordReset({
    required String email,
  }) {
    return _postJson(
      path: '/auth/employee/password-reset/request',
      body: {
        'email': email.trim().toLowerCase(),
      },
      timeout: const Duration(seconds: 30),
    );
  }

  // --------------------------------------------------
  // EMPLOYEE FORGOT PASSWORD: VERIFY OTP AND RESET
  // --------------------------------------------------

  static Future<Map<String, dynamic>> verifyEmployeePasswordReset({
    required String email,
    required String otp,
    required String newPassword,
  }) {
    return _postJson(
      path: '/auth/employee/password-reset/verify',
      body: {
        'email': email.trim().toLowerCase(),
        'otp': otp.trim(),
        'new_password': newPassword,
      },
      timeout: const Duration(seconds: 30),
    );
  }


  // --------------------------------------------------
  // CHANGE EMPLOYEE PASSWORD
  // --------------------------------------------------

  static Future<Map<String, dynamic>> changeEmployeePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (isVisitor) {
      throw Exception('Only employees can change their password here.');
    }

    final result = await _postJson(
      path: '/auth/employee/change-password',
      headers: authHeaders,
      body: {'current_password': currentPassword, 'new_password': newPassword},
      timeout: const Duration(seconds: 20),
    );

    if (result['password_reset_required'] == true) {
      throw Exception('The server has not confirmed the password change.');
    }

    return result;
  }

  // --------------------------------------------------
  // LOGOUT
  // --------------------------------------------------

  // --------------------------------------------------
  // RESTORE SAVED SESSION
  // --------------------------------------------------

  static Future<bool> restoreSession() async {
    try {
      final savedToken = await _storage.read(key: _tokenKey);
      final savedAccount = await _storage.read(key: _accountKey);

      if (savedToken == null || savedToken.isEmpty || savedAccount == null) {
        await logout();
        return false;
      }

      final decoded = jsonDecode(savedAccount);

      if (decoded is! Map) {
        await logout();
        return false;
      }

      final restoredAccount = Map<String, dynamic>.from(decoded);

      // Enforce the visitor's nine-hour expiry locally when
      // the backend provides expires_at in the account response.
      if (restoredAccount['account_type']?.toString().toLowerCase() ==
          'visitor') {
        final expiryValue = restoredAccount['expires_at'];

        if (expiryValue != null) {
          final expiry = DateTime.tryParse(expiryValue.toString());

          if (expiry == null ||
              !DateTime.now().toUtc().isBefore(expiry.toUtc())) {
            await logout();
            return false;
          }
        }
      }

      accessToken = savedToken;
      account = restoredAccount;

      return true;
    } catch (_) {
      await logout();
      return false;
    }
  }

  // --------------------------------------------------
  // LOGOUT
  // --------------------------------------------------
static Future<void> logout() async {
  await _storage.delete(key: 'zentry_access_token');
  await _storage.delete(key: 'zentry_account');

  accessToken = null;
  account = null;
}
  // static Future<void> logout() async {
  //   accessToken = null;
  //   account = null;

  //   await _storage.delete(key: _tokenKey);
  //   await _storage.delete(key: _accountKey);
  // }
}

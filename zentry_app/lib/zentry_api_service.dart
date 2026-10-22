
import 'dart:convert';
import 'package:http/http.dart' as http;

class ZentryApiService {
  // Android emulator. A physical phone needs your computer's LAN IP.
  static const String baseUrl = 'http://10.0.2.2:8000';

  static String? accessToken;
  static Map<String, dynamic>? account;

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

  static String _errorMessage(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['detail'] != null) {
        return data['detail'].toString();
      }
    } catch (_) {
      // Use the fallback message for non-JSON responses.
    }
    return 'Server request failed (${response.statusCode}).';
  }

  // --------------------------------------------------
  // EMPLOYEE LOGIN
  // --------------------------------------------------

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/employee/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim().toLowerCase(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }

    final result = Map<String, dynamic>.from(
      jsonDecode(response.body) as Map,
    );
    final returnedAccount = Map<String, dynamic>.from(
      result['account'] as Map,
    );
    final token = result['access_token']?.toString();

    if (token == null || token.isEmpty) {
      throw Exception('The server did not return a login token.');
    }

    accessToken = token;
    account = returnedAccount;

    return result;
  }

  // --------------------------------------------------
  // VISITOR REGISTRATION
  // --------------------------------------------------

  static Future<Map<String, dynamic>> registerVisitor({
    required String fullName,
    required String email,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/visitor/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'full_name': fullName.trim(),
            'email': email.trim().toLowerCase(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 201) {
      throw Exception(_errorMessage(response));
    }

    return Map<String, dynamic>.from(
      jsonDecode(response.body) as Map,
    );
  }

  // --------------------------------------------------
  // VISITOR EMAIL OTP VERIFICATION
  // --------------------------------------------------

  static Future<Map<String, dynamic>> verifyVisitorEmail({
    required String vrfId,
    required String email,
    required String otp,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/visitor/verify-email'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'vrf_id': vrfId.trim().toUpperCase(),
            'email': email.trim().toLowerCase(),
            'otp': otp.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }

    final result = Map<String, dynamic>.from(
      jsonDecode(response.body) as Map,
    );
    final token = result['access_token']?.toString();
    final returnedAccount = Map<String, dynamic>.from(
      result['account'] as Map,
    );

    if (token == null || token.isEmpty) {
      throw Exception('The server did not return a visitor access token.');
    }

    // Preserve visitor identity so safety responses use the visitor endpoint.
    accessToken = token;
    account = returnedAccount;

    return result;
  }

  // --------------------------------------------------
  // SUBMIT SAFETY RESPONSE: EMPLOYEE OR VISITOR
  // --------------------------------------------------

  static Future<Map<String, dynamic>> submitResponse({
    required int incidentId,
    required String status,
    String? message,
    String? locationDetails,
  }) async {
    final isVisitor =
        account?['account_type']?.toString().toLowerCase() == 'visitor';

    final endpoint = isVisitor
        ? 'visitor-responses'
        : 'responses';

    final body = <String, dynamic>{
      'response_status': status,
      'message': message,
    };

    if (isVisitor) {
      body['location_details'] = locationDetails;
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/incidents/$incidentId/$endpoint'),
          headers: authHeaders,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response));
    }

    return Map<String, dynamic>.from(
      jsonDecode(response.body) as Map,
    );
  }

  static void logout() {
    accessToken = null;
    account = null;
  }
}

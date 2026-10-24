import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WebApiService {
  WebApiService._();
  static const String _tokenKey = 'zentry_officer_token';
  static const String baseUrl =
      'https://subsection-bikes-remembered-swaziland.trycloudflare.com';

  static String? accessToken;

  static Map<String, String> get authHeaders {
    final token = accessToken;

    if (token == null || token.isEmpty) {
      throw Exception('Your session has expired. Please log in again.');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Uri _uri(String path, [Map<String, String>? queryParameters]) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParameters);
  }

  static dynamic _decode(http.Response response) {
    dynamic result;

    try {
      result = response.body.isEmpty ? {} : jsonDecode(response.body);
    } catch (_) {
      result = {'detail': response.body};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic detail;

      if (result is Map) {
        detail = result['detail'] ?? result['message'];
      }

      if (detail is Map) {
        detail = detail['message'] ?? jsonEncode(detail);
      }

      throw Exception(
        detail?.toString() ??
            'Request failed with status ${response.statusCode}.',
      );
    }

    return result;
  }

  static Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final response = await http.get(
      _uri(path, queryParameters),
      headers: authHeaders,
    );
    return _decode(response);
  }

  static Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final response = await http.post(
      _uri(path),
      headers: authHeaders,
      body: jsonEncode(body ?? <String, dynamic>{}),
    );
    return _decode(response);
  }

  static Future<dynamic> patch(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final response = await http.patch(
      _uri(path),
      headers: authHeaders,
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  static Future<Map<String, dynamic>> officerLogin({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      _uri('/auth/officer/login'),
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );

    final result = _decode(response);

    if (result is! Map<String, dynamic>) {
      throw Exception('The server returned an invalid login response.');
    }

    final token = result['access_token']?.toString();

    if (token == null || token.isEmpty) {
      throw Exception('The server did not return an access token.');
    }

    accessToken = token;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);

    return result;
  }

  static Future<Map<String, dynamic>> getOfficerProfile() async {
    final result = await get('/auth/officer/me');
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> updateOfficerProfile({
    required String fullName,
    required String location,
  }) async {
    final result = await patch(
      '/auth/officer/profile',
      body: {
        'full_name': fullName.trim(),
        'location': location.trim().isEmpty ? null : location.trim(),
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }

  static Future<List<Map<String, dynamic>>> getEmployees() async {
    final result = await get('/auth/officers/employees');
    final list = result is Map ? result['employees'] : result;

    if (list is! List) return [];

    return list
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> createEmployee({
    required String employeeCode,
    required String fullName,
    required String email,
  }) async {
    final result = await post(
      '/auth/officers/employees',
      body: {
        'employee_code': employeeCode.trim(),
        'full_name': fullName.trim(),
        'email': email.trim(),
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> updateEmployee({
    required int id,
    required String employeeCode,
    required String fullName,
    required String email,
  }) async {
    final result = await patch(
      '/auth/officers/employees/$id',
      body: {
        'employee_code': employeeCode.trim(),
        'full_name': fullName.trim(),
        'email': email.trim(),
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> setEmployeeStatus({
    required int id,
    required bool isActive,
  }) async {
    final result = await patch(
      '/auth/officers/employees/$id/status',
      body: {'is_active': isActive},
    );

    return Map<String, dynamic>.from(result as Map);
  }

  static Future<List<Map<String, dynamic>>> getVisitors() async {
    final result = await get('/auth/officers/visitors');
    final list = result is Map ? result['visitors'] : result;

    if (list is! List) return [];

    return list
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> setVisitorStatus({
    required int id,
    required bool isActive,
  }) async {
    final result = await patch(
      '/auth/officers/visitors/$id/status',
      body: {'is_active': isActive},
    );

    return Map<String, dynamic>.from(result as Map);
  }

  static Future<List<Map<String, dynamic>>> getIncidents({
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final query = <String, String>{};

    String dateString(DateTime value) {
      final month = value.month.toString().padLeft(2, '0');
      final day = value.day.toString().padLeft(2, '0');
      return '${value.year}-$month-$day';
    }

    if (fromDate != null) query['from_date'] = dateString(fromDate);
    if (toDate != null) query['to_date'] = dateString(toDate);

    final result = await get(
      '/incidents',
      queryParameters: query.isEmpty ? null : query,
    );

    if (result is! List) return [];

    return result
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getActiveIncidents() async {
    final result = await get('/incidents/active');

    if (result is! List) return [];

    return result
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> createIncident({
    required String title,
    required String message,
    required String location,
  }) async {
    final result = await post(
      '/incidents',
      body: {
        'title': title.trim(),
        'message': message.trim(),
        'location': location.trim(),
      },
    );

    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> getIncidentSummary(int id) async {
    final result = await get('/incidents/$id/summary');
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> getIncidentPeople(int id) async {
    final result = await get('/incidents/$id/people');
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<List<Map<String, dynamic>>> getIncidentResponses(int id) async {
    final result = await get('/incidents/$id/responses');

    if (result is! List) return [];

    return result
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Map<String, dynamic>> dispatchWarden({
    required int incidentId,
    required String accountType,
    required int personId,
  }) async {
    final result = await post(
      '/incidents/$incidentId/people/$accountType/$personId/dispatch',
    );

    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> markLocated({
    required int incidentId,
    required String accountType,
    required int personId,
  }) async {
    final result = await post(
      '/incidents/$incidentId/people/$accountType/$personId/located',
    );

    return Map<String, dynamic>.from(result as Map);
  }

  static Future<Map<String, dynamic>> clearIncident(int id) async {
    final result = await post('/incidents/$id/clear');
    return Map<String, dynamic>.from(result as Map);
  }

  static Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString(_tokenKey);
  }

  static Future<void> logout() async {
    accessToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}

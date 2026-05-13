import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class ApiService {
  static const _keyToken = 'auth_token';

  // ── URL de base ────────────────────────────────────────────────────────────

  static String _base() {
    final clean = AppConfig.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$clean/api/v1';
  }

  // ── Token ──────────────────────────────────────────────────────────────────

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
  }

  // ── Requête générique ──────────────────────────────────────────────────────

  static Future<dynamic> request(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final base = _base();
    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('$base$endpoint');
    http.Response response;

    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
        case 'POST':
          response = await http
              .post(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
        case 'PUT':
          response = await http
              .put(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(const Duration(seconds: 15));
        case 'DELETE':
          response = await http
              .delete(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
        default:
          throw ApiException('Méthode HTTP non supportée : $method');
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        'Impossible de joindre le serveur. Vérifiez l\'URL et votre connexion réseau.',
      );
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json;
    }

    final message = (json is Map && json['message'] != null)
        ? json['message'] as String
        : 'Erreur ${response.statusCode}';
    throw ApiException(message, statusCode: response.statusCode);
  }

  // ── Authentification ───────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(
      String email, String password) async {
    final data = await request('POST', '/auth/login', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;
    return data;
  }

  static Future<void> logout() async {
    try {
      await request('POST', '/auth/logout');
    } catch (_) {}
    await clearToken();
  }

  // ── Sites ──────────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getSites() async {
    return await request('GET', '/sites') as List<dynamic>;
  }

  static Future<Map<String, dynamic>> createSite(
      Map<String, dynamic> payload) async {
    return await request('POST', '/sites', body: payload)
        as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateSite(
      int id, Map<String, dynamic> payload) async {
    return await request('PUT', '/sites/$id', body: payload)
        as Map<String, dynamic>;
  }

  // ── Device binding ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> checkDevice(
      int siteId, String deviceId) async {
    return await request('GET',
            '/sites/$siteId/check-device?device_id=${Uri.encodeComponent(deviceId)}')
        as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> bindDevice(
      int siteId, String deviceId, String deviceLabel,
      {bool force = false}) async {
    return await request('POST', '/sites/$siteId/bind-device', body: {
      'device_id': deviceId,
      'device_label': deviceLabel,
      'force': force,
    }) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> unbindDevice(int siteId) async {
    return await request('POST', '/sites/$siteId/unbind-device')
        as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> deleteSite(int id) async {
    return await request('DELETE', '/sites/$id') as Map<String, dynamic>;
  }

  // ── Annonces ──────────────────────────────────────────────────────────────

  static Future<List<dynamic>> getAnnouncements() async =>
      await request('GET', '/announcements') as List<dynamic>;
}

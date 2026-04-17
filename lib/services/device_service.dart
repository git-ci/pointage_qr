import 'dart:io';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  static const _keyDeviceId = 'device_id';
  static const _keySiteJson = 'terminal_site_json';

  // ── Identifiant unique stable de l'appareil ───────────────────────────────
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_keyDeviceId);
    if (id != null && id.isNotEmpty) return id;

    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        id = android.id;
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        id = ios.identifierForVendor ?? '';
      }
    } catch (_) {
      id = '';
    }

    if (id == null || id.isEmpty) {
      id = _generateUuid();
    }

    await prefs.setString(_keyDeviceId, id);
    return id;
  }

  // ── Infos lisibles de l'appareil ─────────────────────────────────────────
  static Future<Map<String, String>> getDeviceInfo() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return {
          'model': android.model,
          'brand': android.brand,
          'id': android.id,
          'os': 'Android ${android.version.release}',
        };
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return {
          'model': ios.model,
          'name': ios.name,
          'id': ios.identifierForVendor ?? '',
          'os': 'iOS ${ios.systemVersion}',
        };
      }
    } catch (_) {}
    return {'model': 'Appareil inconnu', 'id': await getDeviceId()};
  }

  // ── Persistance du site configuré (JSON standard) ─────────────────────────
  static Future<void> saveTerminalSite(Map<String, dynamic> siteJson) async {
    final prefs = await SharedPreferences.getInstance();
    // Utiliser jsonEncode — fiable, pas de problème d'échappement
    await prefs.setString(_keySiteJson, jsonEncode(siteJson));
  }

  static Future<Map<String, dynamic>?> getTerminalSite() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySiteJson);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearTerminalSite() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySiteJson);
  }

  // ── UUID simple ───────────────────────────────────────────────────────────
  static String _generateUuid() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = now ^ (now >> 16);
    return 'dev-${rand.toRadixString(16).padLeft(12, '0')}';
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'constants.dart';

class VersionInfo {
  final String currentVersion;
  final String latestVersion;
  final String minSupportedVersion;
  final bool forceUpdate;
  final String message;
  final String downloadUrl;
  final bool updateAvailable;
  final bool updateRequired;

  VersionInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.forceUpdate,
    required this.message,
    required this.downloadUrl,
    required this.updateAvailable,
    required this.updateRequired,
  });
}

class VersionChecker {
  // Verifica si hay version nueva consultando el JSON remoto.
  // Si el JSON no existe o falla, devuelve null (la app sigue normal).
  static Future<VersionInfo?> check() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http
          .get(Uri.parse(versionCheckUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = data['latest_version']?.toString() ?? currentVersion;
      final minSupported =
          data['min_supported_version']?.toString() ?? currentVersion;
      final forceUpdate = data['force_update'] == true;
      final message = data['message']?.toString() ?? '';
      final downloadUrl = data['download_url']?.toString() ?? '';

      final updateAvailable = _compareVersions(currentVersion, latest) < 0;
      final belowMinSupported =
          _compareVersions(currentVersion, minSupported) < 0;
      final updateRequired = belowMinSupported || (forceUpdate && updateAvailable);

      return VersionInfo(
        currentVersion: currentVersion,
        latestVersion: latest,
        minSupportedVersion: minSupported,
        forceUpdate: forceUpdate,
        message: message,
        downloadUrl: downloadUrl,
        updateAvailable: updateAvailable,
        updateRequired: updateRequired,
      );
    } catch (_) {
      return null;
    }
  }

  // Compara dos versiones tipo "1.2.3"
  // Devuelve < 0 si a es menor, 0 si igual, > 0 si a es mayor.
  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final bParts = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
    while (aParts.length < maxLen) {
      aParts.add(0);
    }
    while (bParts.length < maxLen) {
      bParts.add(0);
    }
    for (var i = 0; i < maxLen; i++) {
      if (aParts[i] != bParts[i]) return aParts[i] - bParts[i];
    }
    return 0;
  }
}
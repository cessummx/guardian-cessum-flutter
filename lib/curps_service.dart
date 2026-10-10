import 'dart:convert';

import 'package:http/http.dart' as http;

/// V425: lee el mapa VIVO de CURPs desde el Guardián
/// (guardian.php?accion=curps_map), que fusiona la hoja 'CURPs' (capa viva,
/// gana) con curps.json (semilla). Así una CURP capturada o corregida dentro
/// de la app se refleja sin resubir ningún archivo. Devuelve {curps:{mat:CURP}}.
///
/// Formato esperado de curps.json (cualquiera de los dos sirve):
///   { "24020131": "AACK980909MSRLSR06", "24020132": "PASD010818MSRRTNA4" }
/// o
///   { "curps": { "24020131": "AACK980909MSRLSR06", ... } }
///
/// El archivo se sube por File Manager a la MISMA carpeta donde está
/// alumnos.json. URL pública: https://app.cessum.mx/curps.json
const String curpsJsonUrl =
    'https://app.cessum.mx/guardian.php?accion=curps_map';

class CurpsService {
  static Map<String, String>? _porMatricula;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 10);

  static Future<void> _asegurarCargada({bool forzar = false}) async {
    final ahora = DateTime.now();
    final valido = _porMatricula != null &&
        _cacheTime != null &&
        ahora.difference(_cacheTime!) < _cacheDuration;
    if (!forzar && valido) return;

    try {
      final resp = await http
          .get(Uri.parse(curpsJsonUrl))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        _porMatricula ??= {};
        return;
      }
      final raw = jsonDecode(utf8.decode(resp.bodyBytes));
      Map<String, dynamic> obj = {};
      if (raw is Map<String, dynamic>) {
        if (raw['curps'] is Map) {
          obj = (raw['curps'] as Map).cast<String, dynamic>();
        } else {
          obj = raw;
        }
      }
      final mapa = <String, String>{};
      obj.forEach((k, v) {
        final curp = (v ?? '').toString().trim().toUpperCase();
        final mat = k.trim();
        if (mat.isNotEmpty && curp.isNotEmpty && curp != '—' && curp != 'N/A') {
          mapa[mat] = curp;
        }
      });
      _porMatricula = mapa;
      _cacheTime = ahora;
    } catch (_) {
      _porMatricula ??= {};
    }
  }

  /// Devuelve la CURP del alumno o '' si no se encuentra.
  static Future<String> curpDe(String matricula) async {
    final mat = matricula.trim();
    if (mat.isEmpty) return '';
    await _asegurarCargada();
    return _porMatricula?[mat] ?? '';
  }
}

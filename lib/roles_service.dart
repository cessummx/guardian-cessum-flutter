import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Cachea los roles de administración asignados dinámicamente (hoja 'Roles
/// admin' del Guardián). Funciona como red: si el Guardián no responde, se
/// usa el último cache local; y la lista fija de admin_config sigue valiendo
/// siempre como base, así nadie se queda sin acceso.
class RolesService {
  static Map<String, String> _roles = {}; // correo -> rol
  static const String _key = 'roles_admin_cache_v1';

  /// Descarga los roles desde el Guardián y los cachea en memoria y disco.
  /// Se llama al arrancar la app, antes de evaluar quién es administrador.
  static Future<void> precargar() async {
    // 1) Cargar primero lo último guardado en disco (sirve sin conexión).
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _roles = m.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}

    // 2) Intentar refrescar desde el servidor.
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=roles_listar'))
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = (data['roles'] as List?) ?? [];
        final m = <String, String>{};
        for (final r in lista) {
          final mr = Map<String, dynamic>.from(r as Map);
          final c = (mr['correo'] ?? '').toString().trim().toLowerCase();
          final rol = (mr['rol'] ?? '').toString().trim();
          if (c.isNotEmpty && rol.isNotEmpty) m[c] = rol;
        }
        _roles = m;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_key, jsonEncode(m));
      }
    } catch (_) {
      // Sin conexión o error: nos quedamos con el cache que ya había.
    }
  }

  /// Rol dinámico de un correo, o null si no tiene uno asignado.
  static String? rolDinamico(String? correo) {
    if (correo == null) return null;
    final c = correo.trim().toLowerCase();
    final r = _roles[c];
    if (r == null || r.isEmpty) return null;
    return r;
  }
}

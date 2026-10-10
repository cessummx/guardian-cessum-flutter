import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda en el navegador que el usuario ya pasó el portón, para no
/// pedir login en cada recarga.
///
/// (9-oct-2026) SESIÓN DESLIZANTE. La sesión local duraba 12 horas fijas
/// desde el login: quien dejaba la pestaña abierta de un día para otro seguía
/// viendo el menú, pero cada pantalla fallaba por su lado («Inicia sesión de
/// nuevo», «Falta el correo del docente») porque [realEmail] ya devolvía null,
/// mientras la sesión del proxy seguía viva. Ahora la sesión dura [_maxDias]
/// días SIN USO: cada uso dentro del plazo la renueva (a lo más una vez por
/// hora, para no escribir en cada llamada). Solo caduca quien no abre la app
/// en [_maxDias] días; para cambiar el plazo basta con mover esa constante.
///
/// Además gestiona el modo "Ver como profesor" (suplantación de solo lectura):
/// cuando un administrador lo activa, [validEmail] devuelve el correo del
/// profesor elegido, de modo que TODA la app carga los datos de ese profesor.
class SessionStore {
  static const String _emailKey = 'cessum_auth_email';
  static const String _nameKey = 'cessum_auth_name';
  static const String _tsKey = 'cessum_auth_ts';

  /// Días sin uso tras los cuales se pide entrar de nuevo.
  static const int _maxDias = 30;
  static const int _maxMs = _maxDias * 24 * 3600 * 1000;

  /// Cada cuánto se renueva la marca de tiempo mientras la sesión se usa.
  static const int _renovarCadaMs = 3600 * 1000;

  // ===== Modo "Ver como profesor" =====
  static const String _impEmailKey = 'cessum_impersonate_email';
  static const String _impNameKey = 'cessum_impersonate_name';

  /// Correo del profesor suplantado (null = no hay suplantación activa).
  /// El banner global escucha este valor para aparecer/desaparecer al vuelo.
  static final ValueNotifier<String?> impersonation =
      ValueNotifier<String?>(null);

  /// Restaura, al arrancar la app, una suplantación que hubiera quedado activa
  /// de una sesión anterior (por ejemplo, tras recargar la página).
  /// Llamar en main() antes de runApp.
  static Future<void> loadImpersonation() async {
    try {
      final p = await SharedPreferences.getInstance();
      final imp = p.getString(_impEmailKey);
      impersonation.value = (imp != null && imp.trim().isNotEmpty)
          ? imp.trim().toLowerCase()
          : null;
    } catch (_) {
      impersonation.value = null;
    }
  }

  /// true si en este momento se está viendo la app como otro profesor.
  static bool get isImpersonating =>
      impersonation.value != null && impersonation.value!.isNotEmpty;

  /// Nombre legible del profesor suplantado (para el banner), o null.
  static Future<String?> impersonatedName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_impNameKey);
  }

  /// Entra al modo "Ver como profesor": de aquí en adelante [validEmail]
  /// devolverá [email], así que toda la app cargará los datos de ese profesor.
  static Future<void> startImpersonation(String email, {String? nombre}) async {
    final e = email.trim().toLowerCase();
    final p = await SharedPreferences.getInstance();
    await p.setString(_impEmailKey, e);
    if (nombre != null && nombre.trim().isNotEmpty) {
      await p.setString(_impNameKey, nombre.trim());
    } else {
      await p.remove(_impNameKey);
    }
    impersonation.value = e;
  }

  /// Sale del modo "Ver como profesor" y vuelve a tu identidad real.
  static Future<void> stopImpersonation() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_impEmailKey);
    await p.remove(_impNameKey);
    impersonation.value = null;
  }

  static Future<void> save(String email, String? name) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_emailKey, email);
    if (name != null) await p.setString(_nameKey, name);
    await p.setInt(_tsKey, DateTime.now().millisecondsSinceEpoch);
    // Un inicio de sesión real siempre cancela cualquier suplantación previa.
    await p.remove(_impEmailKey);
    await p.remove(_impNameKey);
    impersonation.value = null;
  }

  /// Correo EFECTIVO de la app. Si hay modo "Ver como profesor" activo,
  /// devuelve el correo del profesor suplantado; si no, tu correo real.
  static Future<String?> validEmail() async {
    final imp = impersonation.value;
    if (imp != null && imp.isNotEmpty) return imp;
    return realEmail();
  }

  /// Tu correo REAL (de administrador), ignorando la suplantación. Úsalo solo
  /// para decidir si mostrar el selector "Ver como profesor" y el banner.
  ///
  /// Cada lectura dentro del plazo renueva la sesión (deslizante); pasado
  /// [_maxDias] días sin uso, se limpia y se devuelve null.
  static Future<String?> realEmail() async {
    final p = await SharedPreferences.getInstance();
    final email = p.getString(_emailKey);
    final ts = p.getInt(_tsKey);
    if (email == null || ts == null) return null;

    final ahora = DateTime.now().millisecondsSinceEpoch;
    final edadMs = ahora - ts;
    if (edadMs > _maxMs) {
      await clear();
      return null;
    }
    // Sesión deslizante: el uso la renueva, a lo más una vez por hora.
    if (edadMs > _renovarCadaMs) {
      try {
        await p.setInt(_tsKey, ahora);
      } catch (_) {}
    }
    return email;
  }

  /// Cuántos días lleva sin renovarse la sesión guardada (0 si no hay sesión).
  /// Para diagnóstico: una pantalla «Acerca de» puede mostrarlo.
  static Future<int> diasSinUso() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ts = p.getInt(_tsKey);
      if (ts == null) return 0;
      final edadMs = DateTime.now().millisecondsSinceEpoch - ts;
      return edadMs <= 0 ? 0 : edadMs ~/ (24 * 3600 * 1000);
    } catch (_) {
      return 0;
    }
  }

  static Future<String?> name() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_nameKey);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_emailKey);
    await p.remove(_nameKey);
    await p.remove(_tsKey);
    await p.remove(_impEmailKey);
    await p.remove(_impNameKey);
    impersonation.value = null;
  }
}

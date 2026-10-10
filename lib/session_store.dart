import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda en el navegador que el usuario ya pasó el portón, para no
/// pedir login en cada recarga. La sesión local dura [_maxHoras] horas
/// desde el ÚLTIMO USO; pasado ese tiempo se pide entrar de nuevo.
///
/// Además gestiona el modo "Ver como profesor" (suplantación de solo lectura):
/// cuando un administrador lo activa, [validEmail] devuelve el correo del
/// profesor elegido, de modo que TODA la app carga los datos de ese profesor.
///
/// ---------------------------------------------------------------------
/// NOTA (7-ago-2026) — POR QUÉ ESTE ARCHIVO CAMBIÓ
/// El proyecto tenía DOS SessionStore: éste (lib/auth/session_store.dart),
/// que es el que usa toda la app, y una copia en lib/session_store.dart que
/// no importaba nadie salvo una pantalla huérfana. La ampliación de la
/// sesión a 30 días con ventana deslizante se había escrito en la COPIA
/// MUERTA (4-jul-2026), así que nunca surtió efecto: las sesiones seguían
/// caducando a las 12 horas y, al vencer, validEmail() devolvía null y
/// pantallas como "Mis materias" mostraban "No tienes materias asignadas"
/// sin explicar por qué. Aquí queda el arreglo, ya en el archivo vivo.
/// La copia lib/session_store.dart debe BORRARSE para que no vuelva a pasar.
/// ---------------------------------------------------------------------
class SessionStore {
  static const String _emailKey = 'cessum_auth_email';
  static const String _nameKey = 'cessum_auth_name';
  static const String _tsKey = 'cessum_auth_ts';

  /// 30 días. La marca de tiempo se renueva en cada uso (ventana deslizante),
  /// así que en la práctica solo caduca tras 30 días SIN abrir la app.
  static const int _maxHoras = 720;

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
  static Future<String?> realEmail() async {
    final p = await SharedPreferences.getInstance();
    final email = p.getString(_emailKey);
    final ts = p.getInt(_tsKey);
    if (email == null || ts == null) return null;

    final ahora = DateTime.now().millisecondsSinceEpoch;
    final edadMs = ahora - ts;
    if (edadMs > _maxHoras * 3600 * 1000) {
      await clear();
      return null;
    }

    // VENTANA DESLIZANTE: cada uso renueva la marca de tiempo, así la sesión
    // no expira mientras la persona siga trabajando. Se renueva como mucho una
    // vez por hora para no escribir en disco en cada llamada (esta función se
    // invoca en casi todas las pantallas).
    if (edadMs > 3600 * 1000) {
      try {
        await p.setInt(_tsKey, ahora);
      } catch (_) {
        // si falla el guardado, la sesión sigue siendo válida en esta corrida
      }
    }

    return email;
  }

  static Future<String?> name() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_nameKey);
  }

  /// Cierra la sesión local Y la llave de sesión firmada del servidor.
  ///
  /// (24-sep) Desde el 23-sep, al iniciar sesión con Google, api/auth_check.php
  /// deja una llave firmada (cookie csm_sesion) que guardian.php verifica en
  /// las acciones de administración, SIGA y Finanzas. Si solo se borraba la
  /// sesión local, la llave seguía valiendo en este navegador. Todas las
  /// salidas pasan por aquí —«Cerrar sesión» de alumno y de docente, la
  /// bienvenida, el cierre por inactividad y el vencimiento de los 30 días—,
  /// así que expirarla aquí las cubre todas. Si el servidor no responde, no
  /// estorba: la sesión local se borra igual.
  static Future<void> clear() async {
    if (kIsWeb) {
      try {
        await http
            .post(Uri.parse('/api/cerrar_sesion.php'),
                headers: {'Content-Type': 'application/json'}, body: '{}')
            .timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    final p = await SharedPreferences.getInstance();
    await p.remove(_emailKey);
    await p.remove(_nameKey);
    await p.remove(_tsKey);
    await p.remove(_impEmailKey);
    await p.remove(_impNameKey);
    impersonation.value = null;
  }
}

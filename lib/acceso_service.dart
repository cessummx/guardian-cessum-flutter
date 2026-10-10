import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'active_profile.dart';
import 'admin_config.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Registra en el Guardián quién entra a la app y cuándo.
///
/// Se llama desde el portón de entrada (auth_gate.dart) cada vez que un
/// usuario queda autorizado, ya sea porque acaba de iniciar sesión con
/// Google o porque su sesión guardada en el navegador sigue vigente.
///
/// Para no llenar la hoja con registros repetidos cuando la persona
/// recarga la página varias veces, solo se registra de nuevo si han
/// pasado al menos 30 minutos desde el último registro de ese mismo
/// correo en este navegador.
///
/// El registro es "dispara y olvida": si falla (sin internet, Guardián
/// caído, etc.) NO estorba la entrada a la app; simplemente no se anota.
///
/// (24-sep) Cambios:
///  · Usa el correo REAL. Antes usaba validEmail(), que en «Ver como
///    profesor» devuelve el del profesor: se anotaba que el profesor había
///    entrado a la app sin haberlo hecho, y eso ensuciaba cualquier medición
///    de uso. En ese modo ya no se registra nada.
///  · Manda el rol que la persona está usando (Alumno, Docente o
///    Administrador), no solo si es administrador.
///  · El Guardián, además, toma el correo de la llave firmada de la sesión,
///    no el que viene aquí.
///  · cerrarSesionServidor() expira esa llave al cerrar sesión.
class AccesoService {
  static const String _kUltimoKey = 'cessum_ultimo_registro_acceso';
  static const Duration _minEntreRegistros = Duration(minutes: 30);

  static Future<void> registrar() async {
    // Solo aplica en web: en móvil el portón no maneja correo.
    if (!kIsWeb) return;
    try {
      final correo = (await SessionStore.realEmail() ?? '').trim().toLowerCase();
      if (correo.isEmpty) return;
      // «Ver como profesor»: el administrador no está entrando como ese profesor.
      final vista = (await SessionStore.validEmail() ?? '').trim().toLowerCase();
      if (vista.isNotEmpty && vista != correo) return;
      final nombre = await SessionStore.name() ?? '';

      // Filtro local: no registrar el mismo correo dos veces en 30 minutos.
      final p = await SharedPreferences.getInstance();
      final marca = p.getString(_kUltimoKey); // formato: "correo|milisegundos"
      if (marca != null) {
        final partes = marca.split('|');
        if (partes.length == 2 && partes[0] == correo) {
          final ts = int.tryParse(partes[1]) ?? 0;
          final edadMs = DateTime.now().millisecondsSinceEpoch - ts;
          if (edadMs < _minEntreRegistros.inMilliseconds) return;
        }
      }

      await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'acceso_registrar',
              'correo': correo,
              'nombre': nombre,
              'rol': await _rol(correo),
              'plataforma': 'web',
            }),
          )
          .timeout(const Duration(seconds: 20));

      await p.setString(_kUltimoKey, '$correo|${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {
      // Silencioso a propósito: el registro nunca debe bloquear la entrada.
    }
  }

  /// Rol con el que la persona está usando la app. Si queda vacío, el
  /// Guardián lo resuelve con sus propias listas, como antes.
  static Future<String> _rol(String correo) async {
    if (esAdmin(correo)) return 'Administrador';
    try {
      final perfil = await ActiveProfile.getActive();
      if (perfil == ProfileType.teacher) return 'Docente';
      if (perfil == ProfileType.student) return 'Alumno';
    } catch (_) {}
    return '';
  }

  /// Expira la llave de sesión firmada (cookie) en el servidor. Se llama al
  /// cerrar sesión, ANTES de borrar la sesión local. Si falla, no estorba:
  /// la llave vence sola a las 12 horas.
  static Future<void> cerrarSesionServidor() async {
    if (!kIsWeb) return;
    try {
      await http
          .post(Uri.parse('/api/cerrar_sesion.php'),
              headers: {'Content-Type': 'application/json'}, body: '{}')
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }
}

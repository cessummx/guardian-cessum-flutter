import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// Resultado de un intento de acceso al portón.
class AuthResult {
  final bool authorized;
  final String? email;
  final String? name;
  final String? reason;

  const AuthResult({
    required this.authorized,
    this.email,
    this.name,
    this.reason,
  });
}

/// Maneja el inicio de sesión con Google y la verificación contra el backend
/// PHP (auth_check.php), que es quien autoriza de verdad los correos @cessum.mx.
///
/// Usa la API de google_sign_in v7 (GoogleSignIn.instance + authenticationEvents).
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  // =====================================================================
  //  CONFIGURACIÓN  —  PEGA AQUÍ TUS DATOS
  // =====================================================================
  // El Client ID de tipo "Aplicación web" que creaste en Google Cloud.
  static const String webClientId =
      '496483436784-e7ueiqi3216tlgnenar5fncc8q42vtvh.apps.googleusercontent.com';

  // La URL donde subiste auth_check.php.
  static const String backendUrl =
      'https://app.cessum.mx/api/auth_check.php';
  // =====================================================================

  bool _initialized = false;

  final StreamController<AuthResult> _results =
      StreamController<AuthResult>.broadcast();

  /// La pantalla del portón escucha aquí los resultados de acceso.
  Stream<AuthResult> get results => _results.stream;

  /// Inicializa Google Sign-In y empieza a escuchar eventos de login.
  /// Llamar una sola vez al arrancar la app web.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await GoogleSignIn.instance.initialize(clientId: webClientId);

    GoogleSignIn.instance.authenticationEvents.listen(
      _onEvent,
      onError: (Object _) {
        // IMPORTANTE — NO mostrar error aquí.
        //
        // El intento de inicio de sesión "silencioso"
        // (attemptLightweightAuthentication, más abajo) se RECHAZA con un error
        // de red de FedCM cuando el usuario NO tiene una sesión de Google abierta
        // en el navegador. Eso es NORMAL y esperado: simplemente no hay una
        // sesión previa que reusar. En ese caso NO debemos alarmar a la persona;
        // basta con dejar visible el botón "Iniciar sesión con Google" para que
        // entre de forma normal.
        //
        // Los errores REALES y accionables (correo no @cessum.mx, backend caído,
        // token inválido) se manejan en _onEvent() y _verifyWithBackend(), que sí
        // emiten un motivo específico DESPUÉS de un inicio de sesión real.
        //
        // Por eso aquí ignoramos el error a propósito y no emitimos nada.
      },
    );

    // Intento silencioso: si ya había iniciado sesión, reusa esa sesión.
    // Si no hay sesión, fallará silenciosamente (lo de arriba) y el usuario
    // verá el botón de Google para entrar manualmente.
    unawaited(GoogleSignIn.instance.attemptLightweightAuthentication());
  }

  Future<void> _onEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      final GoogleSignInAccount user = event.user;

      // En la API v7, el idToken viene en la "authentication" del usuario.
      final String? idToken = user.authentication.idToken;

      if (idToken == null || idToken.isEmpty) {
        _results.add(const AuthResult(
          authorized: false,
          reason: 'No se obtuvo el token de Google',
        ));
        return;
      }

      final AuthResult result = await _verifyWithBackend(idToken);
      _results.add(result);
    }
    // GoogleSignInAuthenticationEventSignOut: no requiere acción aquí.
  }

  /// Envía el token al PHP de cPanel, que confirma el dominio @cessum.mx.
  Future<AuthResult> _verifyWithBackend(String idToken) async {
    try {
      final resp = await http
          .post(
            Uri.parse(backendUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'id_token': idToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return const AuthResult(
          authorized: false,
          reason: 'El servidor no está disponible',
        );
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final bool ok = data['authorized'] == true;

      return AuthResult(
        authorized: ok,
        email: data['email']?.toString(),
        name: data['name']?.toString(),
        reason: data['reason']?.toString(),
      );
    } catch (_) {
      return const AuthResult(
        authorized: false,
        reason: 'No se pudo conectar con el servidor',
      );
    }
  }

  Future<void> signOut() async {
    // disconnect() REVOCA el permiso de Google: asi el cierre de sesion es real
    // en web y permite entrar luego con OTRA cuenta (no se reconecta solo).
    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {}
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }
}

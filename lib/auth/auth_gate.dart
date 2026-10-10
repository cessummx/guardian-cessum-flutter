import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../acceso_service.dart';
import '../constants.dart';
import 'auth_service.dart';
import 'google_button.dart';
import 'session_store.dart';

/// Porton de entrada de la app web.
/// En WEB exige iniciar sesion con correo @cessum.mx. En MOVIL no estorba.
class AuthGate extends StatefulWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _authorized = false;
  String? _denyReason;
  /// (24-sep) Aviso informativo sobre la pantalla de Google (no es un error).
  String? _aviso;
  StreamSubscription<AuthResult>? _sub;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _authorized = true;
      _checking = false;
    } else {
      _setupWeb();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// (24-sep) ¿Tiene este navegador la llave de sesión firmada?
  /// Devuelve el correo de la llave, '' si no hay llave válida, o null si no
  /// se pudo saber (sin red, servidor caído): en ese caso NO se saca a nadie.
  Future<String?> _llaveDelServidor() async {
    try {
      final r = await http
          .get(Uri.parse('/api/sesion_estado.php'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['firmada'] == true) return '${d['correo'] ?? ''}'.trim().toLowerCase();
      return '';
    } catch (_) {
      return null;
    }
  }

  Future<void> _setupWeb() async {
    final savedEmail = await SessionStore.validEmail();
    if (savedEmail != null && mounted) {
      /* (24-sep) La sesión local dura 30 días y se renueva con el uso: quien
         entró antes de que existiera la llave firmada nunca vuelve a pasar
         por Google y nunca la recibe (y sin ella, la administración, SIGA,
         Finanzas y desde el 5-oct las listas de alumnos le piden volver a
         entrar). Aquí se comprueba: si no hay llave, o es de otra cuenta, se
         pide entrar con Google UNA vez; desde ahí la llave se renueva sola.
         Se compara con el correo REAL, para que «Ver como profesor» no cuente. */
      final real = (await SessionStore.realEmail() ?? '').trim().toLowerCase();
      final llave = await _llaveDelServidor();
      if (!mounted) return;
      if (llave != null && llave != real) {
        await SessionStore.clear();
        if (!mounted) return;
        _aviso = 'Por seguridad, entra una vez más con tu cuenta @cessum.mx. Solo se pide esta vez.';
        // Sigue abajo: pantalla de inicio con Google.
      } else {
        // Registro de acceso: la persona entró con su sesión guardada.
        unawaited(AccesoService.registrar());
        setState(() {
          _authorized = true;
          _checking = false;
        });
        return;
      }
    }

    _sub = AuthService.instance.results.listen((result) async {
      if (!mounted) return;
      if (result.authorized && result.email != null) {
        await SessionStore.save(result.email!, result.name);
        // Registro de acceso: inicio de sesión nuevo con Google.
        unawaited(AccesoService.registrar());
        if (!mounted) return;
        setState(() {
          _authorized = true;
          _denyReason = null;
          _aviso = null;
        });
      } else {
        setState(() {
          _denyReason = result.reason ?? 'No tienes acceso';
        });
      }
    });

    await AuthService.instance.init();
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _contactarSoporte() async {
    final uri = Uri.parse(
      'https://wa.me/$whatsappNumero?text=${Uri.encodeComponent("Hola, intento entrar a la app de CESSUM con mi correo institucional y no me deja.")}',
    );
    try {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } catch (_) {}
  }

  // Soporte por WhatsApp visible siempre en la pantalla de inicio.
  Future<void> _soporteWhatsapp() async {
    final uri = Uri.parse(
      'https://wa.me/$whatsappNumero?text=${Uri.encodeComponent(whatsappMensaje)}',
    );
    try {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_authorized) return widget.child;

    if (_checking) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator(color: cessumRed)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 110,
                      width: 110,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.school, size: 72, color: cessumRed),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'App CESSUM',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ingresa con tu correo institucional @cessum.mx',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 32),
                  if (_aviso != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.lock_outline, color: cessumGold, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_aviso!,
                              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.35)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],
                  buildGoogleSignInButton(),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _soporteWhatsapp,
                    icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                    label: const Text('Comunícate con soporte por WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '+52 1 642 130 5193',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                  if (_denyReason != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: cessumRed.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            _denyReason!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: cessumRed),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _contactarSoporte,
                            child:
                                const Text('Contactar a soporte por WhatsApp'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

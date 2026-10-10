import 'dart:async';

import 'package:flutter/material.dart';

import 'impersonation_banner.dart' show rootNavigatorKey;
import 'auth/session_store.dart';
import 'auth/auth_gate.dart';
import 'splash_screen.dart';

/// Envuelve la app y cierra la sesión automáticamente tras un periodo sin
/// actividad (útil en equipos compartidos de la escuela). También sale del
/// modo "Ver como profesor". El temporizador se reinicia con cualquier
/// interacción (toques, movimiento, scroll).
class InactivityWrapper extends StatefulWidget {
  final Widget child;
  final Duration limite;

  const InactivityWrapper({
    super.key,
    required this.child,
    this.limite = const Duration(minutes: 20),
  });

  @override
  State<InactivityWrapper> createState() => _InactivityWrapperState();
}

class _InactivityWrapperState extends State<InactivityWrapper> {
  Timer? _timer;
  bool _cerrando = false;

  @override
  void initState() {
    super.initState();
    _reiniciar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _reiniciar() {
    _timer?.cancel();
    _timer = Timer(widget.limite, _porInactividad);
  }

  Future<void> _porInactividad() async {
    if (_cerrando) return;
    // Solo cerramos si hay una sesión activa.
    final correo = await SessionStore.realEmail();
    if (correo == null || correo.isEmpty) {
      _reiniciar();
      return;
    }
    _cerrando = true;
    try {
      await SessionStore.stopImpersonation();
    } catch (_) {}
    try {
      await SessionStore.clear();
    } catch (_) {}

    final nav = rootNavigatorKey.currentState;
    nav?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate(child: SplashScreen())),
      (route) => false,
    );
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null) {
      final messenger = ScaffoldMessenger.maybeOf(ctx);
      messenger?.showSnackBar(const SnackBar(
        content: Text('Sesión cerrada por inactividad.'),
      ));
    }
    _cerrando = false;
    _reiniciar();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reiniciar(),
      onPointerMove: (_) => _reiniciar(),
      onPointerSignal: (_) => _reiniciar(),
      child: widget.child,
    );
  }
}

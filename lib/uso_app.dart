// =====================================================================
//  uso_app.dart · CESSUM · (25-sep-2026)
//  MEDIDOR DE USO. Registra cada pantalla que abre la persona (observador
//  de rutas, mismo criterio que ErrorRouteObserver: el tipo del widget de
//  destino) y lo manda al Guardián en lotes, sin frenar la app. Con esos
//  datos se decide qué accesos agrandar, cuáles van primero y cuáles
//  reagrupar (Herramientas → Uso de la app y sugerencias).
//
//  Guardián: POST uso_app { correo, matricula, rol, eventos:[{p,e,d,t}] }
// =====================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'active_profile.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'student_profile.dart';

class UsoApp {
  static final List<Map<String, dynamic>> _cola = [];
  static Timer? _reloj;
  static bool _enviando = false;
  static String _ultima = '';
  static int _ultimaMs = 0;

  /// Pantallas que no dicen nada del uso (arranque, sesión, contenedores).
  static const Set<String> _omitir = {
    'SplashScreen', 'AuthGate', 'WelcomeScreen', 'LoginScreen', 'MenuScreen',
    'TeacherMenuScreen', 'AdminPreviewScreen', 'OnboardingScreen',
  };

  /// Nombre legible a partir del tipo del widget: «MisClasesScreen» → «Mis clases».
  static String etiqueta(String tipo) {
    var t = tipo.replaceAll(RegExp(r'Screen$'), '').replaceAll(RegExp(r'^_'), '');
    t = t.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}');
    t = t.replaceAll('_', ' ').trim();
    if (t.isEmpty) return tipo;
    return t[0].toUpperCase() + t.substring(1).toLowerCase();
  }

  static void registrar(String pantalla, {String detalle = ''}) {
    if (pantalla.isEmpty || _omitir.contains(pantalla)) return;
    final ahora = DateTime.now().millisecondsSinceEpoch;
    // La misma pantalla dos veces en 3 s es un rebote, no un uso.
    if (pantalla == _ultima && ahora - _ultimaMs < 3000) return;
    _ultima = pantalla;
    _ultimaMs = ahora;
    _cola.add({'p': pantalla, 'e': etiqueta(pantalla), 'd': detalle, 't': ahora});
    if (_cola.length >= 12) {
      _enviar();
    } else {
      _reloj ??= Timer(const Duration(seconds: 20), _enviar);
    }
  }

  static Future<void> _enviar() async {
    _reloj?.cancel();
    _reloj = null;
    if (_enviando || _cola.isEmpty) return;
    _enviando = true;
    final lote = List<Map<String, dynamic>>.from(_cola);
    _cola.clear();
    try {
      final correo = await SessionStore.validEmail() ?? '';
      String matricula = '';
      String rol = 'alumno';
      try {
        final tipo = await ActiveProfile.getActive();
        if (tipo == ProfileType.teacher) rol = 'docente';
      } catch (_) {}
      try {
        final p = await StudentProfile.load();
        if (p != null && p.matricula.isNotEmpty) matricula = p.matricula;
      } catch (_) {}
      if (correo.isEmpty && matricula.isEmpty) return;
      await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'uso_app', 'correo': correo, 'matricula': matricula, 'rol': rol, 'eventos': lote}))
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      // Un lote perdido no vale una pantalla de error: la medición es de apoyo.
    } finally {
      _enviando = false;
      if (_cola.isNotEmpty) _reloj ??= Timer(const Duration(seconds: 20), _enviar);
    }
  }
}

/// Observador de rutas: anota cada pantalla a la que se navega.
class UsoAppObserver extends NavigatorObserver {
  void _anotar(Route<dynamic>? ruta) {
    if (ruta == null) return;
    final n = ruta.settings.name;
    if (n != null && n.isNotEmpty && n != '/') {
      UsoApp.registrar(n);
      return;
    }
    if (ruta is MaterialPageRoute) {
      try {
        final ctx = ruta.navigator?.context;
        if (ctx == null) return;
        final w = ruta.builder(ctx);
        UsoApp.registrar(w.runtimeType.toString());
      } catch (_) {}
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _anotar(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _anotar(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

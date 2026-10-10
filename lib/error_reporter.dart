// =====================================================================
//  error_reporter.dart · CESSUM · Aula CESSUM
//  Manda al Guardián las excepciones que hoy nadie ve.
//
//  Por qué existe: las fallas del frontend solo se sabían porque alguien
//  se quejaba. El comprobante de pago estuvo roto un día, el bloque de
//  paquetería cinco, y las grabaciones tres semanas. Con esto cada
//  excepción no atendida queda en la hoja 'Errores Guardián' con la
//  pantalla donde ocurrió, y el resumen diario llega a vicerrectoría.
//
//  Reglas que se respetan a rajatabla:
//   · Nunca interrumpe al usuario. No muestra diálogos ni bloquea nada.
//   · Nunca se reporta a sí mismo (si el envío falla, se traga el error).
//   · Tope por sesión y sin repetir el mismo mensaje, para no inundar
//     la hoja cuando algo falla dentro de un build que se repinta.
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

class ErrorReporter {
  ErrorReporter._();

  /// Número de build con el que se compiló. Se pone desde main().
  static String build = '';

  /// Pantalla en la que está el usuario. La mantiene [ErrorRouteObserver].
  static String pantalla = 'inicio';

  static const int _maxPorSesion = 12;
  static int _enviados = 0;
  static bool _enviando = false;
  static final Set<String> _yaVistos = <String>{};

  /// Engancha los tres caminos por los que Flutter suelta una excepción:
  /// errores de construcción de widgets, errores asíncronos de la
  /// plataforma y lo que caiga en la zona protegida de main().
  static void iniciar({String buildNumero = ''}) {
    build = buildNumero;

    final anterior = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails detalles) {
      anterior?.call(detalles);
      reportar(detalles.exception, detalles.stack,
          contexto: detalles.context?.toString());
    };

    // Se llega al despachador por el binding (ya inicializado en main) para
    // no depender de importar dart:ui directamente.
    WidgetsBinding.instance.platformDispatcher.onError = (Object e, StackTrace s) {
      reportar(e, s);
      return true; // ya quedó registrado; no tumbar la app
    };
  }

  /// Reporta una excepción. Es seguro llamarla desde cualquier lado y en
  /// cualquier momento: si algo sale mal aquí dentro, se queda callada.
  static Future<void> reportar(Object error, StackTrace? stack,
      {String? contexto, String? pantallaForzada}) async {
    try {
      if (_enviados >= _maxPorSesion) return;

      final msg = error.toString();
      if (msg.trim().isEmpty) return;

      // Huella para no repetir: mismo mensaje en la misma pantalla cuenta
      // una sola vez por sesión. Un widget que truena se repinta muchas
      // veces por segundo y llenaría la hoja en un minuto.
      final donde = pantallaForzada ?? pantalla;
      final huella = '$donde|${msg.length > 160 ? msg.substring(0, 160) : msg}';
      if (_yaVistos.contains(huella)) return;
      _yaVistos.add(huella);

      if (_enviando) return;
      _enviando = true;
      _enviados++;

      String correo = '';
      try {
        correo = (await SessionStore.realEmail()) ?? '';
      } catch (_) {
        // sin sesión también se reporta; el error importa igual
      }

      var traza = (stack ?? StackTrace.current).toString();
      if (contexto != null && contexto.isNotEmpty) {
        traza = '$contexto\n$traza';
      }
      if (traza.length > 900) traza = traza.substring(0, 900);

      await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'accion': 'app_error',
                'pantalla': donde,
                'mensaje': msg.length > 900 ? msg.substring(0, 900) : msg,
                'stack': traza,
                'correo': correo,
                'build': build,
              }))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Silencio absoluto: un fallo al reportar JAMÁS debe generar otro
      // error ni molestar a quien está usando la app.
    } finally {
      _enviando = false;
    }
  }
}

/// Anota en qué pantalla está el usuario, para que el error diga dónde
/// ocurrió y no solo qué decía. Se registra en MaterialApp.navigatorObservers.
class ErrorRouteObserver extends NavigatorObserver {
  void _anotar(Route<dynamic>? ruta) {
    final n = ruta?.settings.name;
    if (n != null && n.isNotEmpty) {
      ErrorReporter.pantalla = n;
      return;
    }
    // La app navega casi siempre con MaterialPageRoute sin nombre, así que
    // se usa el tipo del widget de destino, que es igual de identificable.
    if (ruta is MaterialPageRoute) {
      try {
        final w = ruta.builder(ruta.navigator!.context);
        ErrorReporter.pantalla = w.runtimeType.toString();
      } catch (_) {
        // si el builder truena aquí, no vale la pena insistir
      }
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _anotar(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _anotar(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _anotar(newRoute);
}

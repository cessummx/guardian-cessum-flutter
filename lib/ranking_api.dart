import 'dart:convert';

import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Envía el puntaje de un juego al Guardián para el ranking. Es "fire and
/// forget": si falla la red, no interrumpe el juego.
class RankingApi {
  static Future<void> enviar({
    required String matricula,
    required String nombre,
    required String juego,
    required int puntaje,
  }) async {
    if (matricula.trim().isEmpty || puntaje <= 0) return;
    try {
      await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'ranking_guardar',
              'matricula': matricula,
              'nombre': nombre,
              'juego': juego,
              'puntaje': puntaje.toString(),
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // Silencioso: el ranking es secundario al juego.
    }
  }
}

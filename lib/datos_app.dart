import 'dart:convert';

import 'package:http/http.dart' as http;

/// Caché EN MEMORIA por sesión para JSON grandes (alumnos.json, cartas.json).
///
/// Objetivo: que cada archivo se descargue e interprete UNA sola vez por
/// sesión, aunque varias pantallas lo pidan. Al recargar la página se vuelve
/// a pedir (y el navegador, con el .htaccess, responde 304 si no cambió),
/// así que nunca se queda con datos viejos entre sesiones.
///
/// Uso:
///   final data = await DatosApp.i.json('https://app.cessum.mx/alumnos.json');
/// Después de un alta/cambio, para forzar recarga:
///   DatosApp.i.invalidar('https://app.cessum.mx/alumnos.json');
class DatosApp {
  DatosApp._();
  static final DatosApp i = DatosApp._();

  final Map<String, dynamic> _cache = {};
  final Map<String, Future<dynamic>> _enCurso = {};

  /// Devuelve el JSON ya interpretado (Map o List). Lo guarda en memoria.
  /// Si dos pantallas lo piden al mismo tiempo, comparten la misma descarga.
  Future<dynamic> json(String url) {
    if (_cache.containsKey(url)) {
      return Future.value(_cache[url]);
    }
    return _enCurso[url] ??= _descargar(url);
  }

  Future<dynamic> _descargar(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) {
        throw Exception('Error ${r.statusCode} al cargar $url');
      }
      final data = jsonDecode(r.body);
      _cache[url] = data;
      return data;
    } finally {
      _enCurso.remove(url);
    }
  }

  /// Borra de la caché un archivo (o todo si no se pasa url).
  /// Úsalo tras dar de alta alumnos o cambiar datos, para que la próxima
  /// lectura traiga lo más reciente.
  void invalidar([String? url]) {
    if (url == null) {
      _cache.clear();
      _enCurso.clear();
    } else {
      _cache.remove(url);
      _enCurso.remove(url);
    }
  }

  /// ¿Ya está en memoria? (útil para mostrar datos al instante).
  bool tiene(String url) => _cache.containsKey(url);
}

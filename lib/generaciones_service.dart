import 'dart:convert';

import 'package:http/http.dart' as http;

import 'constants.dart';

class GeneracionItem {
  final String nombre;
  final String url;

  const GeneracionItem({required this.nombre, required this.url});
}

class GeneracionesService {
  // Cache en memoria mientras la app esta abierta
  static List<GeneracionItem>? _cache;
  static DateTime? _cacheTime;

  // El cache vive 10 minutos
  static const Duration _cacheDuration = Duration(minutes: 10);

  // Obtiene generaciones desde el Gist (con cache)
  static Future<List<GeneracionItem>> obtener({bool forzarRecarga = false}) async {
    final ahora = DateTime.now();
    final cacheValido = _cache != null &&
        _cacheTime != null &&
        ahora.difference(_cacheTime!) < _cacheDuration;

    if (!forzarRecarga && cacheValido) {
      return _cache!;
    }

    final response = await http
        .get(Uri.parse(pagosJsonUrl))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      // Si tenemos cache vieja, mejor devolverla que fallar
      if (_cache != null) return _cache!;
      throw Exception('No se pudo cargar la lista de generaciones');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (data['generaciones'] as List<dynamic>?) ?? [];

    final result = list
        .map((e) => GeneracionItem(
              nombre: e['nombre']?.toString() ?? '',
              url: e['url']?.toString() ?? '',
            ))
        .where((g) => g.nombre.isNotEmpty && g.url.isNotEmpty)
        .toList();

    _cache = result;
    _cacheTime = ahora;

    return result;
  }

  // Busca la URL de pago de una generacion especifica por nombre
  static Future<String?> obtenerUrlDePago(String nombreGeneracion) async {
    final generaciones = await obtener();
    for (final g in generaciones) {
      if (g.nombre == nombreGeneracion) {
        return g.url;
      }
    }
    return null;
  }
}
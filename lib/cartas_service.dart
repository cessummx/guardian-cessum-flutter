import 'dart:convert';

import 'package:http/http.dart' as http;

import 'constants.dart';

// Una asignatura con los datos de su carta descriptiva
class Asignatura {
  final String denominacion;
  final String semestre;
  final String cicloEscolar;
  final String clave;
  final String fines;
  final String contenido;

  const Asignatura({
    required this.denominacion,
    required this.semestre,
    required this.cicloEscolar,
    required this.clave,
    required this.fines,
    required this.contenido,
  });

  factory Asignatura.fromJson(Map<String, dynamic> j) {
    return Asignatura(
      denominacion: j['denominacion']?.toString() ?? '',
      semestre: j['semestre']?.toString() ?? '',
      cicloEscolar: j['cicloEscolar']?.toString() ?? '',
      clave: j['clave']?.toString() ?? '',
      fines: j['fines']?.toString() ?? '',
      contenido: j['contenido']?.toString() ?? '',
    );
  }
}

// Un programa academico con su lista de asignaturas
class ProgramaCartas {
  final String programa;
  final List<Asignatura> asignaturas;

  const ProgramaCartas({required this.programa, required this.asignaturas});
}

class CartasService {
  // Cache en memoria mientras la app esta abierta
  static List<ProgramaCartas>? _cache;
  static DateTime? _cacheTime;

  // El cache vive 10 minutos
  static const Duration _cacheDuration = Duration(minutes: 10);

  // Obtiene las cartas descriptivas desde el Gist (con cache)
  static Future<List<ProgramaCartas>> obtener({bool forzarRecarga = false}) async {
    final ahora = DateTime.now();
    final cacheValido = _cache != null &&
        _cacheTime != null &&
        ahora.difference(_cacheTime!) < _cacheDuration;

    if (!forzarRecarga && cacheValido) {
      return _cache!;
    }

    final response = await http
        .get(Uri.parse(cartasJsonUrl))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      if (_cache != null) return _cache!;
      throw Exception('No se pudieron cargar las cartas descriptivas');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final list = (data['programas'] as List<dynamic>?) ?? [];

    final result = list
        .map((p) {
          final mapa = p as Map<String, dynamic>;
          final asigsRaw = (mapa['asignaturas'] as List<dynamic>?) ?? [];
          final asignaturas = asigsRaw
              .map((a) => Asignatura.fromJson(a as Map<String, dynamic>))
              .where((a) => a.denominacion.isNotEmpty)
              .toList();

          return ProgramaCartas(
            programa: mapa['programa']?.toString() ?? '',
            asignaturas: asignaturas,
          );
        })
        .where((p) => p.programa.isNotEmpty)
        .toList();

    _cache = result;
    _cacheTime = ahora;

    return result;
  }
}

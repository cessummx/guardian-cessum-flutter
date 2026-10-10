// =====================================================================
//  respuesta_guardian.dart · CESSUM · Aula CESSUM
//  Traduce lo que responde el Guardián a algo que una persona entienda.
//
//  Por qué existe: el 9-ago-2026, al guardar una nota de titulación, la
//  pantalla mostró esto en rojo:
//      "FormatException: SyntaxError: Unexpected token '<',
//       "<!DOCTYPE "... is not valid JSON"
//  Eso no le dice nada a nadie. Peor: no dice si el cambio se guardó o no,
//  que es lo único que la persona necesita saber en ese momento.
//
//  Cada pantalla hace su propio `jsonDecode(resp.body)` y su propio
//  `catch (e) => mostrar '$e'`. Este archivo centraliza esa parte para que
//  el mensaje sea el mismo y sea humano, sin tener que reescribir cada
//  pantalla de golpe: se adopta archivo por archivo.
// =====================================================================

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'error_reporter.dart';

/// Lo que devuelve el Guardián, ya interpretado.
class RespuestaGuardian {
  /// Verdadero solo si el servidor respondió JSON con ok:true.
  final bool ok;

  /// Los datos, cuando ok es verdadero. Vacío si hubo problema.
  final Map<String, dynamic> datos;

  /// Mensaje listo para mostrarle a la persona. Vacío si todo salió bien.
  final String mensaje;

  /// Verdadero cuando NO se puede saber si el cambio se guardó. Importa:
  /// un "no se pudo" que en realidad sí guardó hace que la gente repita la
  /// operación y duplique registros.
  final bool incierto;

  const RespuestaGuardian({
    required this.ok,
    this.datos = const {},
    this.mensaje = '',
    this.incierto = false,
  });

  dynamic operator [](String k) => datos[k];
}

/// Interpreta la respuesta cruda del Guardián.
///
/// [accion] es solo para el reporte de errores: ayuda a saber qué ruta
/// falló cuando llega a la hoja de errores.
RespuestaGuardian leerRespuesta(http.Response resp, {String accion = ''}) {
  final cuerpo = resp.body.trim();

  // El servidor contestó una PÁGINA en vez de datos. Pasa cuando Apps
  // Script devuelve su pantalla de error, cuando el proxy se topa con su
  // límite de tiempo, o cuando la publicación quedó a medias.
  if (cuerpo.startsWith('<')) {
    ErrorReporter.reportar(
      'Respuesta HTML del Guardián en "$accion" '
      '(código ${resp.statusCode}, ${cuerpo.length} caracteres)',
      StackTrace.current,
      pantallaForzada: 'guardian:$accion',
    );
    return const RespuestaGuardian(
      ok: false,
      incierto: true,
      mensaje: 'El servidor tardó demasiado en contestar.\n\n'
          'Es posible que el cambio SÍ se haya guardado: cierra y vuelve a '
          'abrir para revisarlo antes de intentarlo otra vez.',
    );
  }

  if (cuerpo.isEmpty) {
    return const RespuestaGuardian(
      ok: false,
      incierto: true,
      mensaje: 'El servidor no contestó nada. Revisa si el cambio quedó '
          'guardado antes de repetirlo.',
    );
  }

  Map<String, dynamic> d;
  try {
    final crudo = jsonDecode(cuerpo);
    if (crudo is! Map) {
      return const RespuestaGuardian(
        ok: false,
        mensaje: 'El servidor contestó en un formato inesperado.',
      );
    }
    d = Map<String, dynamic>.from(crudo);
  } catch (e) {
    ErrorReporter.reportar(
      'Respuesta ilegible del Guardián en "$accion": $e',
      StackTrace.current,
      pantallaForzada: 'guardian:$accion',
    );
    return const RespuestaGuardian(
      ok: false,
      incierto: true,
      mensaje: 'No se entendió la respuesta del servidor. Revisa si el '
          'cambio quedó guardado antes de repetirlo.',
    );
  }

  if (d['ok'] == true) return RespuestaGuardian(ok: true, datos: d);

  // ok:false con error del propio backend. Ese texto SÍ está escrito para
  // que alguien lo lea ("Solo administradores", "Folio no encontrado"),
  // así que se muestra tal cual — salvo los dos casos de abajo, que son
  // mensajes internos que conviene traducir.
  final err = (d['error'] ?? '').toString().trim();
  return RespuestaGuardian(
    ok: false,
    datos: d,
    mensaje: _humano(err),
  );
}

String _humano(String err) {
  if (err.isEmpty) return 'No se pudo completar la operación.';
  final e = err.toLowerCase();
  if (e.contains('acción get no reconocida') ||
      e.contains('acción post no reconocida')) {
    return 'Esta función todavía no está disponible en el servidor. '
        'Avísale a Vicerrectoría: falta publicar una actualización.';
  }
  if (e.contains('solo administradores')) {
    return 'Tu cuenta no tiene permiso para hacer este cambio.';
  }
  if (e.contains('exceeded maximum execution time')) {
    return 'La operación tardó más de lo permitido. Intenta con menos '
        'registros a la vez.';
  }
  return err;
}

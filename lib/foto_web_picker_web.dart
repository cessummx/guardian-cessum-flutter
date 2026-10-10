// Version WEB del selector de fotos. Usa el selector de archivos propio del
// navegador (no depende de image_picker) y reduce el tamano de la foto con
// un canvas antes de devolverla. Este archivo SOLO se compila para web.
//
// (ago-7) ENDURECIDO. Sintoma que corrige: al adjuntar la guia de envio (y en
// general cualquier foto) el boton "no hacia nada" y parecia que solo aceptaba
// PDF. Causa: la compresion esperaba img.onLoad SIN escuchar onError y SIN
// timeout, asi que un archivo que el navegador no puede decodificar (.HEIC de
// iPhone, .tiff, imagen danada) dejaba la promesa colgada para siempre.
// Cambios:
//   1. accept incluye explicitamente .heic/.heif/.webp/.bmp/.tif/.tiff.
//   2. La carga de la imagen escucha onLoad Y onError, y ademas trae timeout.
//   3. Si el navegador NO puede decodificar la imagen, ya no se cuelga: se
//      sube el archivo ORIGINAL tal cual (hasta 12 MB) con su mime real.
//   4. El mime se deduce de la extension cuando el navegador lo manda vacio
//      (pasa seguido con .heic en Windows).
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'foto_web_picker.dart';

// ---------------------------------------------------------------------------
//  Constantes de formatos aceptados
// ---------------------------------------------------------------------------

/// Imagenes: incluye HEIC/HEIF (iPhone) y los formatos raros que la gente
/// arrastra desde el escritorio. 'image/*' solo NO basta: en varios
/// navegadores de escritorio los .heic quedan grises en el dialogo.
const String _aceptaImagen =
    'image/*,image/heic,image/heif,.heic,.heif,.HEIC,.HEIF,'
    '.jpg,.jpeg,.png,.webp,.bmp,.tif,.tiff';

const String _aceptaPdfWord =
    'application/pdf,.pdf,.doc,.docx,application/msword,'
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Milisegundos maximos que esperamos a que el navegador lea o decodifique.
/// Si se pasa, NO se cuelga: se cae al plan B (subir el original).
const Duration _esperaLectura = Duration(seconds: 30);
const Duration _esperaDecodificado = Duration(seconds: 15);

// ---------------------------------------------------------------------------
//  Utilidades internas
// ---------------------------------------------------------------------------

/// Mime real del archivo. Si el navegador lo manda vacio (tipico en .heic),
/// se deduce de la extension para que el backend lo guarde bien.
String _mimeDe(html.File file) {
  final t = file.type;
  if (t.isNotEmpty) return t;
  final n = file.name.toLowerCase();
  if (n.endsWith('.heic')) return 'image/heic';
  if (n.endsWith('.heif')) return 'image/heif';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.bmp')) return 'image/bmp';
  if (n.endsWith('.tif') || n.endsWith('.tiff')) return 'image/tiff';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.pdf')) return 'application/pdf';
  if (n.endsWith('.docx')) {
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  }
  if (n.endsWith('.doc')) return 'application/msword';
  return 'application/octet-stream';
}

/// ¿El archivo parece imagen (por mime o por extension)?
bool _pareceImagen(html.File file) => _mimeDe(file).startsWith('image/');

/// Lee el archivo con FileReader sin quedarse colgado: escucha onLoad y
/// onError, y ademas corta por timeout. Devuelve null si no se pudo leer.
Future<Object?> _leer(html.File file, {required bool comoDataUrl}) async {
  final reader = html.FileReader();
  final listo = Completer<bool>();
  reader.onLoad.first.then((_) {
    if (!listo.isCompleted) listo.complete(true);
  }).catchError((_) {
    if (!listo.isCompleted) listo.complete(false);
  });
  reader.onError.first.then((_) {
    if (!listo.isCompleted) listo.complete(false);
  }).catchError((_) {
    if (!listo.isCompleted) listo.complete(false);
  });
  if (comoDataUrl) {
    reader.readAsDataUrl(file);
  } else {
    reader.readAsArrayBuffer(file);
  }
  final ok = await listo.future
      .timeout(_esperaLectura, onTimeout: () => false);
  if (!ok) return null;
  return reader.result;
}

/// Carga la imagen en un ImageElement. Devuelve null si el navegador NO la
/// puede decodificar (caso tipico: .HEIC en Chrome/Edge de escritorio).
/// Antes esto se colgaba: aqui se resuelve siempre, por exito, error o tiempo.
Future<html.ImageElement?> _decodificar(html.File file) async {
  final res = await _leer(file, comoDataUrl: true);
  if (res is! String) return null;

  final img = html.ImageElement();
  final listo = Completer<bool>();
  img.onLoad.first.then((_) {
    if (!listo.isCompleted) listo.complete(true);
  }).catchError((_) {
    if (!listo.isCompleted) listo.complete(false);
  });
  img.onError.first.then((_) {
    if (!listo.isCompleted) listo.complete(false);
  }).catchError((_) {
    if (!listo.isCompleted) listo.complete(false);
  });
  img.src = res;

  final ok = await listo.future
      .timeout(_esperaDecodificado, onTimeout: () => false);
  if (!ok) return null;
  if (img.naturalWidth <= 0 || img.naturalHeight <= 0) return null;
  return img;
}

/// Dibuja la imagen ya cargada en un canvas reducido y la exporta como JPEG.
FotoElegida _aJpeg(html.ImageElement img, int maxLado, double calidad) {
  int w = img.naturalWidth;
  int h = img.naturalHeight;
  if (w <= 0 || h <= 0) {
    w = maxLado;
    h = maxLado;
  }
  if (w > maxLado || h > maxLado) {
    if (w >= h) {
      h = (h * maxLado / w).round();
      w = maxLado;
    } else {
      w = (w * maxLado / h).round();
      h = maxLado;
    }
  }
  if (w < 1) w = 1;
  if (h < 1) h = 1;
  final canvas = html.CanvasElement(width: w, height: h);
  canvas.context2D.drawImageScaled(img, 0, 0, w, h);
  final dataUrl = canvas.toDataUrl('image/jpeg', calidad);
  final base64Str = dataUrl.substring(dataUrl.indexOf(',') + 1);
  return FotoElegida(base64Decode(base64Str), 'image/jpeg');
}

/// Devuelve el archivo TAL CUAL (sin comprimir). Es el plan B cuando el
/// navegador no puede decodificar la imagen: mas vale subir un HEIC pesado
/// que dejar al usuario mirando un boton que no responde.
Future<DocElegido> _original(html.File file, {int maxMb = 12}) async {
  if (file.size > maxMb * 1024 * 1024) {
    throw Exception(
        'El archivo pesa ${(file.size / 1048576).toStringAsFixed(1)} MB y el '
        'maximo es $maxMb MB. Reducelo o toma la foto en menor resolucion.');
  }
  final res = await _leer(file, comoDataUrl: false);
  if (res == null) {
    throw Exception('No se pudo leer el archivo; intentalo de nuevo.');
  }
  final bytes = (res as List<int>);
  return DocElegido(bytes, _mimeDe(file), file.name);
}

/// Abre el dialogo del navegador y espera la eleccion del usuario.
Future<html.File?> _pedirArchivo(String accept) async {
  final input = html.FileUploadInputElement()..accept = accept;
  input.click();
  await input.onChange.first;
  final files = input.files;
  if (files == null || files.isEmpty) return null;
  return files.first;
}

// ---------------------------------------------------------------------------
//  API publica
// ---------------------------------------------------------------------------

Future<FotoElegida?> pickFotoImpl() async {
  final file = await _pedirArchivo(_aceptaImagen);
  if (file == null) return null;

  final img = await _decodificar(file);
  if (img == null) {
    // Aqui NO podemos caer al original: quien pide una foto (credencial,
    // firma, comprobante) necesita un JPEG/PNG que se pueda dibujar.
    throw Exception(
        'Tu navegador no pudo abrir esa imagen. Si la tomaste con un iPhone '
        'suele venir en formato HEIC: abrela y guardala como JPG o PNG, o '
        'mandatela por WhatsApp y descargala, y vuelve a intentarlo.');
  }
  return _aJpeg(img, 900, 0.75);
}

Future<DocElegido?> pickDocImpl({String tipo = 'ambos'}) async {
  String accept;
  if (tipo == 'imagen') {
    accept = _aceptaImagen; // celular: Galeria + Camara directo
  } else if (tipo == 'pdf') {
    accept = _aceptaPdfWord; // PDF o Word
  } else if (tipo == 'todos') {
    accept = '$_aceptaImagen,video/*,.pdf,application/pdf';
  } else if (tipo == 'original') {
    accept = '$_aceptaImagen,.svg,application/pdf,.pdf,.zip';
  } else {
    accept = '$_aceptaImagen,$_aceptaPdfWord'; // imagen, PDF o Word
  }

  final file = await _pedirArchivo(accept);
  if (file == null) return null;

  // 'original': se sube el archivo tal cual, sin comprimir (alta calidad).
  if (tipo == 'original') {
    return _original(file, maxMb: 20);
  }

  final nombreLow = file.name.toLowerCase();
  final tipoNav = file.type;

  final esPdf = (tipoNav == 'application/pdf') || nombreLow.endsWith('.pdf');
  final esVideo = tipoNav.startsWith('video/') ||
      nombreLow.endsWith('.mp4') ||
      nombreLow.endsWith('.mov') ||
      nombreLow.endsWith('.webm') ||
      nombreLow.endsWith('.m4v') ||
      nombreLow.endsWith('.3gp') ||
      nombreLow.endsWith('.avi');
  final esWord = (tipoNav == 'application/msword') ||
      (tipoNav ==
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document') ||
      nombreLow.endsWith('.doc') ||
      nombreLow.endsWith('.docx');

  if (esVideo) {
    if (file.size > 25 * 1024 * 1024) {
      throw Exception('El video supera 25 MB; recorta o reduce su tamano.');
    }
    final res = await _leer(file, comoDataUrl: false);
    if (res == null) throw Exception('No se pudo leer el video.');
    final bytes = (res as List<int>);
    final mime = tipoNav.isNotEmpty ? tipoNav : 'video/mp4';
    return DocElegido(bytes, mime, file.name);
  }

  if (esPdf) {
    if (file.size > 8 * 1024 * 1024) {
      throw Exception('El PDF supera 8 MB; reduce su tamano.');
    }
    final res = await _leer(file, comoDataUrl: false);
    if (res == null) throw Exception('No se pudo leer el PDF.');
    final bytes = (res as List<int>);
    return DocElegido(bytes, 'application/pdf', file.name);
  }

  if (esWord) {
    if (file.size > 12 * 1024 * 1024) {
      throw Exception('El documento supera 12 MB; reduce su tamano.');
    }
    final res = await _leer(file, comoDataUrl: false);
    if (res == null) throw Exception('No se pudo leer el documento.');
    final bytes = (res as List<int>);
    final mime = nombreLow.endsWith('.docx')
        ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
        : (nombreLow.endsWith('.doc')
            ? 'application/msword'
            : _mimeDe(file));
    return DocElegido(bytes, mime, file.name);
  }

  // IMAGEN: se intenta comprimir; si el navegador no la puede decodificar
  // (HEIC de iPhone, tiff, archivo danado) se sube el ORIGINAL en vez de
  // quedarse esperando para siempre, que era el bug.
  final img = await _decodificar(file);
  if (img != null) {
    // documentos: mas resolucion que una foto de perfil
    return DocElegido(
        _aJpeg(img, 1400, 0.85).bytes, 'image/jpeg', file.name);
  }

  if (_pareceImagen(file)) {
    return _original(file, maxMb: 12);
  }

  // Formato desconocido que el navegador tampoco pudo abrir como imagen.
  throw Exception(
      'No reconocimos ese archivo (${file.name}). Sube una foto (JPG, PNG o '
      'HEIC) o un PDF.');
}

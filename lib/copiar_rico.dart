import 'dart:html' as html;

import 'package:flutter/services.dart';

/// Utilidades de copiado al portapapeles del navegador (solo web).
///
/// [copiarConFormato] copia contenido HTML: al pegar en Word o Google Docs
/// conserva los títulos en negrita y las viñetas. Si el navegador no lo
/// permite, cae automáticamente a texto plano. [copiarTexto] copia solo
/// texto plano (para WhatsApp, correo, campos simples, etc.).
///
/// Usa el mismo idioma `dart:html` que csv_export.dart (la app compila a web).

/// Copia [htmlContenido] con formato y deja [textoPlano] como respaldo.
/// Devuelve true si logró copiar de alguna forma.
Future<bool> copiarConFormato(String htmlContenido, String textoPlano) async {
  // Elemento editable oculto: se selecciona su contenido y se copia. Así el
  // portapapeles recibe HTML enriquecido (text/html) y el pegado conserva
  // negritas y viñetas en Word/Google Docs.
  try {
    final div = html.DivElement()
      ..style.position = 'fixed'
      ..style.left = '-99999px'
      ..style.top = '0'
      ..style.whiteSpace = 'pre-wrap'
      ..contentEditable = 'true';
    div.setInnerHtml(htmlContenido,
        treeSanitizer: html.NodeTreeSanitizer.trusted);
    html.document.body!.append(div);

    final selection = html.window.getSelection();
    final range = html.document.createRange()..selectNodeContents(div);
    selection!
      ..removeAllRanges()
      ..addRange(range);

    final ok = html.document.execCommand('copy');
    selection.removeAllRanges();
    div.remove();
    if (ok) return true;
  } catch (_) {
    // Cae al respaldo de texto plano.
  }
  return copiarTexto(textoPlano);
}

/// Copia únicamente [texto] plano al portapapeles.
Future<bool> copiarTexto(String texto) async {
  try {
    await Clipboard.setData(ClipboardData(text: texto));
    return true;
  } catch (_) {
    return false;
  }
}

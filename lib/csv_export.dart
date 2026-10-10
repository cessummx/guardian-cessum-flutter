import 'dart:convert';
import 'dart:html' as html;

/// Descarga un archivo CSV en el navegador (solo web). Incluye BOM para que
/// Excel respete acentos.
void descargarCsv(String nombreArchivo, String contenido) {
  final bytes = utf8.encode('\uFEFF$contenido');
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = nombreArchivo
    ..style.display = 'none';
  html.document.body!.append(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
}

/// Escapa un valor para CSV (comillas, comas, saltos de línea).
String csvCampo(Object? v) {
  final s = (v ?? '').toString();
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// Une una fila de campos en una línea CSV.
String csvFila(List<Object?> campos) => campos.map(csvCampo).join(',');

/// Arma un CSV completo a partir de encabezados y filas.
String construirCsv(List<String> encabezados, List<List<Object?>> filas) {
  final b = StringBuffer();
  b.writeln(csvFila(encabezados));
  for (final f in filas) {
    b.writeln(csvFila(f));
  }
  return b.toString();
}

import 'package:flutter/material.dart';

/// Renderizador ligero de Markdown para las respuestas del Asistente CESSUM.
///
/// NO usa librerías externas (no hay que tocar pubspec.yaml). Entiende lo que
/// suele devolver la IA:
///   - Títulos:   # , ## , ###
///   - Negritas:  **texto**
///   - Listas:    - , * , •
///   - Tablas:    | col | col |  con su fila separadora |---|---|
/// Cualquier otra cosa se muestra como texto normal.
///
/// Uso:  CessumMd(m.texto)
class CessumMd extends StatelessWidget {
  final String text;
  final Color color;
  final double fontSize;

  const CessumMd(
    this.text, {
    super.key,
    this.color = const Color(0xFF1A1A1A),
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final bloques = <Widget>[];
    int i = 0;

    while (i < lines.length) {
      final t = lines[i].trim();

      // ---------- TABLA ----------
      if (_esFilaTabla(t)) {
        final filas = <String>[];
        int j = i;
        while (j < lines.length && _esFilaTabla(lines[j].trim())) {
          filas.add(lines[j].trim());
          j++;
        }
        if (filas.length >= 2) {
          final tabla = _tabla(filas);
          if (tabla != null) {
            bloques.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: tabla,
            ));
            i = j;
            continue;
          }
        }
        // No resultó una tabla válida: mostrar como párrafos.
        for (final f in filas) {
          bloques.add(_parrafo(f));
        }
        i = j;
        continue;
      }

      // ---------- TÍTULOS ----------
      if (t.startsWith('### ')) {
        bloques.add(_parrafo(t.substring(4),
            peso: FontWeight.w700, tam: fontSize + 1));
        i++;
        continue;
      }
      if (t.startsWith('## ')) {
        bloques.add(_parrafo(t.substring(3),
            peso: FontWeight.w800, tam: fontSize + 2));
        i++;
        continue;
      }
      if (t.startsWith('# ')) {
        bloques.add(_parrafo(t.substring(2),
            peso: FontWeight.w800, tam: fontSize + 4));
        i++;
        continue;
      }

      // ---------- LISTAS ----------
      if (t.startsWith('- ') || t.startsWith('* ') || t.startsWith('• ')) {
        bloques.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 1, bottom: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ',
                  style: TextStyle(
                      color: color, fontSize: fontSize, height: 1.4)),
              Expanded(child: _rich(t.substring(2))),
            ],
          ),
        ));
        i++;
        continue;
      }

      // ---------- LÍNEA EN BLANCO ----------
      if (t.isEmpty) {
        bloques.add(const SizedBox(height: 6));
        i++;
        continue;
      }

      // ---------- PÁRRAFO NORMAL ----------
      bloques.add(_parrafo(t));
      i++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: bloques,
    );
  }

  // ---- Tablas ----

  bool _esFilaTabla(String t) =>
      t.startsWith('|') && t.endsWith('|') && t.length > 2;

  bool _esSeparador(String t) {
    final celdas = _celdas(t);
    if (celdas.isEmpty) return false;
    for (final c in celdas) {
      final s = c.replaceAll(RegExp(r'[\s:]'), '');
      if (s.isEmpty || !RegExp(r'^-+$').hasMatch(s)) return false;
    }
    return true;
  }

  List<String> _celdas(String fila) {
    var f = fila.trim();
    if (f.startsWith('|')) f = f.substring(1);
    if (f.endsWith('|')) f = f.substring(0, f.length - 1);
    return f.split('|').map((c) => c.trim()).toList();
  }

  Widget? _tabla(List<String> filas) {
    final datos = <List<String>>[];
    for (final f in filas) {
      if (_esSeparador(f)) continue;
      datos.add(_celdas(f));
    }
    if (datos.isEmpty) return null;
    final ncol = datos.first.length;
    if (ncol < 1) return null;

    return Table(
      border: TableBorder.all(color: const Color(0xFFD8D8D8), width: 1),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        for (int r = 0; r < datos.length; r++)
          TableRow(
            decoration: BoxDecoration(
              color: r == 0 ? const Color(0xFFF3EEE2) : Colors.transparent,
            ),
            children: [
              for (int c = 0; c < ncol; c++)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  child: _rich(
                    c < datos[r].length ? datos[r][c] : '',
                    peso: r == 0 ? FontWeight.w700 : FontWeight.w400,
                    selectable: false,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  // ---- Párrafos / inline ----

  Widget _parrafo(String t, {FontWeight peso = FontWeight.w400, double? tam}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: _rich(t, peso: peso, tam: tam),
    );
  }

  /// Procesa **negritas** dentro de una línea y devuelve texto enriquecido.
  Widget _rich(String t,
      {FontWeight peso = FontWeight.w400,
      double? tam,
      bool selectable = true}) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final m in regex.allMatches(t)) {
      if (m.start > last) {
        spans.add(TextSpan(text: t.substring(last, m.start)));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ));
      last = m.end;
    }
    if (last < t.length) spans.add(TextSpan(text: t.substring(last)));

    final root = TextSpan(
      style: TextStyle(
        color: color,
        fontSize: tam ?? fontSize,
        fontWeight: peso,
        height: 1.4,
      ),
      children: spans.isEmpty ? [TextSpan(text: t)] : spans,
    );

    return selectable ? SelectableText.rich(root) : Text.rich(root);
  }
}

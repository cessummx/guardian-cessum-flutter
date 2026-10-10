// GRÁFICAS DE FINANZAS (23-sep-2026)
//
// Dibujadas con CustomPainter, igual que las gráficas que ya existen en la app
// (mi_informe_docente_screen, torre_control_screen): sin librerías nuevas, así
// que no cambia el pubspec ni el «flutter pub get».
//
//   FinGraficaLineas  → varias series, banda de confianza, tramo proyectado
//                       punteado y línea vertical donde empieza la proyección.
//   FinGraficaBarras  → barras agrupadas (por ejemplo, años lado a lado).
//   FinMapaCalor      → año × mes, en verde (o verde/rojo si hay negativos).
import 'package:flutter/material.dart';

const List<String> kFinMes3 = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
];

/// Etiqueta corta de un periodo «2026-08» → «ago 26».
String finEtiqueta(String p) {
  if (p.length < 7) return p;
  final m = int.tryParse(p.substring(5, 7)) ?? 1;
  return '${kFinMes3[(m - 1).clamp(0, 11)]} ${p.substring(2, 4)}';
}

/// Cantidad compacta para ejes: $1.2 M, $850 k, $950.
String finCompacto(double v) {
  final neg = v < 0;
  final a = v.abs();
  String s;
  if (a >= 1000000) {
    s = '\$${(a / 1000000).toStringAsFixed(a >= 10000000 ? 0 : 1)} M';
  } else if (a >= 1000) {
    s = '\$${(a / 1000).toStringAsFixed(0)} k';
  } else {
    s = '\$${a.toStringAsFixed(0)}';
  }
  return neg ? '-$s' : s;
}

class FinSerie {
  final String nombre;
  final Color color;
  final List<double?> valores;
  final bool punteada;
  final double grosor;
  const FinSerie(this.nombre, this.color, this.valores,
      {this.punteada = false, this.grosor = 2.2});
}

class FinLeyenda extends StatelessWidget {
  final List<MapEntry<String, Color>> items;
  const FinLeyenda(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 14, runSpacing: 4, children: [
      for (final it in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: it.value, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(it.key, style: const TextStyle(fontSize: 11.5)),
        ]),
    ]);
  }
}

/// Cantidad completa para los recuadros: $1,234,567.
String finMoneda(double v) {
  final neg = v < 0;
  final e = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < e.length; i++) {
    if (i > 0 && (e.length - i) % 3 == 0) b.write(',');
    b.write(e[i]);
  }
  return '${neg ? '-' : ''}\$$b';
}

/// Recuadro con valores, dibujado sobre el lienzo (para líneas y barras).
void _finRecuadro(Canvas canvas, Size size, double x, String titulo,
    List<MapEntry<String, Color>> lineas, bool oscuro) {
  final tp = TextPainter(textDirection: TextDirection.ltr);
  final spans = <TextSpan>[
    TextSpan(
        text: '$titulo\n',
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: oscuro ? Colors.white : Colors.black87)),
    for (var k = 0; k < lineas.length; k++)
      TextSpan(
          text: '${lineas[k].key}${k < lineas.length - 1 ? '\n' : ''}',
          style: TextStyle(fontSize: 10.5, height: 1.35, color: lineas[k].value, fontWeight: FontWeight.w600)),
  ];
  tp.text = TextSpan(children: spans);
  tp.layout(maxWidth: 240);
  const pad = 8.0;
  final w = tp.width + pad * 2, h = tp.height + pad * 2;
  var left = x + 12;
  if (left + w > size.width) left = x - 12 - w;
  if (left < 0) left = 0;
  final r = RRect.fromRectAndRadius(Rect.fromLTWH(left, 4, w, h), const Radius.circular(8));
  canvas.drawRRect(r.shift(const Offset(0, 2)), Paint()..color = const Color(0x22000000));
  canvas.drawRRect(r, Paint()..color = oscuro ? const Color(0xF0303030) : const Color(0xF7FFFFFF));
  canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = oscuro ? Colors.white24 : Colors.black12);
  tp.paint(canvas, Offset(left + pad, 4 + pad));
}

/* ======================================================================
   LÍNEAS · interactivas: guía y recuadro al pasar el ratón o el dedo,
   series que se prenden y apagan tocando la leyenda, y rango de meses.
   ====================================================================== */
class FinGraficaLineas extends StatefulWidget {
  final List<String> etiquetas;
  final List<FinSerie> series;
  final List<double?>? bandaInf;
  final List<double?>? bandaSup;
  final String? nombreBanda;
  final Color colorBanda;
  final int? corte;
  final double alto;
  final bool rangos; // muestra 12m / 24m / 36m / Todo
  final String Function(double)? formato;
  /// (24-sep) Rótulos del eje. Por omisión, pesos compactos ($12 k), como en Finanzas.
  final String Function(double)? formatoEje;

  const FinGraficaLineas({
    super.key,
    required this.etiquetas,
    required this.series,
    this.bandaInf,
    this.bandaSup,
    this.nombreBanda,
    this.colorBanda = const Color(0xFF1E7F52),
    this.corte,
    this.alto = 220,
    this.rangos = false,
    this.formato,
    this.formatoEje,
  });

  @override
  State<FinGraficaLineas> createState() => _FinGraficaLineasState();
}

class _FinGraficaLineasState extends State<FinGraficaLineas> {
  int? _hover;
  final Set<int> _ocultas = {};
  int _rango = 0; // 0 = todo

  List<T> _corta<T>(List<T> l, int desde) => desde <= 0 ? l : (desde < l.length ? l.sublist(desde) : <T>[]);

  void _ubicar(double dx, double ancho, int n) {
    const izq = 54.0, der = 10.0;
    if (n <= 0) return;
    final w = ancho - izq - der;
    final i = n == 1 ? 0 : (((dx - izq) / w) * (n - 1)).round().clamp(0, n - 1).toInt();
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final n0 = widget.etiquetas.length;
    final desde = (widget.rangos && _rango > 0 && n0 > _rango) ? n0 - _rango : 0;
    final et = _corta(widget.etiquetas, desde);
    final visibles = <FinSerie>[
      for (var k = 0; k < widget.series.length; k++)
        if (!_ocultas.contains(k))
          FinSerie(widget.series[k].nombre, widget.series[k].color, _corta(widget.series[k].valores, desde),
              punteada: widget.series[k].punteada, grosor: widget.series[k].grosor),
    ];
    final inf = widget.bandaInf == null ? null : _corta(widget.bandaInf!, desde);
    final sup = widget.bandaSup == null ? null : _corta(widget.bandaSup!, desde);
    final corte = widget.corte == null ? null : widget.corte! - desde;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final hover = (_hover != null && _hover! < et.length) ? _hover : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var k = 0; k < widget.series.length; k++)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() {
              if (_ocultas.contains(k)) {
                _ocultas.remove(k);
              } else if (_ocultas.length < widget.series.length - 1) {
                _ocultas.add(k);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        color: _ocultas.contains(k) ? Colors.transparent : widget.series[k].color,
                        border: Border.all(color: widget.series[k].color, width: 1.5),
                        shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(widget.series[k].nombre,
                    style: TextStyle(
                        fontSize: 11.5,
                        decoration: _ocultas.contains(k) ? TextDecoration.lineThrough : null)),
              ]),
            ),
          ),
        if (widget.bandaInf != null && widget.nombreBanda != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 10, color: widget.colorBanda.withValues(alpha: 0.25)),
              const SizedBox(width: 5),
              Text(widget.nombreBanda!, style: const TextStyle(fontSize: 11.5)),
            ]),
          ),
        if (widget.rangos && n0 > 12)
          for (final r in const [12, 24, 36, 0])
            if (r == 0 || n0 > r)
              ChoiceChip(
                label: Text(r == 0 ? 'Todo' : '$r m', style: const TextStyle(fontSize: 11)),
                selected: _rango == r,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() {
                  _rango = r;
                  _hover = null;
                }),
              ),
      ]),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (ctx, cons) {
        final ancho = cons.maxWidth;
        return MouseRegion(
          onHover: (e) => _ubicar(e.localPosition.dx, ancho, et.length),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            onTapDown: (e) => _ubicar(e.localPosition.dx, ancho, et.length),
            onHorizontalDragUpdate: (e) => _ubicar(e.localPosition.dx, ancho, et.length),
            child: SizedBox(
              width: ancho,
              height: widget.alto,
              child: CustomPaint(
                painter: _PintorLineas(et, visibles, inf, sup, widget.colorBanda, widget.nombreBanda, corte,
                    oscuro, hover, widget.formato ?? finMoneda, widget.formatoEje ?? finCompacto),
              ),
            ),
          ),
        );
      }),
    ]);
  }
}

class _PintorLineas extends CustomPainter {
  final List<String> et;
  final List<FinSerie> series;
  final List<double?>? inf;
  final List<double?>? sup;
  final Color colorBanda;
  final String? nombreBanda;
  final int? corte;
  final bool oscuro;
  final int? hover;
  final String Function(double) formato;
  final String Function(double) formatoEje;
  _PintorLineas(this.et, this.series, this.inf, this.sup, this.colorBanda, this.nombreBanda, this.corte, this.oscuro,
      this.hover, this.formato, this.formatoEje);

  @override
  void paint(Canvas canvas, Size size) {
    const izq = 54.0, abajo = 22.0, arriba = 8.0, der = 10.0;
    final n = et.length;
    if (n == 0) return;
    final w = size.width - izq - der;
    final h = size.height - abajo - arriba;

    double? mn, mx;
    void mide(List<double?>? l) {
      if (l == null) return;
      for (final v in l) {
        if (v == null || v.isNaN) continue;
        mn = mn == null ? v : (v < mn! ? v : mn);
        mx = mx == null ? v : (v > mx! ? v : mx);
      }
    }

    for (final s in series) {
      mide(s.valores);
    }
    mide(inf);
    mide(sup);
    if (mn == null || mx == null) return;
    var lo = mn!, hi = mx!;
    if (lo > 0 && lo < hi * 0.35) lo = 0;
    if (hi == lo) {
      hi = lo + 1;
    }
    final pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;

    double x(int i) => izq + (n == 1 ? w / 2 : w * i / (n - 1));
    double y(double v) => arriba + h * (1 - (v - lo) / (hi - lo));

    final colTexto = oscuro ? Colors.white60 : Colors.black45;
    final guia = Paint()
      ..color = oscuro ? const Color(0x22FFFFFF) : const Color(0xFFE6E6E6)
      ..strokeWidth = 1;
    final texto = TextPainter(textDirection: TextDirection.ltr);

    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      final yy = y(v);
      canvas.drawLine(Offset(izq, yy), Offset(size.width - der, yy), guia);
      texto
        ..text = TextSpan(text: formatoEje(v), style: TextStyle(fontSize: 9, color: colTexto))
        ..layout();
      texto.paint(canvas, Offset(izq - texto.width - 5, yy - 6));
    }
    if (lo < 0 && hi > 0) {
      canvas.drawLine(Offset(izq, y(0)), Offset(size.width - der, y(0)),
          Paint()
            ..color = oscuro ? Colors.white38 : Colors.black38
            ..strokeWidth = 1.2);
    }

    if (inf != null && sup != null) {
      final banda = Path();
      final idx = <int>[];
      for (var i = 0; i < n && i < inf!.length && i < sup!.length; i++) {
        if (inf![i] != null && sup![i] != null) idx.add(i);
      }
      if (idx.length >= 2) {
        banda.moveTo(x(idx.first), y(sup![idx.first]!));
        for (final i in idx) {
          banda.lineTo(x(i), y(sup![i]!));
        }
        for (final i in idx.reversed) {
          banda.lineTo(x(i), y(inf![i]!));
        }
        banda.close();
        canvas.drawPath(banda, Paint()..color = colorBanda.withValues(alpha: 0.14));
      }
    }

    if (corte != null && corte! > 0 && corte! < n) {
      final xc = x(corte!) - (n > 1 ? w / (n - 1) / 2 : 0);
      final p = Paint()
        ..color = oscuro ? Colors.white38 : Colors.black26
        ..strokeWidth = 1;
      for (var yy = arriba; yy < arriba + h; yy += 8) {
        canvas.drawLine(Offset(xc, yy), Offset(xc, yy + 4), p);
      }
      texto
        ..text = TextSpan(
            text: 'Proyección →', style: TextStyle(fontSize: 9, color: colTexto, fontWeight: FontWeight.w600))
        ..layout();
      texto.paint(canvas, Offset(xc + 4, arriba + (hover == null ? 0 : h - 14)));
    }

    for (final s in series) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.grosor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      var trazo = Path();
      var abierto = false;
      void cierra() {
        if (!abierto) return;
        if (s.punteada) {
          _punteada(canvas, trazo, paint);
        } else {
          canvas.drawPath(trazo, paint);
        }
        trazo = Path();
        abierto = false;
      }

      for (var i = 0; i < n && i < s.valores.length; i++) {
        final v = s.valores[i];
        if (v == null || v.isNaN) {
          cierra();
          continue;
        }
        final o = Offset(x(i), y(v));
        if (!abierto) {
          trazo.moveTo(o.dx, o.dy);
          abierto = true;
        } else {
          trazo.lineTo(o.dx, o.dy);
        }
        if (n <= 40) canvas.drawCircle(o, 2.2, Paint()..color = s.color);
      }
      cierra();
    }

    final paso = n <= 8 ? 1 : (n / 8).ceil();
    for (var i = 0; i < n; i += paso) {
      texto
        ..text = TextSpan(text: et[i], style: TextStyle(fontSize: 9, color: colTexto))
        ..layout();
      final xx = (x(i) - texto.width / 2).clamp(0.0, size.width - texto.width).toDouble();
      texto.paint(canvas, Offset(xx, size.height - abajo + 6));
    }

    // Guía y recuadro del punto señalado.
    if (hover != null && hover! < n) {
      final hx = x(hover!);
      canvas.drawLine(Offset(hx, arriba), Offset(hx, arriba + h),
          Paint()
            ..color = oscuro ? Colors.white54 : Colors.black45
            ..strokeWidth = 1);
      final lineas = <MapEntry<String, Color>>[];
      for (final s in series) {
        final v = hover! < s.valores.length ? s.valores[hover!] : null;
        if (v == null || v.isNaN) continue;
        canvas.drawCircle(Offset(hx, y(v)), 5, Paint()..color = s.color);
        canvas.drawCircle(
            Offset(hx, y(v)),
            5,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
        lineas.add(MapEntry('${s.nombre}: ${formato(v)}', s.color));
      }
      if (inf != null && sup != null && hover! < inf!.length && hover! < sup!.length &&
          inf![hover!] != null && sup![hover!] != null) {
        lineas.add(MapEntry('${nombreBanda ?? 'Intervalo'}: ${formato(inf![hover!]!)} a ${formato(sup![hover!]!)}',
            oscuro ? Colors.white70 : Colors.black54));
      }
      if (lineas.isNotEmpty) _finRecuadro(canvas, size, hx, et[hover!], lineas, oscuro);
    }
  }

  void _punteada(Canvas canvas, Path p, Paint paint) {
    for (final m in p.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final fin = (d + 6 < m.length) ? d + 6 : m.length;
        canvas.drawPath(m.extractPath(d, fin), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/* ======================================================================
   BARRAS AGRUPADAS · interactivas: tocar o pasar el ratón muestra el grupo
   ====================================================================== */
class FinGraficaBarras extends StatefulWidget {
  final List<String> grupos;
  final List<FinSerie> series; // valores por grupo, en el mismo orden
  final double alto;
  final bool mostrarValores;
  final String Function(double)? formato;
  final String Function(double)? formatoEje;
  const FinGraficaBarras({
    super.key,
    required this.grupos,
    required this.series,
    this.alto = 200,
    this.mostrarValores = true,
    this.formato,
    this.formatoEje,
  });

  @override
  State<FinGraficaBarras> createState() => _FinGraficaBarrasState();
}

class _FinGraficaBarrasState extends State<FinGraficaBarras> {
  int? _hover;

  void _ubicar(double dx, double ancho) {
    const izq = 54.0, der = 6.0;
    final g = widget.grupos.length;
    if (g == 0) return;
    final i = (((dx - izq) / (ancho - izq - der)) * g).floor().clamp(0, g - 1).toInt();
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.series.length > 1) FinLeyenda([for (final s in widget.series) MapEntry(s.nombre, s.color)]),
      if (widget.series.length > 1) const SizedBox(height: 8),
      LayoutBuilder(builder: (ctx, cons) {
        final ancho = cons.maxWidth;
        return MouseRegion(
          onHover: (e) => _ubicar(e.localPosition.dx, ancho),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            onTapDown: (e) => _ubicar(e.localPosition.dx, ancho),
            child: SizedBox(
              width: ancho,
              height: widget.alto,
              child: CustomPaint(
                painter: _PintorBarras(widget.grupos, widget.series, widget.mostrarValores, oscuro, _hover,
                    widget.formato ?? finMoneda, widget.formatoEje ?? finCompacto),
              ),
            ),
          ),
        );
      }),
    ]);
  }
}

class _PintorBarras extends CustomPainter {
  final List<String> grupos;
  final List<FinSerie> series;
  final bool valores;
  final bool oscuro;
  final int? hover;
  final String Function(double) formato;
  final String Function(double) formatoEje;
  _PintorBarras(this.grupos, this.series, this.valores, this.oscuro, this.hover, this.formato, this.formatoEje);

  @override
  void paint(Canvas canvas, Size size) {
    const izq = 54.0, abajo = 22.0, arriba = 14.0, der = 6.0;
    final g = grupos.length;
    if (g == 0 || series.isEmpty) return;
    final w = size.width - izq - der;
    final h = size.height - abajo - arriba;
    var lo = 0.0, hi = 0.0;
    for (final s in series) {
      for (final v in s.valores) {
        if (v == null) continue;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    if (hi == lo) hi = lo + 1;
    hi += (hi - lo) * 0.08;
    double y(double v) => arriba + h * (1 - (v - lo) / (hi - lo));

    final colTexto = oscuro ? Colors.white60 : Colors.black45;
    final guia = Paint()
      ..color = oscuro ? const Color(0x22FFFFFF) : const Color(0xFFE6E6E6)
      ..strokeWidth = 1;
    final texto = TextPainter(textDirection: TextDirection.ltr);
    for (var k = 0; k <= 4; k++) {
      final v = lo + (hi - lo) * k / 4;
      canvas.drawLine(Offset(izq, y(v)), Offset(size.width - der, y(v)), guia);
      texto
        ..text = TextSpan(text: formatoEje(v), style: TextStyle(fontSize: 9, color: colTexto))
        ..layout();
      texto.paint(canvas, Offset(izq - texto.width - 5, y(v) - 6));
    }

    final anchoGrupo = w / g;
    final anchoBarra = (anchoGrupo * 0.72) / series.length;
    if (hover != null && hover! < g) {
      canvas.drawRect(Rect.fromLTWH(izq + anchoGrupo * hover!, arriba, anchoGrupo, h),
          Paint()..color = oscuro ? const Color(0x14FFFFFF) : const Color(0x0F000000));
    }
    for (var i = 0; i < g; i++) {
      final x0 = izq + anchoGrupo * i + anchoGrupo * 0.14;
      for (var s = 0; s < series.length; s++) {
        final v = i < series[s].valores.length ? series[s].valores[i] : null;
        if (v == null) continue;
        final xa = x0 + anchoBarra * s;
        final r = Rect.fromLTRB(xa, y(v > 0 ? v : 0), xa + anchoBarra - 2, y(v > 0 ? 0 : v));
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)),
            Paint()..color = (hover == null || hover == i) ? series[s].color : series[s].color.withValues(alpha: 0.45));
        if (valores && anchoBarra > 26 && hover == null) {
          texto
            ..text = TextSpan(text: formatoEje(v), style: TextStyle(fontSize: 8.5, color: colTexto))
            ..layout();
          texto.paint(canvas, Offset(xa + (anchoBarra - 2 - texto.width) / 2, y(v > 0 ? v : 0) - 12));
        }
      }
      texto
        ..text = TextSpan(text: grupos[i], style: TextStyle(fontSize: 10, color: colTexto))
        ..layout();
      texto.paint(canvas, Offset(izq + anchoGrupo * i + (anchoGrupo - texto.width) / 2, size.height - abajo + 6));
    }
    if (lo < 0) {
      canvas.drawLine(Offset(izq, y(0)), Offset(size.width - der, y(0)),
          Paint()
            ..color = oscuro ? Colors.white38 : Colors.black38
            ..strokeWidth = 1.2);
    }
    if (hover != null && hover! < g) {
      final lineas = <MapEntry<String, Color>>[
        for (final s in series)
          if (hover! < s.valores.length && s.valores[hover!] != null)
            MapEntry('${s.nombre}: ${formato(s.valores[hover!]!)}', s.color),
      ];
      if (lineas.isNotEmpty) {
        _finRecuadro(canvas, size, izq + anchoGrupo * (hover! + 0.5), grupos[hover!], lineas, oscuro);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/* ======================================================================
   MAPA DE CALOR · año × mes
   ====================================================================== */
class FinMapaCalor extends StatelessWidget {
  final List<String> filas; // años
  final List<List<double?>> valores; // [fila][mes 0..11]
  final bool divergente; // verde positivo / rojo negativo
  const FinMapaCalor({
    super.key,
    required this.filas,
    required this.valores,
    this.divergente = false,
  });

  @override
  Widget build(BuildContext context) {
    const verde = Color(0xFF1E7F52);
    const rojo = Color(0xFFC8202F);
    double mn = double.infinity, mx = -double.infinity, maxAbs = 0;
    for (final f in valores) {
      for (final v in f) {
        if (v == null) continue;
        if (v < mn) mn = v;
        if (v > mx) mx = v;
        if (v.abs() > maxAbs) maxAbs = v.abs();
      }
    }
    Color color(double? v) {
      if (v == null) return Colors.transparent;
      if (divergente) {
        final t = maxAbs > 0 ? (v.abs() / maxAbs) : 0.0;
        return (v >= 0 ? verde : rojo).withValues(alpha: 0.12 + 0.78 * t);
      }
      final t = (mx > mn) ? (v - mn) / (mx - mn) : 0.5;
      return verde.withValues(alpha: 0.10 + 0.80 * t);
    }

    final muted = Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black45;
    return Column(children: [
      Row(children: [
        const SizedBox(width: 40),
        for (final m in kFinMes3)
          Expanded(
              child: Center(
                  child: Text(m, style: TextStyle(fontSize: 9.5, color: muted)))),
      ]),
      const SizedBox(height: 4),
      for (var r = 0; r < filas.length; r++)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            SizedBox(
                width: 40,
                child: Text(filas[r],
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            for (var c = 0; c < 12; c++)
              Expanded(
                child: Tooltip(
                  message: (c < valores[r].length && valores[r][c] != null)
                      ? '${kFinMes3[c]} ${filas[r]}: ${finCompacto(valores[r][c]!)}'
                      : 'Sin datos',
                  child: Container(
                    height: 26,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: color(c < valores[r].length ? valores[r][c] : null),
                      borderRadius: BorderRadius.circular(4),
                      border: (c < valores[r].length && valores[r][c] == null)
                          ? Border.all(color: muted.withValues(alpha: 0.25))
                          : null,
                    ),
                  ),
                ),
              ),
          ]),
        ),
    ]);
  }
}

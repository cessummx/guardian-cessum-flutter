import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Torre de Control CESSUM: Índice de Salud Institucional (0-100) calculado
/// en vivo de los datos reales, con desglose por dimensión y focos de atención.
class TorreControlScreen extends StatefulWidget {
  const TorreControlScreen({super.key});

  @override
  State<TorreControlScreen> createState() => _TorreControlScreenState();
}

class _TorreControlScreenState extends State<TorreControlScreen> {
  static const Color _verde = Color(0xFF1E8E3E);
  static const Color _naranja = Color(0xFFE08A00);

  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _puntos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=indice_salud'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
      });
      _cargarHistorial();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo calcular el índice. Reintenta en un momento.';
      });
    }
  }

  Future<void> _cargarHistorial() async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=indice_historial'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return;
      if (!mounted) return;
      setState(() {
        _puntos = ((data['puntos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {/* el historial es opcional */}
  }

  Color _colorIndice(int v) {
    if (v >= 85) return _verde;
    if (v >= 70) return cessumGold;
    if (v >= 50) return _naranja;
    return cessumRed;
  }

  String _recomendacion(String dim) {
    if (dim.startsWith('Calidad')) {
      return 'Revisa el panel de Salud de datos y corrige los problemas.';
    }
    if (dim.startsWith('Captura')) {
      return 'Envía recordatorio a los docentes con captura pendiente.';
    }
    if (dim.startsWith('Retención')) {
      return 'Atiende a los alumnos en riesgo desde Riesgo académico.';
    }
    if (dim.startsWith('Actividad')) {
      return 'Contacta a los inactivos desde el Aula Virtual.';
    }
    return 'Revisa esta dimensión.';
  }

  /// Copia el estado institucional como texto, listo para un oficio o reporte.
  void _copiarResumen() {
    if (_data.isEmpty) return;
    final indice = (_data['indice'] ?? 0) as int;
    final nivel = (_data['nivel'] ?? '').toString();
    final dims = (_data['dimensiones'] as List?) ?? [];
    final focos = (_data['focos'] as List?) ?? [];
    final b = StringBuffer()
      ..writeln('CESSUM — Índice de Salud Institucional')
      ..writeln('Índice: $indice/100 — $nivel')
      ..writeln('Alumnos activos: ${_data['alumnosActivos'] ?? 0}')
      ..writeln('Actualizado: ${_data['actualizado'] ?? ''}')
      ..writeln('')
      ..writeln('Dimensiones:');
    for (final d in dims) {
      final m = d as Map;
      b.writeln('- ${m['nombre'] ?? ''}: ${m['valor'] ?? 0}/100');
    }
    if (focos.isNotEmpty) {
      b.writeln('');
      b.writeln('Focos de atención:');
      for (final f in focos) {
        final m = f as Map;
        final nombre = (m['nombre'] ?? '').toString();
        b.writeln('- $nombre (${m['valor'] ?? 0}/100): '
            '${_recomendacion(nombre)}');
      }
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Resumen institucional');
  }

  @override
  Widget build(BuildContext context) {
    final indice = (_data['indice'] ?? 0) as int;
    final nivel = (_data['nivel'] ?? '').toString();
    final dims = (_data['dimensiones'] as List?) ?? [];
    final focos = (_data['focos'] as List?) ?? [];
    final color = _colorIndice(indice);

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Torre de Control',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: (_cargando || _data.isEmpty) ? null : _copiarResumen,
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copiar resumen'),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(color: cessumRed),
                  SizedBox(height: 14),
                  Text('Calculando el índice institucional...',
                      style: TextStyle(color: Colors.black54)),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            textAlign: TextAlign.center),
                      ),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _gauge(indice, nivel, color),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '${_data['alumnosActivos'] ?? 0} alumnos activos · '
                        'actualizado ${_data['actualizado'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black45),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _titulo('Dimensiones'),
                    ...dims.map((d) => _dimension(d as Map)),
                    if (focos.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _titulo('Focos de atención'),
                      ...focos.map((f) => _foco(f as Map)),
                    ] else ...[
                      const SizedBox(height: 22),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _verde.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified, color: _verde),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Todas las dimensiones están en buen nivel. '
                                'Sin focos de atención por ahora.',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _titulo('Evolución del índice'),
                    _evolucion(),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _evolucion() {
    if (_puntos.length < 2) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          'Aún no hay suficiente historial. El índice se guarda solo cada día; '
          'en unos días verás aquí su evolución.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
      );
    }
    final valores = _puntos
        .map((p) => (p['indice'] ?? 0) as int)
        .toList();
    final primero = valores.first;
    final ultimo = valores.last;
    final dif = ultimo - primero;
    final color = _colorIndice(ultimo);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${_puntos.length} días registrados',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54)),
              const Spacer(),
              Icon(
                  dif > 0
                      ? Icons.trending_up
                      : (dif < 0 ? Icons.trending_down : Icons.trending_flat),
                  size: 18,
                  color: dif > 0
                      ? const Color(0xFF1E8E3E)
                      : (dif < 0 ? cessumRed : Colors.black45)),
              const SizedBox(width: 4),
              Text(
                  dif == 0
                      ? 'estable'
                      : (dif > 0 ? '+$dif' : '$dif') + ' pts',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: dif > 0
                          ? const Color(0xFF1E8E3E)
                          : (dif < 0 ? cessumRed : Colors.black45))),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
              painter: _SparkPainter(valores, color),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_puntos.first['fecha']}',
                  style: const TextStyle(fontSize: 10, color: Colors.black45)),
              Text('${_puntos.last['fecha']}',
                  style: const TextStyle(fontSize: 10, color: Colors.black45)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gauge(int indice, String nivel, Color color) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 26),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7A1420), cessumRed],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const Text('ÍNDICE DE SALUD INSTITUCIONAL',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(190, 190),
                    painter: _GaugePainter(indice / 100.0, color),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$indice',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              height: 1.0)),
                      const Text('de 100',
                          style: TextStyle(
                              color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(nivel.toUpperCase(),
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.6)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(t,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed)),
    );
  }

  Widget _dimension(Map d) {
    final valor = (d['valor'] ?? 0) as int;
    final color = _colorIndice(valor);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((d['nombre'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Text('$valor',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (valor / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Text((d['detalle'] ?? '').toString(),
              style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _foco(Map f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.priority_high, color: cessumRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${f['nombre']} · ${f['valor']}/100',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(_recomendacion((f['nombre'] ?? '').toString()),
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibuja el arco del medidor (270°) de fondo y el progreso coloreado.
class _GaugePainter extends CustomPainter {
  final double valor; // 0.0 - 1.0
  final Color color;
  _GaugePainter(this.valor, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const inicio = math.pi * 0.75; // arranca abajo-izquierda
    const barrido = math.pi * 1.5; // 270°

    final fondo = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        inicio, barrido, false, fondo);

    final progreso = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        inicio, barrido * valor.clamp(0.0, 1.0), false, progreso);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.valor != valor || old.color != color;
}

/// Dibuja un sparkline (línea de evolución) del índice con relleno suave.
class _SparkPainter extends CustomPainter {
  final List<int> valores;
  final Color color;
  _SparkPainter(this.valores, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (valores.length < 2) return;
    const minV = 0.0;
    const maxV = 100.0;
    final n = valores.length;
    final dx = size.width / (n - 1);
    double yDe(int v) {
      final t = ((v - minV) / (maxV - minV)).clamp(0.0, 1.0);
      return size.height - t * size.height;
    }

    // líneas guía 50 y 85
    final guia = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    for (final g in [50, 85]) {
      final y = yDe(g);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guia);
    }

    final path = Path();
    final fill = Path();
    for (var i = 0; i < n; i++) {
      final x = dx * i;
      final y = yDe(valores[i]);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(dx * (n - 1), size.height);
    fill.close();

    canvas.drawPath(
        fill,
        Paint()
          ..color = color.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round);

    // punto final
    canvas.drawCircle(
        Offset(dx * (n - 1), yDe(valores[n - 1])), 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.valores != valores || old.color != color;
}

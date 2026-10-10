import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Apartado del profesor: genera y descarga como imagen los banners de cada
/// asignatura. NO mixta: Bienvenida + Semana 1..N (lunes a domingo). Mixta:
/// Bienvenida + Día 1..N (un banner por cada día del periodo intensivo).
class BannersSemanalesScreen extends StatefulWidget {
  const BannersSemanalesScreen({super.key});

  @override
  State<BannersSemanalesScreen> createState() => _BannersSemanalesScreenState();
}

class _BannersSemanalesScreenState extends State<BannersSemanalesScreen> {
  static const List<String> _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];

  static const List<String> _diasSem = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
  ];

  List<Map<String, dynamic>> _materias = [];
  int? _idx;
  String _filtro = 'Vigentes'; // Vigentes | Todas
  bool _cargando = true;
  String? _error;

  bool _precargado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precargado) {
      _precargado = true;
      precacheImage(
              const AssetImage('assets/images/cintillo_fondo.png'), context)
          .catchError((_) {});
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_grupos',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final lista = (data['grupos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Ordena: vigentes (en curso) primero, luego próximas, luego terminadas.
      // Dentro de cada grupo, por fecha de término ascendente.
      lista.sort((a, b) {
        final ca = _estadoMateria(a), cb = _estadoMateria(b);
        if (ca != cb) return ca.compareTo(cb);
        final fa = _fecha((a['termino'] ?? '').toString()) ?? DateTime(2100);
        final fb = _fecha((b['termino'] ?? '').toString()) ?? DateTime(2100);
        return fa.compareTo(fb);
      });
      if (!mounted) return;
      setState(() {
        _materias = lista;
        // Selecciona la primera VIGENTE si hay; si no, la primera.
        int sel = lista.indexWhere((m) => _estadoMateria(m) == 0);
        if (sel < 0) sel = lista.isNotEmpty ? 0 : -1;
        _idx = sel >= 0 ? sel : null;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus materias. Revisa tu conexión.';
      });
    }
  }

  // Mixta = periodo presencial intensivo por días seguidos. Los banners van
  // por DÍA (no por semana). Se detecta por el grupo o el tipo de sesiones.
  bool _esMixta(Map<String, dynamic> m) {
    final g = (m['grupo'] ?? '').toString().toLowerCase();
    final t = (m['tipoSesiones'] ?? m['modalidad'] ?? '').toString().toLowerCase();
    return g.contains('mixt') || t.contains('mixt');
  }

  // ---------- Fechas ----------
  // 0 = vigente (en curso), 1 = próxima (aún no inicia), 2 = terminada.
  int _estadoMateria(Map<String, dynamic> m) {
    final hoy = DateTime.now();
    final ini = _fecha((m['inicio'] ?? '').toString());
    final fin = _fecha((m['termino'] ?? '').toString());
    if (fin != null && hoy.isAfter(fin.add(const Duration(days: 1)))) return 2;
    if (ini != null && hoy.isBefore(ini)) return 1;
    if (ini != null || fin != null) return 0;
    return 1;
  }

  String _etiquetaEstado(int e) =>
      e == 0 ? 'Vigente' : (e == 1 ? 'Próxima' : 'Terminada');

  // Índices de materias visibles según el filtro (respeta el orden ya aplicado).
  List<int> _indicesVisibles() {
    final out = <int>[];
    for (int i = 0; i < _materias.length; i++) {
      if (_filtro == 'Vigentes' && _estadoMateria(_materias[i]) != 0) continue;
      out.add(i);
    }
    return out;
  }

  // Chip pequeño de estado (verde vigente, ámbar próxima, gris terminada).
  Widget _chipEstado(int e) {
    final color = e == 0
        ? const Color(0xFF1E8E3E)
        : (e == 1 ? cessumGold : Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _etiquetaEstado(e),
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  DateTime? _fecha(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final m1 = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m1 != null) {
      return DateTime(int.parse(m1.group(1)!), int.parse(m1.group(2)!),
          int.parse(m1.group(3)!));
    }
    final m2 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
    if (m2 != null) {
      return DateTime(int.parse(m2.group(3)!), int.parse(m2.group(2)!),
          int.parse(m2.group(1)!));
    }
    // Formato en inglés tipo "Mon May 25 2026 00:00:00 GMT-0700 (...)".
    const _mesEn = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
    };
    final m3 =
        RegExp(r'([A-Za-z]{3})[a-z]*\s+(\d{1,2})\s+(\d{4})').firstMatch(s);
    if (m3 != null) {
      final mes = _mesEn[m3.group(1)!.toLowerCase()];
      if (mes != null) {
        return DateTime(
            int.parse(m3.group(3)!), mes, int.parse(m3.group(2)!));
      }
    }
    return null;
  }

  // Lunes de la semana que contiene a la fecha de inicio.
  DateTime _lunesDe(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

  int _numSemanas(Map<String, dynamic> m) {
    final ini = _fecha((m['inicio'] ?? '').toString());
    final fin = _fecha((m['termino'] ?? '').toString());
    if (ini != null && fin != null) {
      final lunes = _lunesDe(ini);
      final dias = fin.difference(lunes).inDays;
      final n = (dias / 7).floor() + 1;
      return n.clamp(1, 16);
    }
    return 4;
  }

  String _rangoSemana(DateTime ini) {
    final fin = ini.add(const Duration(days: 6));
    final d1 = ini.day, d2 = fin.day;
    final m1 = _meses[ini.month - 1], m2 = _meses[fin.month - 1];
    final a1 = ini.year, a2 = fin.year;
    if (a1 != a2) return 'Del $d1 de $m1 de $a1 al $d2 de $m2 de $a2';
    if (ini.month != fin.month) return 'Del $d1 de $m1 al $d2 de $m2 de $a1';
    return 'Del $d1 al $d2 de $m1 de $a1';
  }

  // "Lunes 20 de julio de 2026"
  String _fechaConDia(DateTime d) =>
      '${_diasSem[d.weekday - 1]} ${d.day} de ${_meses[d.month - 1]} de ${d.year}';

  // Lista de banners para la materia elegida. Mixta = por día; resto = por semana.
  List<_Slide> _slides() {
    if (_idx == null) return [];
    final m = _materias[_idx!];
    final out = <_Slide>[
      _Slide(titulo: 'Bienvenida', archivo: 'Bienvenida', bienvenida: true),
    ];
    final ini0 = _fecha((m['inicio'] ?? '').toString());
    // MIXTA: un banner por cada día del periodo (inicio → término).
    if (_esMixta(m)) {
      final fin0 = _fecha((m['termino'] ?? '').toString());
      if (ini0 != null && fin0 != null && !fin0.isBefore(ini0)) {
        final totalDias = fin0.difference(ini0).inDays + 1;
        final tope = totalDias.clamp(1, 31);
        for (var i = 0; i < tope; i++) {
          final dia = ini0.add(Duration(days: i));
          out.add(_Slide(
            titulo: 'Día ${i + 1}. ${_fechaConDia(dia)}',
            archivo: 'Dia_${i + 1}',
            bienvenida: false,
          ));
        }
      }
      return out;
    }
    // NO MIXTA: un banner por semana (lunes a domingo).
    final n = _numSemanas(m);
    if (ini0 != null) {
      final lunes = _lunesDe(ini0);
      for (var i = 0; i < n; i++) {
        final start = lunes.add(Duration(days: 7 * i));
        out.add(_Slide(
          titulo: 'Semana ${i + 1}. ${_rangoSemana(start)}',
          archivo: 'Semana_${i + 1}',
          bienvenida: false,
        ));
      }
    }
    return out;
  }

  String _slugMateria() {
    if (_idx == null) return 'materia';
    final m = (_materias[_idx!]['materia'] ?? 'materia').toString();
    return m.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  }

  // ---------- Descarga PNG ----------
  Future<void> _descargar(GlobalKey key, String nombre) async {
    try {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final blob = html.Blob([bytes.buffer.asUint8List()], 'image/png');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..download = '${_slugMateria()}_$nombre.png'
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar la imagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Banners semanales'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        SkeletonCard(),
        SizedBox(height: 12),
        SkeletonCard(),
      ]);
    }
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        CessumEmptyState(
          title: 'No se pudo cargar',
          subtitle: _error,
          icon: Icons.wifi_off_rounded,
          action: FilledButton.icon(
            onPressed: _cargar,
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ]);
    }
    if (_materias.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        CessumEmptyState(
          title: 'Sin materias',
          subtitle: 'No tienes materias asignadas para generar banners.',
          icon: Icons.image_outlined,
        ),
      ]);
    }

    final slides = _slides();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Text('Elige la asignatura y descarga el banner de cada semana para '
            'subirlo al aula.',
            style: CessumType.body(13, color: cessumMuted(context))),
        const SizedBox(height: 12),
        // Filtro: por defecto solo Vigentes; puedes ver Todas.
        Row(
          children: [
            for (final op in const ['Vigentes', 'Todas'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(op == 'Vigentes'
                      ? 'Vigentes (${_materias.where((m) => _estadoMateria(m) == 0).length})'
                      : 'Todas (${_materias.length})'),
                  selected: _filtro == op,
                  selectedColor: cessumRed.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _filtro == op ? cessumRed : cessumMuted(context),
                    fontWeight:
                        _filtro == op ? FontWeight.w700 : FontWeight.w500,
                  ),
                  onSelected: (_) {
                    setState(() {
                      _filtro = op;
                      // Reajusta la selección a un índice visible.
                      final vis = _indicesVisibles();
                      if (!vis.contains(_idx)) {
                        _idx = vis.isNotEmpty ? vis.first : null;
                      }
                    });
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _indicesVisibles().contains(_idx) ? _idx : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Asignatura',
            isDense: true,
            border: const OutlineInputBorder(),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: cessumRed, width: 1.6),
            ),
          ),
          items: [
            for (final i in _indicesVisibles())
              DropdownMenuItem(
                value: i,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_materias[i]['materia'] ?? ''} · ${_materias[i]['grupo'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    _chipEstado(_estadoMateria(_materias[i])),
                  ],
                ),
              ),
          ],
          onChanged: (v) => setState(() => _idx = v),
        ),
        const SizedBox(height: 6),
        if (_idx != null)
          Text(_infoMateria(), style: CessumType.label(12, color: cessumGold)),
        const SizedBox(height: 16),
        for (final s in slides) _bloqueSlide(s),
      ],
    );
  }

  String _infoMateria() {
    final m = _materias[_idx!];
    final ini = _fecha((m['inicio'] ?? '').toString());
    final fin = _fecha((m['termino'] ?? '').toString());
    // MIXTA: se describe por días del periodo.
    if (_esMixta(m)) {
      if (ini == null) {
        return 'Mixta · (sin fecha de inicio: ajusta la vigencia de la materia)';
      }
      final finTxt = fin != null ? _fechaLarga(fin) : '—';
      final nDias = (ini != null && fin != null && !fin.isBefore(ini))
          ? (fin.difference(ini).inDays + 1).clamp(1, 31)
          : 0;
      return 'Mixta · $nDias día(s) · del ${_fechaLarga(ini)} al $finTxt';
    }
    final n = _numSemanas(m);
    if (ini == null) {
      return '$n semanas · (sin fecha de inicio: ajusta la vigencia de la materia)';
    }
    final finTxt = fin != null ? _fechaLarga(fin) : '—';
    return '$n semanas · del ${_fechaLarga(ini)} al $finTxt';
  }

  String _fechaLarga(DateTime d) =>
      '${d.day} de ${_meses[d.month - 1]} de ${d.year}';

  Widget _bloqueSlide(_Slide s) {
    final key = GlobalKey();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 2000 / 480,
              child: FittedBox(
                fit: BoxFit.contain,
                child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                    width: 2000,
                    height: 480,
                    child: _banner(s.titulo, bienvenida: s.bienvenida),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => _descargar(key, s.archivo),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Descargar imagen'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- El banner (fondo recreado + texto Montserrat) ----------
  Widget _banner(String texto, {required bool bienvenida}) {
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          // Fondo oficial (cintillo CESSUM). Si aún no está el asset, usa la
          // recreación dibujada como respaldo.
          Positioned.fill(
            child: Image.asset(
              'assets/images/cintillo_fondo.png',
              fit: BoxFit.fill,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.white,
                child: CustomPaint(painter: _BannerFondoPainter()),
              ),
            ),
          ),
          // Texto principal centrado en el área blanca.
          Positioned(
            left: 130,
            right: 130,
            top: 225,
            bottom: 28,
            child: Align(
              alignment: Alignment.center,
              child: Text(
                texto,
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: bienvenida ? 122 : 60,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                  height: 1.12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  final String titulo;
  final String archivo;
  final bool bienvenida;
  const _Slide(
      {required this.titulo, required this.archivo, required this.bienvenida});
}

/// Recreación del encabezado rojo angular de CESSUM para los banners.
class _BannerFondoPainter extends CustomPainter {
  static const Color _red = Color(0xFFB11D29);
  static const Color _redDark = Color(0xFF8E121C);
  static const Color _redLight = Color(0xFFD93A47);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Banda superior roja con borde inferior diagonal.
    final banda = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h * 0.30)
      ..lineTo(0, h * 0.44)
      ..close();
    canvas.drawPath(banda, Paint()..color = _red);

    // Franja más clara debajo de la banda.
    final franja = Path()
      ..moveTo(w * 0.30, h * 0.40)
      ..lineTo(w, h * 0.26)
      ..lineTo(w, h * 0.36)
      ..lineTo(w * 0.32, h * 0.50)
      ..close();
    canvas.drawPath(franja, Paint()..color = _redLight);

    // Chevron oscuro en la esquina superior izquierda (apunta hacia abajo).
    final chevron = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.27, 0)
      ..lineTo(w * 0.135, h * 0.66)
      ..close();
    canvas.drawPath(chevron, Paint()..color = _redDark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

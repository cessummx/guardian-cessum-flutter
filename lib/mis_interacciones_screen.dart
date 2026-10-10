// =====================================================================
//  MIS INTERACCIONES DE CLASE (4-oct-2026)
//  El informe del docente sobre las interacciones complejas de sus clases:
//  cada clase analizada con su identificación completa (fecha, materia,
//  programa, generación y grupo), el histórico, el resumen por materia, la
//  distribución por nivel, la comparación con la institución y lo que todo
//  eso aporta a su escalafón (las complejas suman más, las simples suman
//  menos y nunca restan). Lee la ruta mis_interacciones del Guardián.
//  Si se abre con `correo`, muestra el de ese docente (vista de
//  Vicerrectoría); si no, el de quien tiene la sesión.
// =====================================================================
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const Color _verde = Color(0xFF1E7B34);
const Color _azul = Color(0xFF2F5D8A);
const Color _tinta = Color(0xFF1F1A17);

class MisInteraccionesScreen extends StatefulWidget {
  final String? correo;
  final String? nombre;
  const MisInteraccionesScreen({super.key, this.correo, this.nombre});
  @override
  State<MisInteraccionesScreen> createState() => _MisInteraccionesScreenState();
}

class _MisInteraccionesScreenState extends State<MisInteraccionesScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  String _filtroMateria = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final correo = (widget.correo ?? '').isNotEmpty ? widget.correo! : ((await SessionStore.validEmail()) ?? '');
      if (correo.isEmpty) throw Exception('Tu sesión expiró. Vuelve a entrar.');
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'mis_interacciones', 'correo': correo});
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() { _d = d; _cargando = false; if (d['ok'] != true) _error = '${d['error'] ?? 'No se pudo cargar.'}'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  double _n(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
  String _f(num x) => x % 1 == 0 ? x.toInt().toString() : x.toStringAsFixed(1);
  List<Map<String, dynamic>> _lista(dynamic v) => (v is List) ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];

  Future<void> _abrir(String url) async {
    if (url.isEmpty) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el informe.')));
  }

  @override
  Widget build(BuildContext context) {
    final titulo = (widget.nombre ?? '').isNotEmpty ? 'Interacciones · ${widget.nombre}' : 'Mis interacciones de clase';
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(backgroundColor: cessumRed, foregroundColor: Colors.white, title: Text(titulo),
          actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))]),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: cessumRed))))
              : RefreshIndicator(color: cessumRed, onRefresh: _cargar, child: _contenido()),
    );
  }

  Widget _contenido() {
    final res = Map<String, dynamic>.from((_d['resumen'] as Map?) ?? {});
    final clases = _lista(_d['clases']);
    if (clases.isEmpty) {
      return ListView(padding: const EdgeInsets.all(20), children: [
        _tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.forum_outlined, size: 40, color: cessumGold),
          const SizedBox(height: 10),
          const Text('Todavía no hay clases analizadas', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Cuando una de tus sesiones en Meet tenga transcripción, el sistema la analiza y aquí verás cada clase, tu histórico y lo que '
              'aporta a tu escalafón. Las interacciones complejas suman más y las simples suman menos; ninguna resta.',
              style: TextStyle(fontSize: 13.5, height: 1.5, color: cessumMuted(context))),
        ])),
        const SizedBox(height: 14),
        _tarjetaEscalafon(),
      ]);
    }
    final materias = _lista(_d['materias']);
    final visibles = _filtroMateria.isEmpty ? clases : clases.where((c) => '${c['materia']}' == _filtroMateria).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 30), children: [
      _hero(res),
      const SizedBox(height: 14),
      _tarjetaEscalafon(),
      const SizedBox(height: 14),
      _tarjetaHistorico(clases),
      const SizedBox(height: 14),
      _tarjetaNiveles(res),
      const SizedBox(height: 14),
      if (materias.isNotEmpty) ...[_tarjetaMaterias(materias), const SizedBox(height: 14)],
      _encabezado('Cada clase analizada', '${visibles.length} de ${clases.length}'),
      if (materias.length > 1)
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('Todas'), selected: _filtroMateria.isEmpty, selectedColor: cessumRed.withValues(alpha: 0.15), onSelected: (_) => setState(() => _filtroMateria = ''))),
            ...materias.map((m) => '${m['materia']}').toSet().map((m) => Padding(padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(m), selected: _filtroMateria == m, selectedColor: cessumRed.withValues(alpha: 0.15), onSelected: (_) => setState(() => _filtroMateria = m)))),
          ]),
        ),
      const SizedBox(height: 8),
      ...visibles.map(_tarjetaClase),
      const SizedBox(height: 8),
      Text('El análisis es asistido por inteligencia artificial: es apoyo formativo para tu práctica, no una calificación.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
    ]);
  }

  // ── Componentes ──
  Widget _tarjeta({required Widget child, Color? borde}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borde ?? cessumMuted(context).withValues(alpha: 0.18)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))]),
        child: child,
      );

  Widget _encabezado(String t, [String extra = '']) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: cessumGold, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: cessumRed))),
          if (extra.isNotEmpty) Text(extra, style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        ]),
      );

  Widget _barraMeta(double pct, double meta, {double alto = 10}) {
    final ok = pct >= meta;
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      return SizedBox(height: alto + 16, child: Stack(children: [
        Positioned(left: 0, right: 0, top: 0, child: Container(height: alto, decoration: BoxDecoration(color: const Color(0xFFEFE7D8), borderRadius: BorderRadius.circular(alto)))),
        Positioned(left: 0, top: 0, child: Container(width: w * (pct.clamp(0, 100) / 100), height: alto, decoration: BoxDecoration(color: ok ? _verde : cessumRed, borderRadius: BorderRadius.circular(alto)))),
        Positioned(left: math.max(0.0, w * (meta / 100) - 1), top: 0, child: Container(width: 2, height: alto + 4, color: cessumGold)),
        Positioned(left: math.max(0.0, w * (meta / 100) - 30), top: alto + 3, child: Text('Meta ${meta.round()} %', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cessumGold))),
      ]));
    });
  }

  Widget _hero(Map<String, dynamic> res) {
    final pct = _n(res['pct']), meta = _n(_d['meta']), ok = pct >= meta;
    final inst = _n((_d['institucion'] as Map?)?['pct']);
    final tend = res['tendencia'] is Map ? Map<String, dynamic>.from(res['tendencia'] as Map) : null;
    final mejor = res['mejor'] is Map ? Map<String, dynamic>.from(res['mejor'] as Map) : null;
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: cessumRed,
          boxShadow: [BoxShadow(color: cessumRed.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('INTERACCIONES COMPLEJAS EN TUS CLASES', style: TextStyle(fontSize: 10.5, letterSpacing: 1.8, fontWeight: FontWeight.w700, color: Color(0xFFF6EBD3))),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${pct % 1 == 0 ? pct.toInt() : pct}', style: const TextStyle(fontSize: 52, height: 1, fontWeight: FontWeight.w800, color: Colors.white)),
              const Padding(padding: EdgeInsets.only(bottom: 6, left: 4), child: Text('%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Text(ok ? 'Arriba de la meta' : 'Debajo de la meta', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ok ? _verde : cessumRed)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${res['complejas']} complejas de ${res['unidades']} interacciones · ${res['clases']} clase(s) analizada(s)',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFF7DCDC))),
          ]),
        ),
        Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)), border: Border(top: BorderSide(color: cessumGold, width: 4))),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _barraMeta(pct, meta),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip(Icons.account_balance_outlined, 'Institución: ${inst % 1 == 0 ? inst.toInt() : inst} %', _azul),
              _chip(Icons.flag_outlined, '${res['alcanzanMeta']} de ${res['clases']} clases en meta', cessumGold),
              if (tend != null)
                _chip(_n(tend['cambio']) >= 0 ? Icons.trending_up : Icons.trending_down,
                    'Últimas 3: ${tend['reciente']} % (${_n(tend['cambio']) >= 0 ? '+' : ''}${tend['cambio']})', _n(tend['cambio']) >= 0 ? _verde : cessumRed),
            ]),
            if (mejor != null) ...[
              const SizedBox(height: 10),
              Text('Tu mejor clase: ${mejor['materia']} · ${mejor['fecha']} · ${mejor['pct']} %', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _chip(IconData ic, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.35))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(ic, size: 15, color: c), const SizedBox(width: 5), Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c))]),
      );

  Widget _tarjetaEscalafon() {
    final e = Map<String, dynamic>.from((_d['escalafon'] as Map?) ?? {});
    final double bono = _n(e['bono']);
    final double max = _n(e['maximo']) == 0 ? 8.0 : _n(e['maximo']);
    return _tarjeta(
      borde: cessumGold.withValues(alpha: 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.workspace_premium_outlined, color: cessumGold),
          const SizedBox(width: 8),
          const Expanded(child: Text('Lo que suma a tu escalafón', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          Text('+${_f(bono)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cessumGold)),
          Text(' / ${_f(max)} pts', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        ]),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (bono / max).clamp(0, 1).toDouble(), minHeight: 10, backgroundColor: const Color(0xFFEFE7D8), color: cessumGold)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _miniDato('${e['clasesEnVentana'] ?? 0}', 'clases en los últimos ${e['ventanaDias'] ?? 90} días')),
          Expanded(child: _miniDato(e['calidad'] == null ? '—' : '${(_n(e['calidad']) * 100).round()} %', 'calidad promedio')),
          Expanded(child: _miniDato('1 · ${e['pesoSimple'] ?? 0.3}', 'compleja · simple')),
        ]),
        const SizedBox(height: 10),
        Text('${e['comoSeCalcula'] ?? ''}', style: TextStyle(fontSize: 12.3, height: 1.5, color: cessumMuted(context))),
      ]),
    );
  }

  Widget _miniDato(String v, String t) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _tinta)),
        Text(t, style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ]);

  Widget _tarjetaHistorico(List<Map<String, dynamic>> clases) {
    final serie = clases.reversed.toList();
    final meta = _n(_d['meta']);
    return _tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _encabezado('Tu histórico', 'clase por clase'),
      SizedBox(height: 190, width: double.infinity, child: CustomPaint(painter: _HistoricoPainter(serie.map((c) => _n(c['pct'])).toList(), meta))),
      const SizedBox(height: 6),
      Row(children: [
        Container(width: 14, height: 3, color: cessumRed), const SizedBox(width: 5), Text('% de complejas por clase', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        const SizedBox(width: 14),
        Container(width: 14, height: 3, color: cessumGold), const SizedBox(width: 5), Text('meta ${meta.round()} %', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ]),
      if (serie.length > 1) ...[
        const SizedBox(height: 4),
        Text('De ${serie.first['fecha']} a ${serie.last['fecha']}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ],
    ]));
  }

  Widget _tarjetaNiveles(Map<String, dynamic> res) {
    final nv = Map<String, dynamic>.from((res['niveles'] as Map?) ?? {});
    const nombres = {1: 'Contextual', 2: 'Suplementario', 3: 'Selector', 4: 'Sustitutivo referencial', 5: 'Sustitutivo no referencial'};
    final total = [1, 2, 3, 4, 5].fold<double>(0, (a, k) => a + _n(nv['$k']));
    return _tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _encabezado('Tus interacciones por nivel', 'todas tus clases'),
      for (final k in [5, 4, 3, 2, 1])
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(children: [
            SizedBox(width: 150, child: Text('$k · ${nombres[k]}', style: TextStyle(fontSize: 12, fontWeight: k >= 4 ? FontWeight.w800 : FontWeight.w500, color: k >= 4 ? cessumRed : _tinta))),
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: total == 0 ? 0 : _n(nv['$k']) / total, minHeight: 12,
                backgroundColor: const Color(0xFFF2ECE1), color: k >= 4 ? cessumRed : cessumGold))),
            SizedBox(width: 56, child: Text(' ${_n(nv['$k']).toInt()} · ${total == 0 ? 0 : (_n(nv['$k']) / total * 100).round()} %', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700))),
          ]),
        ),
      Text('Complejas son los niveles 4 y 5 (sustitutivos): el alumno trae lo que no está en el aula.', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
    ]));
  }

  Widget _tarjetaMaterias(List<Map<String, dynamic>> materias) {
    final meta = _n(_d['meta']);
    return _tarjeta(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _encabezado('Por materia y grupo'),
      ...materias.map((m) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${m['materia']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
                Text('${m['pct']} %', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _n(m['pct']) >= meta ? _verde : cessumRed)),
              ]),
              Text('${m['programa']} · Generación ${m['generacion']} · Grupo ${m['grupo']} · ${m['clases']} clase(s)',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              const SizedBox(height: 6),
              _barraMeta(_n(m['pct']), meta, alto: 8),
            ]),
          )),
    ]));
  }

  Widget _tarjetaClase(Map<String, dynamic> c) {
    final pct = _n(c['pct']), meta = _n(_d['meta']), ok = c['alcanzaMeta'] == true;
    final u = _n(c['unidades']), comp = _n(c['complejas']);
    final url = '${c['informeUrl'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: ok ? _verde : cessumRed, width: 5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c['fechaLarga'] ?? c['fecha']}'.toUpperCase(), style: const TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: cessumGold)),
            const SizedBox(height: 3),
            Text('${c['materia']}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            Text('${c['programa']} · Generación ${c['generacion']} · Grupo ${c['grupo']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${pct % 1 == 0 ? pct.toInt() : pct} %', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ok ? _verde : cessumRed)),
            Text(ok ? 'en meta' : 'debajo de ${meta.round()} %', style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
          ]),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(children: [
            Expanded(flex: math.max(1, comp.toInt()), child: Container(height: 10, color: cessumRed)),
            Expanded(flex: math.max(1, (u - comp).toInt()), child: Container(height: 10, color: cessumGold.withValues(alpha: 0.55))),
          ]),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _dato('${comp.toInt()} complejas', cessumRed),
          _dato('${(u - comp).toInt()} simples', cessumGold),
          _dato('${u.toInt()} interacciones', _tinta),
          if (_n(c['preguntas']) > 0) _dato('${_n(c['preguntasComplejas']).toInt()} de ${_n(c['preguntas']).toInt()} preguntas abrieron complejas', _azul),
        ]),
        if ('${c['nivelPredominante'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('Nivel predominante: ${c['nivelPredominante']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context)))),
        if (url.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: const BorderSide(color: cessumRed), visualDensity: VisualDensity.compact),
            onPressed: () => _abrir(url),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
            label: const Text('Ver informe completo (PDF)'),
          )),
        ],
      ]),
    );
  }

  Widget _dato(String t, Color c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]);
}

/// Línea del % de complejas clase por clase, con la meta como línea dorada.
class _HistoricoPainter extends CustomPainter {
  final List<double> v;
  final double meta;
  _HistoricoPainter(this.v, this.meta);

  @override
  void paint(Canvas canvas, Size s) {
    const izq = 30.0, abajo = 18.0, arriba = 8.0;
    final w = s.width - izq - 8, h = s.height - abajo - arriba;
    final guia = Paint()..color = const Color(0xFFEFE7D8)..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final y in [0, 25, 50, 75, 100]) {
      final yy = arriba + h - h * y / 100;
      canvas.drawLine(Offset(izq, yy), Offset(izq + w, yy), guia);
      tp.text = TextSpan(text: '$y', style: const TextStyle(fontSize: 9, color: Color(0xFF9A9083)));
      tp.layout();
      tp.paint(canvas, Offset(izq - tp.width - 5, yy - tp.height / 2));
    }
    final ym = arriba + h - h * meta / 100;
    final pMeta = Paint()..color = cessumGold..strokeWidth = 2;
    for (double x = izq; x < izq + w; x += 9) {
      canvas.drawLine(Offset(x, ym), Offset(math.min(x + 5, izq + w), ym), pMeta);
    }
    if (v.isEmpty) return;
    final dx = v.length == 1 ? 0.0 : w / (v.length - 1);
    final pts = <Offset>[for (var i = 0; i < v.length; i++) Offset(izq + (v.length == 1 ? w / 2 : dx * i), arriba + h - h * v[i].clamp(0, 100) / 100)];
    final area = Path()..moveTo(pts.first.dx, arriba + h);
    for (final p in pts) {
      area.lineTo(p.dx, p.dy);
    }
    area..lineTo(pts.last.dx, arriba + h)..close();
    canvas.drawPath(area, Paint()..color = cessumRed.withValues(alpha: 0.08));
    final linea = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      linea.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(linea, Paint()..color = cessumRed..strokeWidth = 3..style = PaintingStyle.stroke..strokeJoin = StrokeJoin.round);
    for (var i = 0; i < pts.length; i++) {
      final ok = v[i] >= meta;
      canvas.drawCircle(pts[i], 5.5, Paint()..color = Colors.white);
      canvas.drawCircle(pts[i], 4, Paint()..color = ok ? const Color(0xFF1E7B34) : cessumRed);
    }
  }

  @override
  bool shouldRepaint(covariant _HistoricoPainter o) => o.v != v || o.meta != meta;
}

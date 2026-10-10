// =====================================================================
//  docente_tesis_screen.dart · CESSUM · Aula CESSUM / El Guardián
//  "Mis tesis dirigidas" — vista del DOCENTE (director / codirector /
//  lector). Rediseño ago-2026, mismo lenguaje que el expediente de admin:
//  cabecera viva, camino de etapas tocable, hitos con dictamen, bitácora
//  de asesorías, entregas con su reloj de plazo y línea de tiempo única.
//
//  Backend usado (todo preexistente):
//    GET  titu_listar&director=<correo> · titu_detalle&matricula
//         tesis_seguimiento_estado&matricula
//    POST titu_etapa · titu_asesoria · titu_interaccion · titu_responder
//         titu_hito_revisar   (OJO: este SÍ le manda correo al alumno)
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'tesis_convenio_screen.dart';

// ---------------------------------------------------------------------
//  Utilidades del archivo
// ---------------------------------------------------------------------

const List<String> _kMesesEs = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
];

String _norm(String s) {
  s = s.toLowerCase();
  const a = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const b = 'aaaaaeeeeiiiiooooouuuun';
  for (var i = 0; i < a.length; i++) {
    s = s.replaceAll(a[i], b[i]);
  }
  return s.trim();
}

/// El Guardián devuelve fechas en tres formatos según la función:
/// 'yyyy-MM-dd HH:mm' (etapas, asesorías, interacciones), '7 de agosto de
/// 2026' (convenio e hitos) y dd/MM/yyyy suelto. Este parser lee los tres.
DateTime? _fecha(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2}))?')
      .firstMatch(s);
  if (iso != null) {
    return DateTime(
      int.parse(iso.group(1)!),
      int.parse(iso.group(2)!),
      int.parse(iso.group(3)!),
      int.tryParse(iso.group(4) ?? '0') ?? 0,
      int.tryParse(iso.group(5) ?? '0') ?? 0,
    );
  }
  final esp = RegExp(r'^(\d{1,2})\s+de\s+([a-zA-Záéíóú]+)\s+de\s+(\d{4})')
      .firstMatch(s);
  if (esp != null) {
    final m = _kMesesEs.indexOf(_norm(esp.group(2)!));
    if (m >= 0) {
      return DateTime(int.parse(esp.group(3)!), m + 1, int.parse(esp.group(1)!));
    }
  }
  final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
  if (dmy != null) {
    return DateTime(int.parse(dmy.group(3)!), int.parse(dmy.group(2)!),
        int.parse(dmy.group(1)!));
  }
  return DateTime.tryParse(s);
}

String _dd(int n) => n < 10 ? '0$n' : '$n';

String _fechaCorta(dynamic v) {
  final d = _fecha(v);
  if (d == null) return v == null ? '' : v.toString();
  return '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
}

Color _colInter(String estado) {
  switch (estado) {
    case 'pendiente':
      return cessumGold;
    case 'vencida':
      return const Color(0xFFC62828);
    case 'respondida':
      return const Color(0xFF1E8E3E);
  }
  return Colors.grey;
}

Color _colHito(String estado) {
  final e = estado.toLowerCase();
  if (e == 'aprobado') return const Color(0xFF1E8E3E);
  if (e == 'devuelto') return const Color(0xFFC62828);
  if (e == 'entregado') return cessumGold;
  return const Color(0xFF9A9A9A);
}

Color _colSemaforo(String s) {
  switch (s) {
    case 'rojo':
      return const Color(0xFFC62828);
    case 'ambar':
      return cessumGold;
    case 'verde':
      return const Color(0xFF1E8E3E);
  }
  return const Color(0xFF7A7A7A);
}

// ---------------------------------------------------------------------
//  Widgets compartidos dentro del archivo
// ---------------------------------------------------------------------

class _Seccion extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final String? contador;
  final bool abierta;
  final Widget? accion;
  final List<Widget> hijos;
  const _Seccion({
    required this.titulo,
    required this.icono,
    required this.hijos,
    this.contador,
    this.abierta = false,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: abierta,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          leading: Icon(icono, color: cessumRed, size: 22),
          title: Row(
            children: [
              Expanded(
                child: Text(titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              if (contador != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(contador!,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cessumRed)),
                ),
              if (accion != null) ...[
                const SizedBox(width: 4),
                accion!,
              ],
            ],
          ),
          children: hijos,
        ),
      ),
    );
  }
}

/// Camino de etapas del reglamento. En modo compacto es una barra de
/// cuadritos; completo, tarjetas tocables.
class _Camino extends StatelessWidget {
  final List<String> etapas;
  final int actual;
  final void Function(String)? onTap;
  final bool compacto;
  const _Camino(
      {required this.etapas,
      required this.actual,
      this.onTap,
      this.compacto = false});

  @override
  Widget build(BuildContext context) {
    if (etapas.isEmpty) return const SizedBox.shrink();
    if (compacto) {
      return Row(
        children: [
          for (var i = 0; i < etapas.length; i++)
            Expanded(
              child: Container(
                height: 6,
                margin: EdgeInsets.only(right: i == etapas.length - 1 ? 0 : 2),
                decoration: BoxDecoration(
                  color: i < actual
                      ? const Color(0xFF1E8E3E)
                      : (i == actual ? cessumRed : const Color(0xFFE2DED5)),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      );
    }
    return SizedBox(
      height: 74,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: etapas.length,
        itemBuilder: (ctx, i) {
          final hecha = i < actual;
          final esActual = i == actual;
          final col = hecha
              ? const Color(0xFF1E8E3E)
              : (esActual ? cessumRed : const Color(0xFFB9B3A6));
          return InkWell(
            onTap: onTap == null ? null : () => onTap!(etapas[i]),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 122,
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: esActual
                    ? cessumRed.withValues(alpha: 0.08)
                    : (hecha
                        ? const Color(0xFF1E8E3E).withValues(alpha: 0.06)
                        : Colors.transparent),
                border: Border.all(
                    color: col.withValues(alpha: esActual ? 0.55 : 0.28)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          hecha
                              ? Icons.check_circle
                              : (esActual
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked),
                          size: 15,
                          color: col),
                      const SizedBox(width: 4),
                      Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: col)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Expanded(
                    child: Text(etapas[i],
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5,
                            height: 1.15,
                            fontWeight:
                                esActual ? FontWeight.w800 : FontWeight.w600,
                            color: esActual ? cessumRed : Colors.black87)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =====================================================================
//  PANTALLA 1 — Mis tesis dirigidas
// =====================================================================

class DocenteTesisScreen extends StatefulWidget {
  const DocenteTesisScreen({super.key});
  @override
  State<DocenteTesisScreen> createState() => _DocenteTesisScreenState();
}

class _DocenteTesisScreenState extends State<DocenteTesisScreen> {
  bool _cargando = true;
  String? _error;
  String _correo = '';
  List<Map<String, dynamic>> _tesis = [];
  List<String> _etapas = [];
  int _slaAvance = 7;
  int _slaCorr = 48;

  final _busca = TextEditingController();
  bool _soloPendientes = false;

  static const int _umbralDiasSinAsesoria = 21;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
    final resp = await http.get(uri).timeout(const Duration(seconds: 60));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      if (correo.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'Tu sesión expiró. Vuelve a entrar para ver tus tesis.';
            _cargando = false;
          });
        }
        return;
      }
      _correo = correo;
      final r = await _get({'accion': 'titu_listar', 'director': correo});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _tesis = (r['tesis'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _etapas = (r['etapas'] as List? ?? []).map((e) => e.toString()).toList();
        _slaAvance = (r['slaAvanceDias'] ?? 7) as int;
        _slaCorr = (r['slaCorreccionHoras'] ?? 48) as int;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  bool _rezagada(Map<String, dynamic> t) {
    final venc = (t['pendientesVencidos'] ?? 0) as int;
    final dias = t['diasSinAsesoria'];
    return venc > 0 || (dias is int && dias >= _umbralDiasSinAsesoria);
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _norm(_busca.text);
    return _tesis.where((t) {
      if (_soloPendientes && !_rezagada(t)) return false;
      if (q.isEmpty) return true;
      return _norm((t['nombre'] ?? '').toString()).contains(q) ||
          _norm((t['titulo'] ?? '').toString()).contains(q) ||
          _norm((t['programa'] ?? '').toString()).contains(q) ||
          (t['matricula'] ?? '').toString().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final vis = _cargando ? <Map<String, dynamic>>[] : _visibles;
    final conPendiente =
        _tesis.where((t) => ((t['pendientesVencidos'] ?? 0) as int) > 0).length;
    final sinAsesoria = _tesis.where((t) {
      final d = t['diasSinAsesoria'];
      return d is int && d >= _umbralDiasSinAsesoria;
    }).length;

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis tesis dirigidas'),
        actions: [
          IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: _cargando ? null : _cargar),
        ],
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? _vistaError()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                    children: [
                      if (_tesis.isNotEmpty) ...[
                        Row(
                          children: [
                            _kpi('Tesis', '${_tesis.length}', cessumRed),
                            const SizedBox(width: 8),
                            _kpi('Esperan tu respuesta', '$conPendiente',
                                conPendiente > 0
                                    ? const Color(0xFFC62828)
                                    : Colors.grey),
                            const SizedBox(width: 8),
                            _kpi('Sin asesoría reciente', '$sinAsesoria',
                                sinAsesoria > 0 ? cessumGold : Colors.grey),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _busca,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Buscar tesista, matrícula o título…',
                            prefixIcon: const Icon(Icons.search),
                            isDense: true,
                            filled: true,
                            fillColor: Theme.of(context).cardColor,
                            border: const OutlineInputBorder(),
                            suffixIcon: _busca.text.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close, size: 18),
                                    onPressed: () =>
                                        setState(() => _busca.clear()),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            label: const Text('Solo las que requieren atención'),
                            selected: _soloPendientes,
                            selectedColor: const Color(0xFFFDE7E7),
                            labelStyle: const TextStyle(fontSize: 12),
                            onSelected: (v) =>
                                setState(() => _soloPendientes = v),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_tesis.isEmpty)
                        const CessumEmptyState(
                          title: 'No tienes tesis asignadas',
                          subtitle:
                              'La vinculación de tesistas la hace administración. '
                              'En cuanto te asignen una, aparecerá aquí con su '
                              'expediente completo.',
                          icon: Icons.menu_book_outlined,
                        )
                      else if (vis.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                              child: Text('Ninguna tesis coincide con el filtro.',
                                  style: TextStyle(color: Colors.black54))),
                        )
                      else
                        ...vis.map(_tarjeta),
                    ],
                  ),
                ),
    );
  }

  Widget _kpi(String label, String valor, Color color) => Expanded(
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            child: Column(
              children: [
                Text(valor, style: CessumType.display(24, color: color)),
                const SizedBox(height: 2),
                Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 10.5, color: Colors.black54, height: 1.2)),
              ],
            ),
          ),
        ),
      );

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 46, color: Colors.grey),
              const SizedBox(height: 10),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton(
                  onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _tarjeta(Map<String, dynamic> t) {
    final idx = (t['etapaIndice'] ?? 0) as int;
    final total = (t['totalEtapas'] ?? _etapas.length) as int;
    final venc = (t['pendientesVencidos'] ?? 0) as int;
    final dias = t['diasSinAsesoria'];
    final prox = (t['proximoVence'] ?? '').toString();
    final titulo = (t['titulo'] ?? '').toString().trim();
    final etapas = _etapas.isNotEmpty
        ? _etapas
        : List<String>.generate(total, (i) => 'Etapa ${i + 1}');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _abrirDetalle(t['matricula'].toString()),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((t['nombre'] ?? '').toString(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        Text('${t['programa']} · ${t['generacion']}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${idx + 1}/$total',
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: cessumRed)),
                  ),
                ],
              ),
              if (titulo.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('“$titulo”',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 8),
              _Camino(etapas: etapas, actual: idx, compacto: true),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text('${t['etapa']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54)),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black38),
                ],
              ),
              if (venc > 0 ||
                  (dias is int && dias >= _umbralDiasSinAsesoria) ||
                  prox.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (venc > 0)
                        _chip('$venc esperan tu respuesta',
                            const Color(0xFFC62828)),
                      if (dias is int && dias >= _umbralDiasSinAsesoria)
                        _chip('$dias días sin asesoría', cessumGold),
                      if (venc == 0 && prox.isNotEmpty)
                        _chip('Próximo vence: $prox', Colors.blueGrey),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String txt, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(txt,
            style: TextStyle(
                fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
      );

  Future<void> _abrirDetalle(String matricula) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ExpedienteDocente(
          matricula: matricula,
          etapas: _etapas,
          slaAvance: _slaAvance,
          slaCorr: _slaCorr,
          correo: _correo,
          get: _get,
          post: _post,
        ),
      ),
    );
    _cargar();
  }
}

// =====================================================================
//  PANTALLA 2 — Expediente que el docente sí puede editar
// =====================================================================

class _ExpedienteDocente extends StatefulWidget {
  final String matricula;
  final List<String> etapas;
  final int slaAvance;
  final int slaCorr;
  final String correo;
  final Future<Map<String, dynamic>> Function(Map<String, String>) get;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) post;
  const _ExpedienteDocente({
    required this.matricula,
    required this.etapas,
    required this.slaAvance,
    required this.slaCorr,
    required this.correo,
    required this.get,
    required this.post,
  });
  @override
  State<_ExpedienteDocente> createState() => _ExpedienteDocenteState();
}

class _ExpedienteDocenteState extends State<_ExpedienteDocente> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _t;
  List<Map<String, dynamic>> _etapasHist = [];
  List<Map<String, dynamic>> _asesorias = [];
  List<Map<String, dynamic>> _inter = [];
  List<Map<String, dynamic>> _hitos = [];
  List<Map<String, dynamic>> _radiografia = [];
  Map<String, dynamic>? _convenio;
  List<String> _catalogo = [];

  @override
  void initState() {
    super.initState();
    _catalogo = List<String>.from(widget.etapas);
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final r = await widget
          .get({'accion': 'titu_detalle', 'matricula': widget.matricula});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      List<Map<String, dynamic>> radio = [];
      try {
        final s = await widget.get({
          'accion': 'tesis_seguimiento_estado',
          'matricula': widget.matricula
        });
        if (s['ok'] == true) {
          radio = (s['hitos'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } catch (_) {
        // la radiografía es un extra; si falla, el expediente abre igual
      }
      if (!mounted) return;
      setState(() {
        _t = Map<String, dynamic>.from(r['tesis'] as Map);
        _etapasHist = (r['etapas'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _asesorias = (r['asesorias'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _inter = (r['interacciones'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _hitos = (r['hitos'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _convenio = r['convenio'] == null
            ? null
            : Map<String, dynamic>.from(r['convenio'] as Map);
        final cat =
            (r['catalogoEtapas'] as List? ?? []).map((e) => e.toString()).toList();
        if (cat.isNotEmpty) _catalogo = cat;
        _radiografia = radio;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? const Color(0xFFC62828) : null,
    ));
  }

  // ------------------ ACCIONES ------------------

  /// Corrige el título y el link del documento con la ruta titu_editar (V485).
  /// Al asesor NO se le ofrece el "fin del último ciclo": ese dato es
  /// administrativo y define el plazo del Art. 90, así que se queda en el
  /// panel de control escolar.
  Future<void> _editarTitulo() async {
    final t = _t;
    if (t == null) return;
    final tituloOrig = (t['titulo'] ?? '').toString();
    final linkOrig = (t['linkDoc'] ?? '').toString();
    final titulo = TextEditingController(text: tituloOrig);
    final link = TextEditingController(text: linkOrig);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Datos de la tesis', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titulo,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Título de la tesis',
                      helperText: 'Como quedará en el acta y en el título.',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: link,
                  decoration: const InputDecoration(
                      labelText: 'Link del documento',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEFF7EF),
                      border: Border.all(color: const Color(0xFFA8CDA8)),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                      '✓ Esto NO toca el convenio ni las firmas, y no le '
                      'envía ningún correo a tu tesista.',
                      style: TextStyle(fontSize: 11.5, height: 1.3)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final nTitulo = titulo.text.trim();
    final nLink = link.text.trim();
    titulo.dispose();
    link.dispose();
    if (ok != true) return;

    final payload = <String, dynamic>{
      'accion': 'titu_editar',
      'matricula': widget.matricula,
      'actor': widget.correo,
    };
    // Solo lo que de verdad cambió: así no se pisa un dato bueno con una
    // cadena vacía por descuido.
    if (nTitulo != tituloOrig) payload['titulo'] = nTitulo;
    if (nLink != linkOrig) payload['linkDoc'] = nLink;
    if (payload.length <= 3) {
      _snack('No cambiaste nada.');
      return;
    }
    try {
      final r = await widget.post(payload);
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('Datos actualizados.');
      _cargar();
    } catch (e) {
      _snack('No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _moverEtapa(String etapa) async {
    final actual = (_t?['etapa'] ?? '').toString();
    if (etapa == actual) {
      _snack('La tesis ya está en “$etapa”.');
      return;
    }
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mover de etapa', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('De “$actual” a “$etapa”.',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: nota,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Nota para el historial (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true),
            ),
            const SizedBox(height: 8),
            const Text('Queda asentado en el historial. No envía correos.',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mover'),
          ),
        ],
      ),
    );
    final texto = nota.text.trim();
    nota.dispose();
    if (ok != true) return;
    try {
      final r = await widget.post({
        'accion': 'titu_etapa',
        'matricula': widget.matricula,
        'etapa': etapa,
        'estado': 'En curso',
        'nota': texto.isEmpty ? 'Cambio de etapa por el asesor' : texto,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('Etapa actualizada.');
      _cargar();
    } catch (e) {
      _snack('No se pudo: $e', error: true);
    }
  }

  Future<void> _registrarAsesoria() async {
    final acuerdos = TextEditingController();
    final compromiso = TextEditingController();
    DateTime? fecha;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: const Text('Registrar asesoría',
              style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: acuerdos,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Acuerdos de la sesión *',
                        hintText: 'Qué se revisó y qué se acordó',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: compromiso,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Compromiso del estudiante',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final hoy = DateTime.now();
                      final f = await showDatePicker(
                        context: ctx,
                        initialDate: fecha ?? hoy.add(const Duration(days: 7)),
                        firstDate: hoy.subtract(const Duration(days: 365)),
                        lastDate: hoy.add(const Duration(days: 730)),
                      );
                      if (f != null) setSt(() => fecha = f);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Fecha del compromiso',
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: Icon(Icons.calendar_today, size: 18)),
                      child: Text(
                          fecha == null
                              ? 'Sin fecha'
                              : '${_dd(fecha!.day)}/${_dd(fecha!.month)}/${fecha!.year}',
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        );
      }),
    );
    final txtA = acuerdos.text.trim();
    final txtC = compromiso.text.trim();
    final f = fecha;
    acuerdos.dispose();
    compromiso.dispose();
    if (ok != true) return;
    if (txtA.isEmpty) {
      _snack('Escribe al menos los acuerdos.', error: true);
      return;
    }
    try {
      final r = await widget.post({
        'accion': 'titu_asesoria',
        'matricula': widget.matricula,
        'acuerdos': txtA,
        'compromiso': txtC,
        'fechaCompromiso':
            f == null ? '' : '${f.year}-${_dd(f.month)}-${_dd(f.day)}',
        'registro': widget.correo,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('Asesoría registrada.');
      _cargar();
    } catch (e) {
      _snack('No se pudo: $e', error: true);
    }
  }

  Future<void> _registrarInteraccion() async {
    String tipo = 'avance';
    String de = 'Alumno';
    String etapa = (_t?['etapa'] ?? '').toString();
    final desc = TextEditingController();
    final link = TextEditingController();
    final lista = _catalogo.isNotEmpty ? _catalogo : widget.etapas;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: const Text('Registrar entrega o corrección',
              style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tipo: se eligen con botones, no con dropdown — son dos
                  // opciones y así se ve de un golpe qué reloj arranca.
                  Row(
                    children: [
                      Expanded(
                        child: _opcion(
                          activo: tipo == 'avance',
                          icono: Icons.upload_file,
                          titulo: 'Avance',
                          detalle: 'Material nuevo',
                          onTap: () => setSt(() => tipo = 'avance'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _opcion(
                          activo: tipo == 'correccion',
                          icono: Icons.undo,
                          titulo: 'Corrección',
                          detalle: 'Devolución',
                          onTap: () => setSt(() => tipo = 'correccion'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: de,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Enviado por',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'Alumno', child: Text('Alumno')),
                      DropdownMenuItem(
                          value: 'Director', child: Text('Director (yo)')),
                      DropdownMenuItem(value: 'Lector', child: Text('Lector')),
                    ],
                    onChanged: (v) => setSt(() => de = v ?? 'Alumno'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: lista.contains(etapa) ? etapa : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Etapa',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: lista
                        .map((e) => DropdownMenuItem(
                            value: e,
                            child:
                                Text(e, style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setSt(() => etapa = v ?? etapa),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: desc,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Descripción',
                        hintText: 'Qué se entregó o qué se pide corregir',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: link,
                    decoration: const InputDecoration(
                        labelText: 'Link del documento (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFBF6EE),
                        border: Border.all(color: CC.goldBorder),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      tipo == 'correccion'
                          ? 'Arranca el reloj: quien recibe tiene ${widget.slaCorr} horas para responder.'
                          : 'Arranca el reloj: quien revisa tiene ${widget.slaAvance} días hábiles para responder.',
                      style: const TextStyle(fontSize: 11.5, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar'),
            ),
          ],
        );
      }),
    );
    final txtD = desc.text.trim();
    final txtL = link.text.trim();
    desc.dispose();
    link.dispose();
    if (ok != true) return;
    try {
      final r = await widget.post({
        'accion': 'titu_interaccion',
        'matricula': widget.matricula,
        'tipo': tipo,
        'de': de,
        'etapa': etapa,
        'descripcion': txtD,
        'link': txtL,
        'registro': widget.correo,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('Registrado.');
      _cargar();
    } catch (e) {
      _snack('No se pudo: $e', error: true);
    }
  }

  Widget _opcion({
    required bool activo,
    required IconData icono,
    required String titulo,
    required String detalle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: activo ? cessumRed.withValues(alpha: 0.08) : null,
          border: Border.all(
              color: activo
                  ? cessumRed.withValues(alpha: 0.55)
                  : const Color(0xFFDDD8CE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icono,
                size: 20, color: activo ? cessumRed : Colors.black45),
            const SizedBox(height: 4),
            Text(titulo,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: activo ? cessumRed : Colors.black87)),
            Text(detalle,
                style:
                    const TextStyle(fontSize: 10.5, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Future<void> _responder(Map<String, dynamic> it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar pendiente', style: TextStyle(fontSize: 17)),
        content: Text(
            '¿Ya atendiste esta ${it['tipo']} del ${_fechaCorta(it['fecha'])}?\n\n'
            '“${it['desc'] ?? ''}”\n\n'
            'Se marca como respondida y deja de contar como vencida. '
            'No envía correos.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, ya respondí'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await widget.post({
        'accion': 'titu_responder',
        'matricula': widget.matricula,
        'fila': it['fila'],
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _cargar();
    } catch (e) {
      _snack('No se pudo: $e', error: true);
    }
  }

  Future<void> _dictaminar(Map<String, dynamic> h, bool aprobar) async {
    final coment =
        TextEditingController(text: (h['comentario'] ?? '').toString());
    final alumno = (_t?['nombre'] ?? 'el estudiante').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aprobar ? 'Aprobar hito' : 'Pedir cambios',
            style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFBF6EE),
                    border: Border.all(color: CC.goldBorder),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                    '⚠ Esto le envía UN correo a $alumno avisándole que '
                    '“${h['hito']}” quedó '
                    '${aprobar ? 'aprobado, y le genera su constancia del hito' : 'devuelto para cambios'}.',
                    style: const TextStyle(fontSize: 11.5, height: 1.3)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: coment,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText:
                        aprobar ? 'Comentario (opcional)' : 'Qué debe corregir *',
                    border: const OutlineInputBorder(),
                    isDense: true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    aprobar ? const Color(0xFF1E8E3E) : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(aprobar ? 'Aprobar y avisar' : 'Devolver y avisar'),
          ),
        ],
      ),
    );
    final texto = coment.text.trim();
    coment.dispose();
    if (ok != true) return;
    if (!aprobar && texto.isEmpty) {
      _snack('Escribe qué debe corregir.', error: true);
      return;
    }
    try {
      final r = await widget.post({
        'accion': 'titu_hito_revisar',
        'matricula': widget.matricula,
        'num': h['num'],
        'decision': aprobar ? 'aprobado' : 'devuelto',
        'comentario': texto,
        'registro': widget.correo,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack(aprobar ? 'Hito aprobado.' : 'Cambios solicitados.');
      _cargar();
    } catch (e) {
      _snack('No se pudo: $e', error: true);
    }
  }

  /// Alta y edición de un hito. Si [h] es null, es alta.
  /// El aviso al tesista es una casilla aparte y viene APAGADA: un plan se
  /// ajusta varias veces mientras se acuerda, y no hay que escribirle en
  /// cada intento.
  Future<void> _editarHito(Map<String, dynamic>? h) async {
    final esNuevo = h == null;
    final nombre =
        TextEditingController(text: esNuevo ? '' : '${h['hito'] ?? ''}');
    final fecha =
        TextEditingController(text: esNuevo ? '' : '${h['fechaCompromiso'] ?? ''}');
    var avisar = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(esNuevo ? 'Agregar entrega al plan' : 'Editar entrega',
              style: const TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nombre,
                    autofocus: esNuevo,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Qué debe entregar *',
                        helperText: 'Por ejemplo: Capítulo II terminado',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: fecha,
                    decoration: const InputDecoration(
                        labelText: 'Fecha compromiso (AAAA-MM-DD)',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: avisar,
                    onChanged: (v) => setSt(() => avisar = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Avisarle a mi tesista por correo',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: avisar
                            ? const Color(0xFFFBF6EE)
                            : const Color(0xFFF4F2ED),
                        border: Border.all(
                            color: avisar ? CC.goldBorder : Colors.black12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        avisar
                            ? 'Le llegará un correo con la entrega y su fecha. '
                                'Si es un cambio, verá también cuál era la '
                                'fecha anterior.'
                            : 'No se le avisa. Puedes hacerlo después, cuando '
                                'el plan quede como lo acordaron.',
                        style: const TextStyle(fontSize: 11.5, height: 1.35)),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                      'Esto NO toca el convenio ni las firmas.',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Color(0xFF1B5E20))),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(esNuevo ? 'Agregar' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    final nHito = nombre.text.trim();
    final nFecha = fecha.text.trim();
    nombre.dispose();
    fecha.dispose();
    if (ok != true) return;
    if (esNuevo && nHito.isEmpty) {
      _snack('Escribe qué debe entregar.', error: true);
      return;
    }
    final payload = <String, dynamic>{
      'accion': esNuevo ? 'tesis_hito_crear' : 'tesis_hito_editar',
      'matricula': widget.matricula,
      'actor': widget.correo,
      if (!esNuevo) 'num': '${h['num']}',
      'hito': nHito,
      'fecha': nFecha,
      if (avisar) 'avisar': '1',
    };
    try {
      final r = await widget.post(payload);
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('${r['aviso'] ?? 'Listo.'}');
      _cargar();
    } catch (e) {
      _snack('No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _borrarHito(Map<String, dynamic> h) async {
    var avisar = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Quitar del plan', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('“${h['hito']}”',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                  'Tu tesista ya no tendrá que entregarla. Si ya la entregó, '
                  'el sistema no te dejará quitarla: en ese caso edita su '
                  'nombre o su fecha.',
                  style: TextStyle(fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: avisar,
                onChanged: (v) => setSt(() => avisar = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Avisarle por correo',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Quitar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await widget.post({
        'accion': 'tesis_hito_borrar',
        'matricula': widget.matricula,
        'num': '${h['num']}',
        'actor': widget.correo,
        if (avisar) 'avisar': '1',
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('${r['aviso'] ?? 'Quitado.'}');
      _cargar();
    } catch (e) {
      _snack('$e', error: true);
    }
  }

  Future<void> _abrirConvenio() async {
    final t = _t;
    if (t == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TesisConvenioScreen(
          matricula: widget.matricula,
          nombre: (t['nombre'] ?? '').toString(),
          programa: (t['programa'] ?? '').toString(),
          generacion: (t['generacion'] ?? '').toString(),
          correo: widget.correo,
          rol: 'asesor',
        ),
      ),
    );
    _cargar();
  }

  // ------------------ BUILD ------------------

  @override
  Widget build(BuildContext context) {
    final pendientes = _inter
        .where((i) => i['estado'] == 'pendiente' || i['estado'] == 'vencida')
        .length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Expediente de tesis'),
        actions: [
          IconButton(
            tooltip: 'Convenio e hitos',
            icon: const Icon(Icons.handshake_outlined),
            onPressed: _cargando ? null : _abrirConvenio,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      floatingActionButton: (_cargando || _error != null)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              onPressed: _registrarInteraccion,
              icon: const Icon(Icons.sync_alt),
              label: const Text('Entrega / corrección'),
            ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off,
                            size: 46, color: Colors.grey),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        ElevatedButton(
                            onPressed: _cargar,
                            child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    children: [
                      _cabecera(),
                      const SizedBox(height: 10),
                      _tarjetaCamino(),
                      _alertas(),
                      _seccionInteracciones(pendientes),
                      _seccionHitos(),
                      _seccionAsesorias(),
                      _seccionLineaTiempo(),
                      _seccionConvenio(),
                    ],
                  ),
                ),
    );
  }

  Widget _cabecera() {
    final t = _t!;
    final titulo = (t['titulo'] ?? '').toString().trim();
    final idx = (t['etapaIndice'] ?? 0) as int;
    final linkDoc = (t['linkDoc'] ?? '').toString().trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB11D29), Color(0xFF8E1720)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((t['nombre'] ?? '').toString(),
                        style: CessumType.heading(16, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                        'Mat. ${t['matricula']} · ${t['programa']} ${t['generacion']}',
                        style: const TextStyle(
                            fontSize: 11.5, color: Colors.white70)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    'Etapa ${idx + 1}/${_catalogo.isEmpty ? '?' : _catalogo.length}',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // (ago-9) EL ASESOR YA PUEDE CORREGIR EL TÍTULO. Antes esta cabecera
          // era de solo lectura y el título solo se cambiaba desde el panel de
          // administración — pero quien conoce el título definitivo es el
          // director de la tesis, no control escolar. Los títulos cambian
          // varias veces durante el proceso y pedir el cambio por correo
          // hacía que el expediente viviera desactualizado.
          InkWell(
            onTap: _editarTitulo,
            borderRadius: BorderRadius.circular(10),
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                          titulo.isEmpty ? 'Sin título registrado' : '“$titulo”',
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              fontStyle: FontStyle.italic,
                              color: titulo.isEmpty
                                  ? Colors.white60
                                  : Colors.white)),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit, size: 15, color: Color(0xFFF0D9A8)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Etapa actual: ${t['etapa']}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF0D9A8))),
              ],
            ),
            ),
          ),
          _fila('Codirector', t['codirector']),
          _fila('Lector 1', t['lector1']),
          _fila('Lector 2', t['lector2']),
          if (linkDoc.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => Helpers.abrirUrlExterna(linkDoc, context),
              child: const Row(
                children: [
                  Icon(Icons.description_outlined,
                      size: 15, color: Color(0xFFF0D9A8)),
                  SizedBox(width: 6),
                  Text('Abrir el documento de la tesis',
                      style: TextStyle(
                          fontSize: 11.5,
                          decoration: TextDecoration.underline,
                          color: Color(0xFFF0D9A8))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fila(String rol, dynamic valor) {
    final v = (valor ?? '').toString().trim();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(rol,
                style: const TextStyle(fontSize: 11, color: Colors.white60)),
          ),
          Expanded(
            child: Text(v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaCamino() {
    final idx = (_t?['etapaIndice'] ?? 0) as int;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.route_outlined, size: 18, color: cessumRed),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Camino de la tesis',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
                Text('toca una etapa para moverla',
                    style:
                        TextStyle(fontSize: 10, color: cessumMuted(context))),
              ],
            ),
            const SizedBox(height: 8),
            _Camino(etapas: _catalogo, actual: idx, onTap: _moverEtapa),
          ],
        ),
      ),
    );
  }

  Widget _alertas() {
    final malos = _radiografia
        .where((h) => h['semaforo'] == 'rojo' || h['semaforo'] == 'ambar')
        .toList();
    if (malos.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFFFFF7F5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    size: 18, color: Color(0xFFC62828)),
                SizedBox(width: 6),
                Text('Atención',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: Color(0xFFC62828))),
              ],
            ),
            const SizedBox(height: 6),
            ...malos.map((h) {
              final debe = (h['debe'] ?? '').toString();
              final dias = ((h['diasAtraso'] ?? 0) as num).toInt();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5, right: 8),
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              _colSemaforo((h['semaforo'] ?? '').toString())),
                    ),
                    Expanded(
                      child: Text(
                          'Hito ${h['num']} · ${h['hito']} — '
                          '${debe == 'asesor' ? 'espera TU retroalimentación' : 'el estudiante no ha entregado'}'
                          '${dias > 0 ? ' ($dias día${dias == 1 ? '' : 's'})' : ''}',
                          style: const TextStyle(fontSize: 12, height: 1.3)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _seccionInteracciones(int pendientes) {
    final orden = [..._inter];
    orden.sort((a, b) {
      int rank(Map m) {
        final e = (m['estado'] ?? '').toString();
        if (e == 'vencida') return 0;
        if (e == 'pendiente') return 1;
        return 2;
      }

      return rank(a).compareTo(rank(b));
    });
    return _Seccion(
      titulo: 'Entregas y correcciones',
      icono: Icons.swap_vert_circle_outlined,
      contador: pendientes > 0
          ? '$pendientes abiertas de ${_inter.length}'
          : '${_inter.length}',
      abierta: true,
      accion: IconButton(
        tooltip: 'Registrar',
        icon: const Icon(Icons.add_circle_outline, size: 20, color: cessumRed),
        onPressed: _registrarInteraccion,
      ),
      hijos: orden.isEmpty
          ? [
              const Text(
                  'Aún no hay entregas ni correcciones registradas. Usa el '
                  'botón de abajo cada vez que recibas material o devuelvas '
                  'observaciones: así queda el rastro del acompañamiento.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54))
            ]
          : orden.map((it) {
              final estado = (it['estado'] ?? '').toString();
              final c = _colInter(estado);
              final abierta = estado == 'pendiente' || estado == 'vencida';
              final link = (it['link'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    border: Border.all(color: c.withValues(alpha: 0.30)),
                    borderRadius: BorderRadius.circular(10),
                    color: abierta ? c.withValues(alpha: 0.04) : null),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text('${it['tipo']} · $estado',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: c,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const Spacer(),
                        Text(_fechaCorta(it['fecha']),
                            style: const TextStyle(
                                fontSize: 10.5, color: Colors.black54)),
                      ],
                    ),
                    if ((it['desc'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(it['desc'].toString(),
                          style: const TextStyle(fontSize: 12.5, height: 1.3)),
                    ],
                    const SizedBox(height: 4),
                    Text(
                        'De: ${it['de'] ?? '—'} · Límite: ${_fechaCorta(it['limite'])}'
                        '${(it['respuesta'] ?? '').toString().isNotEmpty ? ' · Respondida: ${_fechaCorta(it['respuesta'])}' : ''}',
                        style: const TextStyle(
                            fontSize: 10.5, color: Colors.black54)),
                    if (link.isNotEmpty || abierta) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (link.isNotEmpty)
                            _botonLink('Ver documento', link, Icons.attach_file),
                          const Spacer(),
                          if (abierta)
                            TextButton.icon(
                              onPressed: () => _responder(it),
                              icon: const Icon(Icons.done_all, size: 16),
                              label: const Text('Ya respondí',
                                  style: TextStyle(fontSize: 11.5)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
    );
  }

  Widget _seccionHitos() {
    return _Seccion(
      titulo: 'Hitos del convenio',
      icono: Icons.flag_outlined,
      contador: '${_hitos.length}',
      // (ago-9) Antes los hitos solo se podían tocar rehaciendo el convenio,
      // y eso REINICIA LAS CUATRO FIRMAS. Por evitarlo, el plan se quedaba
      // desactualizado y el seguimiento avisaba de fechas que ya nadie
      // respetaba. Estas acciones tocan solo los hitos.
      accion: TextButton.icon(
        style: TextButton.styleFrom(
            foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
        onPressed: () => _editarHito(null),
        icon: const Icon(Icons.add, size: 17),
        label: const Text('Agregar', style: TextStyle(fontSize: 12.5)),
      ),
      abierta: _hitos.any((h) =>
          (h['estado'] ?? '').toString() == 'entregado'),
      hijos: _hitos.isEmpty
          ? [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Sin hitos. Se capturan al definir el convenio de '
                      'trabajo con tu tesista.',
                      style:
                          TextStyle(fontSize: 12.5, color: Colors.black54)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed),
                    onPressed: _abrirConvenio,
                    icon: const Icon(Icons.edit_document, size: 18),
                    label: const Text('Ir al convenio'),
                  ),
                ],
              )
            ]
          : _hitos.map(_tarjetaHito).toList(),
    );
  }

  Widget _tarjetaHito(Map<String, dynamic> h) {
    final estado = (h['estado'] ?? 'pendiente').toString();
    final col = _colHito(estado);
    final link = (h['link'] ?? '').toString();
    final linkRev = (h['linkRevision'] ?? '').toString();
    final linkCor = (h['linkCorreccion'] ?? '').toString();
    final obs = (h['observaciones'] ?? '').toString();
    final coment = (h['comentario'] ?? '').toString();
    final porDictaminar = estado == 'entregado' || estado == 'devuelto';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: col.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
        color: col.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${h['num']}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: col)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text((h['hito'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              // (ago-9) Editar y quitar sin tocar el convenio. Solo mientras
              // esté pendiente: un hito ya entregado es evidencia del trabajo
              // del tesista, y el backend además lo impide.
              if (estado == 'pendiente') ...[
                InkWell(
                  onTap: () => _editarHito(h),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit_calendar_outlined,
                        size: 17, color: Colors.black45),
                  ),
                ),
                InkWell(
                  onTap: () => _borrarHito(h),
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline,
                        size: 17, color: Colors.black38),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(estado,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: col)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              'Compromiso: ${h['fechaCompromiso'] ?? '—'}'
              '${(h['fechaEntrega'] ?? '').toString().isNotEmpty ? '  ·  Entregado: ${h['fechaEntrega']}' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          if (coment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFFFBF6EE),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('Tu dictamen: $coment',
                  style: const TextStyle(fontSize: 11.5, height: 1.3)),
            ),
          ],
          if (link.isNotEmpty ||
              linkRev.isNotEmpty ||
              linkCor.isNotEmpty ||
              obs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (link.isNotEmpty)
                  _botonLink('Entrega', link, Icons.attach_file),
                if (linkRev.isNotEmpty)
                  _botonLink('1ª revisión', linkRev, Icons.history_edu),
                if (linkCor.isNotEmpty)
                  _botonLink('Corrección', linkCor, Icons.autorenew),
                if (obs.isNotEmpty)
                  _botonLink('Observaciones', obs, Icons.rate_review_outlined),
              ],
            ),
          ],
          if (porDictaminar) ...[
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E8E3E)),
                    onPressed: () => _dictaminar(h, true),
                    icon: const Icon(Icons.check_circle_outline, size: 17),
                    label:
                        const Text('Aprobar', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                    onPressed: () => _dictaminar(h, false),
                    icon: const Icon(Icons.undo, size: 17),
                    label: const Text('Pedir cambios',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _botonLink(String texto, String url, IconData icono) => InkWell(
        onTap: () => Helpers.abrirUrlExterna(url, context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
              border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(20)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 13, color: cessumRed),
              const SizedBox(width: 4),
              Text(texto,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cessumRed)),
            ],
          ),
        ),
      );

  Widget _seccionAsesorias() {
    return _Seccion(
      titulo: 'Bitácora de asesorías',
      icono: Icons.chat_outlined,
      contador: '${_asesorias.length}',
      accion: IconButton(
        tooltip: 'Registrar asesoría',
        icon: const Icon(Icons.add_circle_outline, size: 20, color: cessumRed),
        onPressed: _registrarAsesoria,
      ),
      hijos: [
        if (_asesorias.isEmpty)
          const Text(
              'Sin asesorías registradas. Cada sesión que registres cuenta '
              'como evidencia del acompañamiento.',
              style: TextStyle(fontSize: 12.5, color: Colors.black54))
        else
          ..._asesorias.reversed.map((a) => Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE6E1D6)),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_note,
                            size: 15, color: cessumGold),
                        const SizedBox(width: 5),
                        Text(_fechaCorta(a['fecha']),
                            style: const TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text((a['acuerdos'] ?? '—').toString(),
                        style: const TextStyle(fontSize: 12.5, height: 1.3)),
                    if ((a['compromiso'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                          'Compromiso: ${a['compromiso']}'
                          '${(a['fechaComp'] ?? '').toString().isNotEmpty ? ' · para el ${_fechaCorta(a['fechaComp'])}' : ''}',
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.black54)),
                    ],
                  ],
                ),
              )),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed, foregroundColor: Colors.white),
          onPressed: _registrarAsesoria,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Registrar asesoría'),
        ),
      ],
    );
  }

  Widget _seccionLineaTiempo() {
    final eventos = <Map<String, dynamic>>[];

    for (final e in _etapasHist) {
      eventos.add({
        '_f': _fecha(e['entrada']),
        'titulo': 'Etapa · ${e['etapa']}',
        'fecha': [
          _fechaCorta(e['entrada']),
          if ((e['nota'] ?? '').toString().isNotEmpty) e['nota'].toString(),
        ].where((x) => x.isNotEmpty).join(' · '),
      });
    }
    for (final a in _asesorias) {
      final ac = (a['acuerdos'] ?? '').toString();
      eventos.add({
        '_f': _fecha(a['fecha']),
        'titulo': 'Asesoría',
        'fecha':
            '${_fechaCorta(a['fecha'])}${ac.isEmpty ? '' : ' · ${ac.length > 70 ? '${ac.substring(0, 70)}…' : ac}'}',
      });
    }
    for (final i in _inter) {
      final d = (i['desc'] ?? '').toString();
      eventos.add({
        '_f': _fecha(i['fecha']),
        'titulo':
            '${i['tipo'] == 'correccion' ? 'Corrección' : 'Avance'} · de ${i['de'] ?? '—'}',
        'fecha':
            '${_fechaCorta(i['fecha'])}${d.isEmpty ? '' : ' · ${d.length > 70 ? '${d.substring(0, 70)}…' : d}'}',
      });
    }
    for (final h in _hitos) {
      final fe = (h['fechaEntrega'] ?? '').toString();
      if (fe.isEmpty) continue;
      eventos.add({
        '_f': _fecha(fe),
        'titulo': 'Entrega de hito ${h['num']} · ${h['hito']}',
        'fecha': '${_fechaCorta(fe)} · ${h['estado']}',
      });
    }

    eventos.sort((a, b) {
      final fa = a['_f'] as DateTime?;
      final fb = b['_f'] as DateTime?;
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1;
      if (fb == null) return -1;
      return fb.compareTo(fa);
    });

    final hitos = <Map<String, dynamic>>[];
    for (var i = 0; i < eventos.length; i++) {
      hitos.add({
        'titulo': eventos[i]['titulo'],
        'fecha': eventos[i]['fecha'],
        'hecho': i != 0,
        'actual': i == 0,
      });
    }

    return _Seccion(
      titulo: 'Línea de tiempo',
      icono: Icons.timeline,
      contador: '${hitos.length}',
      hijos: hitos.isEmpty
          ? [
              const Text('Todavía no hay movimientos que mostrar.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54))
            ]
          : [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                    'Asesorías, entregas, correcciones y cambios de etapa, del '
                    'más reciente al más antiguo.',
                    style: TextStyle(fontSize: 11, color: Colors.black54)),
              ),
              TimelineCessum(hitos: hitos),
            ],
    );
  }

  Widget _seccionConvenio() {
    final c = _convenio;
    final estado = (c?['estado'] ?? 'Sin convenio').toString();
    final firmas = <String, bool>{
      'Estudiante': (c?['firmaAlumno'] ?? '').toString().isNotEmpty,
      'Tú (asesor)': (c?['firmaAsesor'] ?? '').toString().isNotEmpty,
      'Autoridad 1': (c?['firmaAutoridad'] ?? '').toString().isNotEmpty,
      'Autoridad 2': (c?['firmaAutoridad2'] ?? '').toString().isNotEmpty,
    };
    final linkPdf = (c?['linkPdf'] ?? '').toString();
    return _Seccion(
      titulo: 'Convenio de trabajo',
      icono: Icons.handshake_outlined,
      contador: estado,
      abierta: c == null,
      hijos: [
        if (c == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Todavía no hay convenio. Ahí se define el objetivo, las '
                  'fechas y los hitos de entrega que después dictaminas.',
                  style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: _abrirConvenio,
                icon: const Icon(Icons.edit_document, size: 18),
                label: const Text('Definir convenio'),
              ),
            ],
          )
        else ...[
          if ((c['objetivo'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(c['objetivo'].toString(),
                  style: const TextStyle(fontSize: 12.5, height: 1.3)),
            ),
          Text('Vigencia: ${c['fechaInicio'] ?? '—'} → ${c['fechaTermino'] ?? '—'}',
              style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: firmas.entries
                .map((e) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: e.value
                              ? const Color(0xFF1E8E3E).withValues(alpha: 0.12)
                              : const Color(0xFFEEEEEE),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('${e.value ? '✓' : '○'} ${e.key}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: e.value
                                  ? const Color(0xFF1B5E20)
                                  : Colors.black54)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (linkPdf.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => Helpers.abrirUrlExterna(linkPdf, context),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Ver PDF'),
                ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: _abrirConvenio,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Abrir convenio'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

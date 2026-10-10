// =====================================================================
//  admin_tesis_screen.dart · CESSUM · Aula CESSUM / El Guardián
//  EXPEDIENTE DE TESIS — vista de ADMINISTRACIÓN.
//  Rediseño ago-2026: cabecera de expediente viva, camino de etapas
//  tocable, edición en su lugar (etapa, director, lectores, asesorías,
//  hitos), línea de tiempo unificada, convenio integrado y semáforo de
//  salud (solo lectura, NO envía correos).
//
//  Backend usado (todo preexistente):
//    GET  titu_listar · titu_detalle · docentes_lista · grupos_admin_todos
//         tesis_seguimiento_alertas&prueba=1&forzar=1  (dry-run, sin correo)
//         tesis_seguimiento_estado&matricula=          (radiografía)
//    POST titu_crear · titu_etapa · titu_lectores · titu_reasignar
//         titu_asesoria · titu_responder · titu_hito_revisar
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

// =====================================================================
//  Utilidades del módulo (privadas a este archivo)
// =====================================================================

const List<String> _kMesesEs = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
];

/// Normaliza texto para búsquedas: minúsculas y sin acentos.
String _tNorm(String s) {
  s = s.toLowerCase();
  const a = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const b = 'aaaaaeeeeiiiiooooouuuun';
  for (var i = 0; i < a.length; i++) {
    s = s.replaceAll(a[i], b[i]);
  }
  return s.trim();
}

/// El Guardián entrega fechas en tres formatos distintos según la función:
///   · tesisFmt_   -> 'yyyy-MM-dd HH:mm'   (etapas, asesorías, interacciones)
///   · _fechaEsp_  -> '7 de agosto de 2026' (convenio e hitos)
///   · captura libre -> 'dd/MM/yyyy'
/// Este parser lee los tres; si no puede, regresa null (nunca truena).
DateTime? _tFecha(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;

  // 1) yyyy-MM-dd [HH:mm]
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2}))?');
  final mIso = iso.firstMatch(s);
  if (mIso != null) {
    return DateTime(
      int.parse(mIso.group(1)!),
      int.parse(mIso.group(2)!),
      int.parse(mIso.group(3)!),
      int.tryParse(mIso.group(4) ?? '0') ?? 0,
      int.tryParse(mIso.group(5) ?? '0') ?? 0,
    );
  }

  // 2) '7 de agosto de 2026'
  final esp = RegExp(r'^(\d{1,2})\s+de\s+([a-zA-Záéíóú]+)\s+de\s+(\d{4})');
  final mEsp = esp.firstMatch(s);
  if (mEsp != null) {
    final mes = _kMesesEs.indexOf(_tNorm(mEsp.group(2)!));
    if (mes >= 0) {
      return DateTime(
          int.parse(mEsp.group(3)!), mes + 1, int.parse(mEsp.group(1)!));
    }
  }

  // 3) dd/MM/yyyy
  final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})');
  final mDmy = dmy.firstMatch(s);
  if (mDmy != null) {
    return DateTime(int.parse(mDmy.group(3)!), int.parse(mDmy.group(2)!),
        int.parse(mDmy.group(1)!));
  }

  return DateTime.tryParse(s);
}

String _dosDig(int n) => n < 10 ? '0$n' : '$n';

String _tFechaCorta(dynamic v) {
  final d = _tFecha(v);
  if (d == null) return v == null ? '' : v.toString();
  return '${_dosDig(d.day)}/${_dosDig(d.month)}/${d.year}';
}

/// Quita el título académico del inicio para poder comparar nombres.
String _sinTitulo(String s) {
  var n = _tNorm(s);
  n = n.replaceFirst(
      RegExp(r'^(dr|dra|mtro|mtra|mtr|lic|licda|ing|prof|profa|profe|c)\.?\s+'),
      '');
  return n.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Etiqueta legible de un docente del catálogo.
String _etiquetaDocente(Map<String, dynamic> d) {
  final t = (d['titulo'] ?? '').toString().trim();
  final n = (d['nombre'] ?? '').toString().trim();
  return t.isEmpty ? n : '$t $n';
}

/// Busca en el catálogo al docente que corresponde a un valor guardado en la
/// hoja Tesis. Tolera que la hoja traiga NOMBRE (lo correcto) o CORREO
/// (registros viejos, ver nota de la pantalla).
Map<String, dynamic>? _docentePorValor(
    List<Map<String, dynamic>> docentes, String? valor) {
  final v = (valor ?? '').toString().trim();
  if (v.isEmpty) return null;
  final vNorm = _sinTitulo(v);
  final vCorreo = v.toLowerCase();
  for (final d in docentes) {
    final correo = (d['correo'] ?? '').toString().trim().toLowerCase();
    if (correo.isNotEmpty && correo == vCorreo) return d;
    if (_sinTitulo((d['nombre'] ?? '').toString()) == vNorm) return d;
  }
  return null;
}

Color _colorEstadoInter(String estado) {
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

Color _colorSemaforo(String s) {
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

Color _colorEstadoHito(String estado) {
  final e = estado.toLowerCase();
  if (e == 'aprobado') return const Color(0xFF1E8E3E);
  if (e == 'devuelto') return const Color(0xFFC62828);
  if (e == 'entregado') return cessumGold;
  return const Color(0xFF9A9A9A);
}

// =====================================================================
//  Widgets compartidos por las dos pantallas de este archivo
// =====================================================================

/// Sección colapsable con encabezado guinda.
class _Seccion extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final String? contador;
  final bool abiertaAlInicio;
  final List<Widget> hijos;
  final Widget? accion;

  const _Seccion({
    required this.titulo,
    required this.icono,
    required this.hijos,
    this.contador,
    this.abiertaAlInicio = false,
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
          initiallyExpanded: abiertaAlInicio,
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

/// Camino de etapas del reglamento: hechas ✓ / actual / futuras.
/// Cada etapa es tocable (el admin puede mover la tesis a cualquiera).
class _CaminoEtapas extends StatelessWidget {
  final List<String> etapas;
  final int actual;
  final void Function(String etapa)? onTap;
  final bool compacto;

  const _CaminoEtapas({
    required this.etapas,
    required this.actual,
    this.onTap,
    this.compacto = false,
  });

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
                      : (i == actual
                          ? cessumRed
                          : const Color(0xFFE2DED5)),
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
        padding: const EdgeInsets.symmetric(horizontal: 2),
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
                    child: Text(
                      etapas[i],
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.15,
                          fontWeight:
                              esActual ? FontWeight.w800 : FontWeight.w600,
                          color: esActual ? cessumRed : Colors.black87),
                    ),
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

/// Selector de docente CON BUSCADOR (el catálogo es largo: nada de listas
/// planas). Devuelve el mapa del docente, o {'nombre': ''} si eligió "ninguno".
class _DocentePicker extends StatefulWidget {
  final List<Map<String, dynamic>> docentes;
  final String titulo;
  final bool permitirNinguno;
  const _DocentePicker(
      {required this.docentes,
      required this.titulo,
      this.permitirNinguno = false});
  @override
  State<_DocentePicker> createState() => _DocentePickerState();
}

class _DocentePickerState extends State<_DocentePicker> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _tNorm(_busca.text);
    final lista = q.isEmpty
        ? widget.docentes
        : widget.docentes
            .where((d) =>
                _tNorm(_etiquetaDocente(d)).contains(q) ||
                _tNorm((d['correo'] ?? '').toString()).contains(q))
            .toList();
    return AlertDialog(
      title: Text(widget.titulo, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _busca,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Escribe para filtrar por nombre o correo…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: lista.isEmpty
                  ? Center(
                      child: Text('Sin coincidencias',
                          style: TextStyle(color: cessumMuted(context))))
                  : ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (ctx, i) {
                        final d = lista[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.person_outline,
                              size: 20, color: cessumRed),
                          title: Text(_etiquetaDocente(d),
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text((d['correo'] ?? '—').toString(),
                              style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(context, d),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.permitirNinguno)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, <String, dynamic>{'nombre': ''}),
            child: const Text('Quitar / ninguno'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}

Future<Map<String, dynamic>?> _elegirDocente(
  BuildContext context,
  List<Map<String, dynamic>> docentes, {
  String titulo = 'Elegir docente',
  bool permitirNinguno = false,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _DocentePicker(
        docentes: docentes, titulo: titulo, permitirNinguno: permitirNinguno),
  );
}

// =====================================================================
//  PANTALLA 1 — Tablero y listado de expedientes
// =====================================================================

class AdminTesisScreen extends StatefulWidget {
  const AdminTesisScreen({super.key});
  @override
  State<AdminTesisScreen> createState() => _AdminTesisScreenState();
}

class _AdminTesisScreenState extends State<AdminTesisScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _tesis = [];
  List<String> _etapas = [];
  List<Map<String, dynamic>> _docentes = [];
  List<Map<String, dynamic>> _alumnos = [];

  // Semáforo de salud (dry-run de tesis_seguimiento_alertas: NO manda correos)
  bool _saludCargando = false;
  String? _saludError;
  List<Map<String, dynamic>> _salud = [];

  // Filtros
  final _busca = TextEditingController();
  String? _filtroEtapa;
  String? _filtroAsesor;
  bool _soloRezagadas = false;

  static const int _umbralDiasSinAsesoria = 21;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
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

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final t = await _get({'accion': 'titu_listar'});
      if (t['ok'] != true) throw Exception(t['error'] ?? 'Error al listar tesis');
      final d = await _get({'accion': 'docentes_lista'});
      final a = await _get({'accion': 'grupos_admin_todos'});
      final vistos = <String>{};
      final docs = (d['docentes'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((dd) {
        final clave = _sinTitulo((dd['nombre'] ?? '').toString());
        if (clave.isEmpty || vistos.contains(clave)) return false;
        vistos.add(clave);
        return true;
      }).toList();
      docs.sort((x, y) => _etiquetaDocente(x)
          .toLowerCase()
          .compareTo(_etiquetaDocente(y).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _tesis = (t['tesis'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _etapas = (t['etapas'] as List? ?? []).map((e) => e.toString()).toList();
        _docentes = docs;
        _alumnos = (a['grupos'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
    _cargarSalud();
  }

  /// Radiografía de asesores con pendientes. Se pide SIEMPRE con prueba=1 y
  /// forzar=1: en ese modo la función del Guardián sólo calcula y devuelve el
  /// detalle — no envía ningún correo ni marca el candado del día.
  Future<void> _cargarSalud() async {
    if (!mounted) return;
    setState(() {
      _saludCargando = true;
      _saludError = null;
    });
    try {
      final r = await _get({
        'accion': 'tesis_seguimiento_alertas',
        'prueba': '1',
        'forzar': '1',
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _salud = (r['detalle'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _saludError = '$e');
    } finally {
      if (mounted) setState(() => _saludCargando = false);
    }
  }

  bool _rezagada(Map<String, dynamic> t) {
    final venc = (t['pendientesVencidos'] ?? 0) as int;
    final dias = t['diasSinAsesoria'];
    return venc > 0 || (dias is int && dias >= _umbralDiasSinAsesoria);
  }

  List<Map<String, dynamic>> get _filtradas {
    final q = _tNorm(_busca.text);
    return _tesis.where((t) {
      if (_soloRezagadas && !_rezagada(t)) return false;
      if (_filtroEtapa != null && (t['etapa'] ?? '').toString() != _filtroEtapa) {
        return false;
      }
      if (_filtroAsesor != null &&
          _sinTitulo((t['director'] ?? '').toString()) !=
              _sinTitulo(_filtroAsesor!)) {
        return false;
      }
      if (q.isEmpty) return true;
      return _tNorm((t['nombre'] ?? '').toString()).contains(q) ||
          _tNorm((t['titulo'] ?? '').toString()).contains(q) ||
          _tNorm((t['director'] ?? '').toString()).contains(q) ||
          _tNorm((t['programa'] ?? '').toString()).contains(q) ||
          (t['matricula'] ?? '').toString().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _cargando ? <Map<String, dynamic>>[] : _filtradas;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Expedientes de tesis'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargarTodo,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _cargando ? null : _vincular,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Vincular tesis'),
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? _vistaError()
              : RefreshIndicator(
                  onRefresh: _cargarTodo,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    children: [
                      _panelSalud(),
                      _kpis(),
                      const SizedBox(height: 10),
                      _barraFiltros(),
                      const SizedBox(height: 6),
                      _embudo(),
                      _cargaPorAsesor(),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                            'Expedientes (${lista.length} de ${_tesis.length})',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                      if (_tesis.isEmpty)
                        const CessumEmptyState(
                          title: 'Aún no hay tesis vinculadas',
                          subtitle:
                              'Usa “Vincular tesis” para abrir el primer expediente, '
                              'o asigna un asesor desde las solicitudes de tutor.',
                          icon: Icons.menu_book_outlined,
                        )
                      else if (lista.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                              child: Text(
                                  'Ningún expediente coincide con el filtro.',
                                  style: TextStyle(color: cessumMuted(context)))),
                        )
                      else
                        ...lista.map(_tarjetaTesis),
                    ],
                  ),
                ),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _cargarTodo, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  // ----------------- SEMÁFORO DE SALUD -----------------
  Widget _panelSalud() {
    if (_saludCargando) {
      return const Card(
        margin: EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text('Calculando el estado de las tesis…',
              style: TextStyle(fontSize: 13)),
        ),
      );
    }
    if (_saludError != null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: const Icon(Icons.warning_amber_rounded, color: cessumGold),
          title: const Text('No se pudo calcular el semáforo',
              style: TextStyle(fontSize: 13)),
          subtitle:
              Text(_saludError!, style: const TextStyle(fontSize: 11)),
          trailing: IconButton(
              icon: const Icon(Icons.refresh), onPressed: _cargarSalud),
        ),
      );
    }
    if (_salud.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        color: const Color(0xFFEFF7EF),
        child: const ListTile(
          leading: Icon(Icons.verified_outlined, color: Color(0xFF1E8E3E)),
          title: Text('Sin pendientes de seguimiento',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          subtitle: Text(
              'Ningún asesor tiene entregas esperando retroalimentación ni '
              'tesistas con hitos vencidos.',
              style: TextStyle(fontSize: 11.5)),
        ),
      );
    }
    final totalRetro = _salud.fold<int>(
        0, (p, e) => p + ((e['esperanRetro'] ?? 0) as num).toInt());
    final totalAtras = _salud.fold<int>(
        0, (p, e) => p + ((e['tesistasAtrasados'] ?? 0) as num).toInt());
    return _Seccion(
      titulo: 'Salud del acompañamiento',
      icono: Icons.monitor_heart_outlined,
      contador: '${_salud.length} asesor(es)',
      abiertaAlInicio: true,
      accion: IconButton(
        tooltip: 'Recalcular',
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: _cargarSalud,
      ),
      hijos: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFFBF6EE),
              border: Border.all(color: CC.goldBorder),
              borderRadius: BorderRadius.circular(10)),
          child: Text(
              '$totalRetro entrega(s) esperando retroalimentación · '
              '$totalAtras tesista(s) con hitos vencidos.\n'
              'Esta vista es solo de lectura: no envía ningún correo.',
              style: const TextStyle(fontSize: 11.5, height: 1.3)),
        ),
        const SizedBox(height: 6),
        ..._salud.map((s) {
          final retro = ((s['esperanRetro'] ?? 0) as num).toInt();
          final maxDias = ((s['maxDiasSinRetro'] ?? 0) as num).toInt();
          final atras = ((s['tesistasAtrasados'] ?? 0) as num).toInt();
          final grave = maxDias > 7;
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                grave ? Icons.error_outline : Icons.schedule,
                color: grave ? const Color(0xFFC62828) : cessumGold,
                size: 20),
            title: Text((s['asesor'] ?? '—').toString(),
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            subtitle: Text(
                [
                  if (retro > 0)
                    '$retro esperando retro (máx. $maxDias d)',
                  if (atras > 0) '$atras hito(s) vencidos del tesista',
                ].join(' · '),
                style: const TextStyle(fontSize: 11)),
            trailing: TextButton(
              onPressed: () => setState(() {
                _filtroAsesor = (s['asesor'] ?? '').toString();
                _busca.clear();
              }),
              child: const Text('Ver tesis', style: TextStyle(fontSize: 11.5)),
            ),
          );
        }),
      ],
    );
  }

  // ----------------- KPIs -----------------
  Widget _kpis() {
    final total = _tesis.length;
    final rezagadas = _tesis.where(_rezagada).length;
    final tituladas =
        _tesis.where((t) => (t['etapa'] ?? '').toString() == 'Titulado').length;
    return Row(
      children: [
        _kpi('Expedientes', '$total', cessumRed),
        const SizedBox(width: 8),
        _kpi('Rezagadas', '$rezagadas',
            rezagadas > 0 ? const Color(0xFFC62828) : Colors.grey),
        const SizedBox(width: 8),
        _kpi('Tituladas', '$tituladas', const Color(0xFF1E8E3E)),
      ],
    );
  }

  Widget _kpi(String label, String valor, Color color) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(valor, style: CessumType.display(26, color: color)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------- FILTROS -----------------
  Widget _barraFiltros() {
    final asesores = <String>{};
    for (final t in _tesis) {
      final d = (t['director'] ?? '').toString().trim();
      if (d.isNotEmpty) asesores.add(d);
    }
    final listaAsesores = asesores.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _busca,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar por estudiante, matrícula, título o asesor…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: const OutlineInputBorder(),
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _busca.clear()),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('Solo rezagadas'),
                selected: _soloRezagadas,
                onSelected: (v) => setState(() => _soloRezagadas = v),
                selectedColor: const Color(0xFFFDE7E7),
                labelStyle: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 6),
              _chipMenuEtapa(),
              const SizedBox(width: 6),
              _chipMenuAsesor(listaAsesores),
              if (_filtroEtapa != null ||
                  _filtroAsesor != null ||
                  _soloRezagadas) ...[
                const SizedBox(width: 6),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _filtroEtapa = null;
                    _filtroAsesor = null;
                    _soloRezagadas = false;
                  }),
                  icon: const Icon(Icons.filter_alt_off, size: 16),
                  label: const Text('Limpiar',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _chipMenuEtapa() {
    return PopupMenuButton<String>(
      tooltip: 'Filtrar por etapa',
      onSelected: (v) =>
          setState(() => _filtroEtapa = v == '__todas__' ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '__todas__', child: Text('Todas las etapas')),
        ..._etapas.map((e) => PopupMenuItem(
            value: e, child: Text(e, style: const TextStyle(fontSize: 13)))),
      ],
      child: Chip(
        avatar: const Icon(Icons.timeline, size: 16, color: cessumRed),
        label: Text(_filtroEtapa ?? 'Etapa: todas',
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _chipMenuAsesor(List<String> asesores) {
    return PopupMenuButton<String>(
      tooltip: 'Filtrar por asesor',
      onSelected: (v) =>
          setState(() => _filtroAsesor = v == '__todos__' ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: '__todos__', child: Text('Todos los asesores')),
        ...asesores.map((e) => PopupMenuItem(
            value: e, child: Text(e, style: const TextStyle(fontSize: 13)))),
      ],
      child: Chip(
        avatar: const Icon(Icons.school_outlined, size: 16, color: cessumRed),
        label: Text(
            _filtroAsesor == null
                ? 'Asesor: todos'
                : (_filtroAsesor!.length > 22
                    ? '${_filtroAsesor!.substring(0, 22)}…'
                    : _filtroAsesor!),
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  // ----------------- EMBUDO Y CARGA -----------------
  Widget _embudo() {
    final porEtapa = <String, int>{for (final e in _etapas) e: 0};
    for (final t in _tesis) {
      final e = (t['etapa'] ?? '').toString();
      if (porEtapa.containsKey(e)) porEtapa[e] = porEtapa[e]! + 1;
    }
    final maxEtapa =
        porEtapa.values.fold<int>(0, (p, c) => c > p ? c : p).clamp(1, 9999);
    return _Seccion(
      titulo: 'Embudo por etapa',
      icono: Icons.stacked_bar_chart,
      hijos: _etapas.map((e) {
        final c = porEtapa[e] ?? 0;
        return InkWell(
          onTap: () => setState(() => _filtroEtapa = c == 0 ? null : e),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                    width: 140,
                    child: Text(e, style: const TextStyle(fontSize: 11.5))),
                Expanded(
                  child: LayoutBuilder(builder: (ctx, bc) {
                    final w = bc.maxWidth * (c / maxEtapa);
                    return Stack(
                      children: [
                        Container(
                            height: 15,
                            decoration: BoxDecoration(
                                color: const Color(0xFFEEEEEE),
                                borderRadius: BorderRadius.circular(8))),
                        Container(
                            height: 15,
                            width: w,
                            decoration: BoxDecoration(
                                color: cessumGold,
                                borderRadius: BorderRadius.circular(8))),
                      ],
                    );
                  }),
                ),
                SizedBox(
                    width: 26,
                    child: Text('$c',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _cargaPorAsesor() {
    final porDir = <String, List<int>>{};
    for (final t in _tesis) {
      var dir = (t['director'] ?? '').toString().trim();
      if (dir.isEmpty) dir = '— sin asesor —';
      final m = porDir.putIfAbsent(dir, () => [0, 0]);
      m[0]++;
      if (((t['pendientesVencidos'] ?? 0) as int) > 0) m[1]++;
    }
    final dirs = porDir.keys.toList()
      ..sort((a, b) => porDir[b]![0].compareTo(porDir[a]![0]));
    return _Seccion(
      titulo: 'Carga por asesor',
      icono: Icons.groups_outlined,
      contador: '${dirs.length}',
      hijos: dirs.isEmpty
          ? [Text('—', style: TextStyle(color: cessumMuted(context)))]
          : dirs
              .map((d) => InkWell(
                    onTap: () => setState(() => _filtroAsesor =
                        d.startsWith('—') ? null : d),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                              child: Text(d,
                                  style: const TextStyle(fontSize: 12.5))),
                          Text('${porDir[d]![0]}',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                          if (porDir[d]![1] > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFFDE7E7),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text('${porDir[d]![1]} vencida(s)',
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFFC62828),
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ))
              .toList(),
    );
  }

  // ----------------- TARJETA DE EXPEDIENTE -----------------
  Widget _tarjetaTesis(Map<String, dynamic> t) {
    final idx = (t['etapaIndice'] ?? 0) as int;
    final total = (t['totalEtapas'] ?? _etapas.length) as int;
    final venc = (t['pendientesVencidos'] ?? 0) as int;
    final dias = t['diasSinAsesoria'];
    final rez = _rezagada(t);
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
                        Text(
                            'Mat. ${t['matricula']} · ${t['programa']} ${t['generacion']}',
                            style: TextStyle(
                                fontSize: 11, color: cessumMuted(context))),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${idx + 1}/$total · ${t['etapa']}',
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
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
              _CaminoEtapas(etapas: etapas, actual: idx, compacto: true),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 14, color: cessumFaint(context)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        (t['director'] ?? '').toString().trim().isEmpty
                            ? 'Sin asesor asignado'
                            : t['director'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11.5, color: cessumMuted(context))),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black38),
                ],
              ),
              if (rez)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (venc > 0)
                        _chip('$venc sin responder', const Color(0xFFC62828)),
                      if (dias is int && dias >= _umbralDiasSinAsesoria)
                        _chip('$dias d sin asesoría', cessumGold),
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

  // ----------------- ACCIONES -----------------
  Future<void> _vincular() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _VincularDialog(
        alumnos: _alumnos,
        docentes: _docentes,
        post: _post,
      ),
    );
    if (ok == true) _cargarTodo();
  }

  Future<void> _abrirDetalle(String matricula) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TesisExpedienteAdminScreen(
          matricula: matricula,
          etapas: _etapas,
          docentes: _docentes,
        ),
      ),
    );
    _cargarTodo();
  }
}

// =====================================================================
//  DIÁLOGO: vincular estudiante ↔ asesor
// =====================================================================

class _VincularDialog extends StatefulWidget {
  final List<Map<String, dynamic>> alumnos;
  final List<Map<String, dynamic>> docentes;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) post;
  const _VincularDialog(
      {required this.alumnos, required this.docentes, required this.post});
  @override
  State<_VincularDialog> createState() => _VincularDialogState();
}

class _VincularDialogState extends State<_VincularDialog> {
  final _busca = TextEditingController();
  final _titulo = TextEditingController();
  final _linkDoc = TextEditingController();
  final _finCiclo = TextEditingController();
  Map<String, dynamic>? _alumno;
  Map<String, dynamic>? _director;
  Map<String, dynamic>? _codirector;
  bool _guardando = false;

  @override
  void dispose() {
    _busca.dispose();
    _titulo.dispose();
    _linkDoc.dispose();
    _finCiclo.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_alumno == null) {
      _snack('Elige al estudiante.');
      return;
    }
    if (_director == null ||
        (_director!['nombre'] ?? '').toString().trim().isEmpty) {
      _snack('Elige al director de tesis.');
      return;
    }
    setState(() => _guardando = true);
    try {
      final r = await widget.post({
        'accion': 'titu_crear',
        'matricula': _alumno!['matricula'],
        'nombre': _alumno!['nombre'],
        'programa': _alumno!['programa'],
        'generacion': _alumno!['generacion'],
        'titulo': _titulo.text.trim(),
        // Se guarda el NOMBRE del docente (no el correo): así el Guardián puede
        // resolver su correo con correoDocentePorNombre_ para los avisos.
        'director': (_director!['nombre'] ?? '').toString().trim(),
        'codirector': (_codirector?['nombre'] ?? '').toString().trim(),
        'linkDoc': _linkDoc.text.trim(),
        'finUltimoCiclo': _finCiclo.text.trim(),
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _snack('No se pudo vincular: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickDirector({required bool codirector}) async {
    final d = await _elegirDocente(context, widget.docentes,
        titulo: codirector ? 'Codirector (opcional)' : 'Director de tesis',
        permitirNinguno: codirector);
    if (d == null) return;
    final vacio = (d['nombre'] ?? '').toString().trim().isEmpty;
    setState(() {
      if (codirector) {
        _codirector = vacio ? null : d;
      } else {
        _director = vacio ? null : d;
      }
    });
  }

  Widget _campoDocente(String etiqueta, Map<String, dynamic>? valor,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
            labelText: etiqueta,
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: const Icon(Icons.search, size: 18)),
        child: Text(
            valor == null ? 'Toca para buscar…' : _etiquetaDocente(valor),
            style: TextStyle(
                fontSize: 13,
                color: valor == null ? cessumFaint(context) : cessumInk(context))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _tNorm(_busca.text);
    final res = q.isEmpty
        ? <Map<String, dynamic>>[]
        : widget.alumnos
            .where((a) =>
                _tNorm((a['nombre'] ?? '').toString()).contains(q) ||
                (a['matricula'] ?? '').toString().contains(q))
            .take(20)
            .toList();

    return AlertDialog(
      title: const Text('Vincular tesis', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_alumno == null) ...[
                TextField(
                  controller: _busca,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Buscar estudiante (nombre o matrícula)',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                ...res.map((a) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        dense: true,
                        title: Text((a['nombre'] ?? '').toString(),
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                            'Mat. ${a['matricula']} · ${a['programa']} ${a['generacion']}',
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => setState(() => _alumno = a),
                      ),
                    )),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((_alumno!['nombre'] ?? '').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            Text(
                                'Mat. ${_alumno!['matricula']} · ${_alumno!['programa']} ${_alumno!['generacion']}',
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                      TextButton(
                          onPressed: () => setState(() => _alumno = null),
                          child: const Text('Cambiar')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _campoDocente('Director de tesis *', _director,
                    () => _pickDirector(codirector: false)),
                const SizedBox(height: 10),
                _campoDocente('Codirector (opcional)', _codirector,
                    () => _pickDirector(codirector: true)),
                const SizedBox(height: 10),
                TextField(
                  controller: _titulo,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Título tentativo',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _linkDoc,
                  decoration: const InputDecoration(
                      labelText: 'Link del Google Doc',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _finCiclo,
                  decoration: const InputDecoration(
                      labelText: 'Fin del último ciclo (AAAA-MM-DD)',
                      helperText: 'Para el plazo de titulación (Art. 90)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _guardando ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed, foregroundColor: Colors.white),
          onPressed: (_alumno == null || _guardando) ? null : _crear,
          child: Text(_guardando ? 'Guardando…' : 'Vincular'),
        ),
      ],
    );
  }
}

// =====================================================================
//  PANTALLA 2 — EXPEDIENTE COMPLETO (admin)
// =====================================================================

class TesisExpedienteAdminScreen extends StatefulWidget {
  final String matricula;
  final List<String> etapas;
  final List<Map<String, dynamic>> docentes;
  const TesisExpedienteAdminScreen({
    super.key,
    required this.matricula,
    this.etapas = const [],
    this.docentes = const [],
  });
  @override
  State<TesisExpedienteAdminScreen> createState() =>
      _TesisExpedienteAdminScreenState();
}

class _TesisExpedienteAdminScreenState
    extends State<TesisExpedienteAdminScreen> {
  bool _cargando = true;
  String? _error;
  String _actor = '';

  Map<String, dynamic>? _t;
  List<Map<String, dynamic>> _etapasHist = [];
  List<Map<String, dynamic>> _asesorias = [];
  List<Map<String, dynamic>> _inter = [];
  List<Map<String, dynamic>> _hitos = [];
  Map<String, dynamic>? _convenio;
  List<String> _catalogoEtapas = [];
  List<Map<String, dynamic>> _radiografia = [];

  @override
  void initState() {
    super.initState();
    _catalogoEtapas = List<String>.from(widget.etapas);
    _cargar();
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
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // (24-sep) Correo REAL: en «Ver como profesor» validEmail() devuelve el del
      // profesor, y el Guardián rechazaría la acción por no ser administrador.
      _actor = (await SessionStore.realEmail()) ?? '';
      final r = await _get(
          {'accion': 'titu_detalle', 'matricula': widget.matricula});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      List<Map<String, dynamic>> radio = [];
      try {
        final s = await _get({
          'accion': 'tesis_seguimiento_estado',
          'matricula': widget.matricula
        });
        if (s['ok'] == true) {
          radio = (s['hitos'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } catch (_) {
        // la radiografía es un extra: si falla, el expediente se abre igual
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
        final cat = (r['catalogoEtapas'] as List? ?? [])
            .map((e) => e.toString())
            .toList();
        if (cat.isNotEmpty) _catalogoEtapas = cat;
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

  // ------------------ EDICIONES EN SU LUGAR ------------------

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
            Text(
                'Se registra en el historial de etapas. No envía correos.',
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
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
      final r = await _post({
        'accion': 'titu_etapa',
        'matricula': widget.matricula,
        'etapa': etapa,
        'estado': 'En curso',
        'nota': texto.isEmpty ? 'Cambio de etapa desde el expediente' : texto,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('Etapa actualizada.');
      _cargar();
    } catch (e) {
      _snack('No se pudo mover de etapa: $e', error: true);
    }
  }

  Future<void> _editarAsesor({required bool codirector}) async {
    final d = await _elegirDocente(context, widget.docentes,
        titulo: codirector ? 'Codirector' : 'Director / asesor de tesis',
        permitirNinguno: codirector);
    if (d == null) return;
    final nombre = (d['nombre'] ?? '').toString().trim();
    try {
      final payload = <String, dynamic>{
        'accion': 'titu_reasignar',
        'matricula': widget.matricula,
      };
      if (codirector) {
        payload['codirector'] = nombre;
      } else {
        payload['director'] = nombre;
      }
      final r = await _post(payload);
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack(codirector ? 'Codirector actualizado.' : 'Asesor actualizado.');
      _cargar();
    } catch (e) {
      _snack('No se pudo guardar: $e', error: true);
    }
  }

  Future<void> _editarLector(int cual) async {
    final d = await _elegirDocente(context, widget.docentes,
        titulo: 'Lector $cual', permitirNinguno: true);
    if (d == null) return;
    final nombre = (d['nombre'] ?? '').toString().trim();
    try {
      final r = await _post({
        'accion': 'titu_lectores',
        'matricula': widget.matricula,
        if (cual == 1) 'lector1': nombre,
        if (cual == 2) 'lector2': nombre,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('Lector $cual actualizado.');
      _cargar();
    } catch (e) {
      _snack('No se pudo guardar: $e', error: true);
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
                        hintText:
                            'Qué se revisó y qué se acordó con el estudiante',
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
                              : '${_dosDig(fecha!.day)}/${_dosDig(fecha!.month)}/${fecha!.year}',
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
    final txtAcuerdos = acuerdos.text.trim();
    final txtCompromiso = compromiso.text.trim();
    final f = fecha;
    acuerdos.dispose();
    compromiso.dispose();
    if (ok != true) return;
    if (txtAcuerdos.isEmpty) {
      _snack('Escribe al menos los acuerdos.', error: true);
      return;
    }
    try {
      final r = await _post({
        'accion': 'titu_asesoria',
        'matricula': widget.matricula,
        'acuerdos': txtAcuerdos,
        'compromiso': txtCompromiso,
        'fechaCompromiso':
            f == null ? '' : '${f.year}-${_dosDig(f.month)}-${_dosDig(f.day)}',
        'registro': _actor,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('Asesoría registrada.');
      _cargar();
    } catch (e) {
      _snack('No se pudo registrar: $e', error: true);
    }
  }

  Future<void> _marcarRespondida(Map<String, dynamic> it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar pendiente', style: TextStyle(fontSize: 17)),
        content: Text(
            'Se marcará como respondida:\n\n“${it['desc'] ?? ''}”\n\n'
            'Sirve para cerrar a mano un pendiente que ya se atendió fuera de '
            'la plataforma. No envía correos.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar respondida'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _post({
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

  Future<void> _dictaminarHito(Map<String, dynamic> h, bool aprobar) async {
    final coment = TextEditingController(
        text: (h['comentario'] ?? '').toString());
    final nombreAl = (_t?['nombre'] ?? 'el estudiante').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aprobar ? 'Aprobar hito' : 'Solicitar cambios',
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
                    '⚠ Esto envía UN correo a $nombreAl avisándole que su hito '
                    '“${h['hito']}” fue ${aprobar ? 'aprobado' : 'devuelto para cambios'}'
                    '${aprobar ? ' (y le genera su constancia del hito)' : ''}. '
                    'Normalmente lo dictamina su asesor.',
                    style: const TextStyle(fontSize: 11.5, height: 1.3)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: coment,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText: aprobar
                        ? 'Comentario (opcional)'
                        : 'Qué debe corregir *',
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
      final r = await _post({
        'accion': 'titu_hito_revisar',
        'matricula': widget.matricula,
        'num': h['num'],
        'decision': aprobar ? 'aprobado' : 'devuelto',
        'comentario': texto,
        'registro': _actor,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack(aprobar ? 'Hito aprobado.' : 'Cambios solicitados.');
      _cargar();
    } catch (e) {
      _snack('No se pudo: $e', error: true);
    }
  }

  // ------------------ BUILD ------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Expediente de tesis'),
        actions: [
          IconButton(
            tooltip: 'Convenio de trabajo',
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
                        Icon(Icons.cloud_off,
                            size: 46, color: cessumFaint(context)),
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
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                    children: [
                      _cabecera(),
                      const SizedBox(height: 10),
                      _tarjetaCamino(),
                      _alertasHitos(),
                      _seccionConvenio(),
                      _seccionHitos(),
                      _seccionAsesorias(),
                      _seccionInteracciones(),
                      _seccionLineaTiempo(),
                      _seccionHistorialEtapas(),
                    ],
                  ),
                ),
    );
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
          rol: 'admin',
        ),
      ),
    );
    _cargar();
  }

  // ------------------ CABECERA VIVA ------------------
  Widget _cabecera() {
    final t = _t!;
    final titulo = (t['titulo'] ?? '').toString().trim();
    final etapa = (t['etapa'] ?? '').toString();
    final idx = (t['etapaIndice'] ?? 0) as int;
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
                    color: Theme.of(context).cardColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    'Etapa ${idx + 1}/${_catalogoEtapas.isEmpty ? '?' : _catalogoEtapas.length}',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // El título, el documento y el fin de ciclo se editan AQUÍ, con la
          // ruta titu_editar. Antes la única forma de corregir el título era
          // volver a guardar el convenio, y eso REINICIA las cuatro firmas.
          InkWell(
            onTap: _editarDatos,
            borderRadius: BorderRadius.circular(10),
            child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withValues(alpha: 0.12),
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
                Text('Etapa actual: $etapa',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF0D9A8))),
              ],
            ),
            ),
          ),
          const SizedBox(height: 10),
          _filaPersona('Asesor / director', t['director'],
              () => _editarAsesor(codirector: false)),
          _filaPersona('Codirector', t['codirector'],
              () => _editarAsesor(codirector: true)),
          _filaPersona('Lector 1', t['lector1'], () => _editarLector(1)),
          _filaPersona('Lector 2', t['lector2'], () => _editarLector(2)),
          if ((t['linkDoc'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () =>
                  Helpers.abrirUrlExterna(t['linkDoc'].toString(), context),
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
          if ((t['finUltimoCiclo'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'Fin del último ciclo: ${_tFechaCorta(t['finUltimoCiclo'])} · plazo de titulación (Art. 90)',
                  style:
                      const TextStyle(fontSize: 10.5, color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  /// Corrige título, link del documento y fin del último ciclo con la ruta
  /// titu_editar (V485). Solo manda los campos que de verdad cambiaron: así
  /// no se pisa un dato bueno con una cadena vacía por descuido.
  Future<void> _editarDatos() async {
    final t = _t;
    if (t == null) return;
    final tituloOrig = (t['titulo'] ?? '').toString();
    final linkOrig = (t['linkDoc'] ?? '').toString();
    final finOrig = (t['finUltimoCiclo'] ?? '').toString();
    final titulo = TextEditingController(text: tituloOrig);
    final link = TextEditingController(text: linkOrig);
    final fin = TextEditingController(text: finOrig);
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
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: link,
                  decoration: const InputDecoration(
                      labelText: 'Link del documento',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fin,
                  decoration: const InputDecoration(
                      labelText: 'Fin del último ciclo (AAAA-MM-DD)',
                      helperText: 'Para el plazo de titulación (Art. 90)',
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
                      '✓ Esto NO toca el convenio ni las firmas. Solo corrige '
                      'los datos de la tesis.',
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
    final nFin = fin.text.trim();
    titulo.dispose();
    link.dispose();
    fin.dispose();
    if (ok != true) return;

    final payload = <String, dynamic>{
      'accion': 'titu_editar',
      'matricula': widget.matricula,
      'actor': _actor,
    };
    if (nTitulo != tituloOrig) payload['titulo'] = nTitulo;
    if (nLink != linkOrig) payload['linkDoc'] = nLink;
    if (nFin != finOrig) payload['finUltimoCiclo'] = nFin;
    if (payload.length <= 3) {
      _snack('No cambiaste nada.');
      return;
    }
    try {
      final r = await _post(payload);
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _snack('Datos actualizados.');
      _cargar();
    } catch (e) {
      _snack('No se pudo guardar: $e', error: true);
    }
  }

  Widget _filaPersona(String rol, dynamic valor, VoidCallback onEditar) {
    final v = (valor ?? '').toString().trim();
    final doc = _docentePorValor(widget.docentes, v);
    final muestra = doc != null ? _etiquetaDocente(doc) : v;
    return InkWell(
      onTap: onEditar,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 116,
              child: Text(rol,
                  style: const TextStyle(fontSize: 11, color: Colors.white60)),
            ),
            Expanded(
              child: Text(muestra.isEmpty ? 'Sin asignar' : muestra,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: muestra.isEmpty ? Colors.white54 : Colors.white)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit, size: 15, color: Color(0xFFF0D9A8)),
          ],
        ),
      ),
    );
  }

  // ------------------ CAMINO DE ETAPAS ------------------
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
                  child: Text('Camino de la tesis (Reglamento, Cap. VIII)',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
                Text('toca una etapa para moverla',
                    style: TextStyle(
                        fontSize: 10, color: cessumMuted(context))),
              ],
            ),
            const SizedBox(height: 8),
            _CaminoEtapas(
              etapas: _catalogoEtapas,
              actual: idx,
              onTap: _moverEtapa,
            ),
          ],
        ),
      ),
    );
  }

  // ------------------ SEMÁFORO DE HITOS ------------------
  Widget _alertasHitos() {
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
                          color: _colorSemaforo(
                              (h['semaforo'] ?? '').toString())),
                    ),
                    Expanded(
                      child: Text(
                          'Hito ${h['num']} · ${h['hito']} — '
                          '${debe == 'asesor' ? 'espera retroalimentación del asesor' : 'el estudiante no ha entregado'}'
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

  // ------------------ CONVENIO ------------------
  Widget _seccionConvenio() {
    final c = _convenio;
    final estado = (c?['estado'] ?? 'Sin convenio').toString();
    final firmas = <String, bool>{
      'Estudiante': (c?['firmaAlumno'] ?? '').toString().isNotEmpty,
      'Asesor': (c?['firmaAsesor'] ?? '').toString().isNotEmpty,
      'Autoridad 1': (c?['firmaAutoridad'] ?? '').toString().isNotEmpty,
      'Autoridad 2': (c?['firmaAutoridad2'] ?? '').toString().isNotEmpty,
    };
    final linkPdf = (c?['linkPdf'] ?? '').toString();
    return _Seccion(
      titulo: 'Convenio de trabajo',
      icono: Icons.handshake_outlined,
      contador: estado,
      abiertaAlInicio: c == null,
      hijos: [
        if (c == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Todavía no se ha definido el convenio (objetivo, fechas, '
                  'cláusulas e hitos de entrega).',
                  style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white),
                onPressed: _abrirConvenio,
                icon: const Icon(Icons.edit_document, size: 18),
                label: const Text('Definir convenio'),
              ),
            ],
          )
        else ...[
          if ((c['folio'] ?? '').toString().isNotEmpty)
            _lineaDato('Folio', c['folio'].toString()),
          if ((c['objetivo'] ?? '').toString().isNotEmpty)
            _lineaDato('Objetivo', c['objetivo'].toString()),
          _lineaDato('Vigencia',
              '${c['fechaInicio'] ?? '—'}  →  ${c['fechaTermino'] ?? '—'}'),
          _lineaDato('Autoridades', (c['autoridad'] ?? '—').toString()),
          const SizedBox(height: 8),
          const Text('Firmas',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 4),
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
                      child: Text(
                          '${e.value ? '✓' : '○'} ${e.key}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: e.value
                                  ? const Color(0xFF1B5E20)
                                  : cessumMuted(context))),
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
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white),
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

  Widget _lineaDato(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 96,
                child: Text(k,
                    style: TextStyle(
                        fontSize: 11, color: cessumMuted(context)))),
            Expanded(
                child: Text(v, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      );

  // ------------------ HITOS ------------------
  Widget _seccionHitos() {
    return _Seccion(
      titulo: 'Hitos y entregables',
      icono: Icons.flag_outlined,
      contador: '${_hitos.length}',
      abiertaAlInicio: _hitos.isNotEmpty,
      hijos: _hitos.isEmpty
          ? [
              Text(
                  'Sin hitos: se capturan al definir el convenio de trabajo.',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))
            ]
          : _hitos.map(_tarjetaHito).toList(),
    );
  }

  Widget _tarjetaHito(Map<String, dynamic> h) {
    final estado = (h['estado'] ?? 'pendiente').toString();
    final col = _colorEstadoHito(estado);
    final link = (h['link'] ?? '').toString();
    final linkRev = (h['linkRevision'] ?? '').toString();
    final linkCor = (h['linkCorreccion'] ?? '').toString();
    final obs = (h['observaciones'] ?? '').toString();
    final coment = (h['comentario'] ?? '').toString();
    final entregado = estado == 'entregado' || estado == 'devuelto';
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
              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          if (coment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFFFBF6EE),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('Dictamen del asesor: $coment',
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
          if (entregado) ...[
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E8E3E)),
                    onPressed: () => _dictaminarHito(h, true),
                    icon: const Icon(Icons.check_circle_outline, size: 17),
                    label: const Text('Aprobar',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed),
                    onPressed: () => _dictaminarHito(h, false),
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

  // ------------------ ASESORÍAS ------------------
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
          Text('Sin asesorías registradas.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))
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
                        Text(_tFechaCorta(a['fecha']),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text((a['acuerdos'] ?? '—').toString(),
                        style: const TextStyle(fontSize: 12.5, height: 1.3)),
                    if ((a['compromiso'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                          'Compromiso del estudiante: ${a['compromiso']}'
                          '${(a['fechaComp'] ?? '').toString().isNotEmpty ? ' · para el ${_tFechaCorta(a['fechaComp'])}' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, color: cessumMuted(context))),
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

  // ------------------ INTERACCIONES ------------------
  Widget _seccionInteracciones() {
    final pendientes = _inter
        .where((i) =>
            i['estado'] == 'pendiente' || i['estado'] == 'vencida')
        .length;
    return _Seccion(
      titulo: 'Entregas y correcciones',
      icono: Icons.swap_vert_circle_outlined,
      contador: pendientes > 0
          ? '$pendientes abiertas de ${_inter.length}'
          : '${_inter.length}',
      abiertaAlInicio: pendientes > 0,
      hijos: _inter.isEmpty
          ? [
              Text('Sin movimientos.',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))
            ]
          : _inter.reversed.map((it) {
              final estado = (it['estado'] ?? '').toString();
              final c = _colorEstadoInter(estado);
              final abierta = estado == 'pendiente' || estado == 'vencida';
              final link = (it['link'] ?? '').toString();
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    border: Border.all(color: c.withValues(alpha: 0.30)),
                    borderRadius: BorderRadius.circular(10)),
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
                        Text(_tFechaCorta(it['fecha']),
                            style: TextStyle(
                                fontSize: 10.5, color: cessumMuted(context))),
                      ],
                    ),
                    if ((it['desc'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(it['desc'].toString(),
                          style: const TextStyle(fontSize: 12.5, height: 1.3)),
                    ],
                    const SizedBox(height: 4),
                    Text(
                        'De: ${it['de'] ?? '—'} · Límite: ${_tFechaCorta(it['limite'])}'
                        '${(it['respuesta'] ?? '').toString().isNotEmpty ? ' · Respondida: ${_tFechaCorta(it['respuesta'])}' : ''}',
                        style: TextStyle(
                            fontSize: 10.5, color: cessumMuted(context))),
                    if (link.isNotEmpty || abierta) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (link.isNotEmpty)
                            _botonLink('Ver archivo', link, Icons.attach_file),
                          const Spacer(),
                          if (abierta)
                            TextButton.icon(
                              onPressed: () => _marcarRespondida(it),
                              icon: const Icon(Icons.done_all, size: 16),
                              label: const Text('Cerrar',
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

  // ------------------ LÍNEA DE TIEMPO UNIFICADA ------------------
  Widget _seccionLineaTiempo() {
    final eventos = <Map<String, dynamic>>[];

    for (final e in _etapasHist) {
      final f = _tFecha(e['entrada']);
      eventos.add({
        '_f': f,
        'titulo': 'Etapa · ${e['etapa']}',
        'fecha': [
          _tFechaCorta(e['entrada']),
          if ((e['nota'] ?? '').toString().isNotEmpty) e['nota'].toString(),
        ].where((x) => x.isNotEmpty).join(' · '),
      });
    }
    for (final a in _asesorias) {
      final f = _tFecha(a['fecha']);
      final ac = (a['acuerdos'] ?? '').toString();
      eventos.add({
        '_f': f,
        'titulo': 'Asesoría',
        'fecha':
            '${_tFechaCorta(a['fecha'])}${ac.isEmpty ? '' : ' · ${ac.length > 70 ? '${ac.substring(0, 70)}…' : ac}'}',
      });
    }
    for (final i in _inter) {
      final f = _tFecha(i['fecha']);
      final d = (i['desc'] ?? '').toString();
      eventos.add({
        '_f': f,
        'titulo':
            '${i['tipo'] == 'correccion' ? 'Corrección' : 'Avance'} · de ${i['de'] ?? '—'}',
        'fecha':
            '${_tFechaCorta(i['fecha'])}${d.isEmpty ? '' : ' · ${d.length > 70 ? '${d.substring(0, 70)}…' : d}'}',
      });
    }
    for (final h in _hitos) {
      final fe = (h['fechaEntrega'] ?? '').toString();
      if (fe.isEmpty) continue;
      eventos.add({
        '_f': _tFecha(fe),
        'titulo': 'Entrega de hito ${h['num']} · ${h['hito']}',
        'fecha': '${_tFechaCorta(fe)} · ${h['estado']}',
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
              Text('Todavía no hay movimientos que mostrar.',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))
            ]
          : [
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                    'Asesorías, entregas, correcciones y cambios de etapa, del '
                    'más reciente al más antiguo.',
                    style: TextStyle(fontSize: 11, color: cessumMuted(context))),
              ),
              TimelineCessum(hitos: hitos),
            ],
    );
  }

  // ------------------ HISTORIAL DE ETAPAS ------------------
  Widget _seccionHistorialEtapas() {
    return _Seccion(
      titulo: 'Historial de etapas',
      icono: Icons.history,
      contador: '${_etapasHist.length}',
      hijos: _etapasHist.isEmpty
          ? [
              Text('—',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))
            ]
          : _etapasHist.reversed
              .map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                            (e['cierre'] ?? '').toString().isNotEmpty
                                ? Icons.check_circle_outline
                                : Icons.radio_button_checked,
                            size: 15,
                            color: (e['cierre'] ?? '').toString().isNotEmpty
                                ? const Color(0xFF1E8E3E)
                                : cessumRed),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${e['etapa']} · ${e['estado']}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  '${_tFechaCorta(e['entrada'])}'
                                  '${(e['cierre'] ?? '').toString().isNotEmpty ? ' → ${_tFechaCorta(e['cierre'])}' : ' (abierta)'}'
                                  '${(e['nota'] ?? '').toString().isNotEmpty ? '\n${e['nota']}' : ''}',
                                  style: TextStyle(
                                      fontSize: 11, color: cessumMuted(context))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
    );
  }
}

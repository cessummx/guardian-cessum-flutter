// =====================================================================
//  tesis_solicitudes_admin_screen.dart · CESSUM · Aula CESSUM
//  ADMIN — Solicitudes de tutor de tesis.
//  Rediseño ago-2026: además de revisar y asignar, esta pantalla es la
//  PUERTA al panel de expedientes de tesis (AdminTesisScreen, que estaba
//  huérfana: ningún menú la abría).
//
//  Backend usado (todo preexistente):
//    GET  tesis_solicitudes_listar · docentes_lista · titu_listar
//    POST tesis_solicitud_asignar   (OJO: envía 2 correos — alumno y asesor)
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'admin_tesis_screen.dart';

// ---------------------------------------------------------------------
//  Utilidades locales
// ---------------------------------------------------------------------

String _sNorm(String s) {
  s = s.toLowerCase();
  const a = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const b = 'aaaaaeeeeiiiiooooouuuun';
  for (var i = 0; i < a.length; i++) {
    s = s.replaceAll(a[i], b[i]);
  }
  return s.trim();
}

/// Quita el título académico para poder comparar nombres de docente.
String _sSinTitulo(String s) {
  var n = _sNorm(s);
  n = n.replaceFirst(
      RegExp(r'^(dr|dra|mtro|mtra|mtr|lic|licda|ing|prof|profa|profe|c)\.?\s+'),
      '');
  return n.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _sEtiquetaDoc(Map<String, dynamic> d) {
  final t = (d['titulo'] ?? '').toString().trim();
  final n = (d['nombre'] ?? '').toString().trim();
  return t.isEmpty ? n : '$t $n';
}

// ---------------------------------------------------------------------
//  Selector de docente CON BUSCADOR y carga de tesis a la vista.
//  (Privado a este archivo: los widgets de admin_tesis_screen.dart también
//  lo son, y no vale la pena exponerlos solo para esto.)
// ---------------------------------------------------------------------
class _PickDocente extends StatefulWidget {
  final List<Map<String, dynamic>> docentes;
  final Map<String, int> carga; // nombre normalizado -> tesis dirigidas
  final String? preferencia;
  const _PickDocente(
      {required this.docentes, required this.carga, this.preferencia});
  @override
  State<_PickDocente> createState() => _PickDocenteState();
}

class _PickDocenteState extends State<_PickDocente> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _sNorm(_busca.text);
    final pref = _sSinTitulo(widget.preferencia ?? '');
    final lista = q.isEmpty
        ? widget.docentes
        : widget.docentes
            .where((d) =>
                _sNorm(_sEtiquetaDoc(d)).contains(q) ||
                _sNorm((d['correo'] ?? '').toString()).contains(q))
            .toList();
    return AlertDialog(
      title: const Text('Elegir director de tesis',
          style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 460,
        height: 440,
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
                  ? const Center(
                      child: Text('Sin coincidencias',
                          style: TextStyle(color: Colors.black54)))
                  : ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (ctx, i) {
                        final d = lista[i];
                        final nombre = (d['nombre'] ?? '').toString();
                        final n = widget.carga[_sSinTitulo(nombre)] ?? 0;
                        final esPref =
                            pref.isNotEmpty && _sSinTitulo(nombre) == pref;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              esPref ? Icons.star : Icons.person_outline,
                              size: 20,
                              color: esPref ? cessumGold : cessumRed),
                          title: Text(_sEtiquetaDoc(d),
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                              '${(d['correo'] ?? '—')}  ·  '
                              '${n == 0 ? 'sin tesis a su cargo' : '$n tesis dirigida${n == 1 ? '' : 's'}'}'
                              '${esPref ? '  ·  preferencia del alumno' : ''}',
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
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}

// =====================================================================
//  PANTALLA
// =====================================================================

class TesisSolicitudesAdminScreen extends StatefulWidget {
  const TesisSolicitudesAdminScreen({super.key});

  @override
  State<TesisSolicitudesAdminScreen> createState() =>
      _TesisSolicitudesAdminScreenState();
}

class _TesisSolicitudesAdminScreenState
    extends State<TesisSolicitudesAdminScreen> {
  bool _cargando = true;
  bool _guardando = false;
  String _error = '';
  String _filtro = 'Pendiente';

  final _busca = TextEditingController();
  List<Map<String, dynamic>> _sols = [];
  List<Map<String, dynamic>> _docentes = [];

  /// Expedientes de tesis ya existentes, por matrícula (para detectar
  /// incoherencias antes de asignar).
  Map<String, Map<String, dynamic>> _tesisPorMat = {};

  /// Cuántas tesis dirige cada docente (nombre normalizado -> total).
  Map<String, int> _cargaAsesor = {};

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

  Future<Map<String, dynamic>> _get(String accion) async {
    final r = await http
        .get(Uri.parse('$guardianUrl?accion=$accion'))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _get('tesis_solicitudes_listar');
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');

      // Catálogo de docentes (hoja Docentes). Es el catálogo COMPLETO: el
      // ranking de seguimiento solo trae a quienes ya tienen actividad.
      List<Map<String, dynamic>> docs = [];
      try {
        final rd = await _get('docentes_lista');
        final vistos = <String>{};
        docs = ((rd['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((dd) {
          final clave = _sSinTitulo((dd['nombre'] ?? '').toString());
          if (clave.isEmpty || vistos.contains(clave)) return false;
          vistos.add(clave);
          return true;
        }).toList();
        docs.sort((x, y) => _sEtiquetaDoc(x)
            .toLowerCase()
            .compareTo(_sEtiquetaDoc(y).toLowerCase()));
      } catch (_) {
        // sin catálogo la pantalla sigue sirviendo para revisar solicitudes
      }

      // Expedientes de tesis vivos: para carga por asesor y para avisar si el
      // alumno ya tenía director.
      final porMat = <String, Map<String, dynamic>>{};
      final carga = <String, int>{};
      try {
        final rt = await _get('titu_listar');
        for (final e in ((rt['tesis'] as List?) ?? [])) {
          final t = Map<String, dynamic>.from(e as Map);
          porMat[(t['matricula'] ?? '').toString().trim()] = t;
          final dir = _sSinTitulo((t['director'] ?? '').toString());
          if (dir.isNotEmpty) carga[dir] = (carga[dir] ?? 0) + 1;
        }
      } catch (_) {
        // opcional: si falla, solo perdemos los avisos de contexto
      }

      if (!mounted) return;
      setState(() {
        _sols = ((d['solicitudes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (docs.isNotEmpty) _docentes = docs;
        _tesisPorMat = porMat;
        _cargaAsesor = carga;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
      content: Text(m),
    ));
  }

  // ------------------------------------------------------------------
  //  ASIGNAR DIRECTOR
  // ------------------------------------------------------------------
  Future<void> _asignar(Map<String, dynamic> s) async {
    final matricula = (s['matricula'] ?? '').toString().trim();
    final preferencia = (s['asesorPreferido'] ?? '').toString().trim();
    final yaTiene = _tesisPorMat[matricula];
    final directorPrevio = (yaTiene?['director'] ?? '').toString().trim();

    // Si la preferencia del alumno coincide con alguien del catálogo, viene
    // preseleccionada; si no, se avisa (puede ser un nombre escrito a mano).
    Map<String, dynamic>? elegido;
    if (preferencia.isNotEmpty) {
      final p = _sSinTitulo(preferencia);
      for (final d in _docentes) {
        if (_sSinTitulo((d['nombre'] ?? '').toString()) == p) {
          elegido = d;
          break;
        }
      }
    }
    final preferenciaSinMatch = preferencia.isNotEmpty && elegido == null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        final nombreElegido =
            (elegido?['nombre'] ?? '').toString().trim();
        final correoElegido =
            (elegido?['correo'] ?? '').toString().trim();
        return AlertDialog(
          title: const Text('Asignar director de tesis',
              style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- expediente del solicitante ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF4F2ED),
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s['nombre']}',
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700)),
                        Text(
                            'Mat. $matricula · ${s['programa']} ${s['generacion']}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                        const SizedBox(height: 6),
                        Text('Tema: ${s['tema']}',
                            style: const TextStyle(
                                fontSize: 12, height: 1.35)),
                        if ((s['justificacion'] ?? '')
                            .toString()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('${s['justificacion']}',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  height: 1.35,
                                  color: Colors.black54)),
                        ],
                      ],
                    ),
                  ),

                  // --- incoherencias detectadas ---
                  if (directorPrevio.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _aviso(
                        '⚠ Este alumno YA tiene expediente de tesis con '
                        '$directorPrevio como director. Asignar aquí lo '
                        'reemplaza en la hoja Tesis.',
                        const Color(0xFFFDF3E7),
                        CC.goldBorder),
                  ],
                  if (preferenciaSinMatch) ...[
                    const SizedBox(height: 10),
                    _aviso(
                        'El alumno pidió a «$preferencia», pero ese nombre no '
                        'coincide con ningún docente del catálogo. Elige del '
                        'listado para que el sistema pueda avisarle por correo.',
                        const Color(0xFFFDF3E7),
                        CC.goldBorder),
                  ],

                  const SizedBox(height: 12),
                  const Text('Director de tesis',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final d = await showDialog<Map<String, dynamic>>(
                        context: ctx,
                        builder: (_) => _PickDocente(
                          docentes: _docentes,
                          carga: _cargaAsesor,
                          preferencia: preferencia,
                        ),
                      );
                      if (d != null) setSt(() => elegido = d);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: Icon(Icons.search, size: 18)),
                      child: Text(
                          elegido == null
                              ? 'Toca para buscar entre los docentes…'
                              : _sEtiquetaDoc(elegido!),
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: elegido == null
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                              color: elegido == null
                                  ? Colors.black45
                                  : Colors.black87)),
                    ),
                  ),
                  if (elegido != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        '${correoElegido.isEmpty ? 'Sin correo registrado' : correoElegido}'
                        '  ·  ${_cargaAsesor[_sSinTitulo(nombreElegido)] ?? 0} tesis a su cargo',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54)),
                    if (correoElegido.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                            'Sin correo en la hoja Docentes no le llegará el '
                            'aviso; el alumno sí recibirá el suyo.',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFFC62828))),
                      ),
                  ],

                  // --- advertencia de correos ---
                  const SizedBox(height: 14),
                  _aviso(
                      '📧 Al asignar se envían DOS correos y no se pueden '
                      'silenciar: uno a ${s['nombre']} '
                      '(${(s['correo'] ?? 'sin correo')}) avisándole quién lo '
                      'dirigirá, y otro a '
                      '${elegido == null ? 'el director que elijas' : nombreElegido} '
                      'con el tema propuesto.',
                      const Color(0xFFF1F5FB),
                      const Color(0xFFB9CEE6)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed:
                  elegido == null ? null : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.send, size: 17),
              label: const Text('Asignar y notificar'),
            ),
          ],
        );
      }),
    );

    if (ok != true || elegido == null) return;
    final nombreAsesor = (elegido!['nombre'] ?? '').toString().trim();
    if (nombreAsesor.isEmpty) {
      _snack('Ese docente no tiene nombre registrado.', error: true);
      return;
    }

    setState(() => _guardando = true);
    try {
      final quien = await SessionStore.validEmail();
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'tesis_solicitud_asignar',
                'matricula': matricula,
                // Se manda el NOMBRE (no el correo): el Guardián resuelve el
                // correo del asesor con correoDocentePorNombre_.
                'asesor': nombreAsesor,
                'actor': quien ?? '',
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text('$nombreAsesor asignado. Ambos fueron notificados.'),
          action: SnackBarAction(
            label: 'ABRIR EXPEDIENTE',
            textColor: Colors.white,
            onPressed: () => _abrirExpediente(matricula),
          ),
        ));
        _cargar();
      } else {
        _snack('${d['error']}', error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    }
    if (mounted) setState(() => _guardando = false);
  }

  Widget _aviso(String texto, Color fondo, Color borde) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: fondo,
            border: Border.all(color: borde),
            borderRadius: BorderRadius.circular(10)),
        child: Text(texto,
            style: const TextStyle(fontSize: 11.5, height: 1.35)),
      );

  // ------------------------------------------------------------------
  //  NAVEGACIÓN AL PANEL DE EXPEDIENTES
  // ------------------------------------------------------------------
  Future<void> _abrirPanelTesis() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AdminTesisScreen()));
    _cargar();
  }

  Future<void> _abrirExpediente(String matricula) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TesisExpedienteAdminScreen(
          matricula: matricula,
          docentes: _docentes,
        ),
      ),
    );
    _cargar();
  }

  // ------------------------------------------------------------------
  //  BUILD
  // ------------------------------------------------------------------
  List<Map<String, dynamic>> get _visibles {
    final q = _sNorm(_busca.text);
    return _sols.where((s) {
      if (_filtro != 'Todas' && (s['estado'] ?? '') != _filtro) return false;
      if (q.isEmpty) return true;
      return _sNorm((s['nombre'] ?? '').toString()).contains(q) ||
          _sNorm((s['tema'] ?? '').toString()).contains(q) ||
          _sNorm((s['programa'] ?? '').toString()).contains(q) ||
          _sNorm((s['asesorAsignado'] ?? '').toString()).contains(q) ||
          (s['matricula'] ?? '').toString().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final vis = _cargando ? <Map<String, dynamic>>[] : _visibles;
    final pendientes =
        _sols.where((s) => (s['estado'] ?? '') == 'Pendiente').length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Solicitudes de tutor de tesis',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        actions: [
          IconButton(
              tooltip: 'Expedientes de tesis',
              onPressed: _abrirPanelTesis,
              icon: const Icon(Icons.folder_shared_outlined)),
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(14), child: CessumSkeletonList())
          : _error.isNotEmpty
              ? _vistaError()
              : Column(
                  children: [
                    _accesoExpedientes(),
                    _barraFiltros(pendientes),
                    if (_guardando)
                      const LinearProgressIndicator(color: cessumRed),
                    Expanded(
                      child: vis.isEmpty
                          ? _vacio()
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(14, 6, 14, 20),
                                children: [for (final s in vis) _tarjeta(s)],
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 46, color: Colors.grey),
              const SizedBox(height: 10),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton(
                  onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _vacio() => CessumEmptyState(
        title: _busca.text.trim().isNotEmpty
            ? 'Ninguna solicitud coincide'
            : 'Sin solicitudes en este filtro',
        subtitle: _busca.text.trim().isNotEmpty
            ? 'Prueba con otro nombre, matrícula o tema.'
            : 'Cuando un alumno solicite tutor de tesis desde su menú, '
                'aparecerá aquí firmado y listo para asignarle director.',
        icon: Icons.school_outlined,
        action: OutlinedButton.icon(
          onPressed: _abrirPanelTesis,
          icon: const Icon(Icons.folder_shared_outlined, size: 18),
          label: const Text('Ver expedientes de tesis'),
        ),
      );

  /// Tarjeta de acceso al panel de expedientes. Es la única puerta a
  /// AdminTesisScreen en toda la app.
  Widget _accesoExpedientes() {
    final total = _tesisPorMat.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _abrirPanelTesis,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB11D29), Color(0xFF8E1720)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_shared_outlined,
                    color: Colors.white, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Expedientes de tesis',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      Text(
                          total == 0
                              ? 'Etapas, asesorías, hitos y convenios'
                              : '$total expediente${total == 1 ? '' : 's'} · etapas, asesorías, hitos y convenios',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11.5)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _barraFiltros(int pendientes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Column(
        children: [
          TextField(
            controller: _busca,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por alumno, matrícula, tema o director…',
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
          Row(
            children: [
              for (final f in ['Pendiente', 'Asignada', 'Todas'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f == 'Pendiente' && pendientes > 0
                        ? '$f ($pendientes)'
                        : f),
                    selected: _filtro == f,
                    selectedColor: cessumRed.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                        fontSize: 12,
                        color: _filtro == f ? cessumRed : Colors.black87,
                        fontWeight:
                            _filtro == f ? FontWeight.w700 : FontWeight.w400),
                    onSelected: (_) => setState(() => _filtro = f),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> s) {
    final pendiente = (s['estado'] ?? '') == 'Pendiente';
    final matricula = (s['matricula'] ?? '').toString().trim();
    final tesis = _tesisPorMat[matricula];
    final firma = (s['firmaUrl'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: pendiente
                ? cessumGold.withValues(alpha: 0.55)
                : Colors.black12,
            width: pendiente ? 1.4 : 1),
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
                    Text('${s['nombre']}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text(
                        'Mat. $matricula · ${s['programa']} ${s['generacion']}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black45)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: pendiente
                      ? cessumGold.withValues(alpha: 0.12)
                      : const Color(0xFF1E8E3E).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${s['estado']}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: pendiente
                            ? cessumGold
                            : const Color(0xFF1E8E3E))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: const Color(0xFFF7F5F0),
                borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${s['tema']}',
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
                if ((s['justificacion'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${s['justificacion']}',
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.35, color: Colors.black54)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Solicitó el ${s['fecha']}',
              style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          if ((s['asesorPreferido'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.star, size: 13, color: cessumGold),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('Prefiere a ${s['asesorPreferido']}',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: cessumGold)),
                  ),
                ],
              ),
            ),
          if (!pendiente)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 14, color: Color(0xFF1E8E3E)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        'Director: ${s['asesorAsignado']}'
                        '${tesis != null && (tesis['etapa'] ?? '').toString().isNotEmpty ? '  ·  ${tesis['etapa']}' : ''}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E8E3E))),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (firma.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => Helpers.abrirUrlExterna(firma, context),
                  icon: const Icon(Icons.draw, size: 15),
                  label:
                      const Text('Ver firma', style: TextStyle(fontSize: 12)),
                ),
              if (pendiente)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact),
                  onPressed: _guardando ? null : () => _asignar(s),
                  icon: const Icon(Icons.person_add_alt, size: 16),
                  label: const Text('Asignar director',
                      style: TextStyle(fontSize: 12)),
                ),
              if (tesis != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _abrirExpediente(matricula),
                  icon: const Icon(Icons.folder_open, size: 15),
                  label: const Text('Abrir expediente',
                      style: TextStyle(fontSize: 12)),
                ),
              if (!pendiente && tesis == null)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text('Asignada, pero sin expediente en la hoja Tesis',
                      style:
                          TextStyle(fontSize: 11, color: Color(0xFFC62828))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

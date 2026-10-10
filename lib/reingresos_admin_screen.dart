import 'dart:convert';

import 'package:flutter/material.dart';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Pantalla de Vicerrectoría para dictaminar los REINGRESOS.
///
/// (ago-29) El módulo de reingreso llevaba días completo del lado del
/// backend —`reingreso_listar`, `reingreso_propuesta`, `reingreso_dictaminar`—
/// y sin una sola pantalla que lo usara. Consecuencia: un alumno de baja podía
/// solicitar su reingreso, subir su kárdex y su solicitud firmada, y esa
/// solicitud se quedaba en la hoja sin que nadie la viera. Solo se alcanzaba
/// consultando la URL a mano.
///
/// Aquí se resuelve el trámite completo: expediente, propuesta de convenio con
/// las materias a recursar ya calculadas, y la resolución.
class ReingresosAdminScreen extends StatefulWidget {
  final String actor;
  const ReingresosAdminScreen({super.key, required this.actor});

  @override
  State<ReingresosAdminScreen> createState() => _ReingresosAdminScreenState();
}

class _ReingresosAdminScreenState extends State<ReingresosAdminScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _todas = [];
  List<Map<String, dynamic>> _porEstado = [];
  String _filtro = 'Pendientes';

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
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'reingreso_listar',
        'actor': widget.actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) {
        setState(() {
          _cargando = false;
          _error = (d['error'] ?? 'No se pudo cargar').toString();
        });
        return;
      }
      setState(() {
        _cargando = false;
        _todas = (d['solicitudes'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _porEstado = (d['porEstado'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo conectar. Revisa tu internet e intenta de nuevo.';
      });
    }
  }

  /// Pendientes = todo lo que aún no tiene resolución final. Es lo que abre
  /// por omisión porque es lo único que exige trabajo de Vicerrectoría.
  List<Map<String, dynamic>> get _visibles {
    if (_filtro == 'Todas') return _todas;
    if (_filtro == 'Pendientes') {
      return _todas.where((s) {
        final e = (s['estado'] ?? '').toString();
        return e != 'Autorizada' && e != 'No procede';
      }).toList();
    }
    return _todas.where((s) => (s['estado'] ?? '') == _filtro).toList();
  }

  int get _nPendientes => _todas.where((s) {
        final e = (s['estado'] ?? '').toString();
        return e != 'Autorizada' && e != 'No procede';
      }).length;

  void _aviso(String msg, {bool malo = false}) {
    if (!mounted || msg.trim().isEmpty) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: malo ? cessumRed : const Color(0xFF1E7B34),
      content: Text(msg),
    ));
  }

  Future<void> _abrir(Map<String, dynamic> s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalleReingreso(solicitud: s, actor: widget.actor),
      ),
    );
    if (mounted) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Reingresos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: _lista(),
                ),
    );
  }

  Widget _vistaError() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 50),
          Icon(Icons.cloud_off, size: 46, color: cessumFaint(context)),
          const SizedBox(height: 12),
          Text(_error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cessumMuted(context))),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ),
        ],
      );

  Widget _lista() {
    final v = _visibles;
    final chips = <String>['Pendientes', 'Todas'];
    for (final e in _porEstado) {
      final n = (e['estado'] ?? '').toString();
      if (n.isNotEmpty && !chips.contains(n)) chips.add(n);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_nPendientes > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.pending_actions,
                  size: 19, color: Color(0xFFB07D12)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  _nPendientes == 1
                      ? 'Hay 1 solicitud esperando resolución.'
                      : 'Hay $_nPendientes solicitudes esperando resolución.',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, height: 1.35),
                ),
              ),
            ]),
          ),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips.map((c) {
            final act = _filtro == c;
            final n = c == 'Todas'
                ? _todas.length
                : (c == 'Pendientes'
                    ? _nPendientes
                    : _todas.where((s) => (s['estado'] ?? '') == c).length);
            return ChoiceChip(
              label: Text('$c ($n)', style: const TextStyle(fontSize: 12.5)),
              selected: act,
              onSelected: (_) => setState(() => _filtro = c),
              selectedColor: cessumRed.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                  color: act ? cessumRed : cessumInk(context),
                  fontWeight: act ? FontWeight.w700 : FontWeight.w500),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        if (v.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: Column(children: [
              const Icon(Icons.inbox, size: 34, color: Colors.black26),
              const SizedBox(height: 8),
              Text(
                _filtro == 'Pendientes'
                    ? 'No hay solicitudes esperando resolución.'
                    : 'No hay solicitudes en «$_filtro».',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cessumMuted(context)),
              ),
            ]),
          )
        else
          ...v.map(_tarjeta),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _chipEstado(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: 0.45))),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _tarjeta(Map<String, dynamic> s) {
    final estado = (s['estado'] ?? 'Iniciada').toString();
    final completo = s['completo'] == true;

    Color color;
    IconData ic;
    if (estado == 'Autorizada') {
      color = const Color(0xFF1E7B34);
      ic = Icons.verified;
    } else if (estado == 'No procede') {
      color = cessumRed;
      ic = Icons.cancel;
    } else {
      color = cessumGold;
      ic = Icons.hourglass_top;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrir(s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ic, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((s['nombre'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${s['matricula'] ?? ''} · ${s['programa'] ?? ''}'
                    '${(s['generacion'] ?? '').toString().isNotEmpty ? ' · ${s['generacion']}' : ''}',
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.black45),
                  ),
                  // (4-oct-2026) A qué grupo vuelve, si ya firmó y en qué va su convenio de pago: el reingreso y el pago, en una sola vista.
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      if ('${s['modo'] ?? ''}' == 'mismo') _chipEstado('Mismo grupo', const Color(0xFF1565C0)),
                      if ('${s['modo'] ?? ''}' == 'otra') _chipEstado('Otra generación', const Color(0xFF6A1B9A)),
                      if (s['firmado'] == true) _chipEstado('Convenio firmado', const Color(0xFF1E7B34)),
                      if (s['firmado'] == true && s['convenioPago'] == null) _chipEstado('Sin convenio de pago', cessumRed),
                      if (s['convenioPago'] is Map) _chipEstado('Pago: ${(s['convenioPago'] as Map)['estado'] ?? ''}', cessumGold),
                    ]),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Folio ${s['folio'] ?? ''} · solicitó el ${s['solicitada'] ?? ''}',
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.black45),
                  ),
                  const SizedBox(height: 6),
                  // Sin los tres documentos el backend NO deja autorizar, así
                  // que conviene verlo desde la lista y no al final.
                  Row(children: [
                    _doc('Kárdex', (s['kardex'] ?? '').toString().isNotEmpty),
                    const SizedBox(width: 6),
                    _doc('Financiero',
                        (s['financiero'] ?? '').toString().isNotEmpty),
                    const SizedBox(width: 6),
                    _doc('Solicitud',
                        (s['solicitud'] ?? '').toString().isNotEmpty),
                  ]),
                  if (!completo &&
                      estado != 'Autorizada' &&
                      estado != 'No procede')
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Expediente incompleto: no se puede autorizar todavía.',
                        style: TextStyle(fontSize: 11.5, color: cessumRed),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(estado,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 6),
              const Icon(Icons.chevron_right, size: 20, color: Colors.black26),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _doc(String etq, bool hay) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (hay ? const Color(0xFF1E7B34) : cessumFaint(context))
              .withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(hay ? Icons.check : Icons.remove,
              size: 12,
              color: hay ? const Color(0xFF1E7B34) : cessumFaint(context)),
          const SizedBox(width: 3),
          Text(etq,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: hay ? const Color(0xFF1E7B34) : cessumFaint(context))),
        ]),
      );
}

/* =====================================================================
 *  DETALLE Y RESOLUCIÓN DE UNA SOLICITUD DE REINGRESO
 * ===================================================================== */
class _DetalleReingreso extends StatefulWidget {
  final Map<String, dynamic> solicitud;
  final String actor;
  const _DetalleReingreso({required this.solicitud, required this.actor});

  @override
  State<_DetalleReingreso> createState() => _DetalleReingresoState();
}

class _DetalleReingresoState extends State<_DetalleReingreso> {
  late Map<String, dynamic> _s;
  bool _ocupado = false;
  Map<String, dynamic>? _prop;
  // (26-sep) Sugerencia de generación destino con IA.
  Map<String, dynamic>? _sugIa;
  bool _sugCargando = false;
  /// (ago-29) Materias que Vicerrectoría marca como "debe recursar o cubrir".
  /// La regla es que una materia solo cuenta si está CUBIERTA, y eso se
  /// decide leyendo el kárdex junto con el informe financiero: el sistema no
  /// sabe qué se pagó, así que propone y la persona valida.
  final Set<String> _aRecursar = {};

  final _resolucionCtrl = TextEditingController();
  final _convenioCtrl = TextEditingController();
  /// (ago-29) Quien reingresa NO vuelve a su generación: se integra a una en
  /// curso, y Vicerrectoría elige a cuál al dictaminar. Sin esto, la
  /// autorización no dice dónde va a estudiar.
  final _grupoCtrl = TextEditingController();
  final _genDestinoCtrl = TextEditingController();
  // (6-oct-2026) Corrección manual de la mensualidad: un mismo programa puede tener varias mensualidades según la
  // modalidad (escolarizada, no escolarizada, mixta), y la solicitud de reingreso no guarda en cuál está el alumno,
  // así que el cálculo automático a veces acierta la del programa pero no la de su modalidad real. Se deja en blanco
  // hasta que Vicerrectoría la escriba; mientras esté vacío, manda el cálculo automático, igual que siempre.
  final _mensualidadCtrl = TextEditingController();
  /// (4-oct-2026) 'mismo' = vuelve a su grupo de origen (su generación sigue en curso); 'otra' = se integra a otra generación.
  String _modo = 'mismo';

  @override
  void initState() {
    super.initState();
    _s = Map<String, dynamic>.from(widget.solicitud);
    _resolucionCtrl.text = (_s['resolucion'] ?? '').toString();
    _convenioCtrl.text = (_s['convenio'] ?? '').toString();
    _grupoCtrl.text = (_s['grupoDestino'] ?? '').toString();
    _genDestinoCtrl.text = (_s['generacionDestino'] ?? '').toString();
    final m = '${_s['modo'] ?? ''}';
    final genD = _genDestinoCtrl.text.trim(), genO = '${_s['generacion'] ?? ''}';
    _modo = (m == 'mismo' || m == 'otra') ? m : ((genD.isNotEmpty && genD != genO) ? 'otra' : 'mismo');
    if (_modo == 'mismo') _ponerMismoGrupo();
  }

  void _ponerMismoGrupo() {
    _genDestinoCtrl.text = '${_s['generacion'] ?? ''}';
    if (_grupoCtrl.text.trim().isEmpty) _grupoCtrl.text = '${_s['grupoOrigen'] ?? ''}';
  }

  @override
  void dispose() {
    _resolucionCtrl.dispose();
    _convenioCtrl.dispose();
    _grupoCtrl.dispose();
    _genDestinoCtrl.dispose();
    _mensualidadCtrl.dispose();
    super.dispose();
  }

  String get _folio => (_s['folio'] ?? '').toString();
  String get _estado => (_s['estado'] ?? 'Iniciada').toString();
  bool get _completo => _s['completo'] == true;
  bool get _resuelta => _estado == 'Autorizada' || _estado == 'No procede';

  void _aviso(String m, {bool malo = false}) {
    if (!mounted || m.trim().isEmpty) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: malo ? cessumRed : const Color(0xFF1E7B34),
      content: Text(m),
    ));
  }

  /// (26-sep) Pide a la IA la generación y grupo destino según el kárdex
  /// de quien reingresa, el plan del programa y las generaciones activas.
  Future<void> _sugerirGeneracion() async {
    setState(() => _sugCargando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'reingreso_ia_generacion', 'folio': _folio, 'actor': widget.actor});
      final r = await http.get(uri).timeout(const Duration(seconds: 150));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) {
        _aviso((d['error'] ?? 'No se pudo sugerir').toString(), malo: true);
      } else {
        setState(() => _sugIa = d);
      }
    } catch (_) {
      _aviso('No se pudo consultar la sugerencia.', malo: true);
    }
    if (mounted) setState(() => _sugCargando = false);
  }

  Widget _bloqueSugerenciaIa() {
    final d = _sugIa;
    final sug = d?['sugerencia'] is Map ? Map<String, dynamic>.from(d!['sugerencia'] as Map) : null;
    final gens = ((d?['generaciones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    List<String> lista(dynamic v) => ((v as List?) ?? []).map((e) => '$e').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: cessumRed),
        onPressed: _sugCargando ? null : _sugerirGeneracion,
        icon: _sugCargando
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome, size: 18),
        label: Text(_sugCargando ? 'Analizando su progreso…' : (sug == null ? 'Sugerir generación con IA' : 'Volver a sugerir')),
      ),
      const SizedBox(height: 4),
      Text('Compara su kárdex con el punto en que va cada generación activa del programa y con las materias que vienen.',
          style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
      if (d != null && sug == null && '${d['texto'] ?? ''}'.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('${d['texto']}', style: const TextStyle(fontSize: 12.5, height: 1.4))),
      if (sug != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: cessumGold.withValues(alpha: 0.5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.recommend_outlined, color: cessumGold, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Sugerencia: generación ${sug['generacion']} · grupo ${sug['grupo']}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 6),
            for (final r in lista(sug['porque'])) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('• $r', style: const TextStyle(fontSize: 12.5, height: 1.4))),
            if (lista(sug['materiasARecursarAparte']).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Tendría que recursar aparte: ${lista(sug['materiasARecursarAparte']).join(' · ')}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed)),
            ],
            if (sug['alternativa'] is Map && '${(sug['alternativa'] as Map)['generacion'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Alternativa: ${(sug['alternativa'] as Map)['generacion']} · ${(sug['alternativa'] as Map)['grupo']} — ${(sug['alternativa'] as Map)['porque']}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ],
            if (lista(sug['riesgos']).isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final r in lista(sug['riesgos'])) Text('⚠ $r', style: const TextStyle(fontSize: 12, color: cessumGold, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _genDestinoCtrl.text = '${sug['generacion'] ?? ''}';
                    _grupoCtrl.text = '${sug['grupo'] ?? ''}';
                  });
                  _aviso('Generación y grupo aplicados. Revísalos y genera la propuesta.');
                },
                child: const Text('Usar esta generación'),
              ),
              if (sug['alternativa'] is Map && '${(sug['alternativa'] as Map)['generacion'] ?? ''}'.isNotEmpty)
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _genDestinoCtrl.text = '${(sug['alternativa'] as Map)['generacion'] ?? ''}';
                      _grupoCtrl.text = '${(sug['alternativa'] as Map)['grupo'] ?? ''}';
                    });
                  },
                  child: const Text('Usar la alternativa'),
                ),
            ]),
            if ('${sug['mensajeAlumno'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Para el alumno: ${sug['mensajeAlumno']}', style: TextStyle(fontSize: 12, height: 1.4, fontStyle: FontStyle.italic, color: cessumMuted(context))),
            ],
          ]),
        ),
        if (gens.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Generaciones activas comparadas (${gens.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            children: [
              for (final g in gens)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${g['generacion']} · ${g['grupo']} · ${g['modalidad']} · ${g['alumnos']} alumnos · periodo ${g['periodoActual']}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    'Ya cursó ${g['materiasQueYaCursoLaGeneracion']} materias; de esas el alumno tiene ${g['deEsasLaAlumnaYaAprobo']} y le faltarían ${lista(g['deEsasLeFaltarian']).length}. '
                    'Vienen: ${lista(g['proximasMaterias']).isEmpty ? 'sin asignaciones registradas' : lista(g['proximasMaterias']).join(' · ')}',
                    style: TextStyle(fontSize: 11.5, height: 1.35, color: cessumMuted(context)),
                  ),
                ),
            ],
          ),
        ],
      ],
    ]);
  }

  /// Trae la propuesta: materias a recursar del último ciclo, costo a la
  /// mitad de la mensualidad, y el texto del convenio ya redactado.
  Future<void> _generarPropuesta() async {
    setState(() => _ocupado = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'reingreso_propuesta',
        'folio': _folio,
        'actor': widget.actor,
        // Se manda el grupo para que el convenio salga YA con la cláusula
        // séptima. Sin grupo, el backend no deja autorizar.
        'grupoDestino': _grupoCtrl.text.trim(),
        'generacionDestino': _genDestinoCtrl.text.trim(),
        'modo': _modo,
        // Si ya se validó qué materias cuentan, mandan esas.
        'materias': _aRecursar.join(' · '),
        // Si Vicerrectoría corrigió la mensualidad a mano, manda sobre el cálculo automático del backend.
        if (_mensualidadCtrl.text.trim().isNotEmpty)
          'mensualidad': _mensualidadCtrl.text.trim(),
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _ocupado = false);
      if (d['ok'] != true) {
        _aviso((d['error'] ?? 'No se pudo generar').toString(), malo: true);
        return;
      }
      setState(() {
        _prop = d;
        if (_aRecursar.isEmpty) {
          for (final m in (d['materiasRecursar'] as List<dynamic>? ?? [])) {
            _aRecursar.add('${(m as Map)['materia']}');
          }
        }
        // Solo se rellena si estaba vacío: si Vicerrectoría ya redactó su
        // propio texto, sobrescribirlo sería borrarle el trabajo.
        if (_resolucionCtrl.text.trim().isEmpty) {
          _resolucionCtrl.text = (d['resolucion'] ?? '').toString();
        }
        if (_convenioCtrl.text.trim().isEmpty) {
          _convenioCtrl.text = (d['convenio'] ?? '').toString();
        }
      });
      final av = (d['aviso'] ?? '').toString();
      if (av.isNotEmpty) _aviso(av, malo: true);
      // (ago-29) Si el sistema no pudo ordenar los ciclos, lo dice: cobrar
      // el recursamiento de las materias equivocadas es peor que tardarse
      // en verificarlo a mano.
      final avc = (d['avisoCiclo'] ?? '').toString();
      if (avc.isNotEmpty) _aviso(avc, malo: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      _aviso('$e', malo: true);
    }
  }

  Future<void> _dictaminar(String estado) async {
    // Al alumno le llega correo con la resolución. Se avisa antes, con el
    // nombre a la vista: un dictamen mandado por error no se deshace.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(estado == 'Autorizada'
            ? 'Autorizar el reingreso'
            : 'Declarar que no procede'),
        content: Text(
          estado == 'Autorizada'
              ? 'Se registrará la resolución y se le enviará un correo a '
                  '${_s['nombre']} (${_s['correo']}) con el texto y el '
                  'convenio que escribiste.\n\nEse correo no se puede deshacer.'
              : 'Se registrará la negativa y se le enviará un correo a '
                  '${_s['nombre']} (${_s['correo']}) con el motivo que '
                  'escribiste.\n\nEse correo no se puede deshacer.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    estado == 'Autorizada' ? const Color(0xFF1E7B34) : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(estado == 'Autorizada' ? 'Autorizar' : 'No procede'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _ocupado = true);
    try {
      final resp = await http.post(
        Uri.parse(guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'accion': 'reingreso_dictaminar',
          'folio': _folio,
          'estado': estado,
          'resolucion': _resolucionCtrl.text.trim(),
          'convenio': _convenioCtrl.text.trim(),
          'materias': _aRecursar.join(' · '),
          'costo': _prop?['costoTotal'] ?? '',
          'grupoDestino': _grupoCtrl.text.trim(),
          'generacionDestino': _genDestinoCtrl.text.trim(),
          'actor': widget.actor,
        }),
      );
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _ocupado = false);
      if (d['ok'] != true) {
        _aviso((d['error'] ?? 'No se pudo registrar').toString(), malo: true);
        return;
      }
      _aviso((d['nota'] ?? 'Resolución registrada.').toString());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      _aviso('$e', malo: true);
    }
  }

  Future<void> _cambiarEstado(String estado) async {
    setState(() => _ocupado = true);
    try {
      final resp = await http.post(
        Uri.parse(guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'accion': 'reingreso_dictaminar',
          'folio': _folio,
          'estado': estado,
          'resolucion': _resolucionCtrl.text.trim(),
          'actor': widget.actor,
        }),
      );
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        if (d['ok'] == true) _s['estado'] = estado;
      });
      _aviso(
          (d['nota'] ?? d['error'] ?? '').toString(), malo: d['ok'] != true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      _aviso('$e', malo: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Solicitud de reingreso'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bloqueAlumno(),
          const SizedBox(height: 15),
          _bloqueExpediente(),
          const SizedBox(height: 15),
          _bloqueGrupoDestino(),
          const SizedBox(height: 15),
          _bloquePropuesta(),
          const SizedBox(height: 15),
          _bloqueResolucion(),
          const SizedBox(height: 34),
        ],
      ),
    );
  }

  Widget _tarjeta(IconData ic, String titulo, List<Widget> hijos) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
        ),
        padding: const EdgeInsets.all(15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(ic, size: 18, color: cessumRed),
            const SizedBox(width: 8),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cessumRed)),
          ]),
          const SizedBox(height: 12),
          ...hijos,
        ]),
      );

  Widget _dato(String e, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 122,
              child: Text(e,
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black45))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _bloqueAlumno() => _tarjeta(Icons.person, 'La alumna o alumno', [
        Text((_s['nombre'] ?? '').toString(),
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, height: 1.25)),
        const SizedBox(height: 8),
        _dato('Matrícula', (_s['matricula'] ?? '').toString()),
        _dato('Programa', (_s['programa'] ?? '').toString()),
        _dato('Generación', (_s['generacion'] ?? '').toString()),
        _dato('Correo', (_s['correo'] ?? '').toString()),
        if ((_s['telefono'] ?? '').toString().isNotEmpty)
          _dato('Teléfono', (_s['telefono'] ?? '').toString()),
        _dato('Folio', _folio),
        _dato('Solicitó el', (_s['solicitada'] ?? '').toString()),
        if ((_s['motivoBaja'] ?? '').toString().isNotEmpty)
          _dato('Motivo de baja', (_s['motivoBaja'] ?? '').toString()),
        if ((_s['fechaBaja'] ?? '').toString().isNotEmpty)
          _dato('Fecha de baja', (_s['fechaBaja'] ?? '').toString()),
        if (_s['mesesFuera'] != null)
          _dato('Meses fuera', '${_s['mesesFuera']}'),
      ]);

  Widget _bloqueExpediente() {
    Widget fila(String etq, String url, String ayuda) {
      final hay = url.trim().isNotEmpty;
      return Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          Icon(hay ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: hay ? const Color(0xFF1E7B34) : cessumFaint(context)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(etq,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(hay ? 'Entregado' : ayuda,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: hay ? cessumFaint(context) : cessumRed)),
            ]),
          ),
          if (hay)
            TextButton.icon(
              onPressed: () => html.window.open(url, '_blank'),
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('Ver', style: TextStyle(fontSize: 12.5)),
            ),
        ]),
      );
    }

    return _tarjeta(Icons.folder_open, 'Expediente', [
      fila('Kárdex', (_s['kardex'] ?? '').toString(),
          'Falta. Sin él no se sabe qué acreditó.'),
      fila('Informe financiero', (_s['financiero'] ?? '').toString(),
          'Falta. Sin él no se sabe si hay adeudo previo.'),
      fila('Solicitud firmada', (_s['solicitud'] ?? '').toString(),
          'Falta. Es lo que sostiene el convenio.'),
      if (!_completo)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Text(
            'El expediente está incompleto. El sistema no permite autorizar '
            'sin los tres documentos, y es a propósito: son lo que sostiene '
            'el convenio si después alguien lo cuestiona.',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
    ]);
  }

  Widget _bloqueGrupoDestino() {
    return _tarjeta(Icons.group_add, 'Grupo al que regresa', [
      // (4-oct-2026) Dos caminos: vuelve a su grupo (si su generación sigue en curso) o se integra a otra. El convenio lleva la
      // cláusula que corresponda y el Guardián acepta cualquiera de las dos al autorizar.
      Wrap(spacing: 8, runSpacing: 6, children: [
        ChoiceChip(
          label: const Text('Reincorporación a su mismo grupo'),
          selected: _modo == 'mismo',
          selectedColor: const Color(0xFF1565C0).withValues(alpha: 0.18),
          onSelected: _resuelta ? null : (_) => setState(() { _modo = 'mismo'; _ponerMismoGrupo(); }),
        ),
        ChoiceChip(
          label: const Text('Integración a otra generación'),
          selected: _modo == 'otra',
          selectedColor: const Color(0xFF6A1B9A).withValues(alpha: 0.18),
          onSelected: _resuelta ? null : (_) => setState(() => _modo = 'otra'),
        ),
      ]),
      const SizedBox(height: 10),
      Text(
        _modo == 'mismo'
            ? 'Vuelve a su grupo de origen${'${_s['grupoOrigen'] ?? ''}'.isNotEmpty ? ' (${_s['grupoOrigen']})' : ''}, generación '
              '${_s['generacion'] ?? '—'}, y sigue con su calendario. El convenio llevará la cláusula de REINCORPORACIÓN A SU GRUPO DE ORIGEN.'
            : 'Entra a una generación que ya va en curso. El convenio llevará la cláusula donde acepta esa condición y que sus materias '
              'quedan sujetas al calendario de esa generación.',
        style: const TextStyle(fontSize: 13, height: 1.5),
      ),
      const SizedBox(height: 12),
      if (_modo == 'otra') ...[_bloqueSugerenciaIa(), const SizedBox(height: 12)],
      TextField(
        controller: _grupoCtrl,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          labelText: _modo == 'mismo' ? 'Su grupo *' : 'Grupo destino *',
          hintText: 'ej. 1 - entre semana',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _genDestinoCtrl,
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          labelText: 'Generación destino',
          hintText: 'ej. 26-2',
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Su generación de origen es ${(_s['generacion'] ?? '—')}. '
        'Si escribes la misma, revisa que sea correcto.',
        style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
      ),
    ]);
  }

  Widget _bloquePropuesta() {
    final p = _prop;
    return _tarjeta(Icons.calculate, 'Propuesta de convenio', [
      if (p == null) ...[
        const Text(
          'Genera la propuesta para ver qué materias tendría que recursar, '
          'con el costo al 50 % de la mensualidad, y el texto del convenio ya '
          'redactado. Se calcula del kárdex, no se escribe a mano.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 11),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumGold,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44)),
            onPressed: _ocupado ? null : _generarPropuesta,
            icon: _ocupado
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(_ocupado ? 'Calculando…' : 'Generar propuesta'),
          ),
        ),
      ] else ...[
        if ((p['avisoCiclo'] ?? '').toString().isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('${p['avisoCiclo']}',
                style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ),
        _dato('Ciclo evaluado', (p['cicloEvaluado'] ?? '—').toString()),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(
                width: 122,
                child: Text('Mensualidad',
                    style: TextStyle(fontSize: 12.5, color: Colors.black45))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: _mensualidadCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '\$${p['mensualidad'] ?? 0} (calculada)',
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  (p['mensualidadOrigen'] ?? '').toString() == 'escrita a mano'
                      ? 'Usando la que escribiste. Revisa contra el informe financiero del alumno antes de autorizar.'
                      : 'Calculada sola (${p['mensualidadOrigen'] ?? 'sin precisar'}). Verifica contra el informe '
                          'financiero: el programa puede tener otra mensualidad según la modalidad del alumno; si '
                          'no coincide, escríbela arriba y presiona "Regenerar".',
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: (p['mensualidadOrigen'] ?? '').toString() == 'escrita a mano'
                          ? cessumFaint(context)
                          : cessumGold),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 5),
        _dato('Costo por materia', '\$${p['costoUnitario'] ?? 0}'),
        _dato('Total a pagar', '\$${p['costoTotal'] ?? 0}'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            '${p['reglaCobertura'] ?? ''}',
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Kárdex: marca las que debe RECURSAR',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          'Vienen marcadas las que el sistema detectó sin acreditar. Revisa '
          'contra el informe financiero y marca también las que no estén '
          'cubiertas, aunque su calificación sea aprobatoria: esas también se '
          'recursan completas.',
          style: TextStyle(fontSize: 11.5, color: cessumFaint(context), height: 1.4),
        ),
        const SizedBox(height: 6),
        if ((p['kardex'] as List<dynamic>? ?? []).isEmpty)
          Text('No se encontraron materias en su kárdex.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))
        else
          ...(() {
            final lista = List<Map<String, dynamic>>.from(
                (p['kardex'] as List<dynamic>)
                    .map((e) => Map<String, dynamic>.from(e as Map)));
            lista.sort((a, b) =>
                ((a['orden'] ?? 99) as num).compareTo((b['orden'] ?? 99) as num));
            String? cicloPrev;
            final w = <Widget>[];
            for (final m in lista) {
              final ciclo = '${m['ciclo'] ?? ''}';
              if (ciclo != cicloPrev) {
                cicloPrev = ciclo;
                w.add(Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 2),
                  child: Text(ciclo,
                      style: const TextStyle(
                          fontSize: 11,
                          letterSpacing: .5,
                          fontWeight: FontWeight.w800,
                          color: cessumGold)),
                ));
              }
              final nom = '${m['materia']}';
              final acred = m['acreditada'] == true;
              w.add(CheckboxListTile(
                value: _aRecursar.contains(nom),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _aRecursar.add(nom);
                  } else {
                    _aRecursar.remove(nom);
                  }
                }),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(nom,
                    style: const TextStyle(fontSize: 13, height: 1.3)),
                subtitle: Text(
                  '${m['calificacion'].toString().isEmpty ? 'sin calificar' : m['calificacion']}'
                  '${acred ? ' · acreditada' : ' · no acreditada'}',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: acred ? cessumFaint(context) : cessumRed),
                ),
              ));
            }
            return w;
          })(),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            'Seleccionadas: ${_aRecursar.length} · '
            'Total a pagar: \$${(_aRecursar.length * ((p['costoUnitario'] as num?)?.toInt() ?? 0))}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Al regenerar, el convenio se redacta con estas materias y este '
          'total. Hazlo antes de autorizar.',
          style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: _ocupado ? null : _generarPropuesta,
          icon: const Icon(Icons.refresh, size: 15),
          label: const Text('Regenerar convenio con esta selección',
              style: TextStyle(fontSize: 12.5)),
        ),
      ],
    ]);
  }

  Widget _bloqueResolucion() {
    return _tarjeta(Icons.gavel, 'Resolución', [
      if (_resuelta)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (_estado == 'Autorizada'
                    ? const Color(0xFF1E7B34)
                    : cessumRed)
                .withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            'Esta solicitud ya está como «$_estado»'
            '${_s['avisado'] == true ? ' y al alumno ya se le avisó por correo' : ''}. '
            'Volver a dictaminar manda otro correo.',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
      const Text('Texto de la resolución',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      TextField(
        controller: _resolucionCtrl,
        minLines: 4,
        maxLines: 12,
        style: const TextStyle(fontSize: 13, height: 1.5),
        decoration: InputDecoration(
          hintText: 'Se envía tal cual al alumno.',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
      ),
      const SizedBox(height: 14),
      const Text('Convenio',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      TextField(
        controller: _convenioCtrl,
        minLines: 5,
        maxLines: 20,
        style: const TextStyle(fontSize: 12.5, height: 1.55),
        decoration: InputDecoration(
          hintText: 'Genera la propuesta arriba para rellenarlo.',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
      ),
      const SizedBox(height: 14),

      // Estados intermedios: mover sin resolver ni avisar a nadie.
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in const ['Documentos completos', 'En dictamen'])
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                foregroundColor: cessumMuted(context),
                side: BorderSide(color: cessumFaint(context))),
            onPressed: _ocupado ? null : () => _cambiarEstado(e),
            child: Text(e, style: const TextStyle(fontSize: 12.5)),
          ),
      ]),
      const SizedBox(height: 6),
      Text(
        'Esos dos solo mueven el estado interno: no le llega nada al alumno.',
        style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
      ),
      const SizedBox(height: 16),

      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed),
                minimumSize: const Size(0, 46)),
            onPressed: _ocupado ? null : () => _dictaminar('No procede'),
            icon: const Icon(Icons.block, size: 17),
            label: const Text('No procede'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E7B34),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 46)),
            onPressed: (_ocupado || !_completo || _grupoCtrl.text.trim().isEmpty)
                ? null
                : () => _dictaminar('Autorizada'),
            icon: const Icon(Icons.check_circle, size: 17),
            label: const Text('Autorizar'),
          ),
        ),
      ]),
      if (!_completo || _grupoCtrl.text.trim().isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            !_completo
                ? 'Autorizar está deshabilitado hasta que el expediente esté '
                    'completo. «No procede» sí se puede en cualquier momento.'
                : 'Falta elegir el grupo destino. Una autorización sin grupo '
                    'deja al alumno reingresado a ninguna parte.',
            style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
          ),
        ),
    ]);
  }
}

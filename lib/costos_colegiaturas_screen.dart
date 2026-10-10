import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin · **Costos y colegiaturas**.
///
/// Pestaña 1 — Costos por programa y modalidad (hoja PlanPagos): aquí se
/// corrige, por ejemplo, que Mixta tenga su propio costo. Si a un programa le
/// falta el renglón de una modalidad, el sistema cobraba con el de otra; la
/// pantalla marca esos huecos.
///
/// Pestaña 2 — Ajuste por alumno: fija manualmente la colegiatura de un alumno
/// (o de toda una generación/programa) y anota el motivo: beca o descuento.
class CostosColegiaturasScreen extends StatefulWidget {
  const CostosColegiaturasScreen({super.key});

  @override
  State<CostosColegiaturasScreen> createState() =>
      _CostosColegiaturasScreenState();
}

class _CostosColegiaturasScreenState extends State<CostosColegiaturasScreen> {
  // ---- Costos (PlanPagos) ----
  bool _cargandoPlanes = true;
  String? _errorPlanes;
  List<Map<String, dynamic>> _planes = [];

  // ---- Ajustes (overrides) ----
  bool _cargandoOv = true;
  List<Map<String, dynamic>> _overrides = [];

  static const List<String> _modalidades = [
    'No escolarizada',
    'Mixta',
    'Escolarizada',
  ];

  // Programas que SÍ se ofertan en modalidad Mixta (convocatoria 26-2/26-3).
  // Maestría en Educación y Educación Inclusiva no tienen Mixta, así que no
  // se marcan como hueco.
  static const List<String> _conMixta = [
    'pedagog',
    'psicopedagog',
    'doctorado',
  ];

  @override
  void initState() {
    super.initState();
    _cargarPlanes();
    _cargarOverrides();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cessumRed : null,
    ));
  }

  String _money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  // ================= Costos =================
  Future<void> _cargarPlanes() async {
    setState(() {
      _cargandoPlanes = true;
      _errorPlanes = null;
    });
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'plan_pagos_listar',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _planes = ((data['planes'] ?? []) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _cargandoPlanes = false;
        });
      } else {
        setState(() {
          _errorPlanes = (data['error'] ?? 'No se pudo cargar').toString();
          _cargandoPlanes = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorPlanes = 'No me pude conectar.';
        _cargandoPlanes = false;
      });
    }
  }

  List<String> get _programas {
    final set = <String>{};
    for (final p in _planes) {
      final n = (p['programa'] ?? '').toString().trim();
      if (n.isNotEmpty) set.add(n);
    }
    final l = set.toList()..sort();
    return l;
  }

  // Programas a los que les falta el renglón de alguna modalidad.
  List<String> _faltantes(String modalidad) {
    final fam = modalidad.toLowerCase().contains('mixt')
        ? 'mixta'
        : (modalidad.toLowerCase().contains('no escolar')
            ? 'no escolarizada'
            : 'escolarizada');
    final out = <String>[];
    for (final prog in _programas) {
      if (fam == 'mixta') {
        final n = prog.toLowerCase();
        final oferta = _conMixta.any((k) => n.contains(k));
        if (!oferta) continue; // no se oferta en Mixta: no es hueco
      }
      final tiene = _planes.any((p) =>
          (p['programa'] ?? '').toString().trim() == prog &&
          (p['familia'] ?? '').toString() == fam);
      if (!tiene) out.add(prog);
    }
    return out;
  }

  Future<void> _editarPlan({Map<String, dynamic>? base, String? progFijo}) async {
    final esNuevo = base == null;
    String programa =
        (base?['programa'] ?? progFijo ?? (_programas.isNotEmpty ? _programas.first : ''))
            .toString();
    String modalidad = (base?['modalidad'] ?? 'Mixta').toString();
    if (!_modalidades.contains(modalidad)) {
      modalidad = modalidad.toLowerCase().contains('mixt')
          ? 'Mixta'
          : 'No escolarizada';
    }
    final gene = TextEditingController(
        text: base == null ? '' : (base['generacion'] ?? '').toString());
    final mens = TextEditingController(
        text: base == null ? '' : (base['mensualidad'] ?? '').toString());
    final np = TextEditingController(
        text: base == null ? '' : (base['numPagos'] ?? '').toString());
    final ins = TextEditingController(
        text: base == null ? '450' : (base['inscripcion'] ?? '').toString());
    final rei = TextEditingController(
        text: base == null ? '0' : (base['reinscripcion'] ?? '').toString());
    final nrei = TextEditingController(
        text: base == null ? '0' : (base['numReins'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(esNuevo ? 'Nuevo costo' : 'Editar costo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (esNuevo && progFijo == null)
                  DropdownButtonFormField<String>(
                    initialValue: _programas.contains(programa) ? programa : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Programa', isDense: true),
                    items: [
                      for (final p in _programas)
                        DropdownMenuItem(
                            value: p,
                            child: Text(p, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setD(() => programa = v ?? programa),
                  )
                else
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(programa,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: modalidad,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Modalidad', isDense: true),
                  items: [
                    for (final m in _modalidades)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: esNuevo ? (v) => setD(() => modalidad = v ?? modalidad) : null,
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (ctx, setLocal) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: gene,
                        onChanged: (_) => setLocal(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Generación (vacío = todas)',
                          hintText: 'Ej. 26-2 · vacío = precio general',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          for (final g in const [
                            '25-1', '25-2', '25-3', '25-4',
                            '26-1', '26-2', '26-3', '26-4'
                          ])
                            ChoiceChip(
                              label: Text(g, style: const TextStyle(fontSize: 11)),
                              selected: gene.text.trim() == g,
                              selectedColor: cessumRed.withValues(alpha: 0.15),
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) =>
                                  setLocal(() => gene.text = g),
                            ),
                          ChoiceChip(
                            label: const Text('Todas',
                                style: TextStyle(fontSize: 11)),
                            selected: gene.text.trim().isEmpty,
                            selectedColor: cessumGold.withValues(alpha: 0.2),
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setLocal(() => gene.clear()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: mens,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Colegiatura (mensualidad)',
                      prefixText: '\$ ',
                      isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: np,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Número de pagos', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ins,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Inscripción', prefixText: '\$ ', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: rei,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Reinscripción',
                      prefixText: '\$ ',
                      isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nrei,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Número de reinscripciones', isDense: true),
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
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'plan_pagos_guardar',
        'actor': actor,
        'programa': programa,
        'modalidad': modalidad,
        'generacion': gene.text.trim(),
        'mensualidad': mens.text.trim(),
        'numPagos': np.text.trim(),
        'inscripcion': ins.text.trim(),
        'reinscripcion': rei.text.trim(),
        'numReins': nrei.text.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _aviso('Costo guardado.');
        await _cargarPlanes();
      } else {
        _aviso((data['error'] ?? 'No se pudo guardar').toString(), error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    }
  }

  Future<void> _eliminarPlan(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar costo'),
        content: Text(
            '¿Eliminar el costo de "${p['programa']}" en modalidad ${p['modalidad']}'
            '${(p['generacion'] ?? '').toString().isNotEmpty ? ' (Gen. ${p['generacion']})' : ' (todas las generaciones)'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'plan_pagos_eliminar',
        'actor': actor,
        'programa': (p['programa'] ?? '').toString(),
        'modalidad': (p['modalidad'] ?? '').toString(),
        'generacion': (p['generacion'] ?? '').toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _aviso('Costo eliminado.');
        await _cargarPlanes();
      } else {
        _aviso((data['error'] ?? 'No se pudo eliminar').toString(), error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    }
  }

  // ================= Ajustes por alumno =================
  Future<void> _cargarOverrides() async {
    setState(() => _cargandoOv = true);
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pago_override_listar',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _overrides = ((data['overrides'] ?? data['lista'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoOv = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoOv = false);
    }
  }

  Future<void> _guardarOverride(
      String ambito, String clave, String monto, String nota) async {
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pago_override_guardar_get',
        'actor': actor,
        'ambito': ambito,
        'clave': clave,
        'monto': monto,
        'nota': nota,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _aviso('Ajuste guardado.');
        await _cargarOverrides();
      } else {
        _aviso((data['error'] ?? 'No se pudo guardar').toString(), error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    }
  }

  Future<void> _eliminarOverride(Map<String, dynamic> o) async {
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pago_override_eliminar_get',
        'actor': actor,
        'ambito': (o['ambito'] ?? '').toString(),
        'clave': (o['clave'] ?? '').toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _aviso('Ajuste eliminado.');
        await _cargarOverrides();
      } else {
        _aviso((data['error'] ?? 'No se pudo eliminar').toString(), error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Costos y colegiaturas'),
          actions: [
            IconButton(
              tooltip: 'Recargar',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _cargarPlanes();
                _cargarOverrides();
              },
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Costos por modalidad'),
              Tab(text: 'Ajuste por alumno'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_tabCostos(), _tabAjustes()],
        ),
      ),
    );
  }

  // ---------- Tab 1 ----------
  Widget _tabCostos() {
    if (_cargandoPlanes) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_errorPlanes != null) {
      return Center(child: Text(_errorPlanes!));
    }
    final faltanMixta = _faltantes('Mixta');
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        Text(
          'Costo oficial por programa, modalidad y generación. Un renglón con '
          'generación gana sobre el general; deja la generación vacía para el '
          'precio que aplica a todas. Si falta el renglón de una modalidad, sus '
          'alumnos se cobran con el de otra: abajo se marcan esos huecos.',
          style: CessumType.body(13, color: cessumMuted(context)),
        ),
        const SizedBox(height: 12),
        if (faltanMixta.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBEBED),
              border: Border.all(color: cessumRed),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded,
                        color: cessumRed, size: 18),
                    SizedBox(width: 6),
                    Text('Sin costo de Mixta',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: cessumRed)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Estos programas no tienen costo propio para Mixta, así que '
                  'hoy se cobran como No escolarizada:',
                  style: CessumType.body(12.5, color: cessumMuted(context)),
                ),
                const SizedBox(height: 8),
                for (final p in faltanMixta)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(p,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600))),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                              foregroundColor: cessumRed,
                              minimumSize: const Size(0, 32)),
                          onPressed: () => _editarPlan(progFijo: p),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Agregar Mixta',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        for (final prog in _programas) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6, top: 4),
            child: Text(prog,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          for (final p in _planes.where(
              (x) => (x['programa'] ?? '').toString().trim() == prog))
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text((p['modalidad'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (p['generacion'] ?? '')
                                          .toString()
                                          .isNotEmpty
                                      ? cessumGold.withValues(alpha: 0.16)
                                      : Colors.black12,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  (p['generacion'] ?? '').toString().isNotEmpty
                                      ? 'Gen. ${p['generacion']}'
                                      : 'Todas',
                                  style: const TextStyle(fontSize: 10.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_money((p['mensualidad'] ?? 0) as num)} × ${p['numPagos']} pagos'
                            ' · Inscripción ${_money((p['inscripcion'] ?? 0) as num)}'
                            '${((p['numReins'] ?? 0) as num) > 0 ? ' · Reinsc. ${_money((p['reinscripcion'] ?? 0) as num)} × ${p['numReins']}' : ''}',
                            style: TextStyle(
                                fontSize: 11.5, color: cessumMuted(context)),
                          ),
                          const SizedBox(height: 2),
                          Text('Total: ${_money((p['total'] ?? 0) as num)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: cessumGold)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit, size: 18, color: cessumRed),
                      onPressed: () => _editarPlan(base: p),
                    ),
                    IconButton(
                      tooltip: 'Crear variante para otra generación',
                      icon: const Icon(Icons.copy_all,
                          size: 18, color: cessumGold),
                      onPressed: () {
                        // Copia los montos pero deja la generación vacía para
                        // que el admin elija la generación de la variante.
                        final variante =
                            Map<String, dynamic>.from(p);
                        variante['generacion'] = '';
                        variante.remove('fila'); // fuerza fila nueva
                        _editarPlan(base: variante);
                      },
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline,
                          size: 18, color: cessumRed),
                      onPressed: () => _eliminarPlan(p),
                    ),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => _editarPlan(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuevo costo'),
          ),
        ),
      ],
    );
  }

  // ---------- Tab 2 ----------
  Widget _tabAjustes() {
    return _AjusteAlumnoTab(
      overrides: _overrides,
      cargando: _cargandoOv,
      onGuardar: _guardarOverride,
      onEliminar: _eliminarOverride,
      money: _money,
    );
  }
}

/// Pestaña 2: busca al alumno, muestra lo que paga hoy y permite fijar la
/// colegiatura a mano, anotando si es beca o descuento.
class _AjusteAlumnoTab extends StatefulWidget {
  final List<Map<String, dynamic>> overrides;
  final bool cargando;
  final Future<void> Function(String, String, String, String) onGuardar;
  final Future<void> Function(Map<String, dynamic>) onEliminar;
  final String Function(num) money;

  const _AjusteAlumnoTab({
    required this.overrides,
    required this.cargando,
    required this.onGuardar,
    required this.onEliminar,
    required this.money,
  });

  @override
  State<_AjusteAlumnoTab> createState() => _AjusteAlumnoTabState();
}

class _AjusteAlumnoTabState extends State<_AjusteAlumnoTab> {
  final TextEditingController _busca = TextEditingController();
  final TextEditingController _monto = TextEditingController();
  final TextEditingController _nota = TextEditingController();
  String _motivo = 'Beca';
  bool _buscando = false;
  List<Map<String, dynamic>> _resultados = [];
  Map<String, dynamic>? _alumno;
  Map<String, dynamic>? _pago;

  static const List<String> _motivos = ['Beca', 'Descuento', 'Convenio', 'Otro'];

  @override
  void dispose() {
    _busca.dispose();
    _monto.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  Future<void> _buscar() async {
    final q = _busca.text.trim();
    if (q.length < 3) return;
    setState(() {
      _buscando = true;
      _resultados = [];
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'buscar_alumno',
        'q': q,
        'actor': await _actor(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _resultados = ((data['alumnos'] ?? data['resultados'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _buscando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _buscando = false);
    }
  }

  Future<void> _elegir(Map<String, dynamic> a) async {
    setState(() {
      _alumno = a;
      _resultados = [];
      _pago = null;
      _busca.text = (a['nombre'] ?? '').toString();
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mi_pago_mensual',
        'matricula': (a['matricula'] ?? '').toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) setState(() => _pago = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final a = _alumno;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        TextField(
          controller: _busca,
          decoration: InputDecoration(
            labelText: 'Buscar alumno (nombre o matrícula)',
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.search, color: cessumRed),
              onPressed: _buscar,
            ),
          ),
          onSubmitted: (_) => _buscar(),
        ),
        if (_buscando)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(color: cessumRed)),
          ),
        for (final r in _resultados)
          ListTile(
            dense: true,
            title: Text((r['nombre'] ?? '').toString(),
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              '${r['matricula']} · ${r['programa'] ?? ''} · ${r['generacion'] ?? ''}',
              style: const TextStyle(fontSize: 11.5),
            ),
            onTap: () => _elegir(r),
          ),
        if (a != null) ...[
          const SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((a['nombre'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(
                    '${a['matricula']} · ${a['programa'] ?? ''} · Gen. ${a['generacion'] ?? ''}',
                    style: TextStyle(
                        fontSize: 11.5, color: cessumMuted(context)),
                  ),
                  const SizedBox(height: 8),
                  if (_pago == null)
                    const Text('Consultando su colegiatura…',
                        style: TextStyle(fontSize: 12))
                  else ...[
                    Text(
                      'Paga hoy: ${widget.money((_pago!['montoMensual'] ?? 0) as num)} al mes',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cessumGold),
                    ),
                    if ((_pago!['esBeca'] ?? false) == true)
                      Text(
                        'Con beca del ${_pago!['porcentaje']}% · normal ${widget.money((_pago!['montoNormalGrupo'] ?? 0) as num)}',
                        style: TextStyle(
                            fontSize: 11.5, color: cessumMuted(context)),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Fijar colegiatura a mano',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _monto,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nueva colegiatura mensual',
              prefixText: '\$ ',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _motivo,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Motivo', isDense: true, border: OutlineInputBorder()),
            items: [
              for (final m in _motivos)
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: (v) => setState(() => _motivo = v ?? _motivo),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nota,
            decoration: const InputDecoration(
              labelText: 'Nota (detalle del motivo)',
              hintText: 'Ej. Beca 40% autorizada por Vicerrectoría',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                final m = _monto.text.trim();
                if (m.isEmpty) return;
                final nota =
                    '$_motivo${_nota.text.trim().isNotEmpty ? ' · ${_nota.text.trim()}' : ''}';
                widget.onGuardar(
                    'alumno', (a['matricula'] ?? '').toString(), m, nota);
              },
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Guardar ajuste'),
            ),
          ),
        ],
        const SizedBox(height: 18),
        const Text('Ajustes registrados',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (widget.cargando)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator(color: cessumRed)),
          )
        else if (widget.overrides.isEmpty)
          Text('Aún no hay ajustes.',
              style: TextStyle(fontSize: 12, color: cessumMuted(context)))
        else
          for (final o in widget.overrides)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                dense: true,
                title: Text(
                  '${o['clave']} · ${widget.money(num.tryParse((o['monto'] ?? '0').toString()) ?? 0)}',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${o['ambito'] ?? ''}${(o['nota'] ?? '').toString().isNotEmpty ? ' · ${o['nota']}' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: cessumRed),
                  onPressed: () => widget.onEliminar(o),
                ),
              ),
            ),
      ],
    );
  }
}

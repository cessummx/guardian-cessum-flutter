import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'titulacion_admin_screen.dart';

/// Semáforo de riesgo académico (admin): alumnos a distancia con inactividad
/// en Moodle y/o reprobación, calculado cada noche por el Guardián.
class RiesgoScreen extends StatefulWidget {
  const RiesgoScreen({super.key});

  @override
  State<RiesgoScreen> createState() => _RiesgoScreenState();
}

class _RiesgoScreenState extends State<RiesgoScreen> {
  List<Map<String, dynamic>> _alumnos = [];
  String _filtro = 'Rojo';
  bool _cargando = true;
  bool _analizando = false;
  String? _error;
  final TextEditingController _busqueda = TextEditingController();

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _reanalizar() async {
    setState(() => _analizando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=riesgo_actualizar'))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _analizando = false);
      if (data['ok'] == true) {
        final rojos = (data['rojos'] ?? 0).toString();
        final amar = (data['amarillos'] ?? 0).toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Análisis actualizado: $rojos en rojo, $amar en amarillo. '
                'Se notificó por correo si hubo casos en rojo.')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo analizar: ${data['error'] ?? 'error'}')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _analizando = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo conectar con el sistema.')));
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=riesgo_listar'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _alumnos = (data['alumnos'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el semáforo.';
      });
    }
  }

  List<Map<String, dynamic>> get _visibles {
    var base = _filtro == 'Todos'
        ? _alumnos
        : _alumnos.where((a) => (a['nivel'] ?? '') == _filtro).toList();
    final q = _busqueda.text.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((a) {
      return (a['nombre'] ?? '').toString().toLowerCase().contains(q) ||
          (a['matricula'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  /// Copia la lista visible en formato tabular (TSV) para pegar en Excel.
  void _copiarExcel() {
    final filas = _visibles;
    if (filas.isEmpty) return;
    final b = StringBuffer()
      ..writeln('Nivel\tMatrícula\tNombre\tPrograma\tGeneración\t'
          'Modalidad\tDías sin conexión\tÚltima conexión\tReprobadas');
    for (final a in filas) {
      b.writeln([
        a['nivel'] ?? '',
        a['matricula'] ?? '',
        a['nombre'] ?? '',
        a['programa'] ?? '',
        a['generacion'] ?? '',
        a['modalidad'] ?? '',
        a['diasSinConexion'] ?? '',
        a['ultimaConexion'] ?? '',
        a['reprobadas'] ?? 0,
      ].join('\t'));
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Riesgo (${filas.length})');
  }

  Color _color(String nivel) =>
      nivel == 'Rojo' ? const Color(0xFFB11D29) : const Color(0xFFB8842C);

  @override
  Widget build(BuildContext context) {
    final filtros = ['Rojo', 'Amarillo', 'Todos'];
    final actualizado =
        _alumnos.isNotEmpty ? (_alumnos.first['actualizado'] ?? '') : '';
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Riesgo académico',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _visibles.isEmpty ? null : _copiarExcel,
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copiar para Excel'),
          IconButton(
              onPressed: _analizando ? null : _reanalizar,
              icon: _analizando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.autorenew),
              tooltip: 'Re-analizar y alertar'),
          IconButton(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar lista'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: filtros.map((f) {
                final activo = _filtro == f;
                final cuantos = f == 'Todos'
                    ? _alumnos.length
                    : _alumnos
                        .where((a) => (a['nivel'] ?? '') == f)
                        .length;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$f ($cuantos)'),
                    selected: activo,
                    selectedColor: cessumRed.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: activo ? cessumRed : cessumInk(context),
                      fontWeight:
                          activo ? FontWeight.w700 : FontWeight.w400,
                    ),
                    onSelected: (_) => setState(() => _filtro = f),
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _busqueda,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o matrícula',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: _busqueda.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _busqueda.clear()),
                      ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (actualizado.toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Solo modalidades a distancia · actualizado el $actualizado (corre cada noche)',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.black45),
                ),
              ),
            ),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed: _cargar,
                                child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _visibles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Sin alumnos en este nivel. El semáforo se calcula cada noche; si acaba de instalarlo, ejecute revisionDiaria una vez desde el editor del Guardián.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: cessumMuted(context), height: 1.5),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _visibles.length,
                            itemBuilder: (ctx, i) {
                              final a = _visibles[i];
                              final nivel = (a['nivel'] ?? '') as String;
                              final dias =
                                  (a['diasSinConexion'] ?? '').toString();
                              final rep = a['reprobadas'] ?? 0;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 9,
                                    backgroundColor: _color(nivel),
                                  ),
                                  title: Text(
                                    '${a['nombre']} (${a['matricula']})',
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    '${a['programa']} · ${a['generacion']} · ${a['modalidad']}\n'
                                    '${dias == 'Nunca' ? 'Nunca se ha conectado a Moodle' : '$dias días sin conectarse'}'
                                    '${(a['ultimaConexion'] ?? '').toString().isNotEmpty ? ' (última: ${a['ultimaConexion']})' : ''}'
                                    '${rep > 0 ? ' · $rep materia(s) reprobada(s)' : ''}',
                                    style: const TextStyle(
                                        fontSize: 12, height: 1.4),
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right,
                                      color: cessumRed),
                                  onTap: () => _abrirDecision(a),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  // ---- FICHA DE DECISIÓN: información completa + fijar estatus ----
  Future<void> _abrirDecision(Map a) async {
    final mat = (a['matricula'] ?? '').toString();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: cessumRed)),
    );
    Map<String, dynamic>? ficha;
    try {
      final resp = await http
          .get(Uri.parse(
              '$guardianUrl?accion=riesgo_ficha&matricula=${Uri.encodeComponent(mat)}'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) ficha = data;
    } catch (_) {}
    if (!mounted) return;
    Navigator.pop(context); // cierra el cargando
    if (ficha == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.red,
        content: Text('No se pudo cargar la ficha del alumno.'),
      ));
      return;
    }
    final f = ficha;

    String decision = '';
    final notasCtrl = TextEditingController();
    // (ago-2026) Baja FORMAL desde Riesgo: tipo, temporalidad y motivo para
    // tramitarla completa (acta + notificación + salida del padrón/grupos)
    // sin brincar al panel de Bajas.
    var tramitarFormal = true;
    var tipoBaja = 'Automática';
    var temporalidad = 'Definitiva';
    final motivoCtrl = TextEditingController();
    final reprobadas = (f['reprobadas'] as List?) ?? [];
    final clasif = (f['clasificacion'] ?? 'Activo').toString();
    final origen = (f['clasificacionOrigen'] ?? '').toString();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${a['nombre']}',
              style: const TextStyle(fontSize: 15.5)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$mat · ${f['programa']} · ${f['generacion']}\n'
                    '${f['grupo']} · ${f['modalidad']}\n'
                    '${f['correo']}',
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _pillInfo(
                          'Clasificación: $clasif${origen == 'manual' ? ' (manual)' : ''}',
                          cessumRed),
                      _pillInfo(
                          'Avance: ${f['validadas']}/${f['totalPlan']} materias (${f['avancePct']}%)',
                          const Color(0xFF1E8E3E)),
                      _pillInfo(
                          '${a['diasSinConexion']} días sin conexión'
                          '${(a['ultimaConexion'] ?? '').toString().isNotEmpty ? ' · última ${a['ultimaConexion']}' : ''}',
                          cessumGold),
                    ],
                  ),
                  if (reprobadas.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Materias reprobadas:',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ...reprobadas.map((r) {
                      final m = r as Map;
                      return Text(
                          '· ${m['materia']} — ${m['cal']} (${m['fecha']})',
                          style: const TextStyle(fontSize: 11.5, height: 1.4));
                    }),
                  ],
                  const SizedBox(height: 14),
                  const Text('¿Qué decides sobre este alumno?',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['Egresado', 'Titulado', 'Baja', 'Activo']
                        .map((t) => ChoiceChip(
                              label:
                                  Text(t == 'Activo' ? 'Sigue activo' : t),
                              selected: decision == t,
                              selectedColor:
                                  cessumRed.withValues(alpha: 0.16),
                              onSelected: (_) =>
                                  setLocal(() => decision = t),
                            ))
                        .toList(),
                  ),
                  if (decision == 'Baja') ...[
                    const SizedBox(height: 10),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: cessumRed,
                      title: const Text(
                          'Tramitar la baja FORMAL ahora',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      subtitle: const Text(
                          'Acta PDF firmada (Arts. 36-42), notificación al '
                          'alumno con su derecho de alegaciones (Art. 41) y '
                          'salida del padrón y los grupos.',
                          style: TextStyle(fontSize: 11)),
                      value: tramitarFormal,
                      onChanged: (v) => setLocal(() => tramitarFormal = v),
                    ),
                    if (tramitarFormal) ...[
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: tipoBaja,
                            decoration: const InputDecoration(
                                labelText: 'Tipo',
                                border: OutlineInputBorder(),
                                isDense: true),
                            items: const [
                              DropdownMenuItem(
                                  value: 'Voluntaria',
                                  child: Text('Voluntaria')),
                              DropdownMenuItem(
                                  value: 'Automática',
                                  child: Text('Automática')),
                              DropdownMenuItem(
                                  value: 'Disciplinaria',
                                  child: Text('Disciplinaria')),
                            ],
                            onChanged: (v) => setLocal(
                                () => tipoBaja = v ?? 'Automática'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: temporalidad,
                            decoration: const InputDecoration(
                                labelText: 'Temporalidad',
                                border: OutlineInputBorder(),
                                isDense: true),
                            items: const [
                              DropdownMenuItem(
                                  value: 'Definitiva',
                                  child: Text('Definitiva')),
                              DropdownMenuItem(
                                  value: 'Temporal',
                                  child: Text('Temporal (reactivable)')),
                            ],
                            onChanged: (v) => setLocal(
                                () => temporalidad = v ?? 'Definitiva'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      TextField(
                        controller: motivoCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Motivo de la baja (obligatorio)',
                          hintText:
                              'p. ej. Inactividad prolongada y materias reprobadas',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Solo se CLASIFICARÁ como baja; el trámite formal '
                          'quedará pendiente en el panel de Bajas.',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFFB08D57)),
                        ),
                      ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: notasCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notas (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cerrar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: decision.isEmpty
                  ? null
                  : () {
                      if (decision == 'Baja' &&
                          tramitarFormal &&
                          motivoCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                backgroundColor: cessumRed,
                                content: Text(
                                    'El motivo de la baja es obligatorio.')));
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
              child: const Text('Guardar decisión'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || decision.isEmpty) return;
    await _fijarClasificacion(a, decision, notasCtrl.text.trim());
    // (ago-2026) VÍNCULOS de la decisión — un solo lugar dispara los flujos
    // hermanos, para no repetir el trabajo en dos pantallas:
    //  · Baja      → baja FORMAL (acta + correo + salida de bases)
    //  · Egresado  → ofrece marcar EGRESADA a toda la generación (lote)
    //  · Titulado  → acceso directo al panel de Titulación
    //  · Activo    → solo clasifica (no hay flujo hermano)
    if (decision == 'Baja' && tramitarFormal) {
      await _tramitarBajaFormal(
          f, tipoBaja, temporalidad, motivoCtrl.text.trim());
    } else if (decision == 'Egresado') {
      await _ofrecerEgresoGeneracion(f);
    } else if (decision == 'Titulado') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF1E8E3E),
        duration: const Duration(seconds: 6),
        content: const Text('Clasificado como Titulado. Su expediente y '
            'trámite viven en el panel de Titulación.'),
        action: SnackBarAction(
          label: 'ABRIR TITULACIÓN',
          textColor: Colors.white,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const TitulacionAdminScreen()),
          ),
        ),
      ));
    }
  }

  // (ago-2026) Si un alumno egresó, casi siempre egresó SU GENERACIÓN
  // completa: se ofrece el lote (clasificacion_fijar_grupo) para retirarla
  // de golpe de Sin maestro, Próxima materia y las listas de asignación.
  Future<void> _ofrecerEgresoGeneracion(Map<String, dynamic> f) async {
    final prog = (f['programa'] ?? '').toString();
    final gen = (f['generacion'] ?? '').toString();
    if (prog.isEmpty || gen.isEmpty || !mounted) return;
    final todos = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Egresó toda la generación?'),
        content: Text(
            '¿Marcar como EGRESADA a TODA la generación $prog · $gen?\n\n'
            'Con eso desaparece completa de "Sin maestro", "Próxima materia" '
            'y de las listas de asignación (respeta bajas y clasificaciones '
            'manuales previas).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Solo este alumno')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Toda la generación')),
        ],
      ),
    );
    if (todos != true) return;
    try {
      final quien = await SessionStore.realEmail();
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'clasificacion_fijar_grupo',
        'programa': prog,
        'generacion': gen,
        'tipo': 'Egresado',
        'actor': quien ?? 'vicerrectoria@cessum.mx',
      });
      final r = await http.get(u).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: const Color(0xFF1E8E3E),
            content: Text('Generación marcada egresada: '
                '${d['marcados']} alumno(s)'
                '${((d['saltados'] as List?)?.isNotEmpty ?? false) ? ' · ${(d['saltados'] as List).length} respetado(s)' : ''}.')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text('No se pudo el lote: ${d['error']}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text('No se pudo el lote: $e')));
      }
    }
  }

  // (ago-2026) Baja FORMAL desde Riesgo: mismo flujo que Candidatos a baja
  // (baja_validar sin fila: crea y valida, genera acta, notifica al alumno
  // y lo saca del padrón y de los grupos).
  Future<void> _tramitarBajaFormal(Map<String, dynamic> f, String tipoBaja,
      String temporalidad, String motivo) async {
    try {
      final quien = await SessionStore.realEmail();
      final payload = <String, dynamic>{
        'accion': 'baja_validar',
        'estatus': 'Validada',
        'validadaPor': quien ?? 'Vicerrectoría',
        'matricula': (f['matricula'] ?? '').toString(),
        'nombre': (f['nombre'] ?? '').toString(),
        'correo': (f['correo'] ?? '').toString(),
        'programa': (f['programa'] ?? '').toString(),
        'generacion': (f['generacion'] ?? '').toString(),
        'tipoBaja': tipoBaja,
        'motivo': '$temporalidad · $motivo',
        'comentarios': 'Tramitada desde Riesgo académico',
      };
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Color(0xFF1E8E3E),
            content: Text('Baja formal tramitada: acta generada, alumno '
                'notificado y fuera de padrón y grupos.')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text(
                'La clasificación quedó, pero la baja formal falló: '
                '${data['error']}. Puedes terminarla en el panel de Bajas.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text(
                'La clasificación quedó, pero la baja formal falló: $e. '
                'Puedes terminarla en el panel de Bajas.')));
      }
    }
  }

  Widget _pillInfo(String txt, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Future<void> _fijarClasificacion(Map a, String tipo, String notas) async {
    try {
      final actor = await SessionStore.realEmail() ?? 'Administración';
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'clasificacion_fijar',
              'matricula': a['matricula'],
              'tipo': tipo,
              'nombre': a['nombre'],
              'notas': notas.isEmpty
                  ? 'Decidido desde Riesgo académico por $actor'
                  : '$notas — $actor',
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo guardar.');
      }
      if (!mounted) return;
      // Si ya no es alumno activo, sácalo de la lista local: con la nueva
      // regla, el análisis nocturno tampoco lo volverá a incluir.
      if (tipo != 'Activo') {
        setState(() {
          _alumnos.removeWhere(
              (x) => (x['matricula'] ?? '') == (a['matricula'] ?? ''));
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF1E8E3E),
        content: Text(tipo == 'Activo'
            ? 'Se mantiene como activo (clasificación fijada).'
            : 'Clasificado como $tipo. Ya no aparecerá en riesgo.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('No se pudo guardar: $e'),
        ));
      }
    }
  }
}

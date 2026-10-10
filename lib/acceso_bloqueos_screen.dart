// =====================================================================
//  acceso_bloqueos_screen.dart · CESSUM · (26-sep-2026)
//  BLOQUEOS DE ACCESO (administración)
//
//  Interrumpe temporalmente el acceso a la app de un alumno —por falta de
//  pago u otro motivo— con un mensaje que el alumno ve al entrar, y lo
//  reactiva con un interruptor. No es una baja: el alumno sigue inscrito.
//    · Bloqueados: los activos, con interruptor para reactivar.
//    · Candidatos: alumnos con colegiaturas incompletas (mismo cálculo de
//      bajas por pago), con «Analizar con IA»: acción sugerida (bloquear,
//      convenio, recordatorio, esperar), prioridad y mensaje.
//    · Buscar: cualquier alumno, para bloquearlo o reactivarlo.
//  Desde cada alumno se abre el convenio de pago ya con su matrícula.
//
//  Guardián: GET acceso_bloqueos_listar · GET acceso_candidatos
//            POST acceso_bloquear · POST acceso_desbloquear · POST acceso_candidatos_ia
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'convenio_pago_screen.dart';

const _verde = Color(0xFF1E7F52);
const _azul = Color(0xFF2F5D8A);

class AccesoBloqueosScreen extends StatefulWidget {
  const AccesoBloqueosScreen({super.key});
  @override
  State<AccesoBloqueosScreen> createState() => _AccesoBloqueosScreenState();
}

class _AccesoBloqueosScreenState extends State<AccesoBloqueosScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _activos = [];
  List<Map<String, dynamic>> _historial = [];
  List<String> _motivos = const ['Falta de pago', 'Documentación pendiente', 'Disciplinario', 'Solicitud del alumno', 'Otro'];

  bool _cargandoCand = false;
  List<Map<String, dynamic>> _candidatos = [];
  String _generado = '';
  bool _iaCargando = false;
  String _iaLectura = '';
  final Map<String, Map<String, dynamic>> _iaPor = {};
  String _filtroAccion = '';

  final _busca = TextEditingController();
  bool _buscando = false;
  List<Map<String, dynamic>> _resultados = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _busca.dispose();
    super.dispose();
  }

  Future<String> _actor() async => await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';

  Future<Map<String, dynamic>> _get(Map<String, String> qp, {int segundos = 150}) async {
    final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: {...qp, 'actor': await _actor()})).timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int segundos = 150}) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode({...body, 'actor': await _actor()}))
        .timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> _lista(dynamic v) => ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final d = await _get({'accion': 'acceso_bloqueos_listar'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo leer.');
      if (!mounted) return;
      setState(() {
        _activos = _lista(d['activos']);
        _historial = _lista(d['historial']);
        final m = ((d['motivos'] as List?) ?? []).map((e) => '$e').toList();
        if (m.isNotEmpty) _motivos = m;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _cargarCandidatos({bool refrescar = false}) async {
    setState(() => _cargandoCand = true);
    try {
      final d = await _get({'accion': 'acceso_candidatos', if (refrescar) 'refrescar': '1'}, segundos: 240);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo calcular.');
      if (!mounted) return;
      setState(() {
        _candidatos = _lista(d['alumnos']);
        _generado = '${d['generado'] ?? ''}';
      });
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _cargandoCand = false);
  }

  Future<void> _analizarIa() async {
    setState(() => _iaCargando = true);
    try {
      final d = await _post({'accion': 'acceso_candidatos_ia'}, segundos: 200);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo analizar.');
      if (!mounted) return;
      setState(() {
        _iaLectura = '${d['lectura'] ?? ''}';
        _iaPor.clear();
        for (final r in _lista(d['recomendaciones'])) {
          _iaPor['${r['matricula']}'] = r;
        }
        // Las prioridades de la IA ordenan la lista.
        _candidatos.sort((a, b) {
          final pa = ((_iaPor['${a['matricula']}']?['prioridad'] ?? 9) as num).toInt();
          final pb = ((_iaPor['${b['matricula']}']?['prioridad'] ?? 9) as num).toInt();
          return pa != pb ? pa.compareTo(pb) : ((b['faltaPesos'] ?? 0) as num).compareTo((a['faltaPesos'] ?? 0) as num);
        });
      });
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _iaCargando = false);
  }

  Future<void> _buscar() async {
    final q = _busca.text.trim();
    if (q.length < 2) return;
    setState(() => _buscando = true);
    try {
      final d = await _get({'accion': 'buscar_alumno', 'q': q});
      _resultados = _lista(d['alumnos']);
      if (d['ok'] != true) _aviso('${d['error'] ?? 'Sin resultados.'}', error: true);
    } catch (_) {
      _aviso('No se pudo buscar.', error: true);
    }
    if (mounted) setState(() => _buscando = false);
  }

  // ───────────────────────── acciones ─────────────────────────
  Future<void> _bloquear(Map<String, dynamic> a, {String? mensajeSugerido}) async {
    final nombre = '${a['nombre'] ?? ''}';
    final mat = '${a['matricula'] ?? ''}'.replaceAll('.0', '');
    var motivo = _motivos.first;
    final mensaje = TextEditingController(text: mensajeSugerido ?? '');
    final hasta = TextEditingController();
    var notificar = false;
    String porDefecto(String m) {
      final n = nombre.split(' ').first;
      if (m == 'Falta de pago') {
        return 'Hola $n. Tu acceso a la app está pausado mientras se regulariza tu colegiatura. Puedes ponerte al corriente o solicitar un convenio de pago con Administración; en cuanto quede registrado, el acceso se reactiva.';
      }
      if (m == 'Documentación pendiente') {
        return 'Hola $n. Tu acceso a la app está pausado hasta completar la documentación pendiente de tu expediente. Escríbenos a Administración para indicarte qué falta.';
      }
      return 'Hola $n. Tu acceso a la app está pausado temporalmente. Por favor comunícate con Administración para resolverlo.';
    }

    if (mensaje.text.isEmpty) mensaje.text = porDefecto(motivo);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Pausar el acceso de $nombre', style: const TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<String>(
                value: motivo,
                decoration: const InputDecoration(labelText: 'Motivo', border: OutlineInputBorder(), isDense: true),
                items: [for (final m in _motivos) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => setLocal(() {
                  motivo = v ?? motivo;
                  if (mensajeSugerido == null) mensaje.text = porDefecto(motivo);
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: mensaje,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Mensaje que verá el alumno al entrar', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: hasta,
                decoration: const InputDecoration(labelText: 'Levantar solo el (opcional, AAAA-MM-DD)', hintText: 'Vacío = hasta que se reactive a mano', border: OutlineInputBorder(), isDense: true),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: notificar,
                onChanged: (v) => setLocal(() => notificar = v == true),
                title: const Text('Avisarle también por correo con este mensaje', style: TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Pausar acceso')),
          ],
        ),
      ),
    );
    final msg = mensaje.text.trim(), h = hasta.text.trim();
    mensaje.dispose();
    hasta.dispose();
    if (ok != true) return;
    try {
      final d = await _post({'accion': 'acceso_bloquear', 'matricula': mat, 'motivo': motivo, 'mensaje': msg, 'hasta': h, 'notificar': notificar ? '1' : ''});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo bloquear.');
      _aviso('Acceso de $nombre pausado${d['notificado'] == true ? ' y avisado por correo' : ''}.');
      _cargar();
      setState(() => _candidatos.removeWhere((c) => '${c['matricula']}' == mat));
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _desbloquear(Map<String, dynamic> b) async {
    final mat = '${b['matricula']}';
    try {
      final d = await _post({'accion': 'acceso_desbloquear', 'matricula': mat});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo reactivar.');
      _aviso('Acceso de ${b['nombre']} reactivado.');
      _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _convenio(Map<String, dynamic> a) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ConvenioPagoScreen(matriculaInicial: '${a['matricula']}'.replaceAll('.0', ''), plantillaInicial: 'falta_pago')));
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? cessumRed : _verde, content: Text(t)));
  }

  String _pesos(dynamic v) {
    final n = ((v ?? 0) as num).round();
    final s = n.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '${n < 0 ? '-' : ''}\$$s';
  }

  // ───────────────────────── vista ─────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Bloqueos de acceso'),
        actions: [IconButton(tooltip: 'Recargar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Bloqueados${_activos.isNotEmpty ? ' (${_activos.length})' : ''}'),
            Tab(text: 'Candidatos${_candidatos.isNotEmpty ? ' (${_candidatos.length})' : ''}'),
            const Tab(text: 'Buscar'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : TabBarView(controller: _tabs, children: [_pestanaBloqueados(), _pestanaCandidatos(), _pestanaBuscar()]),
    );
  }

  Widget _pestanaBloqueados() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text(
        'Un alumno bloqueado sigue inscrito: al abrir la app ve el mensaje y puede avisar que ya pagó o contactar a Administración. Apague el interruptor para reactivarlo.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context)),
      ),
      const SizedBox(height: 10),
      if (_activos.isEmpty)
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('No hay alumnos con el acceso pausado.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context))),
        ),
      for (final b in _activos) _tarjetaBloqueado(b),
      if (_historial.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('Historial reciente', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
        const SizedBox(height: 6),
        for (final h in _historial.take(30))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_open, size: 18, color: _verde),
            title: Text('${h['nombre']} · ${h['matricula']}', style: const TextStyle(fontSize: 13)),
            subtitle: Text('${h['motivo']} · del ${h['desde']} al ${h['levantadoEl']} · por ${h['levantadoPor']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ),
      ],
    ]);
  }

  Widget _tarjetaBloqueado(Map<String, dynamic> b) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${b['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                Text('${b['matricula']} · ${b['programa']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              ]),
            ),
            Column(children: [
              Switch(value: true, activeThumbColor: cessumRed, onChanged: (_) => _desbloquear(b)),
              Text('Bloqueado', style: TextStyle(fontSize: 10, color: cessumRed, fontWeight: FontWeight.w700)),
            ]),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip('${b['motivo']}', cessumRed),
            _chip('desde ${b['desde']}', _azul),
            if ('${b['hasta'] ?? ''}'.isNotEmpty) _chip('hasta ${b['hasta']}', cessumGold),
            if ('${b['notificado'] ?? ''}'.isNotEmpty) _chip('avisado por correo', _verde),
          ]),
          const SizedBox(height: 6),
          Text('${b['mensaje']}', style: const TextStyle(fontSize: 12.5, height: 1.35)),
          if ('${b['notas'] ?? ''}'.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('${b['notas']}', style: TextStyle(fontSize: 11.5, color: cessumGold, fontWeight: FontWeight.w600))),
          Row(children: [
            TextButton.icon(onPressed: () => _convenio(b), icon: const Icon(Icons.handshake_outlined, size: 16), label: const Text('Convenio de pago')),
            TextButton.icon(onPressed: () => _bloquear(b, mensajeSugerido: '${b['mensaje']}'), icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Editar')),
          ]),
        ]),
      ),
    );
  }

  Widget _pestanaCandidatos() {
    final filtrados = _filtroAccion.isEmpty ? _candidatos : _candidatos.where((c) => '${_iaPor['${c['matricula']}']?['accion'] ?? ''}' == _filtroAccion).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text(
        'Alumnos con colegiaturas incompletas, con el mismo cálculo de bajas por pago, sin contar a los ya bloqueados. La IA propone para cada uno: pausar el acceso, ofrecer convenio, solo recordar o esperar.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context)),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: _cargandoCand ? null : () => _cargarCandidatos(),
          icon: _cargandoCand ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.search, size: 18),
          label: Text(_cargandoCand ? 'Calculando…' : (_candidatos.isEmpty ? 'Buscar candidatos' : 'Actualizar')),
        ),
        if (_candidatos.isNotEmpty)
          OutlinedButton.icon(
            onPressed: _iaCargando ? null : _analizarIa,
            icon: _iaCargando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, size: 18),
            label: Text(_iaCargando ? 'Analizando…' : (_iaPor.isEmpty ? 'Analizar con IA' : 'Volver a analizar')),
          ),
      ]),
      if (_generado.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Cálculo del $_generado', style: TextStyle(fontSize: 11, color: cessumMuted(context)))),
      if (_iaLectura.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Text(_iaLectura, style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ),
      if (_iaPor.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in ['', 'bloquear', 'convenio', 'recordatorio', 'esperar'])
            ChoiceChip(
              label: Text(f.isEmpty ? 'Todos' : f[0].toUpperCase() + f.substring(1)),
              selected: _filtroAccion == f,
              onSelected: (_) => setState(() => _filtroAccion = f),
            ),
        ]),
      ],
      const SizedBox(height: 8),
      if (!_cargandoCand && _candidatos.isEmpty && _generado.isNotEmpty)
        Padding(padding: const EdgeInsets.all(20), child: Text('Ningún alumno con adeudo fuera de los ya bloqueados.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))),
      for (final c in filtrados) _tarjetaCandidato(c),
    ]);
  }

  Widget _tarjetaCandidato(Map<String, dynamic> c) {
    final ia = _iaPor['${c['matricula']}'];
    final accion = '${ia?['accion'] ?? ''}';
    final colorAccion = accion == 'bloquear' ? cessumRed : accion == 'convenio' ? cessumGold : accion == 'recordatorio' ? _azul : _verde;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${c['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                Text('${c['matricula']} · ${c['programa']} · ${c['generacion']} ${c['grupo']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              ]),
            ),
            if (ia != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: colorAccion.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text('P${ia['prioridad']} · ${accion.isEmpty ? '' : accion[0].toUpperCase() + accion.substring(1)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colorAccion)),
              ),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip('faltan ${_pesos(c['faltaPesos'])}', cessumRed),
            _chip('${c['faltanColegiaturas']} colegiatura(s)', cessumRed),
            if (((c['faltanReinscripciones'] ?? 0) as num) > 0) _chip('${c['faltanReinscripciones']} reinscripción(es)', cessumGold),
            _chip('último pago: ${'${c['ultimoPago'] ?? ''}'.isEmpty ? 'sin pagos' : c['ultimoPago']}', _azul),
            if ('${c['convenio'] ?? ''}'.isNotEmpty) _chip('convenio vigente', _verde),
            if ('${c['decision'] ?? ''}'.isNotEmpty) _chip('bajas: ${c['decision']}', cessumGold),
          ]),
          if (ia != null) ...[
            const SizedBox(height: 6),
            Text('${ia['porque']}', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
            if ('${ia['mensaje'] ?? ''}'.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: cessumBg(context), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Expanded(child: Text('${ia['mensaje']}', style: const TextStyle(fontSize: 12, height: 1.35))),
                  IconButton(
                    tooltip: 'Copiar mensaje',
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: '${ia['mensaje']}'));
                      _aviso('Mensaje copiado.');
                    },
                  ),
                ]),
              ),
          ],
          Row(children: [
            TextButton.icon(
              onPressed: () => _bloquear(c, mensajeSugerido: ia != null && accion == 'bloquear' ? '${ia['mensaje']}' : null),
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Pausar acceso'),
            ),
            TextButton.icon(onPressed: () => _convenio(c), icon: const Icon(Icons.handshake_outlined, size: 16), label: const Text('Convenio de pago')),
          ]),
        ]),
      ),
    );
  }

  Widget _pestanaBuscar() {
    return ListView(padding: const EdgeInsets.all(14), children: [
      TextField(
        controller: _busca,
        onSubmitted: (_) => _buscar(),
        decoration: InputDecoration(
          labelText: 'Nombre o matrícula',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(onPressed: _buscando ? null : _buscar, icon: _buscando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search)),
        ),
      ),
      const SizedBox(height: 8),
      for (final a in _resultados)
        Builder(builder: (context) {
          final mat = '${a['matricula']}'.replaceAll('.0', '');
          final bloqueado = _activos.any((b) => '${b['matricula']}' == mat);
          return ListTile(
            title: Text('${a['nombre']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            subtitle: Text('$mat · ${a['programa'] ?? ''}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            trailing: bloqueado
                ? TextButton(onPressed: () => _desbloquear({'matricula': mat, 'nombre': a['nombre']}), child: const Text('Reactivar', style: TextStyle(color: _verde)))
                : TextButton(onPressed: () => _bloquear(a), child: const Text('Pausar acceso', style: TextStyle(color: cessumRed))),
          );
        }),
    ]);
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      );
}

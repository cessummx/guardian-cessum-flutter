// =====================================================================
//  dictaminacion_screen.dart · CESSUM · App CESSUM (administración)
//  DICTAMINACIÓN — seguimiento de los trabajos enviados a COINEDU 2026 y a
//  la Revista CESSUMEX, su recordatorio diario y la aceptación de los
//  dictaminadores.
//
//  (9-oct-2026) El comité tenía los trabajos de la revista en admin.php, los
//  del congreso en comite.php y las respuestas de los revisores en su correo.
//  Aquí está todo junto, por sistema:
//    · contadores (sin asignar, sin aceptar, vencidos, listos para resolver…)
//    · cada trabajo con su línea de tiempo (recibido → asignado → aceptado →
//      dictámenes → resolución → autor notificado → correcciones → cuota)
//    · cada revisor con su estado de aceptación, su plazo y sus recordatorios
//    · acciones: recordar ahora, registrar aceptación/declinación a mano,
//      asignar y resolver (CESSUMEX), abrir el panel web
//    · el recordatorio diario: estado, encendido/apagado y corrida de prueba
//
//  Backend (Guardián V1085): dictamen_seguimiento, dictamen_recordatorio_*,
//  dictamen_recordar_ahora, dictamen_aceptacion_registrar, dictamen_coinedu_diag,
//  cessumex_asignar, cessumex_resolver.
//  Encender el recordatorio o «Recordar ahora» ENVÍA CORREOS a dictaminadores
//  externos: la pantalla lo advierte y pide confirmación cada vez.
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

const List<String> _kSistemas = ['coinedu', 'cessumex'];

class DictaminacionScreen extends StatefulWidget {
  const DictaminacionScreen({super.key});

  @override
  State<DictaminacionScreen> createState() => _DictaminacionScreenState();
}

class _DictaminacionScreenState extends State<DictaminacionScreen>
    with SingleTickerProviderStateMixin {
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  String _correo = '';
  Map<String, dynamic> _datos = {};
  late TabController _tabs;
  String _busqueda = '';
  String _filtro = 'accion'; // accion | todos | enDictamen | resueltos
  final Set<String> _abiertos = {};
  DateTime? _actualizado;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _kSistemas.length, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ---------- red ----------

  Future<Map<String, dynamic>> _get(Map<String, String> q) async {
    final uri = Uri.parse(guardianUrl)
        .replace(queryParameters: {...q, 'actor': _correo});
    final r = await http.get(uri).timeout(const Duration(seconds: 120));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    body['actor'] = _correo;
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 120));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      _correo = await SessionStore.validEmail() ?? '';
      final d = await _get({'accion': 'dictamen_seguimiento'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _datos = d;
        _actualizado = DateTime.now();
      });
    } catch (e) {
      final m = '$e'.replaceFirst('Exception: ', '');
      if (mounted) {
        setState(() => _error = (m.contains('TimeoutException') ||
                m.contains('ClientException') ||
                m.contains('SocketException') ||
                m.startsWith('FormatException'))
            ? 'No se pudo cargar el seguimiento. Revisa tu conexión e intenta de nuevo.'
            : m);
      }
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // ---------- acceso a los datos ----------

  Map<String, dynamic> _sistema(String clave) {
    final s = (_datos['sistemas'] as Map?) ?? {};
    final m = s[clave];
    return m is Map ? Map<String, dynamic>.from(m) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _trabajos(String clave) {
    final l = (_sistema(clave)['trabajos'] as List?) ?? [];
    return l.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Map<String, dynamic> get _recordatorio {
    final r = _datos['recordatorio'];
    return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
  }

  List<String> get _motivos =>
      ((_datos['motivos'] as List?) ?? []).map((e) => e.toString()).toList();

  int _i(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _norm(String s) {
    s = s.toLowerCase();
    const a = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const b = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  List<Map<String, dynamic>> _visibles(String clave) {
    final q = _norm(_busqueda);
    return _trabajos(clave).where((t) {
      final resuelto = t['resuelto'] == true;
      final alertas = (t['alertas'] as List?) ?? [];
      if (_filtro == 'accion' && alertas.isEmpty) return false;
      if (_filtro == 'enDictamen' && resuelto) return false;
      if (_filtro == 'resueltos' && !resuelto) return false;
      if (q.isEmpty) return true;
      final txt = _norm('${t['folio']} ${t['titulo']} ${t['autor']} ${t['linea']} '
          '${((t['revisores'] as List?) ?? []).map((r) => (r as Map)['nombre']).join(' ')}');
      return txt.contains(q);
    }).toList();
  }

  // ---------- UI ----------

  Color get _superficie => Theme.of(context).cardColor;
  Color get _borde => cessumIsDark(context) ? Colors.white12 : Colors.black12;
  static const Color _verde = Color(0xFF1E7A38);
  static const Color _morado = Color(0xFF6A4FB0);

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : null,
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Dictaminación'),
        actions: [
          IconButton(
            tooltip: 'Correr el recordatorio en PRUEBA (no envía nada)',
            icon: const Icon(Icons.science_outlined),
            onPressed: _cargando || _ocupado ? null : () => _correrRecordatorio(prueba: true),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más',
            onSelected: (v) {
              if (v == 'correr') _correrRecordatorio(prueba: false);
              if (v == 'config') _dialogoConfig();
              if (v == 'diag') _diagCoinedu();
              if (v == 'copiar') _copiarResumen();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'correr', child: Text('Correr el recordatorio AHORA (envía correos)')),
              PopupMenuItem(value: 'config', child: Text('Configurar hora, cadencia y destinatarios')),
              PopupMenuItem(value: 'diag', child: Text('Diagnóstico de la lectura de COINEDU')),
              PopupMenuItem(value: 'copiar', child: Text('Copiar resumen para Excel')),
            ],
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
        bottom: _cargando || _error != null
            ? null
            : TabBar(
                controller: _tabs,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: _kSistemas.map((s) {
                  final sis = _sistema(s);
                  final c = (sis['contadores'] as Map?) ?? {};
                  final pend = _i(c['sinAsignar']) + _i(c['sinAceptar']) + _i(c['vencidos']) +
                      _i(c['listos']) + _i(c['declinados']);
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text((sis['nombre'] ?? s).toString(),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        if (pend > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.white, borderRadius: BorderRadius.circular(10)),
                            child: Text('$pend',
                                style: const TextStyle(
                                    color: cessumRed, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
      body: _cargando
          ? const Padding(padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? _vistaError()
              : Column(
                  children: [
                    _bandaRecordatorio(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: _kSistemas.map(_vistaSistema).toList(),
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
              Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
                  onPressed: _cargar,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar')),
            ],
          ),
        ),
      );

  // ---------- banda del recordatorio diario ----------

  Widget _bandaRecordatorio() {
    final r = _recordatorio;
    final encendido = r['encendido'] == true;
    final hora = _i(r['hora']);
    final cadencia = (r['cadencia'] ?? 'diario').toString();
    final dias = (r['dias'] ?? 'L-V').toString();
    final mecanismo = (r['mecanismo'] ?? '').toString();
    final ultimo = (r['ultimoDia'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: encendido ? _verde.withValues(alpha: 0.5) : cessumGold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(encendido ? Icons.notifications_active : Icons.notifications_off_outlined,
              color: encendido ? _verde : cessumGold, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  encendido
                      ? 'Recordatorio diario ENCENDIDO · ${hora.toString().padLeft(2, '0')}:00 · $cadencia · $dias'
                      : 'Recordatorio diario APAGADO',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumInk(context)),
                ),
                const SizedBox(height: 2),
                Text(
                  encendido
                      ? '$mecanismo${ultimo.isNotEmpty ? ' · último envío: $ultimo' : ''}'
                      : 'Nada sale solo. Pruébalo con el matraz (no envía nada) y enciéndelo aquí.',
                  style: TextStyle(fontSize: 11, color: cessumMuted(context), height: 1.3),
                ),
              ],
            ),
          ),
          Switch(
            value: encendido,
            activeThumbColor: _verde,
            onChanged: _ocupado ? null : (v) => v ? _encender() : _apagar(),
          ),
        ],
      ),
    );
  }

  int _revisoresPendientesTotal() {
    var n = 0;
    for (final s in _kSistemas) {
      n += _i(((_sistema(s)['contadores'] as Map?) ?? {})['revisoresPendientes']);
    }
    return n;
  }

  Future<void> _encender() async {
    final para = ((_recordatorio['resumenPara'] as List?) ?? []).map((e) => e.toString()).join(', ');
    final n = _revisoresPendientesTotal();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encender el recordatorio diario', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cessumGold)),
              child: Text(
                'ESTO ENVÍA CORREOS A DICTAMINADORES EXTERNOS. Cada día (según la cadencia) '
                'recibirá un correo cada revisor con dictámenes pendientes: hoy serían $n asignación(es) '
                'pendiente(s). El resumen diario llega a $para.',
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Si todavía no revisaste la lista, cancela y toca el matraz: la corrida en PRUEBA muestra '
              'a quién le llegaría sin enviar nada.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Encender'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _accion({'accion': 'dictamen_recordatorio_instalar'}, 'Recordatorio diario encendido.');
  }

  Future<void> _apagar() async {
    await _accion({'accion': 'dictamen_recordatorio_quitar'}, 'Recordatorio diario apagado.');
  }

  Future<void> _accion(Map<String, dynamic> body, String exito) async {
    setState(() => _ocupado = true);
    try {
      final d = await _post(body);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo.');
      _aviso(exito);
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _correrRecordatorio({required bool prueba}) async {
    if (!prueba) {
      final n = _revisoresPendientesTotal();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Correr el recordatorio ahora', style: TextStyle(fontSize: 16)),
          content: Text(
            'Se enviará un correo a cada dictaminador con pendientes ($n asignación(es) pendiente(s) '
            'en total, según la cadencia configurada) y el resumen diario al comité. ¿Continuar?',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _ocupado = true);
    try {
      final d = await _post({
        'accion': 'dictamen_recordatorio_correr',
        'prueba': prueba ? '1' : '0',
        'forzar': '1',
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo.');
      if (!mounted) return;
      final rec = (d['recordatorios'] as Map?) ?? {};
      final revs = ((rec['revisores'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final resumen = (d['resumen'] as Map?) ?? {};
      final respaldo = (d['respaldoCoinedu'] as Map?) ?? {};
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(prueba ? 'Corrida en PRUEBA' : 'Recordatorio enviado', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((d['nota'] ?? '').toString(), style: const TextStyle(fontSize: 13, height: 1.4)),
                  const SizedBox(height: 8),
                  Text('Cadencia: ${d['cadencia']} · días: ${d['dias']}',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  if ((rec['motivoOmision'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Revisores: ${rec['motivoOmision']}',
                          style: const TextStyle(fontSize: 12.5, color: cessumGold)),
                    ),
                  const SizedBox(height: 8),
                  if (revs.isEmpty)
                    Text('Ningún dictaminador con pendientes por avisar.',
                        style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))
                  else
                    ...revs.map((r) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(r['enviado'] == true ? Icons.check_circle : Icons.mail_outline,
                                  size: 16, color: r['enviado'] == true ? _verde : cessumGold),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${r['nombre'] ?? r['correo']} <${r['correo']}> · ${r['trabajos']} trabajo(s): ${((r['folios'] as List?) ?? []).join(', ')}',
                                  style: const TextStyle(fontSize: 12.5, height: 1.3),
                                ),
                              ),
                            ],
                          ),
                        )),
                  const SizedBox(height: 8),
                  Text(
                    'Resumen al comité: ${resumen['enviado'] == true ? 'enviado' : (prueba ? 'iría' : 'no enviado')} a ${((resumen['para'] as List?) ?? []).join(', ')}',
                    style: const TextStyle(fontSize: 12.5, height: 1.3),
                  ),
                  if ((respaldo['nota'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('COINEDU (API): ${respaldo['nota']}',
                          style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                    ),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        ),
      );
      if (!prueba) await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _dialogoConfig() async {
    final r = _recordatorio;
    final horaCtrl = TextEditingController(text: _i(r['hora']).toString());
    final paraCtrl = TextEditingController(
        text: ((r['resumenPara'] as List?) ?? []).map((e) => e.toString()).join(', '));
    final cierreCtrl = TextEditingController(text: (r['cierreCoinedu'] ?? '').toString());
    var cadencia = (r['cadencia'] ?? 'diario').toString();
    var dias = (r['dias'] ?? 'L-V').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Configurar el recordatorio', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: horaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Hora de envío (0-23, Hermosillo)', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: cadencia,
                    decoration: const InputDecoration(
                        labelText: 'Cadencia a dictaminadores', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'diario', child: Text('Diario: todo pendiente, cada día')),
                      DropdownMenuItem(value: 'vencimiento', child: Text('Solo sin confirmar, ≤3 días hábiles o vencidos')),
                      DropdownMenuItem(value: 'apagado', child: Text('Apagado: solo el resumen al comité')),
                    ],
                    onChanged: (v) => setLocal(() => cadencia = v ?? 'diario'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: dias,
                    decoration: const InputDecoration(
                        labelText: 'Días en que se avisa a dictaminadores', border: OutlineInputBorder(), isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'L-V', child: Text('Lunes a viernes')),
                      DropdownMenuItem(value: 'L-S', child: Text('Lunes a sábado')),
                      DropdownMenuItem(value: 'L-D', child: Text('Todos los días')),
                    ],
                    onChanged: (v) => setLocal(() => dias = v ?? 'L-V'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: paraCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Resumen diario para (correos separados por coma)',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cierreCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Cierre de dictaminación COINEDU (AAAA-MM-DD)',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Guardar NO enciende el recordatorio si está apagado; solo ajusta la configuración. '
                    'El resumen al comité sale siempre que el recordatorio esté encendido.',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.3),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final encendido = _recordatorio['encendido'] == true;
    // instalar guarda la configuración; si estaba apagado, se vuelve a apagar enseguida.
    final body = {
      'accion': 'dictamen_recordatorio_instalar',
      'hora': horaCtrl.text.trim(),
      'cadencia': cadencia,
      'dias': dias,
      'para': paraCtrl.text.trim(),
      'cierreCoinedu': cierreCtrl.text.trim(),
    };
    setState(() => _ocupado = true);
    try {
      final d = await _post(body);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo.');
      if (!encendido) {
        final q = await _post({'accion': 'dictamen_recordatorio_quitar'});
        if (q['ok'] != true) throw Exception(q['error'] ?? 'No se pudo apagar de nuevo.');
      }
      _aviso('Configuración guardada.');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _diagCoinedu() async {
    setState(() => _ocupado = true);
    try {
      final d = await _get({'accion': 'dictamen_coinedu_diag'});
      if (!mounted) return;
      const enc = JsonEncoder.withIndent('  ');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lectura de COINEDU', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: SelectableText(enc.convert(d), style: const TextStyle(fontSize: 11.5, height: 1.35)),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Helpers.copiarAlPortapapeles(context, enc.convert(d), 'Diagnóstico'),
                child: const Text('Copiar')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _copiarResumen() {
    final sb = StringBuffer()..writeln('Dictaminación CESSUM · ${_actualizado != null ? Helpers.haceTexto(_actualizado) : ''}');
    for (final s in _kSistemas) {
      final sis = _sistema(s);
      sb.writeln();
      sb.writeln('${sis['nombre']} · ${sis['numero']}');
      sb.writeln('Folio\tTítulo\tAutor\tEstado\tEtapa\tRevisores\tAlertas');
      for (final t in _trabajos(s)) {
        final et = (t['etapas'] as List?) ?? [];
        final idx = _i(t['etapaActual']);
        final etapa = idx < et.length ? ((et[idx] as Map)['nombre'] ?? '') : '';
        final revs = ((t['revisores'] as List?) ?? []).map((r) {
          final m = r as Map;
          return '${m['nombre']} (${m['aceptacion']}${m['entregado'] == true ? ', ${m['veredicto']}' : ''})';
        }).join('; ');
        sb.writeln('${t['folio']}\t${t['titulo']}\t${t['autor']}\t${t['estado']}\t$etapa\t$revs\t${((t['alertas'] as List?) ?? []).join(' / ')}');
      }
    }
    Helpers.copiarAlPortapapeles(context, sb.toString(), 'Resumen de dictaminación');
  }

  // ---------- vista por sistema ----------

  Widget _vistaSistema(String clave) {
    final sis = _sistema(clave);
    final c = (sis['contadores'] as Map?) ?? {};
    final errores = ((sis['errores'] as List?) ?? []).map((e) => e.toString()).toList();
    final vis = _visibles(clave);
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 30),
        children: [
          _cabecera(sis, c, clave),
          if (errores.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.08),
                  border: Border.all(color: cessumRed.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('No se pudo leer completo: ${errores.join(' · ')}',
                  style: const TextStyle(fontSize: 12, height: 1.35)),
            ),
          const SizedBox(height: 10),
          _filtros(clave),
          const SizedBox(height: 8),
          ...vis.map((t) => _tarjetaTrabajo(clave, t)),
          if (vis.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  _trabajos(clave).isEmpty
                      ? 'Sin trabajos registrados.'
                      : (_filtro == 'accion' ? 'Nada requiere acción con este filtro.' : 'Nadie coincide con el filtro.'),
                  style: TextStyle(color: cessumMuted(context)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cabecera(Map<String, dynamic> sis, Map c, String clave) {
    Widget chip(String n, String etq, Color color, {String? filtro}) {
      final activo = n != '0';
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: filtro == null || !activo ? null : () => setState(() => _filtro = filtro),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: activo ? color : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text('$n $etq',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: activo ? Colors.white : Colors.white70)),
        ),
      );
    }

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
          Text((sis['nombre'] ?? '').toString(), style: CessumType.heading(15, color: Colors.white)),
          Text(
            '${sis['numero'] ?? ''}${(sis['cierre'] ?? '').toString().isNotEmpty ? ' · cierre de dictaminación: ${sis['cierre']}' : ''}',
            style: const TextStyle(fontSize: 11.5, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              chip('${_i(c['trabajos'])}', 'trabajos', const Color(0xFF5F5E5A), filtro: 'todos'),
              chip('${_i(c['sinAsignar'])}', 'sin asignar', const Color(0xFFA56B16), filtro: 'accion'),
              chip('${_i(c['enDictamen'])}', 'en dictamen', _verde, filtro: 'enDictamen'),
              chip('${_i(c['sinAceptar'])}', 'sin aceptar', const Color(0xFFA56B16), filtro: 'accion'),
              chip('${_i(c['declinados'])}', 'declinados', const Color(0xFF8E1720), filtro: 'accion'),
              chip('${_i(c['vencidos'])}', 'vencidos', const Color(0xFF8E1720), filtro: 'accion'),
              chip('${_i(c['listos'])}', 'listos para resolver', _verde, filtro: 'accion'),
              chip('${_i(c['discrepancia'])}', 'con discrepancia', _morado, filtro: 'accion'),
              chip('${_i(c['resueltos'])}', 'resueltos', const Color(0xFF5F5E5A), filtro: 'resueltos'),
              if (clave == 'cessumex') ...[
                chip('${_i(c['correccionVencida'])}', 'correcciones vencidas', const Color(0xFF8E1720), filtro: 'accion'),
                chip('${_i(c['cuotasPendientes'])}', 'cuotas por confirmar', const Color(0xFFA56B16), filtro: 'accion'),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => Helpers.abrirUrlExterna((sis['panel'] ?? '').toString(), context),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Panel del comité', style: TextStyle(fontSize: 11.5)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => Helpers.abrirUrlExterna((sis['panelRevisor'] ?? '').toString(), context),
                icon: const Icon(Icons.rate_review_outlined, size: 15),
                label: const Text('Panel del dictaminador', style: TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filtros(String clave) {
    Widget f(String v, String txt) => ChoiceChip(
          label: Text(txt, style: const TextStyle(fontSize: 12)),
          selected: _filtro == v,
          selectedColor: cessumRed.withValues(alpha: 0.16),
          onSelected: (_) => setState(() => _filtro = v),
        );
    return Column(
      children: [
        TextField(
          onChanged: (v) => setState(() => _busqueda = v),
          decoration: InputDecoration(
            hintText: 'Buscar folio, título, autor o revisor…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: _superficie,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              f('accion', 'Requieren acción'),
              const SizedBox(width: 6),
              f('enDictamen', 'En proceso'),
              const SizedBox(width: 6),
              f('resueltos', 'Resueltos'),
              const SizedBox(width: 6),
              f('todos', 'Todos'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String txt, Color fg, Color bg, {IconData? icono}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icono != null) ...[Icon(icono, size: 11, color: fg), const SizedBox(width: 3)],
            Text(txt, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      );

  Widget _tarjetaTrabajo(String clave, Map<String, dynamic> t) {
    final folio = (t['folio'] ?? '').toString();
    final abierto = _abiertos.contains('$clave|$folio');
    final alertas = ((t['alertas'] as List?) ?? []).map((e) => e.toString()).toList();
    final resuelto = t['resuelto'] == true;
    final etapas = ((t['etapas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final actual = _i(t['etapaActual']);
    final revisores = ((t['revisores'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final borde = alertas.isNotEmpty && !resuelto
        ? cessumRed.withValues(alpha: 0.45)
        : (resuelto ? _verde.withValues(alpha: 0.35) : _borde);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              if (abierto) {
                _abiertos.remove('$clave|$folio');
              } else {
                _abiertos.add('$clave|$folio');
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
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
                            Text(
                              '$folio${(t['modalidad'] ?? '').toString().isNotEmpty ? ' · ${t['modalidad']}' : ''}${(t['linea'] ?? '').toString().isNotEmpty ? ' · ${t['linea']}' : ''}',
                              style: TextStyle(fontSize: 10.5, color: cessumFaint(context)),
                            ),
                            Text((t['titulo'] ?? '(sin título)').toString(),
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context))),
                            if ((t['autor'] ?? '').toString().isNotEmpty)
                              Text(
                                '${t['autor']}${(t['institucion'] ?? '').toString().isNotEmpty ? ' · ${t['institucion']}' : ''} · recibido ${t['recibido'] ?? ''}',
                                style: TextStyle(fontSize: 11, color: cessumMuted(context)),
                              ),
                          ],
                        ),
                      ),
                      Icon(abierto ? Icons.expand_less : Icons.expand_more, size: 20, color: cessumFaint(context)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _lineaTiempo(etapas, actual, resuelto),
                  if (alertas.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: alertas.map((a) {
                        final bueno = a.startsWith('Listo');
                        final c = bueno ? _verde : (a.contains('discrep') || a.contains('opuestos') ? _morado : cessumRed);
                        return _chip(a, c, c.withValues(alpha: 0.10), icono: bueno ? Icons.check_circle_outline : Icons.priority_high);
                      }).toList(),
                    ),
                  ],
                  if (revisores.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: revisores.map(_chipRevisor).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (abierto) _detalleTrabajo(clave, t, etapas, revisores),
        ],
      ),
    );
  }

  Widget _lineaTiempo(List<Map<String, dynamic>> etapas, int actual, bool resuelto) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(etapas.length, (i) {
          final e = etapas[i];
          final hecho = e['hecho'] == true;
          final esActual = i == actual && !hecho;
          final color = hecho ? _verde : (esActual ? cessumGold : cessumFaint(context));
          return Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hecho ? _verde : (esActual ? cessumGold : Colors.transparent),
                      border: Border.all(color: color, width: 2),
                    ),
                    child: hecho ? const Icon(Icons.check, size: 9, color: Colors.white) : null,
                  ),
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 64,
                    child: Text(
                      (e['nombre'] ?? '').toString(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: 9,
                          height: 1.1,
                          fontWeight: esActual ? FontWeight.w800 : FontWeight.w500,
                          color: hecho || esActual ? cessumInk(context) : cessumMuted(context)),
                    ),
                  ),
                ],
              ),
              if (i < etapas.length - 1)
                Container(
                  width: 12,
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 20),
                  color: (etapas[i + 1]['hecho'] == true) ? _verde : cessumFaint(context).withValues(alpha: 0.5),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _chipRevisor(Map<String, dynamic> r) {
    final acept = (r['aceptacion'] ?? '').toString();
    final entregado = r['entregado'] == true;
    final vencido = r['vencido'] == true;
    Color c;
    IconData ic;
    String txt;
    if (entregado) {
      c = _verde;
      ic = Icons.task_alt;
      txt = '${r['nombre']}: ${r['veredicto']}';
    } else if (acept == 'Declina') {
      c = cessumRed;
      ic = Icons.block;
      txt = '${r['nombre']}: declinó';
    } else if (vencido) {
      c = cessumRed;
      ic = Icons.schedule;
      txt = '${r['nombre']}: vencido (${r['diasDeMas']} d)';
    } else if (acept == 'Acepta') {
      c = _verde;
      ic = Icons.thumb_up_alt_outlined;
      txt = '${r['nombre']}: aceptó · ${r['diasHabilesRestantes'] ?? '?'} d';
    } else {
      c = cessumGold;
      ic = Icons.hourglass_top;
      txt = '${r['nombre']}: sin confirmar · ${r['diasHabilesRestantes'] ?? '?'} d';
    }
    return _chip(txt, c, c.withValues(alpha: 0.10), icono: ic);
  }

  Widget _detalleTrabajo(String clave, Map<String, dynamic> t, List<Map<String, dynamic>> etapas, List<Map<String, dynamic>> revisores) {
    final sis = _sistema(clave);
    final resuelto = t['resuelto'] == true;
    final esCmx = clave == 'cessumex';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: _borde),
          // Etapas con fecha y detalle
          ...etapas.map((e) {
            final hecho = e['hecho'] == true;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(hecho ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 15, color: hecho ? _verde : cessumFaint(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${e['nombre']}${(e['fecha'] ?? '').toString().isNotEmpty ? ' · ${e['fecha']}' : ''}${(e['detalle'] ?? '').toString().isNotEmpty ? ' · ${e['detalle']}' : ''}',
                      style: TextStyle(fontSize: 11.5, color: hecho ? cessumInk(context) : cessumMuted(context), height: 1.3),
                    ),
                  ),
                ],
              ),
            );
          }),
          if ((t['veredicto'] ?? '').toString().isNotEmpty || (t['estado'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Estado: ${t['estado']}${(t['veredicto'] ?? '').toString().isNotEmpty ? ' · Veredicto: ${t['veredicto']}' : ''}'
                '${(t['venceCorreccion'] ?? '').toString().isNotEmpty ? ' · correcciones hasta ${t['venceCorreccion']}' : ''}'
                '${_i(t['cuota']) > 0 ? ' · cuota \$${t['cuota']}' : ''}'
                '${(t['pagoEstatus'] ?? '').toString().isNotEmpty ? ' · pago: ${t['pagoEstatus']}' : ''}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.3),
              ),
            ),
          const SizedBox(height: 8),
          // Revisores
          Text('Dictaminadores', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cessumRed, letterSpacing: 0.6)),
          if (revisores.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                esCmx ? 'Sin asignar. Usa «Asignar revisor».' : 'Sin asignar. Se asigna en comite.php (COINEDU).',
                style: TextStyle(fontSize: 12, color: cessumMuted(context)),
              ),
            ),
          ...revisores.map((r) => _filaRevisor(clave, t, r)),
          const SizedBox(height: 8),
          // Acciones del trabajo
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: [
              if (esCmx && !resuelto)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cessumRed, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: _ocupado ? null : () => _dialogoAsignar(t),
                  icon: const Icon(Icons.person_add_alt, size: 16),
                  label: const Text('Asignar revisor', style: TextStyle(fontSize: 11.5)),
                ),
              if (esCmx && !resuelto && _i(t['entregados']) > 0)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: _verde, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: _ocupado ? null : () => _dialogoResolver(t),
                  icon: const Icon(Icons.gavel, size: 16),
                  label: const Text('Resolver y notificar', style: TextStyle(fontSize: 11.5)),
                ),
              if ((t['archivo'] ?? '').toString().isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cessumGold, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: () => Helpers.abrirUrlExterna((t['archivo'] ?? '').toString(), context),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Documento', style: TextStyle(fontSize: 11.5)),
                ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cessumMuted(context), padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => Helpers.abrirUrlExterna((sis['panel'] ?? '').toString(), context),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(esCmx ? 'admin.php' : 'comite.php', style: const TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filaRevisor(String clave, Map<String, dynamic> t, Map<String, dynamic> r) {
    final entregado = r['entregado'] == true;
    final acept = (r['aceptacion'] ?? 'Sin respuesta').toString();
    final plazo = entregado
        ? 'entregó ${r['entregadoEl'] ?? ''}${r['puntaje'] != null ? ' · ${r['puntaje']} pts' : ''}'
        : (r['vencido'] == true
            ? 'VENCIÓ ${r['vence'] ?? ''} (${r['diasDeMas']} d hábiles de retraso)'
            : 'vence ${r['vence'] ?? '—'}${r['diasHabilesRestantes'] != null ? ' · ${r['diasHabilesRestantes']} d hábiles' : ''}');
    final cAcept = acept == 'Acepta' ? _verde : (acept == 'Declina' ? cessumRed : cessumGold);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: cessumMuted(context).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${r['nombre']}${(r['institucion'] ?? '').toString().isNotEmpty ? ' · ${r['institucion']}' : ''}${(r['clave'] ?? '').toString().isNotEmpty ? ' · ${r['clave']}' : ''}',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: cessumInk(context)),
          ),
          Text((r['correo'] ?? '').toString(), style: TextStyle(fontSize: 10.5, color: cessumFaint(context))),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (!entregado)
                _chip(
                    acept == 'Acepta'
                        ? 'Aceptó ${r['respondidoEl'] ?? ''}'
                        : (acept == 'Declina' ? 'Declinó ${r['respondidoEl'] ?? ''}${(r['motivo'] ?? '').toString().isNotEmpty ? ' · ${r['motivo']}' : ''}' : 'Sin confirmar${r['asignado'] != null && (r['asignado'] ?? '').toString().isNotEmpty ? ' · asignado ${r['asignado']}' : ''}'),
                    cAcept,
                    cAcept.withValues(alpha: 0.12)),
              _chip(entregado ? 'Dictamen: ${r['veredicto']}' : plazo,
                  entregado ? _verde : (r['vencido'] == true ? cessumRed : cessumMuted(context)),
                  (entregado ? _verde : (r['vencido'] == true ? cessumRed : cessumMuted(context))).withValues(alpha: 0.10)),
              if (_i(r['recordatorios']) > 0)
                _chip('${r['recordatorios']} recordatorio(s)${(r['ultimoRecordatorio'] ?? '').toString().isNotEmpty ? ' · último ${r['ultimoRecordatorio']}' : ''}',
                    cessumMuted(context), cessumMuted(context).withValues(alpha: 0.12), icono: Icons.mail_outline),
            ],
          ),
          if (!entregado && acept != 'Declina')
            Wrap(
              spacing: 2,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cessumRed, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: _ocupado ? null : () => _recordarAhora(clave, t, r),
                  icon: const Icon(Icons.send_outlined, size: 15),
                  label: const Text('Recordar ahora', style: TextStyle(fontSize: 11.5)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cessumGold, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  onPressed: _ocupado ? null : () => _registrarRespuesta(clave, t, r),
                  icon: const Icon(Icons.how_to_reg_outlined, size: 15),
                  label: const Text('Registrar respuesta', style: TextStyle(fontSize: 11.5)),
                ),
                if ((r['archivoAnonimo'] ?? '').toString().isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: cessumMuted(context), padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () => Helpers.abrirUrlExterna((r['archivoAnonimo'] ?? '').toString(), context),
                    icon: const Icon(Icons.insert_drive_file_outlined, size: 15),
                    label: const Text('Copia anónima', style: TextStyle(fontSize: 11.5)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  // ---------- acciones por revisor ----------

  Future<void> _recordarAhora(String clave, Map<String, dynamic> t, Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recordar ahora', style: TextStyle(fontSize: 16)),
        content: Text(
          'Se enviará UN correo a ${r['nombre']} <${r['correo']}> con todos sus dictámenes pendientes '
          '(incluido ${t['folio']}) y los botones de aceptación. ¿Enviar?',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _accion({
      'accion': 'dictamen_recordar_ahora',
      'sistema': clave,
      'correo': (r['correo'] ?? '').toString(),
    }, 'Recordatorio enviado a ${r['correo']}.');
  }

  Future<void> _registrarRespuesta(String clave, Map<String, dynamic> t, Map<String, dynamic> r) async {
    var respuesta = 'Acepta';
    var motivo = _motivos.isNotEmpty ? _motivos.first : 'Otro';
    final comentario = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Registrar respuesta del revisor', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['nombre']} · ${t['folio']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Para cuando el revisor contestó por otro medio (teléfono, WhatsApp, correo).',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Acepta', label: Text('Acepta'), icon: Icon(Icons.thumb_up_alt_outlined)),
                    ButtonSegment(value: 'Declina', label: Text('Declina'), icon: Icon(Icons.block)),
                  ],
                  selected: {respuesta},
                  onSelectionChanged: (v) => setLocal(() => respuesta = v.first),
                ),
                if (respuesta == 'Declina') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: motivo,
                    decoration: const InputDecoration(labelText: 'Motivo', border: OutlineInputBorder(), isDense: true),
                    items: (_motivos.isNotEmpty ? _motivos : ['Otro'])
                        .map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setLocal(() => motivo = v ?? motivo),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    clave == 'cessumex'
                        ? 'Al declinar se retira la asignación en CESSUMEX y se avisa al comité para reasignar.'
                        : 'Al declinar se avisa al comité; la reasignación se hace en comite.php.',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.3),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: comentario,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Comentario (opcional)', border: OutlineInputBorder(), isDense: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _accion({
      'accion': 'dictamen_aceptacion_registrar',
      'sistema': clave,
      'folio': (t['folio'] ?? '').toString(),
      'correo': (r['correo'] ?? '').toString(),
      'nombre': (r['nombre'] ?? '').toString(),
      'titulo': (t['titulo'] ?? '').toString(),
      'clave': (r['clave'] ?? '').toString(),
      'respuesta': respuesta,
      'motivo': respuesta == 'Declina' ? motivo : '',
      'comentario': comentario.text.trim(),
    }, respuesta == 'Acepta' ? 'Aceptación registrada.' : 'Declinación registrada.');
  }

  // ---------- CESSUMEX: asignar y resolver ----------

  Future<void> _dialogoAsignar(Map<String, dynamic> t) async {
    final revisores = ((_sistema('cessumex')['revisores'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((r) => r['activo'] != false)
        .toList();
    final ya = ((t['revisores'] as List?) ?? []).map((e) => ((e as Map)['correo'] ?? '').toString()).toSet();
    final sel = <String>{};
    var q = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final lista = revisores.where((r) {
            if (q.isEmpty) return true;
            return _norm('${r['nombre']} ${r['institucion']} ${r['lineas']} ${r['correo']}').contains(_norm(q));
          }).toList();
          return AlertDialog(
            title: Text('Asignar revisor · ${t['folio']}', style: const TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    onChanged: (v) => setLocal(() => q = v),
                    decoration: const InputDecoration(
                        hintText: 'Buscar por nombre, institución o línea…',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: lista.map((r) {
                        final correo = (r['correo'] ?? '').toString();
                        final tiene = ya.contains(correo);
                        return CheckboxListTile(
                          dense: true,
                          value: sel.contains(correo),
                          activeColor: cessumRed,
                          title: Text('${r['nombre']}${tiene ? ' (ya asignado)' : ''}', style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${r['institucion']} · ${r['lineas']}', style: const TextStyle(fontSize: 11)),
                          onChanged: tiene ? null : (v) => setLocal(() => v == true ? sel.add(correo) : sel.remove(correo)),
                        );
                      }).toList(),
                    ),
                  ),
                  Text(
                    'Se les avisará por correo con la copia anónima y los botones para aceptar o declinar. '
                    'Plazo: 15 días hábiles desde hoy.',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.3),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: sel.isEmpty ? null : () => Navigator.pop(ctx, true),
                child: Text('Asignar (${sel.length})'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || sel.isEmpty) return;
    setState(() => _ocupado = true);
    try {
      final d = await _post({'accion': 'cessumex_asignar', 'folio': t['folio'], 'revisores': sel.toList()});
      if (d['ok'] != true) throw Exception(d['error'] ?? (d['omitidos'] is List ? (d['omitidos'] as List).join('; ') : 'No se asignó.'));
      _aviso((d['nota'] ?? 'Asignado.').toString());
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _dialogoResolver(Map<String, dynamic> t) async {
    var veredicto = 'Aceptado con cambios';
    final mensaje = TextEditingController();
    final cuota = TextEditingController(text: '500');
    final revisores = ((t['revisores'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((r) => r['entregado'] == true).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Resolver · ${t['folio']}', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((t['titulo'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Dictámenes recibidos: ${revisores.map((r) => '${r['nombre']} → ${r['veredicto']}').join(' · ')}',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context), height: 1.3)),
                  if (t['discrepancia'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('Los dictámenes son opuestos: la convocatoria pide un tercer árbitro, no promediar.',
                          style: TextStyle(fontSize: 12, color: cessumRed, fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ['Aceptado', 'Aceptado con cambios', 'Rechazado'].map((v) {
                      final activo = veredicto == v;
                      return ChoiceChip(
                        label: Text(v, style: TextStyle(fontSize: 12.5, color: activo ? Colors.white : null)),
                        selected: activo,
                        selectedColor: v == 'Rechazado' ? cessumRed : _verde,
                        onSelected: (_) => setLocal(() => veredicto = v),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  if (veredicto != 'Rechazado')
                    TextField(
                      controller: cuota,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Cuota de publicación (MXN): 500 general · 300 CESSUM',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: mensaje,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Nota del comité para el autor (opcional)', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Al resolver se le envía al autor el resultado con los comentarios de los dictaminadores, SIN sus nombres.',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.3),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Resolver y notificar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    try {
      final d = await _post({
        'accion': 'cessumex_resolver',
        'folio': t['folio'],
        'veredicto': veredicto,
        'mensaje': mensaje.text.trim(),
        'cuota': veredicto == 'Rechazado' ? '' : cuota.text.trim(),
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo resolver.');
      _aviso((d['nota'] ?? 'Resuelto.').toString());
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }
}

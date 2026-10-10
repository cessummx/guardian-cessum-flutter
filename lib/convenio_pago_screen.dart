// =====================================================================
//  convenio_pago_screen.dart · CESSUM · (25-sep-2026)
//  ASISTENTE DE CONVENIO DE PAGO (administración)
//
//  Para el alumno que pide plazo para ponerse al corriente. Usa el sistema
//  de convenios que ya existe (firma del alumno en la app, compromisos con
//  fecha, vigilancia de vencidos, PDF) y le agrega un flujo para PAGOS:
//   1. Alumno y adeudo real (vencidos y próximos) + el mensaje del alumno.
//   2. Plan de pagos TOTALMENTE editable: fechas, montos y conceptos.
//      «Repartir en N pagos» o «Proponer con IA»; se verifica que la suma
//      cuadre con el adeudo.
//   3. Redacción con IA: título, antecedentes, cláusulas y respuesta al
//      alumno, todo editable. Las cláusulas de PAGO las escribe el sistema
//      con los montos y fechas exactos del plan, y cada pago queda como
//      compromiso vigilado.
//   4. Crear el convenio (queda para firma del alumno) y, si se quiere,
//      posponer su baja por pago hasta la última fecha del plan.
//
//  Guardián: GET buscar_alumno · GET convenio_pago_datos
//            POST convenio_pago_ia · POST convenio_crear · GET bajas_pago_decidir
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const _verde = Color(0xFF1E7F52);

class _Pago {
  DateTime? fecha;
  final TextEditingController monto;
  final TextEditingController concepto;
  _Pago({this.fecha, String monto = '', String concepto = 'Parcialidad'})
      : monto = TextEditingController(text: monto),
        concepto = TextEditingController(text: concepto);
  double get valor => double.tryParse(monto.text.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
  void dispose() {
    monto.dispose();
    concepto.dispose();
  }
}

class ConvenioPagoScreen extends StatefulWidget {
  /// (26-sep) Puede abrirse ya con un alumno (desde Bloqueos de acceso) y con
  /// un tipo de convenio preseleccionado.
  final String? matriculaInicial;
  final String? plantillaInicial;
  // (29-sep) Cuando se abre desde una solicitud del propio alumno: prellena
  // su mensaje y, al crear el convenio, lo deja vinculado a esa solicitud
  // (el backend la marca resuelta sola — no hay un flujo aparte de "aceptar").
  final String? solicitudId;
  final String? mensajeInicial;
  const ConvenioPagoScreen({super.key, this.matriculaInicial, this.plantillaInicial,
      this.solicitudId, this.mensajeInicial});
  @override
  State<ConvenioPagoScreen> createState() => _ConvenioPagoScreenState();
}

class _ConvenioPagoScreenState extends State<ConvenioPagoScreen> {
  // 1. Alumno
  final _busca = TextEditingController();
  bool _buscando = false;
  List<Map<String, dynamic>> _resultados = [];
  Map<String, dynamic>? _alumno;
  Map<String, dynamic>? _datos;
  bool _cargandoDatos = false;
  // (2-oct-2026) Informe financiero REAL (materias exigibles vs. pagos),
  // distinto del adeudo manual de Vencimientos que ya se mostraba arriba.
  // Es de uso interno del admin: el alumno nunca ve esta pantalla.
  Map<String, dynamic>? _informeFinanciero;
  bool _cargandoInforme = false;
  final _mensaje = TextEditingController();
  final _notas = TextEditingController();
  String _sujeto = 'alumno';

  // 2. Plan
  final List<_Pago> _plan = [];
  int _nPagos = 3;
  int _cadaDias = 15;
  DateTime _desde = DateTime.now().add(const Duration(days: 15));
  bool _iaPlan = false;
  String _analisis = '';

  // 3. Redacción
  // (26-sep) Plantillas por tipo de convenio (base del Guardián + propias).
  List<Map<String, dynamic>> _plantillas = [];
  String _plantillaId = 'falta_pago';
  bool _iaRedactando = false;
  final _titulo = TextEditingController();
  final _terminos = TextEditingController();
  final _respuesta = TextEditingController();
  int _compromisos = 0;

  // 4. Crear
  bool _posponer = true;
  bool _creando = false;
  String _resultado = '';

  @override
  void initState() {
    super.initState();
    _plantillaId = widget.plantillaInicial ?? 'falta_pago';
    _cargarPlantillas();
    final mi = widget.mensajeInicial?.trim() ?? '';
    if (mi.isNotEmpty) _mensaje.text = mi;
    final m = widget.matriculaInicial?.trim() ?? '';
    if (m.isNotEmpty) {
      _busca.text = m;
      WidgetsBinding.instance.addPostFrameCallback((_) => _buscarYElegir(m));
    }
  }

  Future<void> _cargarPlantillas() async {
    try {
      final d = await _get({'accion': 'convenio_plantillas'});
      if (d['ok'] == true && mounted) {
        setState(() => _plantillas = ((d['plantillas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
        _aplicarPlantilla(soloSiPlanVacio: true);
      }
    } catch (_) {
      // (4-oct-2026) Sin plantillas el convenio se arma igual, a mano; solo se avisa para que no parezca que no existen.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudieron cargar los tipos de convenio; puedes armarlo a mano.')));
      }
    }
  }

  Map<String, dynamic>? get _plantilla {
    for (final p in _plantillas) {
      if ('${p['id']}' == _plantillaId) return p;
    }
    return null;
  }

  /// Toma del tipo de convenio el número de pagos y la cadencia sugeridos.
  void _aplicarPlantilla({bool soloSiPlanVacio = false}) {
    final p = _plantilla;
    if (p == null) return;
    if (soloSiPlanVacio && _plan.isNotEmpty) return;
    setState(() {
      _nPagos = ((p['pagos'] ?? 2) as num).toInt().clamp(1, 12);
      _cadaDias = ((p['cadaDias'] ?? 30) as num).toInt() == 15 ? 15 : 30;
    });
  }

  Future<void> _buscarYElegir(String matricula) async {
    try {
      final d = await _get({'accion': 'buscar_alumno', 'q': matricula});
      final lista = ((d['alumnos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final exacto = lista.where((a) => '${a['matricula']}'.replaceAll('.0', '') == matricula).toList();
      // (4-oct-2026) Antes, si la matrícula no coincidía exacto, tomaba el PRIMER resultado de la búsqueda: el convenio
      // podía quedar a nombre de otro alumno sin que nadie lo notara. Ahora solo se elige la coincidencia exacta.
      if (exacto.isNotEmpty) {
        await _elegir(exacto.first);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(lista.isEmpty
                ? 'No encontré la matrícula $matricula. Búscala a mano.'
                : 'La matrícula $matricula no coincide exacto con ningún alumno; elige el correcto en la búsqueda.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo buscar al alumno: $e')));
      }
    }
  }

  Future<void> _guardarPlantilla() async {
    final p = _plantilla ?? {};
    final nombre = TextEditingController(text: '${p['origen']}' == 'propia' ? '${p['nombre'] ?? ''}' : '');
    final cuando = TextEditingController(text: '${p['cuando'] ?? ''}');
    final clausulas = TextEditingController(text: ((p['clausulas'] as List?) ?? []).join('\n'));
    var pagos = ((p['pagos'] ?? _nPagos) as num).toInt();
    var cada = ((p['cadaDias'] ?? _cadaDias) as num).toInt();
    var tono = '${p['tono'] ?? 'acompañamiento'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Guardar como plantilla de convenio', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre del tipo de convenio', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 8),
              TextField(controller: cuando, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Cuándo se usa', border: OutlineInputBorder(), isDense: true)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: pagos.clamp(1, 12),
                    decoration: const InputDecoration(labelText: 'Pagos sugeridos', border: OutlineInputBorder(), isDense: true),
                    items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setLocal(() => pagos = v ?? pagos),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: cada == 15 ? 15 : 30,
                    decoration: const InputDecoration(labelText: 'Cada', border: OutlineInputBorder(), isDense: true),
                    items: const [DropdownMenuItem(value: 15, child: Text('15 días')), DropdownMenuItem(value: 30, child: Text('30 días'))],
                    onChanged: (v) => setLocal(() => cada = v ?? cada),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: ['acompañamiento', 'institucional', 'cálido'].contains(tono) ? tono : 'acompañamiento',
                decoration: const InputDecoration(labelText: 'Tono', border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'acompañamiento', child: Text('Acompañamiento')),
                  DropdownMenuItem(value: 'institucional', child: Text('Institucional')),
                  DropdownMenuItem(value: 'cálido', child: Text('Cálido')),
                ],
                onChanged: (v) => setLocal(() => tono = v ?? tono),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: clausulas,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Cláusulas base (una por renglón)', hintText: 'La IA las adapta a cada caso. Las cláusulas de pago las escribe el sistema.', border: OutlineInputBorder(), isDense: true),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (nombre.text.trim().isEmpty) {
      _aviso('Ponle nombre a la plantilla.', error: true);
      return;
    }
    try {
      final quien = await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';
      final d = await _post({
        'accion': 'convenio_plantilla_guardar',
        'actor': quien,
        if ('${p['origen']}' == 'propia') 'id': '${p['id']}',
        'nombre': nombre.text.trim(),
        'cuando': cuando.text.trim(),
        'pagos': pagos,
        'cadaDias': cada,
        'tono': tono,
        'clausulas': clausulas.text.split('\n').map((c) => c.trim()).where((c) => c.isNotEmpty).toList(),
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      if (!mounted) return;
      setState(() {
        _plantillas = ((d['plantillas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _plantillaId = '${d['id']}';
      });
      _aviso('Plantilla «${d['nombre']}» guardada.');
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  @override
  void dispose() {
    for (final c in [_busca, _mensaje, _notas, _titulo, _terminos, _respuesta]) {
      c.dispose();
    }
    for (final p in _plan) {
      p.dispose();
    }
    super.dispose();
  }

  // ---------------- utilidades ----------------
  Future<Map<String, dynamic>> _get(Map<String, String> qp, {int segundos = 90}) async {
    final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: qp)).timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int segundos = 150}) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
        .timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _aviso(String t, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : _verde,
      duration: const Duration(seconds: 5),
      content: Text(t),
    ));
  }

  String _pesos(num n) {
    final entero = n.truncate();
    final cent = ((n - entero) * 100).round().abs().toString().padLeft(2, '0');
    final t = entero.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      if (i > 0 && (t.length - i) % 3 == 0) b.write(',');
      b.write(t[i]);
    }
    return '${n < 0 ? '-' : ''}\$$b.$cent';
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _corta(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  double get _total => ((_datos?['total'] ?? 0) as num).toDouble();
  double get _sumaPlan => _plan.fold(0.0, (a, p) => a + p.valor);

  // ---------------- 1. alumno ----------------
  Future<void> _buscar() async {
    final q = _busca.text.trim();
    if (q.length < 2) return;
    setState(() => _buscando = true);
    try {
      final d = await _get({'accion': 'buscar_alumno', 'q': q});
      _resultados = ((d['alumnos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (d['ok'] != true) _aviso('${d['error'] ?? 'Sin resultados.'}', error: true);
    } catch (e) {
      _aviso('No se pudo buscar.', error: true);
    }
    if (mounted) setState(() => _buscando = false);
  }

  Future<void> _elegir(Map<String, dynamic> a) async {
    setState(() {
      _alumno = a;
      _resultados = [];
      _datos = null;
      _cargandoDatos = true;
      _sujeto = RegExp(r'a$', caseSensitive: false).hasMatch('${a['nombre']}'.split(' ').first) ? 'alumna' : 'alumno';
      for (final p in _plan) {
        p.dispose();
      }
      _plan.clear();
      _titulo.clear();
      _terminos.clear();
      _respuesta.clear();
      _resultado = '';
      _analisis = '';
    });
    try {
      final d = await _get({'accion': 'convenio_pago_datos', 'matricula': '${a['matricula']}'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo leer el adeudo.');
      _datos = d;
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _cargandoDatos = false);

    // (2-oct-2026) Informe financiero real, en paralelo lógico (después del
    // adeudo manual, que es lo que bloquea el paso 2). Si falla, no se
    // interrumpe el flujo del convenio: solo no se muestra esa sección.
    if (mounted) setState(() => _cargandoInforme = true);
    try {
      final quienIF = await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';
      final di = await _get({
        'accion': 'informe_financiero_decision',
        'matricula': '${a['matricula']}',
        'actor': quienIF,
      });
      if (mounted) setState(() => _informeFinanciero = di['ok'] == true ? di : null);
    } catch (_) {
      if (mounted) setState(() => _informeFinanciero = null);
    }
    if (mounted) setState(() => _cargandoInforme = false);
  }

  // ---------------- 2. plan ----------------
  void _repartir() {
    if (_total <= 0) {
      _aviso('No hay adeudo que repartir.', error: true);
      return;
    }
    final base = (_total / _nPagos * 100).floor() / 100;
    setState(() {
      for (final p in _plan) {
        p.dispose();
      }
      _plan.clear();
      for (var i = 0; i < _nPagos; i++) {
        final ultimo = i == _nPagos - 1;
        final monto = ultimo ? ((_total - base * (_nPagos - 1)) * 100).round() / 100 : base;
        _plan.add(_Pago(
          fecha: _desde.add(Duration(days: _cadaDias * i)),
          monto: monto.toStringAsFixed(2),
          concepto: 'Parcialidad ${i + 1} de $_nPagos',
        ));
      }
    });
  }

  Future<void> _proponerIa() async {
    if (_alumno == null) return;
    setState(() => _iaPlan = true);
    try {
      final d = await _post({
        'accion': 'convenio_pago_ia',
        'modo': 'plan',
        'matricula': '${_alumno!['matricula']}',
        'mensaje': _mensaje.text.trim(),
        'notas': _notas.text.trim(),
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo proponer.');
      setState(() {
        for (final p in _plan) {
          p.dispose();
        }
        _plan.clear();
        for (final x in ((d['plan'] as List?) ?? [])) {
          final m = Map<String, dynamic>.from(x as Map);
          _plan.add(_Pago(
            fecha: DateTime.tryParse('${m['fecha']}'),
            monto: ((m['monto'] ?? 0) as num).toStringAsFixed(2),
            concepto: '${m['concepto'] ?? 'Parcialidad'}',
          ));
        }
        _analisis = '${d['analisis'] ?? ''}${'${d['razon'] ?? ''}'.isNotEmpty ? '\n\n${d['razon']}' : ''}'
            '${((d['ajuste'] ?? 0) as num) != 0 ? '\n\nSe ajustó el último pago en ${_pesos((d['ajuste'] as num))} para que la suma cuadre con el adeudo.' : ''}';
      });
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _iaPlan = false);
  }

  List<String> get _problemasPlan {
    final out = <String>[];
    if (_plan.isEmpty) out.add('El plan no tiene pagos.');
    final hoy = DateTime.now();
    DateTime? previa;
    for (var i = 0; i < _plan.length; i++) {
      final p = _plan[i];
      if (p.fecha == null) out.add('El pago ${i + 1} no tiene fecha.');
      if (p.valor <= 0) out.add('El pago ${i + 1} no tiene monto.');
      if (p.fecha != null && p.fecha!.isBefore(DateTime(hoy.year, hoy.month, hoy.day))) out.add('El pago ${i + 1} tiene una fecha pasada.');
      if (p.fecha != null && previa != null && p.fecha!.isBefore(previa)) out.add('Las fechas no están en orden (pago ${i + 1}).');
      if (p.fecha != null) previa = p.fecha;
    }
    return out;
  }

  // ---------------- 3. redacción ----------------
  Future<void> _redactar() async {
    final prob = _problemasPlan;
    if (prob.isNotEmpty) {
      _aviso(prob.first, error: true);
      return;
    }
    setState(() => _iaRedactando = true);
    try {
      final d = await _post({
        'accion': 'convenio_pago_ia',
        'modo': 'redactar',
        'matricula': '${_alumno!['matricula']}',
        'mensaje': _mensaje.text.trim(),
        'notas': _notas.text.trim(),
        'sujeto': _sujeto,
        'plantilla': _plantillaId,
        'plan': _plan
            .map((p) => {'fecha': _iso(p.fecha!), 'monto': p.valor, 'concepto': p.concepto.text.trim().isEmpty ? 'Parcialidad' : p.concepto.text.trim()})
            .toList(),
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo redactar.');
      setState(() {
        _titulo.text = '${d['titulo'] ?? ''}';
        _terminos.text = '${d['terminos'] ?? ''}';
        _respuesta.text = '${d['respuesta'] ?? ''}';
        _compromisos = ((d['compromisosDetectados'] ?? 0) as num).toInt();
      });
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _iaRedactando = false);
  }

  // ---------------- 4. crear ----------------
  Future<void> _crear() async {
    if (_titulo.text.trim().isEmpty || _terminos.text.trim().isEmpty) {
      _aviso('Falta redactar el convenio.', error: true);
      return;
    }
    final a = _alumno!;
    final ultima = _plan.where((p) => p.fecha != null).map((p) => p.fecha!).fold<DateTime?>(null, (m, f) => m == null || f.isAfter(m) ? f : m);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Crear el convenio?', style: TextStyle(fontSize: 17)),
        content: Text(
          'Se crea el convenio de ${a['nombre']} con ${_plan.length} pago(s) por ${_pesos(_sumaPlan)}. '
          'Quedará en la app para que lo firme; cada pago queda como compromiso vigilado. '
          'No se envía ningún correo: para avisarle, use «Promover» en Convenios o envíele la respuesta por WhatsApp.'
          '${_posponer && ultima != null ? '\n\nSi está en la bandeja de bajas por pago, su baja se pospone hasta el ${_corta(ultima)}.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear convenio'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _creando = true);
    final partes = <String>[];
    try {
      final quien = await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';
      final d = await _post({
        'accion': 'convenio_crear',
        'titulo': _titulo.text.trim(),
        'terminos': _terminos.text.trim(),
        'programa': '',
        'generacion': '',
        'grupo': '',
        'matriculas': '${a['matricula']}',
        'firmantesInst': '',
        'actor': quien,
        if (widget.solicitudId != null) 'solicitudId': widget.solicitudId,
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo crear el convenio.');
      partes.add('Convenio ${d['id'] ?? ''} creado: ${a['nombre']} lo verá en la app para firmarlo.');
      if (_posponer && ultima != null) {
        try {
          final r = await _get({
            'accion': 'bajas_pago_decidir',
            'actor': quien,
            'matricula': '${a['matricula']}',
            'programa': '${_datos?['alumno']?['programa'] ?? a['programa'] ?? ''}',
            'decision': 'posponer',
            'hasta': _iso(ultima),
            'motivo': 'Convenio de pago ${d['id'] ?? ''}: ${_plan.length} pago(s), último el ${_corta(ultima)}.',
          });
          partes.add(r['ok'] == true
              ? 'Baja por pago pospuesta hasta el ${_corta(ultima)}.'
              : 'La baja por pago no se pospuso: ${r['error'] ?? 'el alumno no está en la bandeja'}.');
        } catch (_) {
          partes.add('No se pudo posponer la baja por pago; puede hacerlo desde Bajas por pago.');
        }
      }
      setState(() => _resultado = partes.join('\n'));
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _creando = false);
  }

  // ---------------- vista ----------------
  Widget _paso(String n, String titulo, Widget hijo, {bool activo = true}) {
    return Opacity(
      opacity: activo ? 1 : 0.45,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cessumMuted(context).withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(radius: 13, backgroundColor: cessumRed, child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          IgnorePointer(ignoring: !activo, child: hijo),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hayAlumno = _alumno != null && _datos != null;
    final hayPlan = _plan.isNotEmpty;
    final hayTexto = _terminos.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Convenio de pago'),
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        _paso('1', 'Alumno y adeudo', _pasoAlumno()),
        _paso('2', 'Plan de pagos', _pasoPlan(), activo: hayAlumno),
        _paso('3', 'Convenio y respuesta', _pasoRedaccion(), activo: hayAlumno && hayPlan),
        _paso('4', 'Crear el convenio', _pasoCrear(), activo: hayTexto),
      ]),
    );
  }

  Widget _pasoAlumno() {
    final d = _datos;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _busca,
            onSubmitted: (_) => _buscar(),
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.search), hintText: 'Nombre o matrícula del alumno'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: _buscando ? null : _buscar,
          child: Text(_buscando ? '…' : 'Buscar'),
        ),
      ]),
      for (final a in _resultados.take(12))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${a['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${a['matricula']} · ${a['programa']} · ${a['generacion']} · ${a['estatus']}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _elegir(a),
        ),
      if (_cargandoDatos) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator(color: cessumRed)),
      if (_alumno != null && d != null) ...[
        const SizedBox(height: 8),
        Text('${_alumno!['nombre']} · ${_alumno!['matricula']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        Text('${d['alumno']?['programa'] ?? ''} · ${d['alumno']?['generacion'] ?? ''}', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 6, children: [
          _cifra('Vencido', d['vencido'], cessumRed),
          _cifra('Próximo', d['proximo'], cessumGold),
          _cifra('Total', d['total'], _verde),
        ]),
        const SizedBox(height: 8),
        for (final p in ((d['pendientes'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)))
          Text('• ${p['concepto']} · ${_pesos(((p['monto'] ?? 0) as num))} · límite ${p['fecha']}${p['estatus'] == 'Vencido' ? ' · VENCIDO' : ''}',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: p['estatus'] == 'Vencido' ? cessumRed : null)),
        if (((d['pendientes'] as List?) ?? []).isEmpty)
          const Text('No tiene pagos pendientes registrados.', style: TextStyle(fontSize: 12.5, color: _verde)),
        const SizedBox(height: 10),
        _seccionInformeFinanciero(),
        const SizedBox(height: 10),
        TextField(
          controller: _mensaje,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Mensaje del alumno (péguelo aquí)', hintText: 'Lo que escribió por WhatsApp o correo'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notas,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Notas de Administración (opcional)', hintText: 'Ej. máximo 3 pagos; primer pago después del 15 de octubre'),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('En el convenio decir: ', style: TextStyle(fontSize: 13)),
          ChoiceChip(label: const Text('El alumno'), selected: _sujeto == 'alumno', onSelected: (_) => setState(() => _sujeto = 'alumno')),
          const SizedBox(width: 6),
          ChoiceChip(label: const Text('La alumna'), selected: _sujeto == 'alumna', onSelected: (_) => setState(() => _sujeto = 'alumna')),
        ]),
      ],
    ]);
  }

  // (2-oct-2026) INFORME FINANCIERO VINCULADO — de uso interno: el alumno
  // nunca ve esta pantalla (es el asistente del admin). Es el cálculo REAL
  // (materias exigibles vs. pagos), distinto del adeudo manual de
  // Vencimientos que ya se mostraba arriba como las cifras Vencido/Próximo/
  // Total. Colapsado por defecto para no saturar el paso 1; el admin lo
  // abre si quiere el desglose completo antes de decidir el plan.
  Widget _seccionInformeFinanciero() {
    if (_cargandoInforme) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed)),
          SizedBox(width: 8),
          Text('Calculando informe financiero…', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );
    }
    final inf = _informeFinanciero;
    if (inf == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('No se pudo calcular el informe financiero automático para este alumno.',
            style: TextStyle(fontSize: 11.5, color: Colors.black45, fontStyle: FontStyle.italic)),
      );
    }
    final ac = Map<String, dynamic>.from(inf['adeudoCalculado'] as Map? ?? {});
    final calculable = ac['calculable'] == true;
    final materias = ((ac['detalleMaterias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final anomalias = ((ac['anomalias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final avisos = ((ac['avisos'] as List?) ?? []).map((e) => '$e').toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          title: Row(children: [
            const Icon(Icons.fact_check_outlined, size: 16, color: Color(0xFF1565C0)),
            const SizedBox(width: 6),
            Text(
                calculable
                    ? 'Informe financiero (cálculo real): ${_pesos((ac['adeudoCalculado'] ?? 0) as num)}'
                    : 'Informe financiero: no calculable automáticamente',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF1565C0))),
          ]),
          subtitle: calculable
              ? Text('${ac['materiasFaltantes'] ?? 0} de ${ac['materiasExigibles'] ?? 0} materia(s) exigibles sin cubrir · uso interno, el alumno no ve esto',
                  style: TextStyle(fontSize: 11, color: cessumMuted(context)))
              : Text('${inf['nota'] ?? ''}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (calculable) ...[
                  Text('Modo de pago: ${ac['modoPago'] ?? '—'} · costo por materia: ${_pesos((ac['costoPorMateria'] ?? 0) as num)}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (materias.isNotEmpty) ...[
                    const Text('Materias exigibles a la fecha:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    for (final m in materias)
                      Text('  • ${m['denominacion'] ?? ''} (${m['periodo'] ?? ''}) — ${m['estado'] ?? ''}',
                          style: const TextStyle(fontSize: 11, height: 1.4)),
                    const SizedBox(height: 6),
                  ],
                  if (anomalias.isNotEmpty) ...[
                    const Text('Anomalías detectadas:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cessumRed)),
                    for (final a2 in anomalias)
                      Text('  • [${a2['tipo'] ?? ''}] ${a2['fecha'] ?? ''} — ${a2['detalle'] ?? ''}',
                          style: const TextStyle(fontSize: 11, height: 1.4, color: cessumRed)),
                    const SizedBox(height: 6),
                  ],
                  if (avisos.isNotEmpty) ...[
                    const Text('Avisos:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    for (final av in avisos)
                      Text('  • $av', style: const TextStyle(fontSize: 11, height: 1.4)),
                  ],
                ] else
                  Text('${inf['nota'] ?? 'No se pudo calcular automáticamente. Revisa el adeudo manual arriba.'}',
                      style: const TextStyle(fontSize: 11.5)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cifra(String t, dynamic v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_pesos(((v ?? 0) as num)), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c)),
          Text(t, style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ]),
      );

  Widget _pasoPlan() {
    final dif = ((_total - _sumaPlan) * 100).round() / 100;
    final prob = _problemasPlan;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Repartir en', style: TextStyle(fontSize: 13)),
        DropdownButton<int>(
          value: _nPagos,
          items: [2, 3, 4, 5, 6].map((n) => DropdownMenuItem(value: n, child: Text('$n pagos'))).toList(),
          onChanged: (v) => setState(() => _nPagos = v ?? 3),
        ),
        DropdownButton<int>(
          value: _cadaDias,
          items: const [DropdownMenuItem(value: 15, child: Text('cada 15 días')), DropdownMenuItem(value: 30, child: Text('cada 30 días'))],
          onChanged: (v) => setState(() => _cadaDias = v ?? 15),
        ),
        OutlinedButton(
          onPressed: () async {
            // (4-oct-2026) Si «desde» quedó en el pasado, showDatePicker truena (initialDate antes de firstDate).
            final hoy = DateUtils.dateOnly(DateTime.now());
            final f = await showDatePicker(context: context, initialDate: _desde.isBefore(hoy) ? hoy : _desde, firstDate: hoy, lastDate: hoy.add(const Duration(days: 365)));
            if (f != null && mounted) setState(() => _desde = f);
          },
          child: Text('desde el ${_corta(_desde)}'),
        ),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: _repartir, child: const Text('Repartir')),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: cessumGold),
          onPressed: _iaPlan ? null : _proponerIa,
          icon: _iaPlan
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: cessumGold))
              : const Icon(Icons.auto_awesome, size: 16),
          label: Text(_iaPlan ? 'Proponiendo…' : 'Proponer con IA'),
        ),
      ]),
      if (_analisis.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(_analisis, style: const TextStyle(fontSize: 12.8, height: 1.45)),
        ),
      const SizedBox(height: 8),
      for (var i = 0; i < _plan.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 22, child: Text('${i + 1}.', style: const TextStyle(fontWeight: FontWeight.w700))),
            OutlinedButton(
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                // (4-oct-2026) Una fecha propuesta por la IA o guardada antes puede estar en el pasado: se acota a hoy.
                final hoy = DateUtils.dateOnly(DateTime.now());
                final ini = _plan[i].fecha ?? hoy.add(const Duration(days: 7));
                final f = await showDatePicker(
                    context: context,
                    initialDate: ini.isBefore(hoy) ? hoy : (ini.isAfter(hoy.add(const Duration(days: 365))) ? hoy.add(const Duration(days: 365)) : ini),
                    firstDate: hoy,
                    lastDate: hoy.add(const Duration(days: 365)));
                if (f != null && mounted) setState(() => _plan[i].fecha = f);
              },
              child: Text(_plan[i].fecha == null ? 'Fecha' : _corta(_plan[i].fecha!)),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _plan[i].monto,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), prefixText: '\$ '),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _plan[i].concepto,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'Concepto'),
              ),
            ),
            IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _plan.removeAt(i).dispose()),
            ),
          ]),
        ),
      TextButton.icon(
        onPressed: () => setState(() => _plan.add(_Pago(fecha: _plan.isNotEmpty ? _plan.last.fecha?.add(Duration(days: _cadaDias)) : _desde))),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Agregar pago'),
      ),
      if (_plan.isNotEmpty) ...[
        Text('Suma del plan: ${_pesos(_sumaPlan)} · adeudo: ${_pesos(_total)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: dif.abs() < 0.01 ? _verde : cessumRed)),
        if (dif.abs() >= 0.01)
          Text(dif > 0 ? 'Faltan ${_pesos(dif)} para cubrir el adeudo (puede ser intencional).' : 'El plan supera el adeudo por ${_pesos(-dif)}.',
              style: const TextStyle(fontSize: 12, color: cessumRed)),
        for (final p in prob) Text('• $p', style: const TextStyle(fontSize: 12, color: cessumRed)),
      ],
    ]);
  }

  Widget _pasoRedaccion() {
    final p = _plantilla;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // (26-sep) Tipo de convenio: decide el tono y las cláusulas base.
      DropdownButtonFormField<String>(
        value: _plantillas.any((x) => '${x['id']}' == _plantillaId) ? _plantillaId : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Tipo de convenio', border: OutlineInputBorder(), isDense: true),
        items: [
          for (final x in _plantillas)
            DropdownMenuItem(value: '${x['id']}', child: Text('${x['nombre']}${'${x['origen']}' == 'propia' ? '  · propia' : ''}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() => _plantillaId = v);
          _aplicarPlantilla(soloSiPlanVacio: true);
        },
      ),
      if (p != null && '${p['cuando'] ?? ''}'.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text('${p['cuando']}  ·  sugiere ${p['pagos']} pago(s) cada ${p['cadaDias']} días',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _guardarPlantilla,
          icon: const Icon(Icons.bookmark_add_outlined, size: 16),
          label: Text('${p != null && '${p['origen']}' == 'propia' ? 'Editar' : 'Guardar como'} plantilla'),
        ),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: cessumRed),
        onPressed: _iaRedactando ? null : _redactar,
        icon: _iaRedactando
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome, size: 18),
        label: Text(_iaRedactando ? 'Redactando…' : (_terminos.text.isEmpty ? 'Redactar con IA' : 'Volver a redactar')),
      ),
      const SizedBox(height: 6),
      Text('Las cláusulas de pago las escribe el sistema con los montos y fechas exactos del plan; la IA redacta el resto. Todo es editable.',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      if (_terminos.text.isNotEmpty) ...[
        const SizedBox(height: 10),
        TextField(controller: _titulo, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Título')),
        const SizedBox(height: 8),
        TextField(
          controller: _terminos,
          minLines: 8,
          maxLines: 20,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Términos del convenio (lo que el alumno firma)'),
        ),
        const SizedBox(height: 4),
        Text('Compromisos de pago con fecha que se vigilarán: $_compromisos',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _compromisos == _plan.length ? _verde : cessumGold)),
        const SizedBox(height: 10),
        TextField(
          controller: _respuesta,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Respuesta para el alumno (WhatsApp)'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _respuesta.text));
              if (mounted) _aviso('Respuesta copiada.');
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copiar respuesta'),
          ),
        ),
      ],
    ]);
  }

  Widget _pasoCrear() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _posponer,
        onChanged: (v) => setState(() => _posponer = v == true),
        title: const Text('Si está en la bandeja de bajas por pago, posponer su baja hasta la última fecha del plan', style: TextStyle(fontSize: 13)),
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: _verde),
        onPressed: _creando || _resultado.isNotEmpty ? null : _crear,
        icon: _creando
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.task_alt, size: 18),
        label: Text(_creando ? 'Creando…' : 'Crear convenio para firma'),
      ),
      if (_resultado.isNotEmpty)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: _verde.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
          child: Text(_resultado, style: const TextStyle(fontSize: 13, height: 1.45)),
        ),
    ]);
  }
}

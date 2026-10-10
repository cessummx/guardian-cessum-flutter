import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// V1083: listado y notificación administrativa de un acta por corte exacto.
/// No ejecuta lotes multi-acta ni reintentos automáticos. Una interrupción
/// puede dejar un envío incierto, que requiere conciliación en el servidor.
class BoletasPendientesScreen extends StatefulWidget {
  const BoletasPendientesScreen({super.key});

  @override
  State<BoletasPendientesScreen> createState() =>
      _BoletasPendientesScreenState();
}

class _BoletasPendientesScreenState extends State<BoletasPendientesScreen> {
  final _desde = TextEditingController();
  final _hasta = TextEditingController();
  final _ciclo = TextEditingController();
  final _periodo = TextEditingController();

  bool _cargando = false;
  bool _enviando = false;
  bool _resultadoIncierto = false;
  String? _error;
  String? _aviso;
  String? _consultaCorte;
  int? _seleccion;
  int _totalActas = 0;
  int _totalAlumnos = 0;
  List<Map<String, dynamic>> _actas = [];

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _desde.text = _fmt(DateTime(hoy.year, hoy.month - 3, 1));
    _hasta.text = _fmt(hoy);
    // Ciclo/periodo NO se infieren de la fecha o la generación.
  }

  @override
  void dispose() {
    _desde.dispose();
    _hasta.dispose();
    _ciclo.dispose();
    _periodo.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _corteActual => '${_ciclo.text.trim()}||${_periodo.text.trim()}||'
      '${_desde.text.trim()}||${_hasta.text.trim()}';

  void _invalidar() {
    if (!mounted || _enviando) return;
    setState(() {
      _consultaCorte = null;
      _seleccion = null;
      _actas = [];
      _totalActas = 0;
      _totalAlumnos = 0;
      _aviso = null;
      _error = null;
    });
  }

  Map<String, String> _params(String accion) => {
    'accion': accion,
    'ciclo': _ciclo.text.trim(),
    'periodo': _periodo.text.trim(),
    if (_desde.text.trim().isNotEmpty) 'desde': _desde.text.trim(),
    if (_hasta.text.trim().isNotEmpty) 'hasta': _hasta.text.trim(),
  };

  String? _validarCorte() {
    if (_ciclo.text.trim().isEmpty || _periodo.text.trim().isEmpty) {
      return 'Es obligatorio indicar el ciclo y periodo exactos de Calificaciones.';
    }
    final f = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if ((_desde.text.trim().isNotEmpty && !f.hasMatch(_desde.text.trim())) ||
        (_hasta.text.trim().isNotEmpty && !f.hasMatch(_hasta.text.trim()))) {
      return 'Las fechas deben tener formato AAAA-MM-DD.';
    }
    return null;
  }

  Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final url = Uri.parse(guardianUrl).replace(queryParameters: params);
    final res = await http.get(url).timeout(const Duration(seconds: 100));
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}. Consulta el estado antes de repetir.');
    }
    final body = jsonDecode(res.body);
    if (body is! Map) throw const FormatException('Respuesta del servidor inválida');
    return Map<String, dynamic>.from(body);
  }

  Future<void> _detectar() async {
    if (_cargando || _enviando) return;
    final validacion = _validarCorte();
    if (validacion != null) {
      setState(() => _error = validacion);
      return;
    }
    final marca = _corteActual;
    setState(() {
      _cargando = true;
      _error = null;
      _aviso = null;
      _actas = [];
      _seleccion = null;
      _consultaCorte = null;
    });
    try {
      final data = await _get(_params('boletas_acta_pendientes'));
      if (!mounted) return;
      if (data['ok'] != true) {
        throw Exception((data['error'] ?? 'No se pudo consultar.').toString());
      }
      final lista = (data['actas'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        _actas = lista;
        _totalActas = (data['totalActas'] as num?)?.toInt() ?? lista.length;
        _totalAlumnos = (data['totalAlumnos'] as num?)?.toInt() ?? 0;
        _consultaCorte = marca;
        _cargando = false;
        _aviso = 'Estas son candidatas según las marcas históricas. '
            'El servidor puede retener algunas por conflictos o envíos inciertos.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error de consulta: $e';
        _cargando = false;
      });
    }
  }

  Future<void> _enviarSeleccionada() async {
    if (_cargando || _enviando || _resultadoIncierto ||
        _consultaCorte == null || _consultaCorte != _corteActual ||
        _seleccion == null || _seleccion! >= _actas.length) return;
    final acta = _actas[_seleccion!];
    final datos = <String, String>{
      ..._params('boletas_acta_notificar'),
      'programa': (acta['programa'] ?? '').toString().trim(),
      'generacion': (acta['generacion'] ?? '').toString().trim(),
      'grupo': (acta['grupo'] ?? '').toString().trim(),
      'materia': (acta['materia'] ?? '').toString().trim(),
      if ((acta['clave'] ?? '').toString().trim().isNotEmpty)
        'clave': (acta['clave'] ?? '').toString().trim(),
    };
    if (['programa', 'generacion', 'grupo', 'materia', 'ciclo', 'periodo']
        .any((k) => (datos[k] ?? '').isEmpty)) {
      setState(() => _error = 'Acta o corte incompleto. No se envió nada.');
      return;
    }
    setState(() {
      _enviando = true;
      _error = null;
      _aviso = 'Comprobando vista previa en servidor…';
    });
    try {
      // Primera petición obligatoriamente SIN confirmar: solo vista previa.
      final vista = await _get(datos);
      if (!mounted) return;
      if (vista['ok'] != true || vista['previa'] != true) {
        throw Exception((vista['error'] ?? 'Vista previa no verificada.').toString());
      }
      final pendientes = (vista['pendientes'] as num?)?.toInt() ?? -1;
      if (pendientes < 0) throw const FormatException('Vista previa sin conteo');
      if (pendientes == 0) {
        setState(() => _aviso = 'Sin candidatas en este corte. No se envió nada.');
        return;
      }
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar un acta y un corte'),
          content: Text('Programa: ${datos['programa']}\n'
              'Generación: ${datos['generacion']} · Grupo: ${datos['grupo']}\n'
              'Materia: ${datos['materia']}\n'
              'Ciclo: ${datos['ciclo']} · Periodo: ${datos['periodo']}\n\n'
              '$pendientes fila(s) candidata(s), de las cuales se intentarán '
              'como máximo 10 en esta operación. El servidor retendrá casos '
              'históricos o inciertos.\n\n'
              'Si se corta la conexión, no repitas el envío sin conciliación.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar una tanda'),
            ),
          ],
        ),
      );
      if (confirmar != true || !mounted) return;
      setState(() => _aviso = 'Ejecutando una sola tanda; no cierres esta pantalla…');
      // NUNCA repetir automáticamente, ni por tiempo ni por resultados parciales.
      _resultadoIncierto = true;
      final res = await _get({...datos, 'confirmar': 'ENVIAR', 'max': '10'});
      if (!mounted) return;
      if (res['ok'] != true) {
        throw Exception((res['error'] ?? 'Resultado no confirmado.').toString());
      }
      _resultadoIncierto = false; // Respuesta recibida; otro envío exige nueva detección.
      final enviados = (res['correosEnviados'] as num?)?.toInt() ?? 0;
      setState(() {
        _consultaCorte = null;
        _seleccion = null;
        _actas = [];
        _aviso = 'El servidor reportó $enviados correo(s) enviados en esta tanda. '
            'Otros registros pueden estar retenidos: consulta la cola antes de continuar.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Operación no confirmada: $e. '
          'Si se intentó enviar, concilia en administración antes de repetir.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Boletas por acta y corte'),
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Consulta únicamente un ciclo y periodo exactos. '
                  'Las marcas antiguas o envíos inciertos no se reenvían automáticamente.',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(
                  controller: _ciclo,
                  enabled: !_enviando,
                  onChanged: (_) => _invalidar(),
                  decoration: const InputDecoration(
                    labelText: 'Ciclo académico exacto',
                    border: OutlineInputBorder(), isDense: true,
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: _periodo,
                  enabled: !_enviando,
                  onChanged: (_) => _invalidar(),
                  decoration: const InputDecoration(
                    labelText: 'Periodo exacto del acta',
                    border: OutlineInputBorder(), isDense: true,
                  ),
                )),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(
                  controller: _desde,
                  enabled: !_enviando,
                  onChanged: (_) => _invalidar(),
                  decoration: const InputDecoration(
                    labelText: 'Término desde (AAAA-MM-DD)',
                    border: OutlineInputBorder(), isDense: true,
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: _hasta,
                  enabled: !_enviando,
                  onChanged: (_) => _invalidar(),
                  decoration: const InputDecoration(
                    labelText: 'Término hasta (AAAA-MM-DD)',
                    border: OutlineInputBorder(), isDense: true,
                  ),
                )),
              ]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: (_cargando || _enviando) ? null : _detectar,
                icon: const Icon(Icons.search),
                label: const Text('Consultar candidatas del corte'),
              )),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: cessumRed)),
              ),
              if (_aviso != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_aviso!, style: TextStyle(color: cessumMuted(context), fontSize: 12)),
              ),
              if (_resultadoIncierto) const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Reenvíos bloqueados en esta sesión por resultado incierto. '
                    'Consulta el registro de la cola con administración.',
                    style: TextStyle(color: cessumRed, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          if (_cargando)
            const Expanded(child: Center(child: CircularProgressIndicator(color: cessumRed)))
          else
            Expanded(child: _lista(context)),
        ]),
      ),
    );
  }

  Widget _lista(BuildContext context) {
    if (_consultaCorte == null) {
      return Center(child: Text('Indica el corte y consulta las actas.',
          style: TextStyle(color: cessumMuted(context))));
    }
    if (_actas.isEmpty) {
      return Center(child: Text('No hay candidatas registradas con esos filtros.',
          style: TextStyle(color: cessumMuted(context))));
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text('$_totalActas acta(s) · $_totalAlumnos fila(s) candidatas. '
            'Elige UNA acta para consultar vista previa antes de enviar.',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      Expanded(child: ListView.separated(
        itemCount: _actas.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final acta = _actas[i];
          return RadioListTile<int>(
            value: i,
            groupValue: _seleccion,
            onChanged: _enviando ? null : (v) => setState(() => _seleccion = v),
            title: Text((acta['materia'] ?? '').toString()),
            subtitle: Text('${acta['programa'] ?? ''} · Gen. ${acta['generacion'] ?? ''} '
                '· Grupo ${acta['grupo'] ?? ''}\nCiclo ${_ciclo.text} · Periodo ${_periodo.text} '
                '· ${acta['alumnos'] ?? 0} candidata(s)'),
            activeColor: cessumRed,
          );
        },
      )),
      SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(width: double.infinity, child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: cessumRed, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: (_enviando || _resultadoIncierto || _seleccion == null)
              ? null : _enviarSeleccionada,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(_enviando ? 'Procesando…' : 'Vista previa de un acta'),
        )),
      )),
    ]);
  }
}

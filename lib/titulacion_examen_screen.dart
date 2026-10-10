import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Fase 2 de titulación (admin): asignar sínodos, programar el examen de
/// grado (Meet o presencial) y registrar el resultado para generar el acta.
class TitulacionExamenScreen extends StatefulWidget {
  final Map<String, dynamic> expediente;
  const TitulacionExamenScreen({super.key, required this.expediente});

  @override
  State<TitulacionExamenScreen> createState() =>
      _TitulacionExamenScreenState();
}

class _TitulacionExamenScreenState extends State<TitulacionExamenScreen> {
  late Map<String, dynamic> _e;
  List<Map<String, dynamic>> _docentes = [];
  bool _guardando = false;

  // sínodos
  Map<String, dynamic>? _pres, _sec, _voc;
  // examen
  String _modalidad = 'Virtual';
  final _fecha = TextEditingController();
  final _horaIni = TextEditingController(text: '10:00');
  final _horaFin = TextEditingController(text: '11:30');
  final _lugar = TextEditingController();
  // resultado
  String _resultado = 'Aprobado';

  @override
  void initState() {
    super.initState();
    _e = Map<String, dynamic>.from(widget.expediente);
    _cargarDocentes();
    _precargar();
  }

  @override
  void dispose() {
    _fecha.dispose();
    _horaIni.dispose();
    _horaFin.dispose();
    _lugar.dispose();
    super.dispose();
  }

  void _precargar() {
    if (((_e['examenModalidad'] ?? '') as String).isNotEmpty) {
      _modalidad = _e['examenModalidad'] as String;
    }
    _fecha.text = (_e['examenFecha'] ?? '') as String;
    if (((_e['examenLugar'] ?? '') as String).isNotEmpty &&
        _modalidad == 'Presencial') {
      _lugar.text = _e['examenLugar'] as String;
    }
  }

  Future<void> _cargarDocentes() async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=docentes_lista'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && mounted) {
        setState(() {
          _docentes = (data['docentes'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          // precargar sínodos ya asignados
          _pres = _buscaDoc(_e['presidente']);
          _sec = _buscaDoc(_e['secretario']);
          _voc = _buscaDoc(_e['vocal']);
        });
      }
    } catch (_) {}
  }

  Map<String, dynamic>? _buscaDoc(dynamic nombre) {
    final n = (nombre ?? '').toString().trim();
    if (n.isEmpty) return null;
    for (final d in _docentes) {
      if ((d['nombre'] ?? '') == n) return d;
    }
    return null;
  }

  Future<bool> _post(Map<String, dynamic> payload) async {
    setState(() => _guardando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _guardarSinodos() async {
    if (_pres == null || _sec == null || _voc == null) {
      _aviso('Selecciona presidente, secretario y vocal.');
      return;
    }
    final ok = await _post({
      'accion': 'titulacion_sinodos',
      'folio': _e['folio'],
      'presidente': {'nombre': _pres!['nombre'], 'correo': _pres!['correo']},
      'secretario': {'nombre': _sec!['nombre'], 'correo': _sec!['correo']},
      'vocal': {'nombre': _voc!['nombre'], 'correo': _voc!['correo']},
    });
    if (ok && mounted) {
      _aviso('Sínodos asignados y notificados.', ok: true);
      setState(() => _e['etapa'] = 'Sínodos asignados');
    }
  }

  Future<void> _programarExamen() async {
    if (_fecha.text.trim().isEmpty) {
      _aviso('Indica la fecha (dd/mm/aaaa).');
      return;
    }
    if (_modalidad == 'Presencial' && _lugar.text.trim().isEmpty) {
      _aviso('Indica el lugar del examen presencial.');
      return;
    }
    final ok = await _post({
      'accion': 'titulacion_examen',
      'folio': _e['folio'],
      'modalidad': _modalidad,
      'fecha': _fecha.text.trim(),
      'horaInicio': _horaIni.text.trim(),
      'horaFin': _horaFin.text.trim(),
      'lugar': _lugar.text.trim(),
    });
    if (ok && mounted) {
      _aviso('Examen programado y notificado a todos.', ok: true);
      setState(() => _e['etapa'] = 'Examen programado');
    }
  }

  Future<void> _registrarResultado() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar resultado'),
        content: Text(
            'Se registrará "$_resultado"'
            '${_resultado != 'Suspendido' ? ' y se generará el acta de examen de grado firmada, sellada y con QR' : ''}. ¿Continuar?'),
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
      ),
    );
    if (confirma != true) return;
    final ok = await _post({
      'accion': 'titulacion_acta',
      'folio': _e['folio'],
      'resultado': _resultado,
    });
    if (ok && mounted) {
      _aviso('Resultado registrado. El alumno fue notificado.', ok: true);
      Navigator.pop(context, true);
    }
  }

  void _aviso(String m, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? Colors.green : Colors.redAccent,
      content: Text(m),
    ));
  }

  Widget _dropDoc(String etiqueta, Map<String, dynamic>? valor,
      void Function(Map<String, dynamic>?) onSel) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<Map<String, dynamic>>(
        value: _docentes.contains(valor) ? valor : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: etiqueta,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
        ),
        items: _docentes
            .map((d) => DropdownMenuItem(
                  value: d,
                  child: Text(
                    '${d['titulo']} ${d['nombre']}'.trim(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ))
            .toList(),
        onChanged: onSel,
      ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: cessumRed)),
      );

  @override
  Widget build(BuildContext context) {
    final tieneSinodos =
        ((_e['presidente'] ?? '') as String).isNotEmpty;
    final actaPdf = (_e['actaPdf'] ?? '') as String;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Sínodos y examen',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: AbsorbPointer(
        absorbing: _guardando,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFFF5F1E8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_e['nombre']} (${_e['matricula']})',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      '${_e['programa']} · ${_e['generacion']}\nOpción: ${_e['opcion']} · Etapa: ${_e['etapa']}',
                      style: const TextStyle(fontSize: 12.5, height: 1.45),
                    ),
                  ],
                ),
              ),
            ),
            if (_guardando) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(color: cessumRed),
            ],

            _seccion('1. Sínodo'),
            if (_docentes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Cargando docentes...',
                    style: TextStyle(color: Colors.black54)),
              )
            else ...[
              _dropDoc('Presidente', _pres, (v) => setState(() => _pres = v)),
              _dropDoc('Secretario', _sec, (v) => setState(() => _sec = v)),
              _dropDoc('Vocal', _voc, (v) => setState(() => _voc = v)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _guardando ? null : _guardarSinodos,
                  icon: const Icon(Icons.groups),
                  label: const Text('Guardar sínodo y notificar'),
                ),
              ),
            ],

            _seccion('2. Examen de grado'),
            if (!tieneSinodos)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                    'Asigna primero el sínodo para programar el examen.',
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.black54)),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      value: 'Virtual',
                      groupValue: _modalidad,
                      activeColor: cessumRed,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Virtual (Meet)',
                          style: TextStyle(fontSize: 13)),
                      onChanged: (v) => setState(() => _modalidad = v!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      value: 'Presencial',
                      groupValue: _modalidad,
                      activeColor: cessumRed,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Presencial',
                          style: TextStyle(fontSize: 13)),
                      onChanged: (v) => setState(() => _modalidad = v!),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _fecha,
                decoration: const InputDecoration(
                  labelText: 'Fecha (dd/mm/aaaa) *',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _horaIni,
                      decoration: const InputDecoration(
                        labelText: 'Hora inicio',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _horaFin,
                      decoration: const InputDecoration(
                        labelText: 'Hora fin',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              if (_modalidad == 'Presencial') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _lugar,
                  decoration: const InputDecoration(
                    labelText: 'Lugar del examen *',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _guardando ? null : _programarExamen,
                  icon: Icon(_modalidad == 'Virtual'
                      ? Icons.videocam
                      : Icons.event),
                  label: Text(_modalidad == 'Virtual'
                      ? 'Crear Meet y notificar'
                      : 'Programar y notificar'),
                ),
              ),
              if (((_e['examenLugar'] ?? '') as String).isNotEmpty &&
                  _modalidad == 'Virtual')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: () => Helpers.abrirUrlExterna(
                        (_e['examenLugar'] ?? '') as String, context),
                    icon: const Icon(Icons.link, size: 16, color: cessumGold),
                    label: const Text('Abrir Meet del examen',
                        style: TextStyle(color: cessumGold, fontSize: 12.5)),
                  ),
                ),
            ],

            _seccion('3. Resultado y acta'),
            if (!tieneSinodos)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Disponible tras programar el examen.',
                    style: TextStyle(
                        fontSize: 12.5, color: Colors.black54)),
              )
            else ...[
              DropdownButtonFormField<String>(
                value: _resultado,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Resultado del examen',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'Aprobado', child: Text('Aprobado')),
                  DropdownMenuItem(
                      value: 'Aprobado con mención honorífica',
                      child: Text('Aprobado con mención honorífica')),
                  DropdownMenuItem(
                      value: 'Suspendido', child: Text('Suspendido')),
                ],
                onChanged: (v) => setState(() => _resultado = v!),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8E3E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _guardando ? null : _registrarResultado,
                  icon: const Icon(Icons.verified),
                  label: const Text('Registrar resultado y generar acta'),
                ),
              ),
              if (actaPdf.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextButton.icon(
                    onPressed: () =>
                        Helpers.abrirUrlExterna(actaPdf, context),
                    icon: const Icon(Icons.picture_as_pdf,
                        size: 16, color: cessumRed),
                    label: const Text('Ver acta de examen (PDF)',
                        style: TextStyle(color: cessumRed, fontSize: 12.5)),
                  ),
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

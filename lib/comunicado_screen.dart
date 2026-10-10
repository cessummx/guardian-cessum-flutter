import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Comunicado institucional segmentado (admin): envía un aviso a
/// alumnos (todos o por programa/generación/grupo), docentes o
/// ambos, in-app y opcionalmente por correo. Incluye "previa".
class ComunicadoScreen extends StatefulWidget {
  const ComunicadoScreen({super.key});

  @override
  State<ComunicadoScreen> createState() => _ComunicadoScreenState();
}

class _ComunicadoScreenState extends State<ComunicadoScreen> {
  String _correo = '';
  String _destino = 'alumnos';
  final _prog = TextEditingController();
  final _gen = TextEditingController();
  final _grupo = TextEditingController();
  final _asunto = TextEditingController();
  final _mensaje = TextEditingController();
  bool _conCorreo = false;

  bool _cargando = false;
  String _msg = '';
  Color _msgColor = Colors.black54;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // (24-sep) Correo REAL: en «Ver como profesor» el de la vista es el del profesor.
    _correo = (await SessionStore.realEmail()) ?? '';
  }

  @override
  void dispose() {
    _prog.dispose();
    _gen.dispose();
    _grupo.dispose();
    _asunto.dispose();
    _mensaje.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 120));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Map<String, dynamic> _body(String accion) => {
        'accion': accion,
        'actor': _correo,
        'destino': _destino,
        'programa': _prog.text.trim(),
        'generacion': _gen.text.trim(),
        'grupo': _grupo.text.trim(),
        'asunto': _asunto.text.trim(),
        'mensaje': _mensaje.text.trim(),
        'correo': _conCorreo,
      };

  bool _valido() {
    if (_asunto.text.trim().isEmpty || _mensaje.text.trim().isEmpty) {
      if (mounted) setState(() {
        _msg = 'Escribe asunto y mensaje.';
        _msgColor = cessumRed;
      });
      return false;
    }
    return true;
  }

  Future<void> _previa() async {
    if (!_valido()) return;
    if (mounted) setState(() { _cargando = true; _msg = ''; });
    try {
      final d = await _post(_body('comunicado_previa'));
      if (d['ok'] != true) {
        if (mounted) setState(() { _msg = (d['error'] ?? 'No se pudo calcular.').toString(); _msgColor = cessumRed; _cargando = false; });
        return;
      }
      if (mounted) setState(() {
        _msg = 'Alcance: ${d['total']} destinatario(s) — '
            '${d['alumnos']} alumno(s), ${d['docentes']} docente(s). '
            'Revisa y pulsa Enviar.';
        _msgColor = Colors.black87;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() { _msg = 'Error de conexión.'; _msgColor = cessumRed; _cargando = false; });
    }
  }

  Future<void> _enviar() async {
    if (!_valido()) return;
    // (24-sep) ANTES de enviar se calcula el alcance, aunque no se haya pulsado
    // «Ver alcance»: la confirmación dice a CUÁNTAS personas les llega, el asunto
    // y si va también por correo. Antes solo decía «alumnos» o «docentes».
    if (mounted) setState(() { _cargando = true; _msg = ''; });
    Map<String, dynamic> prev;
    try {
      prev = await _post(_body('comunicado_previa'));
    } catch (_) {
      if (mounted) setState(() { _msg = 'No se pudo calcular el alcance. Error de conexión.'; _msgColor = cessumRed; _cargando = false; });
      return;
    }
    if (mounted) setState(() => _cargando = false);
    if (prev['ok'] != true) {
      if (mounted) setState(() { _msg = (prev['error'] ?? 'No se pudo calcular el alcance.').toString(); _msgColor = cessumRed; });
      return;
    }
    final total = (prev['total'] as num?)?.toInt() ?? 0;
    if (total <= 0) {
      if (mounted) setState(() { _msg = 'Con esos filtros no hay destinatarios: no se envió nada.'; _msgColor = cessumRed; });
      return;
    }
    if (!mounted) return;
    final filtros = [
      if (_prog.text.trim().isNotEmpty) _prog.text.trim(),
      if (_gen.text.trim().isNotEmpty) 'Gen. ${_gen.text.trim()}',
      if (_grupo.text.trim().isNotEmpty) 'Grupo ${_grupo.text.trim()}',
    ].join(' · ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Enviar comunicado a $total persona(s)'),
        content: SingleChildScrollView(
          child: Text(
              'Destinatarios: ${prev['alumnos'] ?? 0} alumno(s) y ${prev['docentes'] ?? 0} docente(s)'
              '${filtros.isNotEmpty ? '\nFiltro: $filtros' : ''}'
              '\n\nAsunto: «${_asunto.text.trim()}»'
              '${_conCorreo ? '\n\nLlegará en la app Y POR CORREO a cada uno.' : '\n\nSolo como notificación en la app (sin correo).'}'
              '\n\n¿Confirma el envío?',
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Enviar a $total persona(s)'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (mounted) setState(() { _cargando = true; _msg = ''; });
    try {
      final d = await _post(_body('comunicado_enviar'));
      if (d['ok'] != true) {
        if (mounted) setState(() { _msg = (d['error'] ?? 'No se pudo enviar.').toString(); _msgColor = cessumRed; _cargando = false; });
        return;
      }
      if (mounted) setState(() {
        _msg = 'Enviado a ${d['enviados']} destinatario(s)'
            '${(d['correos'] ?? 0) != 0 ? ' (${d['correos']} por correo)' : ''}.';
        _msgColor = const Color(0xFF1E8E3E);
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() { _msg = 'Error de conexión.'; _msgColor = cessumRed; _cargando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Comunicado institucional'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Destinatarios',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'alumnos', label: Text('Alumnos')),
              ButtonSegment(value: 'docentes', label: Text('Docentes')),
              ButtonSegment(value: 'ambos', label: Text('Ambos')),
            ],
            selected: {_destino},
            onSelectionChanged: (s) => setState(() => _destino = s.first),
          ),
          if (_destino != 'docentes') ...[
            const SizedBox(height: 12),
            const Text('Filtros (opcionales, para alumnos)',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            TextField(controller: _prog, decoration: const InputDecoration(
                labelText: 'Programa', isDense: true)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _gen, decoration: const InputDecoration(
                  labelText: 'Generación', isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _grupo, decoration: const InputDecoration(
                  labelText: 'Grupo', isDense: true))),
            ]),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _asunto,
            decoration: const InputDecoration(labelText: 'Asunto', isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _mensaje,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Mensaje',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enviar también por correo'),
            subtitle: const Text('Para segmentos chicos; muchos correos pueden topar el límite diario.',
                style: TextStyle(fontSize: 11)),
            value: _conCorreo,
            activeColor: cessumRed,
            onChanged: (v) => setState(() => _conCorreo = v),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cargando ? null : _previa,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Ver alcance'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _cargando ? null : _enviar,
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                icon: _cargando
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: const Text('Enviar'),
              ),
            ),
          ]),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _msgColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_msg, style: TextStyle(color: _msgColor, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

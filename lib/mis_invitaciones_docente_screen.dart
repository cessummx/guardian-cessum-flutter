import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// MEJORA DOCENTE — Mis invitaciones de materia (responder desde la app).
///
/// El profesor ve las materias que le proponen y su estado, y puede
/// ACEPTAR o RECHAZAR sin salir al correo: elige día y hora y deja
/// comentarios. Usa `mis_invitaciones` (lectura, por correo de sesión) y
/// `invitacion_responder_app` (responde validando correo + fila).
class MisInvitacionesDocenteScreen extends StatefulWidget {
  const MisInvitacionesDocenteScreen({super.key});

  @override
  State<MisInvitacionesDocenteScreen> createState() =>
      _MisInvitacionesDocenteScreenState();
}

class _MisInvitacionesDocenteScreenState
    extends State<MisInvitacionesDocenteScreen> {
  bool _cargando = true;
  String? _error;
  String _correo = '';
  List<Map<String, dynamic>> _mias = [];
  final Set<int> _enviando = {};

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
      final correo = (await SessionStore.validEmail()) ?? '';
      _correo = correo.toLowerCase();
      if (_correo.isEmpty) {
        setState(() {
          _error = 'No se pudo identificar tu correo de docente.';
          _cargando = false;
        });
        return;
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_invitaciones',
        'correo': _correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = (data['invitaciones'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _mias = lista;
          _cargando = false;
        });
      } else {
        setState(() {
          _error = (data['error'] ?? 'No se pudo cargar').toString();
          _cargando = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Sin conexión o error: $e';
        _cargando = false;
      });
    }
  }

  String _estadoDe(Map<String, dynamic> a) {
    final est = (a['invitacionEstado'] ?? '').toString().trim();
    return est.isEmpty ? 'Pendiente' : est;
  }

  Color _colorEstado(String est) {
    switch (est) {
      case 'Aceptada':
        return const Color(0xFF1E8E3E);
      case 'Rechazada':
        return cessumRed;
      default:
        return cessumGold;
    }
  }

  Future<void> _responder(Map<String, dynamic> a) async {
    final resultado = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _FormularioRespuesta(
        materia: (a['materia'] ?? '').toString(),
        grupo: (a['grupo'] ?? '').toString(),
      ),
    );
    if (resultado == null) return;

    final fila = int.tryParse('${a['fila']}') ?? 0;
    if (fila < 2) return;
    setState(() => _enviando.add(fila));
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'invitacion_responder_app',
                'correo': _correo,
                'fila': fila,
                'respuesta': resultado['respuesta'],
                'dia': resultado['dia'] ?? '',
                'hora': resultado['hora'] ?? '',
                'comentarios': resultado['comentarios'] ?? '',
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        final est = (data['estado'] ?? '').toString();
        _aviso(est == 'Aceptada'
            ? 'Aceptaste la materia. ¡Gracias!'
            : (est == 'Rechazada'
                ? 'Registramos que no puedes impartirla.'
                : 'Respuesta registrada.'));
        await _cargar();
      } else {
        _aviso((data['error'] ?? 'No se pudo registrar.').toString(),
            error: true);
      }
    } catch (e) {
      if (mounted) _aviso('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _enviando.remove(fila));
    }
  }

  void _aviso(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final conteo = <String, int>{'Pendiente': 0, 'Aceptada': 0, 'Rechazada': 0};
    for (final a in _mias) {
      final e = _estadoDe(a);
      conteo[e] = (conteo[e] ?? 0) + 1;
    }
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis invitaciones'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _vistaError()
              : Column(
                  children: [
                    _resumen(conteo),
                    Expanded(child: _lista()),
                  ],
                ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }

  Widget _resumen(Map<String, int> c) {
    Widget chip(String etq, int n, Color color) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text('$n',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              Text(etq,
                  style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Row(
        children: [
          chip('Pendientes', c['Pendiente'] ?? 0, cessumGold),
          chip('Aceptadas', c['Aceptada'] ?? 0, const Color(0xFF1E8E3E)),
          chip('Rechazadas', c['Rechazada'] ?? 0, cessumRed),
        ],
      ),
    );
  }

  Widget _lista() {
    if (_mias.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No tienes invitaciones de materia registradas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context))),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _mias.length,
        itemBuilder: (_, i) => _tarjeta(_mias[i]),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final est = _estadoDe(a);
    final color = _colorEstado(est);
    final fila = int.tryParse('${a['fila']}') ?? 0;
    final enviando = _enviando.contains(fila);
    final dia = (a['dia'] ?? '').toString().trim();
    final hora = (a['hora'] ?? '').toString().trim();
    final coment = (a['comentarios'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text((a['materia'] ?? '(sin materia)').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(est,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                '${a['programa']} · Grupo ${a['grupo']} · Gen. ${a['generacion']}',
                style: TextStyle(color: cessumMuted(context), fontSize: 12)),
            if ((est == 'Aceptada') && (dia.isNotEmpty || hora.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.event_available,
                      size: 16, color: Color(0xFF1E8E3E)),
                  const SizedBox(width: 4),
                  Text('$dia ${hora.isNotEmpty ? '· $hora' : ''}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF1E8E3E),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            if (coment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cessumMuted(context).withValues(alpha: 0.10), // (24-sep) modo oscuro
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('“$coment”',
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
              ),
            ],
            if (est == 'Pendiente') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: enviando ? null : () => _responder(a),
                  icon: enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.reply),
                  label: Text(enviando ? 'Enviando…' : 'Responder invitación'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hoja inferior para responder: aceptar/rechazar + día, hora y comentarios.
class _FormularioRespuesta extends StatefulWidget {
  final String materia;
  final String grupo;
  const _FormularioRespuesta({required this.materia, required this.grupo});

  @override
  State<_FormularioRespuesta> createState() => _FormularioRespuestaState();
}

class _FormularioRespuestaState extends State<_FormularioRespuesta> {
  String _respuesta = 'acepta';
  String _dia = 'Lunes';
  TimeOfDay? _hora;
  final TextEditingController _coment = TextEditingController();

  static const _dias = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo'
  ];

  // Mixta = periodo presencial intensivo (bloque de días seguidos), no una
  // sesión semanal: no se elige un día. Los días salen de las fechas del
  // periodo (inicio/término), igual que en la agenda del admin.
  bool get _esMixta => widget.grupo.toLowerCase().contains('mixt');

  @override
  void dispose() {
    _coment.dispose();
    super.dispose();
  }

  String _horaTexto() {
    final h = _hora;
    if (h == null) return '';
    final hh = h.hour.toString().padLeft(2, '0');
    final mm = h.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _enviar() {
    if (_respuesta == 'acepta' && _hora == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Para aceptar, elige la hora de la sesión.'),
      ));
      return;
    }
    Navigator.pop(context, {
      'respuesta': _respuesta,
      'dia': (_respuesta == 'acepta' && !_esMixta) ? _dia : '',
      'hora': _respuesta == 'acepta' ? _horaTexto() : '',
      'comentarios': _coment.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final acepta = _respuesta == 'acepta';
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.materia,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          const Text('¿Aceptas impartir esta materia?',
              style: TextStyle(fontWeight: FontWeight.w600)),
          RadioListTile<String>(
            value: 'acepta',
            groupValue: _respuesta,
            activeColor: cessumRed,
            contentPadding: EdgeInsets.zero,
            title: const Text('Sí, acepto'),
            onChanged: (v) => setState(() => _respuesta = v ?? 'acepta'),
          ),
          RadioListTile<String>(
            value: 'rechaza',
            groupValue: _respuesta,
            activeColor: cessumRed,
            contentPadding: EdgeInsets.zero,
            title: const Text('No puedo'),
            onChanged: (v) => setState(() => _respuesta = v ?? 'rechaza'),
          ),
          if (acepta) ...[
            const SizedBox(height: 8),
            if (!_esMixta) ...[
              DropdownButtonFormField<String>(
                value: _dia,
                decoration: InputDecoration(
                  labelText: 'Día de la sesión semanal',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: _dias
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) => setState(() => _dia = v ?? 'Lunes'),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10), // (24-sep) modo oscuro
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD9C189)),
                ),
                child: const Text(
                  'Mixta: periodo presencial intensivo (días seguidos). No se '
                  'elige un día de la semana: los días del periodo quedan '
                  'definidos por las fechas de inicio y término.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
            ],
            InkWell(
              onTap: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: _hora ?? const TimeOfDay(hour: 17, minute: 0),
                );
                if (t != null) setState(() => _hora = t);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: _esMixta ? 'Horario del periodo' : 'Hora de la sesión',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(_hora == null ? 'Toca para elegir' : _horaTexto()),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _coment,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Comentarios (opcional)',
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _enviar,
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(acepta ? 'Aceptar materia' : 'Enviar respuesta'),
            ),
          ),
        ],
      ),
    );
  }
}

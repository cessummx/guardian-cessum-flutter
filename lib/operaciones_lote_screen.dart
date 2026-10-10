// Pantalla de administrador: "Operaciones por lote".
//
// Aplica una misma acción a VARIOS alumnos a la vez, pegando una lista:
//   - Dar de baja: una matrícula por renglón.
//   - Cambiar de programa/generación: por renglón
//       matricula, programa, generacion, grupo
//
// Acción del Guardián:
//   POST lote_procesar {modo:'baja'|'mover', filas:[...]} -> {ok, exitos, fallos, resultados}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class OperacionesLoteScreen extends StatefulWidget {
  const OperacionesLoteScreen({super.key});

  @override
  State<OperacionesLoteScreen> createState() => _OperacionesLoteScreenState();
}

class _OperacionesLoteScreenState extends State<OperacionesLoteScreen> {
  final _texto = TextEditingController();
  String _modo = 'baja'; // 'baja' | 'mover'
  bool _procesando = false;
  String _actor = '';
  List<Map<String, dynamic>> _resultados = [];
  int _exitos = 0;
  int _fallos = 0;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  // Convierte el texto pegado en filas según el modo.
  List<dynamic> _parsear() {
    final lineas = _texto.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (_modo == 'baja') {
      return lineas.map((l) => l.split(',').first.trim()).toList();
    }
    // mover: matricula, programa, generacion, grupo
    return lineas.map((l) {
      final c = l.split(',').map((x) => x.trim()).toList();
      return {
        'matricula': c.isNotEmpty ? c[0] : '',
        'programa': c.length > 1 ? c[1] : '',
        'generacion': c.length > 2 ? c[2] : '',
        'grupo': c.length > 3 ? c[3] : '',
      };
    }).toList();
  }

  Future<void> _aplicar() async {
    final filas = _parsear();
    if (filas.isEmpty) {
      _aviso('Pega al menos una matrícula.', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar lote'),
        content: Text(_modo == 'baja'
            ? 'Se dará de baja a ${filas.length} alumno(s). ¿Continuar?'
            : 'Se cambiará de programa/generación a ${filas.length} alumno(s). '
                '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _procesando = true;
      _resultados = [];
    });
    try {
      _actor = (await SessionStore.realEmail()) ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'lote_procesar',
                'actor': _actor,
                'modo': _modo,
                'filas': filas,
              }))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _exitos = (data['exitos'] ?? 0) as int;
        _fallos = (data['fallos'] ?? 0) as int;
        _resultados = ((data['resultados'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _aviso('Listo: $_exitos correcto(s), $_fallos con error.');
      } else {
        _aviso('${data['error'] ?? 'No se pudo procesar.'}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
    if (mounted) setState(() => _procesando = false);
  }

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : cessumGold,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final esBaja = _modo == 'baja';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operaciones por lote'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'baja',
                  label: Text('Dar de baja'),
                  icon: Icon(Icons.person_off_outlined)),
              ButtonSegment(
                  value: 'mover',
                  label: Text('Cambiar programa'),
                  icon: Icon(Icons.swap_horiz)),
            ],
            selected: {_modo},
            onSelectionChanged: (s) => setState(() {
              _modo = s.first;
              _resultados = [];
            }),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: cessumRed, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    esBaja
                        ? 'Pega una matrícula por renglón. Cada alumno quedará '
                            'con estatus de Baja (reversible).'
                        : 'Un alumno por renglón, separado por comas:\n'
                            'matrícula, programa, generación, grupo\n'
                            'Ej.: 24060200, Maestria en Educacion, 26-1, 1 - entre semana',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: cessumMuted(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _texto,
            maxLines: 10,
            minLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: esBaja
                  ? 'Matrículas (una por renglón)'
                  : 'matrícula, programa, generación, grupo',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _procesando ? null : _aplicar,
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _procesando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.playlist_add_check),
              label: Text(_procesando ? 'Procesando…' : 'Aplicar a todos'),
            ),
          ),
          if (_resultados.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                _contador('Correctos', _exitos, const Color(0xFF1E8E3E)),
                const SizedBox(width: 10),
                _contador('Con error', _fallos, cessumRed),
              ],
            ),
            const SizedBox(height: 10),
            ..._resultados.map(_filaResultado),
          ],
        ],
      ),
    );
  }

  Widget _contador(String t, int n, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.withValues(alpha: 0.30)),
          ),
          child: Column(
            children: [
              Text('$n',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700, color: c)),
              Text(t,
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ],
          ),
        ),
      );

  Widget _filaResultado(Map<String, dynamic> r) {
    final ok = r['ok'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.error_outline,
              size: 18, color: ok ? const Color(0xFF1E8E3E) : cessumRed),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${r['matricula'] ?? ''}'
              '${ok ? '' : ' — ${r['error'] ?? 'error'}'}',
              style: TextStyle(
                  fontSize: 12.5,
                  color: cessumIsDark(context) ? Colors.white70 : cessumInk(context)),
            ),
          ),
        ],
      ),
    );
  }
}

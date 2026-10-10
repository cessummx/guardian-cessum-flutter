import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'modos_aprendizaje.dart';
import 'student_profile.dart';

class PerfilAprendizajeScreen extends StatefulWidget {
  final String matricula;
  final String nombre;
  final String programa;
  final String generacion;
  const PerfilAprendizajeScreen({
    super.key,
    this.matricula = '',
    this.nombre = '',
    this.programa = '',
    this.generacion = '',
  });

  @override
  State<PerfilAprendizajeScreen> createState() =>
      _PerfilAprendizajeScreenState();
}

class _PerfilAprendizajeScreenState extends State<PerfilAprendizajeScreen> {
  String _matricula = '';
  String _nombre = '';
  String _programa = '';
  String _generacion = '';

  final _bio = TextEditingController();
  final _inst = TextEditingController();
  final _puesto = TextEditingController();
  final _anios = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  bool _testHecho = false;
  Map<String, int> _conteo = {};
  List<String> _dominante = [];

  @override
  void initState() {
    super.initState();
    _matricula = widget.matricula.trim();
    _nombre = widget.nombre;
    _programa = widget.programa;
    _generacion = widget.generacion;
    _init();
  }

  @override
  void dispose() {
    _bio.dispose();
    _inst.dispose();
    _puesto.dispose();
    _anios.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_matricula.isEmpty || _nombre.isEmpty) {
      final p = await StudentProfile.load();
      if (p != null) {
        if (_matricula.isEmpty) _matricula = p.matricula;
        if (_nombre.isEmpty) _nombre = p.nombreCompleto;
        if (_programa.isEmpty) _programa = p.programa;
        if (_generacion.isEmpty) _generacion = p.generacion;
      }
    }
    await _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> p) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: p);
    final r = await http.get(uri).timeout(const Duration(seconds: 45));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 45));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (_matricula.isEmpty) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo identificar tu matrícula.';
        });
        return;
      }
      final data =
          await _get({'accion': 'perfil_aprendizaje_get', 'matricula': _matricula});
      if (!mounted) return;
      final per = data['perfil'];
      if (per is Map) {
        _bio.text = '${per['biografia'] ?? ''}';
        _inst.text = '${per['institucion'] ?? ''}';
        _puesto.text = '${per['puesto'] ?? ''}';
        _anios.text = '${per['anios'] ?? ''}';
        _testHecho = per['hecho'] == true;
        final t = (per['test'] as Map?) ?? {};
        _conteo = {
          for (final k in kModos) k: (t[k] is int ? t[k] as int : int.tryParse('${t[k]}') ?? 0)
        };
        _dominante = '${per['dominante'] ?? ''}'
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
      setState(() => _cargando = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu perfil.';
      });
    }
  }

  void _snack(String t, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), backgroundColor: ok ? Colors.green : cessumRed));
  }

  Future<void> _guardarPerfil() async {
    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'perfil_aprendizaje_guardar',
        'matricula': _matricula,
        'nombre': _nombre,
        'programa': _programa,
        'generacion': _generacion,
        'biografia': _bio.text.trim(),
        'institucion': _inst.text.trim(),
        'puesto': _puesto.text.trim(),
        'anios': _anios.text.trim(),
      });
      if (data['ok'] == true) {
        _snack('Perfil guardado.', ok: true);
      } else {
        _snack('${data['error'] ?? 'No se pudo guardar.'}');
      }
    } catch (e) {
      _snack('Error de conexión.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _hacerTest() async {
    final respuestas = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => const _TestModosScreen()),
    );
    if (respuestas == null || respuestas.length < kReactivos.length) return;
    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'perfil_test_guardar',
        'matricula': _matricula,
        'nombre': _nombre,
        'programa': _programa,
        'generacion': _generacion,
        'respuestas': respuestas,
      });
      if (data['ok'] == true) {
        _snack('¡Test guardado!', ok: true);
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo guardar.'}');
      }
    } catch (e) {
      _snack('Error de conexión.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _generarCV() async {
    setState(() => _guardando = true);
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'cv_trayectoria',
                'matricula': _matricula,
                'programa': _programa,
              }))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['ok'] == true && '${data['pdf'] ?? ''}'.isNotEmpty) {
        if (mounted) Helpers.abrirUrlExterna('${data['pdf']}', context);
      } else {
        _snack('${data['error'] ?? 'No se pudo generar tu trayectoria.'}');
      }
    } catch (e) {
      _snack('Error de conexión al generar el PDF.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _cardCV() {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mi trayectoria CESSUM',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'Genera tu CV/portafolio académico en PDF (con folio y QR): tu '
              'semblanza, formación, historial de materias, horas acumuladas y '
              'tu perfil de modos de interacción.',
              style: TextStyle(fontSize: 12, color: cessumMuted(context)),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                icon: const Icon(Icons.workspace_premium),
                label: _guardando
                    ? const Text('Generando…')
                    : const Text('Generar mi trayectoria (PDF)'),
                onPressed: _guardando ? null : _generarCV,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tip: completa tu semblanza y haz el test para un CV más rico.',
              style: TextStyle(fontSize: 11, color: cessumFaint(context)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi perfil de aprendizaje'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _cardPerfil(),
                    const SizedBox(height: 12),
                    _cardTest(),
                    const SizedBox(height: 12),
                    _cardCV(),
                  ],
                ),
    );
  }

  Widget _cardPerfil() {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_nombre.isEmpty ? 'Mi perfil' : _nombre,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (_programa.isNotEmpty)
              Text(_programa,
                  style: TextStyle(color: cessumMuted(context), fontSize: 12.5)),
            const SizedBox(height: 12),
            TextField(
              controller: _bio,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                  labelText: 'Biografía corta',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _inst,
              decoration: const InputDecoration(
                  labelText: 'Escuela o institución donde trabajas',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _puesto,
              decoration: const InputDecoration(
                  labelText: 'Puesto',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _anios,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Años de experiencia',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                icon: const Icon(Icons.save),
                label: const Text('Guardar perfil'),
                onPressed: _guardando ? null : _guardarPerfil,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardTest() {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis modos de interacción didáctica',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              'Tamiz de 8 preguntas para identificar bajo qué condiciones aprendes '
              'mejor. No mide "estilos": describe tus preferencias de interacción.',
              style: TextStyle(fontSize: 12, color: cessumMuted(context)),
            ),
            const SizedBox(height: 12),
            if (!_testHecho) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumGold,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.quiz),
                  label: const Text('Hacer el test (8 preguntas)'),
                  onPressed: _guardando ? null : _hacerTest,
                ),
              ),
            ] else ...[
              BarrasModos(conteo: _conteo),
              const SizedBox(height: 12),
              if (_dominante.isNotEmpty) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _dominante
                      .map((k) => Chip(
                            backgroundColor:
                                (kModoColor[k] ?? cessumRed).withValues(alpha: 0.15),
                            label: Text(kModoNombre[k] ?? k,
                                style: TextStyle(
                                    color: kModoColor[k] ?? cessumRed,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                ..._dominante.map((k) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${kModoDescripcion[k] ?? ''}',
                          style: const TextStyle(fontSize: 12.5)),
                    )),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Repetir test'),
                onPressed: _guardando ? null : _hacerTest,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Flujo del test: una pregunta por pantalla, 5 opciones (una por modo).
class _TestModosScreen extends StatefulWidget {
  const _TestModosScreen();

  @override
  State<_TestModosScreen> createState() => _TestModosScreenState();
}

class _TestModosScreenState extends State<_TestModosScreen> {
  int _i = 0;
  final List<String> _resp = List.filled(kReactivos.length, '');

  void _elegir(String modo) {
    setState(() {
      _resp[_i] = modo;
      if (_i < kReactivos.length - 1) {
        _i++;
      }
    });
    if (_resp.every((r) => r.isNotEmpty) && _i == kReactivos.length - 1) {
      // queda en la última; el usuario confirma con el botón
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = kReactivos[_i];
    final completo = _resp.every((x) => x.isNotEmpty);
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Pregunta ${_i + 1} de ${kReactivos.length}'),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_i + 1) / kReactivos.length,
            backgroundColor: cessumMuted(context).withValues(alpha: 0.18),
            valueColor: const AlwaysStoppedAnimation(cessumGold),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(r.situacion,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                ...r.opciones.map((op) {
                  final sel = _resp[_i] == op.key;
                  return Card(
                    color: sel
                        ? (kModoColor[op.key] ?? cessumRed).withValues(alpha: 0.15)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                          color: sel
                              ? (kModoColor[op.key] ?? cessumRed)
                              : cessumMuted(context).withValues(alpha: 0.18),
                          width: sel ? 2 : 1),
                    ),
                    child: ListTile(
                      title: Text(op.value),
                      trailing: sel
                          ? Icon(Icons.check_circle,
                              color: kModoColor[op.key] ?? cessumRed)
                          : null,
                      onTap: () => _elegir(op.key),
                    ),
                  );
                }),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_i > 0)
                    TextButton.icon(
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Atrás'),
                      onPressed: () => setState(() => _i--),
                    ),
                  const Spacer(),
                  if (_i < kReactivos.length - 1)
                    Text('Selecciona una opción',
                        style: TextStyle(color: cessumMuted(context)))
                  else
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.check),
                      label: const Text('Finalizar'),
                      onPressed: completo
                          ? () => Navigator.pop(context, _resp)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

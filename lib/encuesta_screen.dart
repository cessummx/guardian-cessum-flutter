import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

const List<String> kPreguntasEncuesta = [
  'El o la docente domina los temas de la materia.',
  'Explica con claridad y resuelve dudas.',
  'Las clases son puntuales y están bien organizadas.',
  'La evaluación fue justa y clara.',
  'El trato hacia el grupo fue respetuoso.',
  'En general, ¿qué tan satisfecho(a) estás con la materia?',
];

/// Alumno: encuesta de satisfacción. Lista las materias/docentes que cursa y
/// permite evaluarlas (1 a 5) con un comentario.
class EncuestaScreen extends StatefulWidget {
  const EncuestaScreen({super.key});

  @override
  State<EncuestaScreen> createState() => _EncuestaScreenState();
}

class _EncuestaScreenState extends State<EncuestaScreen> {
  bool _cargando = true;
  String? _error;
  StudentProfile? _perfil;
  List<Map<String, dynamic>> _materias = [];
  // (2-oct) Materias cuya evaluación AÚN NO abre: se abre en la última semana de clase y queda abierta después.
  List<Map<String, dynamic>> _proximas = [];

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
      final p = await StudentProfile.load();
      if (p == null) {
        setState(() {
          _cargando = false;
          _error = 'Completa tu perfil para responder la encuesta.';
        });
        return;
      }
      _perfil = p;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'encuesta_materias_alumno',
        'matricula': p.matricula,
        'programa': p.programa,
        'generacion': p.generacion,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _materias = ((data['materias'] as List<dynamic>? ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Un servidor anterior no manda «proximas»: queda vacía y todo se ve como antes.
      _proximas = ((data['proximas'] as List<dynamic>? ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      _error = 'No se pudo cargar la encuesta. Intenta de nuevo.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _abrirFormulario(Map<String, dynamic> m) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EncuestaForm(perfil: _perfil!, materia: m),
      ),
    );
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _materias.where((m) => m['evaluada'] != true).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Encuesta de satisfacción'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Tu opinión es anónima para los docentes y nos ayuda a '
                        'mejorar. Evalúa cada materia que cursas. '
                        '${pendientes > 0 ? '\nTe faltan $pendientes por responder.' : '\n¡Ya respondiste todas, gracias!'}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_materias.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          _proximas.isEmpty
                              ? 'Aún no hay materias registradas para evaluar.'
                              : 'Todavía no hay materias por evaluar: la evaluación de cada materia se abre en su última semana de clase.',
                          style: TextStyle(color: cessumMuted(context)),
                        ),
                      ),
                    ..._materias.map(_tarjeta),
                    if (_proximas.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('Próximas a abrirse',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: cessumMuted(context))),
                      const SizedBox(height: 6),
                      ..._proximas.map(_tarjetaProxima),
                    ],
                    const SizedBox(height: 30),
                  ],
                ),
    );
  }

  /// Materia cuya evaluación todavía no abre: se muestra apagada, con la fecha en que se abre.
  Widget _tarjetaProxima(Map<String, dynamic> m) {
    final abre = (m['abreEl'] ?? '').toString();
    return Card(
      child: ListTile(
        leading: Icon(Icons.schedule, color: cessumFaint(context)),
        title: Text((m['materia'] ?? '').toString(),
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: cessumMuted(context))),
        subtitle: Text((m['docente'] ?? 'Docente por asignar').toString(),
            style: const TextStyle(fontSize: 12)),
        trailing: Text(abre.isEmpty ? 'Pronto' : 'Se abre\n$abre',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 11.5,
                color: cessumMuted(context),
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> m) {
    final evaluada = m['evaluada'] == true;
    return Card(
      child: ListTile(
        leading: Icon(
            evaluada ? Icons.check_circle : Icons.rate_review_outlined,
            color: evaluada ? const Color(0xFF1E8E3E) : cessumRed),
        title: Text((m['materia'] ?? '').toString(),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text((m['docente'] ?? 'Docente por asignar').toString(),
            style: const TextStyle(fontSize: 12)),
        trailing: evaluada
            ? const Text('Evaluada',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E8E3E),
                    fontWeight: FontWeight.w700))
            : const Icon(Icons.chevron_right, color: cessumRed),
        onTap: evaluada ? null : () => _abrirFormulario(m),
      ),
    );
  }
}

class _EncuestaForm extends StatefulWidget {
  final StudentProfile perfil;
  final Map<String, dynamic> materia;
  const _EncuestaForm({required this.perfil, required this.materia});

  @override
  State<_EncuestaForm> createState() => _EncuestaFormState();
}

class _EncuestaFormState extends State<_EncuestaForm> {
  final List<int> _resp = [0, 0, 0, 0, 0, 0];
  final _comentario = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : Colors.green));
  }

  Future<void> _enviar() async {
    if (_resp.any((v) => v < 1)) {
      _aviso('Responde todas las preguntas (1 a 5).', error: true);
      return;
    }
    setState(() => _enviando = true);
    try {
      final p = widget.perfil;
      final m = widget.materia;
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'encuesta_guardar',
                'matricula': p.matricula,
                'nombre': p.nombreCompleto,
                'programa': p.programa,
                'generacion': p.generacion,
                'clave': m['clave'] ?? '',
                'materia': m['materia'] ?? '',
                'docente': m['docente'] ?? '',
                'correoDocente': m['correoDocente'] ?? '',
                'ciclo': m['ciclo'] ?? '',
                'p1': _resp[0],
                'p2': _resp[1],
                'p3': _resp[2],
                'p4': _resp[3],
                'p5': _resp[4],
                'p6': _resp[5],
                'comentario': _comentario.text.trim(),
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso('¡Gracias! Tu evaluación se registró.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.materia;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Evaluar materia'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text((m['materia'] ?? '').toString(),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text((m['docente'] ?? 'Docente por asignar').toString(),
              style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          const SizedBox(height: 6),
          Text('1 = muy en desacuerdo · 5 = muy de acuerdo',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          const SizedBox(height: 14),
          ...List.generate(kPreguntasEncuesta.length, (i) => _pregunta(i)),
          const SizedBox(height: 8),
          TextField(
            controller: _comentario,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comentario (opcional)',
              hintText: 'Lo que más te gustó o lo que se puede mejorar…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send),
            label: const Text('Enviar evaluación'),
            onPressed: _enviando ? null : _enviar,
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _pregunta(int i) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${i + 1}. ${kPreguntasEncuesta[i]}',
              style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (k) {
              final valor = k + 1;
              final activo = _resp[i] >= valor;
              return IconButton(
                onPressed: () => setState(() => _resp[i] = valor),
                icon: Icon(
                  activo ? Icons.star : Icons.star_border,
                  color: activo ? cessumGold : cessumFaint(context),
                  size: 32,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

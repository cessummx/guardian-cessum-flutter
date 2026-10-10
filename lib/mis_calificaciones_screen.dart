import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'evaluacion_docente_screen.dart';
import 'student_profile.dart';

/// Alumno: "Mis calificaciones por materia". Desglose por ciclo con promedio
/// y foco en lo que está en riesgo (materias reprobadas o sin calificar).
/// Lee el agregador del Guardián (accion=mis_calificaciones).
class MisCalificacionesScreen extends StatefulWidget {
  final String matricula;
  const MisCalificacionesScreen({super.key, required this.matricula});

  @override
  State<MisCalificacionesScreen> createState() =>
      _MisCalificacionesScreenState();
}

class _MisCalificacionesScreenState extends State<MisCalificacionesScreen> {
  bool _cargando = true;
  String _error = '';
  String _promedio = '';
  num _aprobatoria = 7;
  Map<String, dynamic> _resumen = {};
  // (25-sep) Materias cuya calificación se ve al evaluar al docente.
  String _avisoEvaluacion = '';
  List<Map<String, dynamic>> _ciclos = [];
  List<Map<String, dynamic>> _materias = [];
  List<Map<String, dynamic>> _riesgo = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_calificaciones',
        'matricula': widget.matricula,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() {
          _cargando = false;
          _error = '${data['error'] ?? 'No se pudieron cargar tus calificaciones.'}';
        });
        return;
      }
      List<Map<String, dynamic>> lst(String k) => ((data[k] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _promedio = '${data['promedioGeneral'] ?? ''}';
        _aprobatoria = (data['aprobatoria'] is num)
            ? data['aprobatoria'] as num
            : num.tryParse('${data['aprobatoria']}') ?? 7;
        _resumen = Map<String, dynamic>.from((data['resumen'] as Map?) ?? {});
        _ciclos = lst('ciclos');
        _materias = lst('materias');
        _riesgo = lst('riesgo');
        _avisoEvaluacion = '${data['avisoEvaluacion'] ?? ''}';
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus calificaciones. Revisa tu conexión.';
      });
    }
  }

  Color _colorEstatus(String e) {
    switch (e) {
      case 'aprobada':
        return Colors.green;
      case 'reprobada':
        return cessumRed;
      case 'evaluar':
        return const Color(0xFF2F5D8A);
      default:
        return cessumGold;
    }
  }

  String _textoEstatus(String e) {
    switch (e) {
      case 'aprobada':
        return 'Aprobada';
      case 'reprobada':
        return 'Reprobada';
      case 'evaluar':
        return 'Evaluar para ver';
      default:
        return 'Sin calificar';
    }
  }

  /// (25-sep) Abre la evaluación docente; al volver, recarga: la
  /// calificación aparece en cuanto la evaluación queda registrada.
  Future<void> _evaluar() async {
    final p = await StudentProfile.load();
    if (p == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EvaluacionDocenteScreen(perfil: p)));
    if (mounted) _cargar();
  }

  Widget _bannerEvaluar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2F5D8A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2F5D8A).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.lock_clock, color: Color(0xFF2F5D8A)),
          SizedBox(width: 8),
          Expanded(
            child: Text('Evalúa a tu docente para ver tu calificación',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: Color(0xFF2F5D8A))),
          ),
        ]),
        const SizedBox(height: 6),
        Text(_avisoEvaluacion, style: const TextStyle(fontSize: 13, height: 1.4)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2F5D8A)),
            onPressed: _evaluar,
            icon: const Icon(Icons.rate_review, size: 18),
            label: const Text('Evaluar ahora'),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis calificaciones'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(child: Text(_error, textAlign: TextAlign.center)),
                    const SizedBox(height: 12),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _cargar,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                      ),
                    ),
                  ])
                : _materias.isEmpty
                    ? _vacio()
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_avisoEvaluacion.isNotEmpty) ...[
                            _bannerEvaluar(),
                            const SizedBox(height: 16),
                          ],
                          _encabezado(),
                          if (_riesgo.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _seccionRiesgo(),
                          ],
                          const SizedBox(height: 16),
                          const Text('Desglose por ciclo',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          ..._ciclos.map(_bloqueCiclo),
                          const SizedBox(height: 20),
                          _avisoRevision(),
                          const SizedBox(height: 8),
                        ],
                      ),
      ),
    );
  }

  /// (ago-25) Qué hacer si una calificación está mal o no aparece.
  ///
  /// Sin esto, el alumno que ve un error escribe por WhatsApp al docente, al
  /// grupo, o a quien le contesta primero — y el reclamo se pierde sin que
  /// nadie lleve la cuenta. Con un ticket queda registrado, con folio y con
  /// responsable, que es lo que permite corregirlo y demostrar que se
  /// corrigió.
  ///
  /// Va al FINAL de la lista a propósito: se lee después de revisar las
  /// calificaciones, que es cuando surge la duda. Arriba sería una alarma
  /// antes de que hubiera algo que reclamar.
  Widget _avisoRevision() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: Colors.amber.shade800, width: 4),
          top: BorderSide(color: Colors.amber.withValues(alpha: 0.25)),
          right: BorderSide(color: Colors.amber.withValues(alpha: 0.25)),
          bottom: BorderSide(color: Colors.amber.withValues(alpha: 0.25)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.report_problem_outlined,
                size: 20, color: Colors.amber.shade900),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '¿Falta una calificación o crees que hay un error?',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.amber.shade900),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          const Text(
            'No lo dejes pasar ni lo reportes por WhatsApp: levanta un ticket '
            'en la Mesa de ayuda, en la categoría «Calificaciones». Así queda '
            'registrado con folio, se revisa con tu docente y te avisamos el '
            'resultado por este mismo sistema.',
            style: TextStyle(fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 10),
          const Text(
            'Indica la materia, el ciclo y qué calificación esperabas. Si '
            'tienes el trabajo entregado o el correo del docente, adjúntalo: '
            'con evidencia se resuelve mucho más rápido.',
            style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.support_agent, size: 17, color: Colors.grey.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Menú principal → Mesa de ayuda → Calificaciones',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _encabezado() {
    final apro = '${_resumen['aprobadas'] ?? 0}';
    final repro = '${_resumen['reprobadas'] ?? 0}';
    final pend = '${_resumen['pendientes'] ?? 0}';
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cessumRed.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
        ),
        child: Column(children: [
          const Text('Promedio general',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 2),
          Text(_promedio.isEmpty ? '—' : _promedio,
              style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: cessumRed)),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        _chip('Aprobadas', apro, Colors.green),
        const SizedBox(width: 8),
        _chip('Reprobadas', repro, cessumRed),
        const SizedBox(width: 8),
        _chip('Sin calificar', pend, cessumGold),
      ]),
    ]);
  }

  Widget _chip(String etiqueta, String valor, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          Text(valor,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(etiqueta,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _seccionRiesgo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: const [
          Icon(Icons.warning_amber_rounded, color: cessumRed),
          SizedBox(width: 8),
          Text('Atención: en riesgo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        ..._riesgo.map((m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${m['materia'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    '${m['ciclo'] ?? ''} · ${_textoEstatus('${m['estatus'] ?? ''}')}'
                    '${'${m['necesita'] ?? ''}'.isNotEmpty ? ' · ${m['necesita']}' : ''}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                ],
              ),
            )),
      ]),
    );
  }

  Widget _bloqueCiclo(Map<String, dynamic> c) {
    final ciclo = '${c['ciclo'] ?? ''}';
    final prom = '${c['promedio'] ?? ''}';
    final mats =
        _materias.where((m) => '${m['ciclo'] ?? ''}' == ciclo).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(ciclo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            if (prom.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Prom. $prom',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: cessumGold)),
              ),
          ]),
          const Divider(),
          ...mats.map(_filaMateria),
        ]),
      ),
    );
  }

  Widget _filaMateria(Map<String, dynamic> m) {
    final est = '${m['estatus'] ?? ''}';
    final color = _colorEstatus(est);
    final cal = '${m['calificacion'] ?? ''}';
    final docente = '${m['docente'] ?? ''}';
    // (25-sep) Calificación oculta hasta evaluar al docente.
    if (est == 'evaluar') {
      return InkWell(
        onTap: _evaluar,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.lock_outline, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m['materia'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(docente.isNotEmpty ? '$docente · toca para evaluar' : 'Toca para evaluar',
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(_textoEstatus(est), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(cal.isEmpty ? '—' : cal,
              style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${m['materia'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (docente.isNotEmpty)
                Text(docente,
                    style:
                        const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(_textoEstatus(est),
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _vacio() {
    return ListView(children: const [
      SizedBox(height: 90),
      Icon(Icons.menu_book, color: Colors.black26, size: 64),
      SizedBox(height: 12),
      Center(
        child: Text('Aún no hay calificaciones registradas.',
            style: TextStyle(fontSize: 16)),
      ),
    ]);
  }
}

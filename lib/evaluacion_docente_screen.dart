import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

const List<String> _itemsMediacion = [
  'El docente demuestra un profundo conocimiento y entendimiento de la materia que imparte.',
  'Llega bien preparado a cada videollamada, con un plan claro y recursos tecnológicos pertinentes.',
  'Presenta el contenido de manera clara, organizada y atractiva.',
  'Fomenta la participación activa, promoviendo el pensamiento crítico y la discusión constructiva.',
  'Proporciona retroalimentación constructiva y puntual que ayuda a mejorar tu aprendizaje.',
  'Se adapta a las necesidades y habilidades cambiantes de los estudiantes a lo largo del curso.',
  'Muestra respeto por las opiniones y perspectivas de los estudiantes, fomentando un ambiente inclusivo.',
  'Incorpora nuevas tecnologías y enfoques pedagógicos para mejorar la enseñanza y el aprendizaje.',
  'Está disponible y es accesible para orientación académica y consultas fuera de la clase en vivo.',
  'Busca activamente mejorar su enseñanza y se mantiene actualizado en su campo de estudio.',
  'Cumple con las políticas del centro: asistencia, puntualidad, integridad académica y trato respetuoso.',
  'Contribuye al desarrollo del programa como agente activo en los eventos de la comunidad académica.',
];

/// (25-sep) Nombres cortos de las 12 dimensiones, para elegir la que más
/// ayudó y la que más puede mejorar (M1-M12, los mismos del Guardián).
const List<String> _dimsCortas = [
  'Dominio de la materia',
  'Preparación de cada clase',
  'Claridad y organización del contenido',
  'Fomento de la participación y pensamiento crítico',
  'Retroalimentación constructiva y puntual',
  'Adaptación a las necesidades del grupo',
  'Respeto e inclusión',
  'Innovación tecnológica y pedagógica',
  'Disponibilidad fuera de clase',
  'Actualización y mejora continua',
  'Cumplimiento de políticas institucionales',
  'Participación en la comunidad académica',
];

/// (25-sep) Escala por FRECUENCIA: obliga a pensar en lo que el docente hizo,
/// no en «estar de acuerdo». Se guarda igual: 5 = Siempre … 1 = Nunca.
const List<String> _escala = ['Nunca', 'Pocas veces', 'A veces', 'Casi siempre', 'Siempre'];

const List<String> _itemsTecnologica = [
  'La bienvenida del curso corresponde a la asignatura y describe su síntesis curricular.',
  'Debajo de la bienvenida aparece la imagen alusiva al curso.',
  'Está habilitado un Foro de avisos debajo de la imagen alusiva al curso.',
  'Aparece el Contenido temático a revisar en el curso.',
  'Es visible el apartado "Conoce a tu profesor(a)" con la síntesis curricular del docente.',
  'Es visible un organizador gráfico con temas, actividades y tareas dosificados por semana.',
  'Se presenta el Encuadre del curso con actividades y tareas con su ponderación.',
  'Se comparte el archivo de Plantillas de trabajos CESSUM.',
  'Se presenta el apartado Clase en vivo con el enlace de Google Meet.',
  'La estructura del curso está claramente identificada por sesión.',
  'En cada sesión aparece el tema y el cintillo correcto que te ubica en el tiempo.',
  'En cada sesión, tras el cintillo, se presenta una síntesis de actividades y trabajos.',
  'En cada sesión aparece inserta la diapositiva del tema con vista preliminar directa.',
  'Las presentaciones retoman el formato institucional CESSUM (colores, tipografía, logo).',
  'En cada sesión aparecen las actividades y tareas con la fecha de entrega correcta.',
  'En cada sesión aparece el video de la clase para tu consulta.',
  'En cada sesión aparece la lista de asistencia a la clase.',
  'Al terminar el curso aparece un apartado de Acta de Calificaciones.',
];

/// Evaluación del Desempeño Docente: pendientes del alumno y formulario
/// personalizado por asignatura. Anónima: la respuesta no guarda la matrícula.
class EvaluacionDocenteScreen extends StatefulWidget {
  final StudentProfile perfil;
  const EvaluacionDocenteScreen({super.key, required this.perfil});

  @override
  State<EvaluacionDocenteScreen> createState() =>
      _EvaluacionDocenteScreenState();
}

class _EvaluacionDocenteScreenState extends State<EvaluacionDocenteScreen> {
  List<Map<String, dynamic>> _pendientes = [];
  bool _cargando = true;
  String? _error;

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
      final uri = Uri.parse(
          '$guardianUrl?accion=evaluaciones_pendientes&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _pendientes = (data['pendientes'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus evaluaciones.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Evaluación docente',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _pendientes.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          '¡Estás al corriente!\nNo tienes evaluaciones docentes pendientes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54, height: 1.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pendientes.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Tu opinión es fundamental y la evaluación es obligatoria al cierre de cada asignatura. '
                              'Es anónima: tus respuestas no se ligan a tu nombre ni matrícula.',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade700,
                                  height: 1.45),
                            ),
                          );
                        }
                        final p = _pendientes[i - 1];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            title: Text(
                              (p['materia'] ?? '') as String,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${p['docente']}\n${p['programa']} · ${p['generacion']}',
                              style: const TextStyle(
                                  fontSize: 12, height: 1.4),
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.rate_review,
                                color: cessumRed),
                            onTap: () async {
                              final ok = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _FormularioEvaluacion(
                                    perfil: widget.perfil,
                                    acta: p,
                                  ),
                                ),
                              );
                              if (ok == true) _cargar();
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}

class _FormularioEvaluacion extends StatefulWidget {
  final StudentProfile perfil;
  final Map<String, dynamic> acta;
  final VoidCallback? onEnviada;
  const _FormularioEvaluacion(
      {required this.perfil, required this.acta, this.onEnviada});

  @override
  State<_FormularioEvaluacion> createState() => _FormularioEvaluacionState();
}

class _FormularioEvaluacionState extends State<_FormularioEvaluacion> {
  final List<int?> _m = List.filled(12, null);
  final List<String?> _t = List.filled(18, null);
  double _dificultad = 5;
  final _comentarios = TextEditingController();
  // (25-sep) Preguntas que discriminan aunque todo sea «Siempre».
  String? _fortaleza; // M1..M12
  String? _mejora; // M1..M12 o 'Ninguna'
  final _ayudo = TextEditingController();
  final _sugerencia = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentarios.dispose();
    _ayudo.dispose();
    _sugerencia.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_m.contains(null)) {
      _aviso('Responde todos los puntos de Mediación docente.');
      return;
    }
    if (_t.contains(null)) {
      _aviso('Responde todos los puntos de Mediación tecnológica (Sí/No).');
      return;
    }
    if (_fortaleza == null || _mejora == null) {
      _aviso('Elige lo que más te ayudó y en qué puede mejorar tu docente.');
      return;
    }
    // Comentario: el general más las dos preguntas guiadas, etiquetadas.
    final partes = <String>[
      if (_comentarios.text.trim().isNotEmpty) _comentarios.text.trim(),
      if (_ayudo.text.trim().isNotEmpty) '[Lo que más me ayudó] ${_ayudo.text.trim()}',
      if (_sugerencia.text.trim().isNotEmpty) '[Sugerencia] ${_sugerencia.text.trim()}',
    ];
    setState(() => _enviando = true);
    try {
      final payload = {
        'accion': 'evaluacion_enviar',
        'matricula': widget.perfil.matricula,
        'programa': widget.acta['programa'],
        'generacion': widget.acta['generacion'],
        'grupo': widget.acta['grupo'],
        'materia': widget.acta['materia'],
        'docente': widget.acta['docente'],
        'm': _m,
        't': _t,
        'dificultad': _dificultad.round(),
        'comentarios': partes.join('\n'),
        'fortaleza': _fortaleza,
        'mejora': _mejora,
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.green,
        content: Text('¡Gracias! Tu evaluación se registró de forma anónima.'),
      ));
      if (widget.onEnviada != null) {
        widget.onEnviada!();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No se pudo enviar. Intenta de nuevo.');
    }
  }

  void _aviso(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.redAccent,
      content: Text(m),
    ));
  }

  Widget _likert(int idx) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${idx + 1}. ${_itemsMediacion[idx]}',
                style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 8),
            // (25-sep) Escala por frecuencia, de «Nunca» a «Siempre».
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(5, (v) {
                final val = v + 1;
                final sel = _m[idx] == val;
                return ChoiceChip(
                  label: Text(_escala[v],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.black87,
                      )),
                  selected: sel,
                  selectedColor: cessumRed,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: sel ? cessumRed : Colors.black26),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _m[idx] = val),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// (25-sep) Elección de una dimensión (fortaleza o «puede mejorar»).
  Widget _eleccionDimension({
    required String pregunta,
    required String? valor,
    required ValueChanged<String?> alCambiar,
    bool conNinguna = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pregunta, style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: valor,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Elige una opción'),
            items: [
              for (var i = 0; i < _dimsCortas.length; i++)
                DropdownMenuItem(value: 'M${i + 1}', child: Text(_dimsCortas[i], overflow: TextOverflow.ellipsis)),
              if (conNinguna)
                const DropdownMenuItem(value: 'Ninguna', child: Text('No tengo sugerencia: todo fue excelente')),
            ],
            onChanged: alCambiar,
          ),
        ]),
      ),
    );
  }

  Widget _siNo(int idx) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          children: [
            Expanded(
              child: Text('${idx + 1}. ${_itemsTecnologica[idx]}',
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
            ),
            const SizedBox(width: 8),
            ...['Sí', 'No'].map((op) {
              final sel = _t[idx] == op;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(op),
                  selected: sel,
                  selectedColor: cessumRed.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                    color: sel ? cessumRed : Colors.black87,
                  ),
                  onSelected: (_) => setState(() => _t[idx] = op),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _tituloSeccion(String t, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: cessumRed)),
          if (sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sub,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54, height: 1.4)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.acta;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Evaluación docente',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            color: const Color(0xFFF5F1E8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (a['materia'] ?? '') as String,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Docente: ${a['docente']}\n${a['programa']} · Generación ${a['generacion']} · ${(a['grupo'] ?? '').toString() == '2' ? 'Sabatino' : 'Entre semana'}',
                    style: const TextStyle(fontSize: 12.5, height: 1.45),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Indica con qué frecuencia ocurrió cada punto, de «Nunca» a «Siempre». Piensa en lo que tu docente hizo en clase. Tu participación es anónima.',
                    style: TextStyle(
                        fontSize: 11.5, color: Colors.black54, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          _tituloSeccion('Dimensión: Mediación docente', ''),
          ...List.generate(12, _likert),
          _tituloSeccion('Dimensión: Mediación tecnológica',
              'Sobre el aula virtual de la asignatura en Moodle.'),
          ...List.generate(18, _siNo),
          // (25-sep) Dos elecciones obligatorias que discriminan aunque todo
          // sea «Siempre», y dos preguntas abiertas guiadas (opcionales).
          _tituloSeccion('Lo más valioso y lo que puede mejorar',
              'Elige una sola opción en cada pregunta. Ayuda a tu docente a saber qué conservar y qué cuidar.'),
          _eleccionDimension(
            pregunta: '¿Qué fue lo que MÁS te ayudó a aprender con este docente?',
            valor: _fortaleza,
            alCambiar: (v) => setState(() => _fortaleza = v),
          ),
          _eleccionDimension(
            pregunta: '¿En qué aspecto podría mejorar MÁS?',
            valor: _mejora,
            alCambiar: (v) => setState(() => _mejora = v),
            conNinguna: true,
          ),
          TextField(
            controller: _ayudo,
            maxLines: 2,
            maxLength: 400,
            decoration: const InputDecoration(
              labelText: '¿Qué hizo tu docente que más te ayudó? (opcional)',
              hintText: 'Por ejemplo: un ejemplo, una actividad o una forma de explicar',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _sugerencia,
            maxLines: 2,
            maxLength: 400,
            decoration: const InputDecoration(
              labelText: '¿Qué le sugerirías para la próxima vez? (opcional)',
              hintText: 'Una acción concreta que te habría ayudado más',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          _tituloSeccion('Nivel de dificultad', ''),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'En una escala de 1 a 10, ¿cómo calificarías el nivel de dificultad de la asignatura? Tu respuesta: ${_dificultad.round()}',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  Slider(
                    value: _dificultad,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    activeColor: cessumRed,
                    label: '${_dificultad.round()}',
                    onChanged: (v) => setState(() => _dificultad = v),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Demasiado sencillo',
                          style: TextStyle(
                              fontSize: 10, color: Colors.black45)),
                      Text('Demasiado complicado',
                          style: TextStyle(
                              fontSize: 10, color: Colors.black45)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comentarios,
            maxLines: 4,
            maxLength: 800,
            decoration: const InputDecoration(
              labelText:
                  'Comentarios generales sobre la asignatura, el docente o CESSUM',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _enviando ? null : _enviar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label:
                  Text(_enviando ? 'Enviando...' : 'Enviar evaluación'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
//  EVALUACIÓN DOCENTE DESTACADA (jul-2026)
//  Presenta la evaluación de la materia MÁS RECIENTE del alumno como
//  invitación destacada (NO bloqueante: puede regresar cuando quiera).
//  Reutiliza _FormularioEvaluacion (definido arriba, mismo archivo).
//  Se invoca desde el banner del menú del alumno.
// ============================================================
class EvaluacionObligatoriaGate extends StatelessWidget {
  final StudentProfile perfil;
  final Map<String, dynamic> obligatoria;
  const EvaluacionObligatoriaGate({
    super.key,
    required this.perfil,
    required this.obligatoria,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Evalúa a tu docente',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          // Mensaje persuasivo (no obligatorio).
          Container(
            width: double.infinity,
            color: cessumGold.withValues(alpha: 0.12),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.volunteer_activism,
                        color: cessumGold, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tu opinión hace mejores tus clases',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: cessumGold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${obligatoria['materia'] ?? ''} · ${obligatoria['docente'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Es anónima y te toma menos de 2 minutos. Con tu respuesta, '
                  'CESSUM reconoce lo que funciona y mejora lo que no.',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          // El formulario de esa materia (reutiliza el existente).
          Expanded(
            child: _FormularioEvaluacion(
              perfil: perfil,
              acta: obligatoria,
              onEnviada: () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
    );
  }
}

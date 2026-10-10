import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'foto_web_picker.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Solicitud de ADAPTACIÓN AL PLAN DE ESTUDIOS por UN SOLO PERIODO.
/// A diferencia del "Cambio de modalidad" (que es permanente), aquí el alumno
/// de modalidad Mixta pide cursar de forma virtual SOLO un periodo específico.
/// Se registra como trámite (tipo "Adaptación de modalidad (un periodo)") y lo
/// evalúa el Consejo Directivo de CESSUM (respuesta en máx. 72 horas).
class SolicitudAdaptacionModalidadScreen extends StatefulWidget {
  const SolicitudAdaptacionModalidadScreen({super.key});

  @override
  State<SolicitudAdaptacionModalidadScreen> createState() =>
      _SolicitudAdaptacionModalidadScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _SolicitudAdaptacionModalidadScreenState
    extends State<SolicitudAdaptacionModalidadScreen> {
  final _nombre = TextEditingController();
  final _programa = TextEditingController();
  final _periodo = TextEditingController();
  // (ago-2026) ALCANCE del ajuste: la solicitud puede ser tan específica
  // como una sola materia (caso típico: reposo médico de una semana), unas
  // semanas, o el periodo completo.
  String _alcance = 'Materia';
  List<Map<String, dynamic>> _misMaterias = [];
  Map<String, dynamic>? _materiaSel;
  final _semanas = TextEditingController();
  final _descripcion = TextEditingController();

  String _matricula = '';
  String _correo = '';
  String _modalidadActual = '';
  String _generacion = '';

  FotoElegida? _evidencia;
  bool _acepta = false;
  bool _enviando = false;
  bool _enviado = false;

  @override
  void initState() {
    super.initState();
    _prellenar();
  }

  Future<void> _prellenar() async {
    final perfil = await StudentProfile.load();
    final correo = await SessionStore.validEmail();
    if (!mounted) return;
    setState(() {
      if (perfil != null) {
        _nombre.text = perfil.nombreCompleto;
        _programa.text = perfil.programa;
        _matricula = perfil.matricula;
        _modalidadActual = perfil.modalidad;
        _generacion = perfil.generacion;
      }
      if (correo != null && correo.isNotEmpty) _correo = correo;
    });
    _cargarMisMaterias();
  }

  Future<void> _cargarMisMaterias() async {
    if (_matricula.trim().isEmpty) return;
    try {
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alumno_materias_panorama',
        'matricula': _matricula,
      });
      final r = await http.get(u).timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true || !mounted) return;
      final lista = <Map<String, dynamic>>[];
      for (final k in ['enCurso', 'futuras']) {
        for (final m in ((d[k] as List?) ?? [])) {
          lista.add(Map<String, dynamic>.from(m as Map));
        }
      }
      setState(() => _misMaterias = lista);
    } catch (_) {
      // Sin lista no pasa nada: el alumno describe con semanas o periodo.
    }
  }

  Future<void> _elegirMateria() async {
    final sel = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        var filtro = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final vis = _misMaterias.where((m) {
              if (filtro.isEmpty) return true;
              final t = '${m['materia']} ${m['docente'] ?? ''}'.toLowerCase();
              return t.contains(filtro.toLowerCase());
            }).toList();
            return AlertDialog(
              title: const Text('¿De qué materia es el ajuste?'),
              content: SizedBox(
                width: 460,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: 'Buscar materia…',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setLocal(() => filtro = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: vis.isEmpty
                          ? Center(
                              child: Text(
                                  'No hay materias próximas registradas.\nElige "Semanas" o "Periodo" y descríbela.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12, color: cessumMuted(context))))
                          : ListView(
                              children: [
                                for (final m in vis)
                                  ListTile(
                                    dense: true,
                                    title: Text('${m['materia']}',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                        'Del ${m['inicio']} al ${m['termino']}'
                                        '${(m['docente'] ?? '').toString().isNotEmpty ? '\n${m['docente']}' : ''}',
                                        style:
                                            const TextStyle(fontSize: 11.5)),
                                    onTap: () => Navigator.pop(ctx, m),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar')),
              ],
            );
          },
        );
      },
    );
    if (sel != null) setState(() => _materiaSel = sel);
  }

  String _detalleAlcance() {
    if (_alcance == 'Materia') {
      return _materiaSel == null
          ? ''
          : 'SOLO la materia "${_materiaSel!['materia']}" '
              '(del ${_materiaSel!['inicio']} al ${_materiaSel!['termino']}'
              '${(_materiaSel!['docente'] ?? '').toString().isNotEmpty ? ', con ${_materiaSel!['docente']}' : ''})';
    }
    if (_alcance == 'Semanas') {
      return _semanas.text.trim().isEmpty
          ? ''
          : 'Las semanas: ${_semanas.text.trim()}';
    }
    return _periodo.text.trim().isEmpty
        ? ''
        : 'El periodo completo: ${_periodo.text.trim()}';
  }

  @override
  void dispose() {
    for (final c in [_nombre, _programa, _periodo, _semanas, _descripcion]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirEvidencia() async {
    try {
      final foto = await seleccionarFoto();
      if (foto != null && mounted) setState(() => _evidencia = foto);
    } catch (_) {
      _aviso('No se pudo abrir el selector de archivos.');
    }
  }

  String? _falta() {
    if (_nombre.text.trim().isEmpty) return 'Escribe tu nombre completo.';
    if (_matricula.trim().isEmpty) return 'No encontramos tu matrícula.';
    if (_programa.text.trim().isEmpty) return 'Escribe tu programa académico.';
    if (_alcance == 'Materia' && _materiaSel == null) {
      return 'Elige la materia de la que solicitas el ajuste.';
    }
    if (_alcance == 'Semanas' && _semanas.text.trim().isEmpty) {
      return 'Indica las semanas del ajuste (ej. del 5 al 16 de agosto).';
    }
    if (_alcance == 'Periodo' && _periodo.text.trim().isEmpty) {
      return 'Indica el periodo del que solicitas el ajuste.';
    }
    if (_descripcion.text.trim().isEmpty) {
      return 'Describe detalladamente tu solicitud.';
    }
    if (!_acepta) {
      return 'Confirma que entiendes que el Consejo Directivo evaluará tu solicitud.';
    }
    return null;
  }

  Future<void> _enviar() async {
    final falta = _falta();
    if (falta != null) {
      _aviso(falta);
      return;
    }
    setState(() => _enviando = true);
    try {
      final actual = _modalidadActual.trim().isEmpty
          ? 'Sin registrar'
          : _modalidadActual.trim();
      final detalle = _detalleAlcance();
      final observaciones = 'Solicitud de ADAPTACIÓN DE MODALIDAD '
          '(temporal, no permanente).\n'
          'ALCANCE del ajuste: $detalle\n'
          'Modalidad actual: $actual\n'
          'Descripción: ${_descripcion.text.trim()}\n'
          'Evaluación: Consejo Directivo de CESSUM (máx. 72 horas).';

      final payload = <String, dynamic>{
        'accion': 'tramite_enviar',
        'tipoTramite': 'Adaptación de modalidad (un periodo)',
        'nombre': _nombre.text.trim(),
        'matricula': _matricula,
        'correo': _correo,
        'programa': _programa.text.trim(),
        'modalidad': actual,
        'generacion': _generacion,
        'observaciones': observaciones,
        'clientToken':
            'adapta-modalidad|$_matricula|${_detalleAlcance()}',
      };
      if (_evidencia != null) {
        payload['comprobanteBase64'] = base64Encode(_evidencia!.bytes);
        payload['comprobanteMime'] = _evidencia!.mime;
      }

      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(
            data['error'] ?? 'El Guardián no pudo registrar la solicitud.');
      }
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _enviado = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No se pudo enviar: $e');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Adaptación de modalidad'),
      ),
      body: _enviado ? _exito() : _formulario(),
    );
  }

  Widget _exito() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: _verdeOk, size: 64),
            const SizedBox(height: 16),
            Text('¡Solicitud enviada!',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: cessumInk(context))),
            const SizedBox(height: 8),
            Text(
              'El Consejo Directivo de CESSUM evaluará tu solicitud. '
              'Recibirás una respuesta en un plazo máximo de 72 horas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context)),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulario() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: cessumGold.withValues(alpha: 0.12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Solicita cursar de forma virtual SOLO un periodo específico '
              '(no es un cambio permanente). Tu solicitud será valorada por el '
              'Consejo Directivo de CESSUM.',
              style: TextStyle(color: cessumInk(context)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _label('Nombre completo'),
        TextField(
            controller: _nombre, decoration: _dec('Tu nombre completo')),
        const SizedBox(height: 8),
        _label('Matrícula'),
        TextField(
          enabled: false,
          decoration: _dec(_matricula.isEmpty ? 'Cargando…' : _matricula),
        ),
        const SizedBox(height: 8),
        _label('Programa académico'),
        TextField(
            controller: _programa, decoration: _dec('Tu programa académico')),
        const SizedBox(height: 8),
        _label('¿Qué tan específico es tu ajuste?'),
        Wrap(
          spacing: 8,
          children: [
            for (final a in ['Materia', 'Semanas', 'Periodo'])
              ChoiceChip(
                label: Text(a == 'Materia'
                    ? 'Una materia'
                    : a == 'Semanas'
                        ? 'Una o varias semanas'
                        : 'Un periodo completo'),
                selected: _alcance == a,
                selectedColor: cessumRed.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _alcance == a ? cessumRed : cessumInk(context)),
                onSelected: (_) => setState(() => _alcance = a),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_alcance == 'Materia') ...[
          _label('Materia del ajuste'),
          InkWell(
            onTap: _elegirMateria,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: _dec(_materiaSel == null
                  ? 'Toca para elegir tu materia (con buscador)'
                  : ''),
              child: Text(
                _materiaSel == null
                    ? 'Elegir materia…'
                    : '${_materiaSel!['materia']}\nDel ${_materiaSel!['inicio']} al ${_materiaSel!['termino']}'
                        '${(_materiaSel!['docente'] ?? '').toString().isNotEmpty ? ' · ${_materiaSel!['docente']}' : ''}',
                style: TextStyle(
                    fontSize: 13,
                    color: _materiaSel == null
                        ? cessumFaint(context)
                        : cessumInk(context)),
              ),
            ),
          ),
        ] else if (_alcance == 'Semanas') ...[
          _label('¿Qué semanas?'),
          TextField(
            controller: _semanas,
            decoration: _dec('Ej. del 5 al 16 de agosto de 2026'),
          ),
        ] else ...[
          _label('Periodo del que solicitas el ajuste'),
          TextField(
            controller: _periodo,
            decoration: _dec('Ej. Cuatrimestre Sep–Dic 2026'),
          ),
        ],
        const SizedBox(height: 8),
        _label('Describe detalladamente tu solicitud'),
        TextField(
          controller: _descripcion,
          maxLines: 5,
          decoration: _dec(
              'Motivos por los que solicitas cursar virtual este periodo y '
              'cualquier circunstancia personal (laboral, salud, etc.).'),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          icon: const Icon(Icons.attach_file, color: cessumRed),
          label: Text(
            _evidencia == null
                ? 'Adjuntar evidencia (opcional)'
                : 'Evidencia adjuntada ✓',
            style: const TextStyle(color: cessumRed),
          ),
          onPressed: _elegirEvidencia,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _acepta,
          activeColor: cessumRed,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) => setState(() => _acepta = v ?? false),
          title: Text(
            'Entiendo que mi solicitud será evaluada por el Consejo Directivo '
            'de CESSUM y recibiré una respuesta en un plazo máximo de 72 horas.',
            style: TextStyle(fontSize: 13, color: cessumInk(context)),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: cessumRed,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _enviando ? null : _enviar,
          child: _enviando
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Enviar solicitud'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 4),
        child: Text(t,
            style: TextStyle(
                fontWeight: FontWeight.w700, color: cessumInk(context))),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Theme.of(context).cardColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

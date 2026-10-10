import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'foto_web_picker.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Justificación de faltas DESDE la app (reemplaza el formulario de Google).
/// Prellena los datos que ya están en la base, permite adjuntar una evidencia
/// (foto) y la envía al Guardián. La solicitud llega al docente y al admin.
class JustificacionFaltasScreen extends StatefulWidget {
  const JustificacionFaltasScreen({super.key});

  @override
  State<JustificacionFaltasScreen> createState() =>
      _JustificacionFaltasScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _JustificacionFaltasScreenState extends State<JustificacionFaltasScreen> {
  final _nombre = TextEditingController();
  final _matricula = TextEditingController();
  final _correo = TextEditingController();
  final _celular = TextEditingController();
  final _fechaSesion = TextEditingController();
  final _fechasAdicionales = TextEditingController();
  final _materia = TextEditingController();
  final _docente = TextEditingController();

  // Materias del alumno (encuesta_materias_alumno): así elige de una lista y el
  // nombre del docente queda EXACTO al de la base, para que su justificación le
  // aparezca al profesor correcto en su pantalla de solo lectura.
  List<Map<String, String>> _misMaterias = [];
  String? _materiaSel; // clave del dropdown: 'materia||docente'
  bool _cargandoMaterias = false;
  bool _materiasManual = false; // fallback a texto si no hay lista
  final _detalles = TextEditingController();

  String _programa = '';
  String _generacion = '';

  String? _motivo;
  static const List<String> _motivos = [
    'Enfermedad',
    'Cita o emergencia médica',
    'Asunto laboral',
    'Asunto familiar',
    'Problema de conexión o técnico',
    'Otro',
  ];

  FotoElegida? _evidencia;
  bool _declara = false;
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
        _matricula.text = perfil.matricula;
        _programa = perfil.programa;
        _generacion = perfil.generacion;
      }
      if (correo != null && correo.isNotEmpty) _correo.text = correo;
    });
    await _cargarMisMaterias();
  }

  Future<void> _cargarMisMaterias() async {
    final mat = _matricula.text.trim();
    if (mat.isEmpty) {
      setState(() => _materiasManual = true);
      return;
    }
    setState(() => _cargandoMaterias = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'encuesta_materias_alumno',
        'matricula': mat,
        'vigentes': 'true', // solo materias que el alumno cursa ahora
        if (_programa.isNotEmpty) 'programa': _programa,
        if (_generacion.isNotEmpty) 'generacion': _generacion,
      });
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final lista = (data['materias'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((m) => (m['materia'] ?? '').toString().trim().isNotEmpty)
          .map((m) => {
                'materia': (m['materia'] ?? '').toString().trim(),
                'docente': (m['docente'] ?? '').toString().trim(),
              })
          .toList();
      if (!mounted) return;
      setState(() {
        _misMaterias = lista;
        _materiasManual = lista.isEmpty; // sin lista -> permite escribir
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _materiasManual = true); // error -> no bloquear
    } finally {
      if (mounted) setState(() => _cargandoMaterias = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nombre, _matricula, _correo, _celular, _fechaSesion,
      _fechasAdicionales, _materia, _docente, _detalles
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    try {
      final f = await showDatePicker(
        context: context,
        initialDate: ahora,
        firstDate: DateTime(ahora.year - 1),
        lastDate: DateTime(ahora.year + 1),
      );
      if (f != null) {
        final dd = f.day.toString().padLeft(2, '0');
        final mm = f.month.toString().padLeft(2, '0');
        setState(() => _fechaSesion.text = '$dd/$mm/${f.year}');
      }
    } catch (_) {
      _aviso('Si el calendario no abre, escribe la fecha como DD/MM/AAAA.');
    }
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
    if (_matricula.text.trim().isEmpty) return 'Escribe tu matrícula.';
    if (_correo.text.trim().isEmpty) return 'Escribe tu correo.';
    if (_celular.text.trim().isEmpty) return 'Escribe tu número de celular.';
    if (_fechaSesion.text.trim().isEmpty) return 'Indica la fecha de la sesión.';
    if (_materia.text.trim().isEmpty) {
      return _materiasManual
          ? 'Escribe el nombre de la materia.'
          : 'Elige tu materia de la lista.';
    }
    if (_docente.text.trim().isEmpty) return 'Falta el docente de la materia.';
    if (_motivo == null) return 'Selecciona el motivo de la falta.';
    if (_detalles.text.trim().isEmpty) return 'Explica brevemente la situación.';
    if (!_declara) return 'Debes confirmar que la información es veraz.';
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
      final payload = <String, dynamic>{
        'accion': 'justificacion_enviar',
        'nombre': _nombre.text.trim(),
        'matricula': _matricula.text.trim(),
        'correo': _correo.text.trim(),
        'celular': _celular.text.trim(),
        'fechaSesion': _fechaSesion.text.trim(),
        'fechasAdicionales': _fechasAdicionales.text.trim(),
        'materia': _materia.text.trim(),
        'docente': _docente.text.trim(),
        'motivo': _motivo,
        'detalles': _detalles.text.trim(),
        'programa': _programa,
        'generacion': _generacion,
      };
      if (_evidencia != null) {
        payload['evidenciaBase64'] = base64Encode(_evidencia!.bytes);
        payload['evidenciaMime'] = _evidencia!.mime;
      }
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || data.containsKey('guardadas')) {
        throw Exception(data['error'] ??
            'El Guardián no pudo registrar la justificación.');
      }
      if (mounted) {
        setState(() {
          _enviando = false;
          _enviado = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _enviando = false);
      _aviso('No se pudo enviar: $e');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Justificación de faltas'),
      ),
      body: _enviando
          ? Center(child: CircularProgressIndicator(color: cessumRed))
          : _enviado
              ? _vistaEnviado()
              : _formulario(),
    );
  }

  Widget _vistaEnviado() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: _verdeOk, size: 64),
            SizedBox(height: 16),
            Text(
              'Tu justificación se envió correctamente.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cessumInk(context)),
            ),
            SizedBox(height: 8),
            Text(
              'Tu docente y la coordinación la recibirán. La revisión y '
              'validación la hace la administración.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
              child: Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulario() {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        _aviso0(
          'Justifica tu ausencia en una sesión en vivo. Adjunta la evidencia '
          'y da información precisa. Envíala al menos una hora antes de la '
          'clase, salvo casos excepcionales.',
        ),
        _seccion('Información personal'),
        _campo(_nombre, 'Nombre completo *'),
        _campo(_matricula, 'Número de matrícula *',
            tipo: TextInputType.number),
        _campo(_correo, 'Correo electrónico *',
            tipo: TextInputType.emailAddress),
        _campo(_celular, 'Número de celular *', tipo: TextInputType.phone),
        _seccion('Información de la sesión'),
        _campoFecha(),
        _campo(_fechasAdicionales,
            'Si faltó a más sesiones, escribe las otras fechas (opcional)',
            lineas: 2),
        _selectorMateria(),
        _seccion('Motivo de la falta'),
        _dropdownMotivo(),
        _campo(_detalles, 'Detalles del motivo (explicación breve) *',
            lineas: 3),
        SizedBox(height: 6),
        _evidenciaWidget(),
        _seccion('Confirmación'),
        _checkDeclaracion(),
        SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _enviar,
            icon: Icon(Icons.send),
            label: Text('Enviar justificación'),
          ),
        ),
        SizedBox(height: 24),
      ],
    );
  }

  Widget _aviso0(String txt) {
    return Container(
      padding: EdgeInsets.all(12),
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
      ),
      child: Text(
        txt,
        style: TextStyle(fontSize: 12, color: cessumMuted(context), height: 1.35),
      ),
    );
  }

  Widget _seccion(String t) {
    return Padding(
      padding: EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        t,
        style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed),
      ),
    );
  }

  // Selector de materia: dropdown poblado con las materias del alumno. Al
  // elegir, fija _materia y _docente (nombre EXACTO de la base). Si no hay
  // lista (sin conexión / sin materias), cae a dos campos de texto.
  Widget _selectorMateria() {
    if (_cargandoMaterias) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Cargando tus materias...'),
        ]),
      );
    }

    if (_materiasManual) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _campo(_materia, 'Nombre de la materia *'),
          _campo(_docente, 'Nombre del docente *'),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'No pudimos cargar tu lista de materias; escríbelas tal como '
              'aparecen en tu horario.',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: DropdownButtonFormField<String>(
            value: _materiaSel,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Materia *',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: _misMaterias.map((m) {
              final key = '${m['materia']}||${m['docente']}';
              final docTxt = (m['docente'] ?? '').isEmpty
                  ? ''
                  : ' — ${m['docente']}';
              return DropdownMenuItem(
                value: key,
                child: Text('${m['materia']}$docTxt',
                    overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) {
              if (v == null) return;
              final sel = _misMaterias.firstWhere(
                (m) => '${m['materia']}||${m['docente']}' == v,
                orElse: () => {'materia': '', 'docente': ''},
              );
              setState(() {
                _materiaSel = v;
                _materia.text = sel['materia'] ?? '';
                _docente.text = sel['docente'] ?? '';
              });
            },
          ),
        ),
        if (_docente.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Docente: ${_docente.text.trim()}',
                style: TextStyle(fontSize: 12.5, color: cessumFaint(context))),
          ),
      ],
    );
  }

  Widget _campo(TextEditingController c, String etq,
      {TextInputType? tipo, int lineas = 1}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: tipo,
        maxLines: lineas,
        inputFormatters: tipo == TextInputType.number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: etq,
          filled: true,
          fillColor: cessumEsOscuro(context) ? const Color(0xFF211F1D) : Colors.white,
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _campoFecha() {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _fechaSesion,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          labelText: 'Fecha de la sesión en vivo *',
          hintText: 'DD/MM/AAAA (o toca el calendario)',
          filled: true,
          fillColor: cessumEsOscuro(context) ? const Color(0xFF211F1D) : Colors.white,
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            icon: Icon(Icons.calendar_today, color: cessumRed),
            tooltip: 'Elegir en el calendario',
            onPressed: _elegirFecha,
          ),
        ),
      ),
    );
  }

  Widget _dropdownMotivo() {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: _motivo,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Motivo de la falta *',
          filled: true,
          fillColor: cessumEsOscuro(context) ? const Color(0xFF211F1D) : Colors.white,
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: _motivos
            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
            .toList(),
        onChanged: (v) => setState(() => _motivo = v),
      ),
    );
  }

  Widget _evidenciaWidget() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: cessumEsOscuro(context) ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: _evidencia != null
                ? Image.memory(
                    Uint8List.fromList(_evidencia!.bytes),
                    fit: BoxFit.cover,
                  )
                : Icon(Icons.attach_file, color: cessumFaint(context)),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Evidencia (foto)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: cessumInk(context)),
                ),
                Text(
                  _evidencia != null
                      ? 'Foto adjuntada'
                      : 'Opcional: toma o elige una foto del comprobante',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _elegirEvidencia,
            child: Text(_evidencia != null ? 'Cambiar' : 'Adjuntar',
                style: TextStyle(color: cessumRed)),
          ),
        ],
      ),
    );
  }

  Widget _checkDeclaracion() {
    return InkWell(
      onTap: () => setState(() => _declara = !_declara),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: _declara ? _verdeOk : cessumMuted(context).withValues(alpha: 0.18),
              width: _declara ? 1.4 : 1),
        ),
        child: Row(
          children: [
            Checkbox(
              value: _declara,
              activeColor: _verdeOk,
              onChanged: (v) => setState(() => _declara = v ?? false),
            ),
            Expanded(
              child: Text(
                'Declaro que la información proporcionada es veraz y que leí el '
                'procedimiento para justificar faltas. *',
                style: TextStyle(fontSize: 13, color: cessumInk(context), height: 1.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'foto_web_picker.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Solicitud de baja DESDE la app. Prellena datos de la base, registra el tipo
/// (temporal/definitiva) y el motivo, y la envía al Guardián para que la
/// administración la valide.
class SolicitudBajaScreen extends StatefulWidget {
  const SolicitudBajaScreen({super.key});

  @override
  State<SolicitudBajaScreen> createState() => _SolicitudBajaScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _SolicitudBajaScreenState extends State<SolicitudBajaScreen> {
  final _nombre = TextEditingController();
  final _programa = TextEditingController();
  final _generacion = TextEditingController();
  final _tiempo = TextEditingController();
  final _comentarios = TextEditingController();

  String _matricula = '';
  String _correo = '';

  String? _tipoBaja;
  static const List<String> _tipos = ['Temporal', 'Definitiva'];

  String? _motivo;
  static const List<String> _motivos = [
    'Motivos académicos',
    'Motivos personales',
    'Motivos financieros',
    'Calidad de la enseñanza y plan de estudios',
    'Factores externos',
    'Otro',
  ];

  FotoElegida? _evidencia;
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
        _generacion.text = perfil.generacion;
        _matricula = perfil.matricula;
      }
      if (correo != null && correo.isNotEmpty) _correo = correo;
    });
  }

  @override
  void dispose() {
    for (final c in [_nombre, _programa, _generacion, _tiempo, _comentarios]) {
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
    if (_programa.text.trim().isEmpty) return 'Escribe tu programa.';
    if (_generacion.text.trim().isEmpty) return 'Escribe tu generación.';
    if (_tiempo.text.trim().isEmpty) {
      return 'Indica cuánto tiempo llevas cursando.';
    }
    if (_tipoBaja == null) return 'Selecciona el tipo de baja.';
    if (_motivo == null) return 'Selecciona el motivo principal.';
    if (_comentarios.text.trim().isEmpty) {
      return 'Cuéntanos los detalles de tu decisión.';
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
      final payload = <String, dynamic>{
        'accion': 'baja_enviar',
        'nombre': _nombre.text.trim(),
        'matricula': _matricula,
        'correo': _correo,
        'programa': _programa.text.trim(),
        'generacion': _generacion.text.trim(),
        'tiempoCursando': _tiempo.text.trim(),
        'tipoBaja': _tipoBaja,
        'motivo': _motivo,
        'comentarios': _comentarios.text.trim(),
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
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || data.containsKey('guardadas')) {
        throw Exception(
            data['error'] ?? 'El Guardián no pudo registrar la solicitud.');
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
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Solicitud de baja'),
      ),
      body: _enviando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _enviado
              ? _vistaEnviado()
              : _formulario(),
    );
  }

  Widget _vistaEnviado() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: _verdeOk, size: 64),
            const SizedBox(height: 16),
            Text(
              'Tu solicitud de baja se envió.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cessumInk(context)),
            ),
            const SizedBox(height: 8),
            Text(
              'La administración la revisará y te contactará. Gracias por '
              'compartir tus motivos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
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
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
          ),
          child: Text(
            'Lamentamos que estés considerando darte de baja. Tus respuestas '
            'son confidenciales y nos ayudan a mejorar. Cuéntanos con detalle '
            'tus motivos.',
            style:
                TextStyle(fontSize: 12, color: cessumMuted(context), height: 1.35),
          ),
        ),
        _seccion('Datos del estudiante'),
        _campo(_nombre, 'Nombre del estudiante *'),
        _campo(_programa, 'Programa académico *'),
        _campo(_generacion, 'Generación *'),
        _campo(_tiempo, 'Tiempo que llevas cursando el programa *'),
        _seccion('Tipo y motivo de la baja'),
        _dropdown('Tipo de baja *', _tipos, _tipoBaja,
            (v) => setState(() => _tipoBaja = v)),
        _dropdown('Motivo principal *', _motivos, _motivo,
            (v) => setState(() => _motivo = v)),
        _campo(_comentarios,
            'Comentarios y detalles (mientras más detalle, mejor) *',
            lineas: 4),
        const SizedBox(height: 6),
        _evidenciaWidget(),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _enviar,
            icon: const Icon(Icons.send),
            label: const Text('Enviar solicitud de baja'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _seccion(String t) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        t,
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed),
      ),
    );
  }

  Widget _campo(TextEditingController c, String etq, {int lineas = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lineas,
        decoration: InputDecoration(
          labelText: etq,
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dropdown(String etq, List<String> ops, String? val,
      ValueChanged<String?> onCh) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: val,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: etq,
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: ops
            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
            .toList(),
        onChanged: onCh,
      ),
    );
  }

  Widget _evidenciaWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
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
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: _evidencia != null
                ? Image.memory(Uint8List.fromList(_evidencia!.bytes),
                    fit: BoxFit.cover)
                : Icon(Icons.attach_file, color: cessumFaint(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Documento o evidencia (opcional)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: cessumInk(context))),
                Text(
                  _evidencia != null
                      ? 'Archivo adjuntado'
                      : 'Si quieres, adjunta una foto de algún documento',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _elegirEvidencia,
            child: Text(_evidencia != null ? 'Cambiar' : 'Adjuntar',
                style: const TextStyle(color: cessumRed)),
          ),
        ],
      ),
    );
  }
}

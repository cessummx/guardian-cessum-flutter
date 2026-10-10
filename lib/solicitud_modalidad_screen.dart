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

/// Solicitud de CAMBIO DE MODALIDAD desde la app del estudiante.
/// Prellena los datos del alumno, deja elegir la modalidad deseada, pedir los
/// motivos y (opcional) adjuntar evidencia. Se registra como un trámite escolar
/// (tipo "Cambio de modalidad") para que la administración lo revise y valide.
/// El cambio NO es automático: depende de la aprobación de Vicerrectoría.
class SolicitudModalidadScreen extends StatefulWidget {
  const SolicitudModalidadScreen({super.key});

  @override
  State<SolicitudModalidadScreen> createState() =>
      _SolicitudModalidadScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _SolicitudModalidadScreenState extends State<SolicitudModalidadScreen> {
  final _nombre = TextEditingController();
  final _programa = TextEditingController();
  final _generacion = TextEditingController();
  final _comentarios = TextEditingController();

  String _matricula = '';
  String _correo = '';
  String _modalidadActual = '';

  // Modalidades que maneja CESSUM. La deseada nunca puede ser la actual.
  static const List<String> _modalidades = [
    'Virtual',
    'Mixta',
    'No Escolarizada',
  ];
  String? _modalidadDeseada;

  String? _motivo;
  static const List<String> _motivos = [
    'Motivos laborales',
    'Motivos personales o de salud',
    'Cambio de domicilio o distancia',
    'Motivos económicos',
    'Disponibilidad de horario',
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
        _modalidadActual = perfil.modalidad;
      }
      if (correo != null && correo.isNotEmpty) _correo = correo;
    });
  }

  @override
  void dispose() {
    for (final c in [_nombre, _programa, _generacion, _comentarios]) {
      c.dispose();
    }
    super.dispose();
  }

  // Opciones de modalidad deseada: todas menos la actual (sin distinguir
  // mayúsculas/acentos para no ofrecer la misma que ya tiene).
  List<String> get _opcionesDeseada {
    final actual = _norm(_modalidadActual);
    return _modalidades.where((m) => _norm(m) != actual).toList();
  }

  String _norm(String s) {
    s = s.toLowerCase().trim();
    const con = 'áàäâéèëêíìïîóòöôúùüûñ';
    const sin = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
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
    if (_modalidadDeseada == null) {
      return 'Selecciona la modalidad a la que quieres cambiarte.';
    }
    if (_motivo == null) return 'Selecciona el motivo principal.';
    if (_comentarios.text.trim().isEmpty) {
      return 'Explica las razones de tu solicitud.';
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
      final actual =
          _modalidadActual.trim().isEmpty ? 'Sin registrar' : _modalidadActual.trim();
      final observaciones = 'Solicitud de cambio de modalidad.\n'
          'Modalidad actual: $actual\n'
          'Modalidad deseada: $_modalidadDeseada\n'
          'Motivo principal: $_motivo\n'
          'Razones: ${_comentarios.text.trim()}';

      final payload = <String, dynamic>{
        'accion': 'tramite_enviar',
        'tipoTramite': 'Cambio de modalidad',
        'nombre': _nombre.text.trim(),
        'matricula': _matricula,
        'correo': _correo,
        'programa': _programa.text.trim(),
        'modalidad': actual,
        'generacion': _generacion.text.trim(),
        'observaciones': observaciones,
        'clientToken': 'modalidad|$_matricula|$_modalidadDeseada',
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
      if (mounted) {
        setState(() {
          _enviando = false;
          _enviado = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _enviando = false);
      _aviso('No se pudo enviar: $e'.replaceAll('Exception: ', ''));
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
        title: const Text('Cambio de modalidad'),
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
              'Tu solicitud de cambio de modalidad se envió.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cessumInk(context)),
            ),
            const SizedBox(height: 8),
            Text(
              'Quedó registrada como trámite escolar con estatus Pendiente. '
              'Vicerrectoría la revisará y te notificaremos la resolución por '
              'correo. Recuerda: el cambio no es automático, depende de la '
              'aprobación.',
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
            'El cambio de modalidad está sujeto a revisión y aprobación de '
            'Vicerrectoría. No es automático: tu solicitud será evaluada con '
            'base en tus razones y, si procede, te cambiaremos al grupo de la '
            'nueva modalidad. Te notificaremos la resolución por correo.',
            style:
                TextStyle(fontSize: 12, color: cessumMuted(context), height: 1.35),
          ),
        ),
        _seccion('Datos del estudiante'),
        _campo(_nombre, 'Nombre del estudiante *'),
        _campo(_programa, 'Programa académico *'),
        _campo(_generacion, 'Generación *'),
        _campoModalidadActual(),
        _seccion('Cambio que solicitas'),
        _dropdown('Modalidad deseada *', _opcionesDeseada, _modalidadDeseada,
            (v) => setState(() => _modalidadDeseada = v)),
        _dropdown('Motivo principal *', _motivos, _motivo,
            (v) => setState(() => _motivo = v)),
        _campo(_comentarios,
            'Explica con detalle las razones de tu solicitud *',
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
            label: const Text('Enviar solicitud'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _campoModalidadActual() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: TextEditingController(
          text: _modalidadActual.trim().isEmpty
              ? 'Sin registrar'
              : _modalidadActual.trim(),
        ),
        enabled: false,
        decoration: InputDecoration(
          labelText: 'Modalidad actual',
          filled: true,
          fillColor: cessumMuted(context).withValues(alpha: 0.10),
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
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
                      : 'Si aplica, adjunta una foto o documento que respalde '
                          'tu solicitud',
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

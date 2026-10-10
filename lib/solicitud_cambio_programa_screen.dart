import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Solicitud de CAMBIO DE PROGRAMA desde la app del estudiante.
/// El alumno pide cambiarse a otro programa EMPEZANDO DESDE CERO: conserva su
/// misma matrícula, su historial anterior se guarda como referencia (no cuenta
/// para el nuevo programa) y arranca desde el primer periodo. El cambio NO es
/// automático: queda como solicitud para que la administración lo apruebe y
/// aplique (backend: cambio_programa_solicitar).
class SolicitudCambioProgramaScreen extends StatefulWidget {
  const SolicitudCambioProgramaScreen({super.key});

  @override
  State<SolicitudCambioProgramaScreen> createState() =>
      _SolicitudCambioProgramaScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _SolicitudCambioProgramaScreenState
    extends State<SolicitudCambioProgramaScreen> {
  final _nombre = TextEditingController();
  final _programaActual = TextEditingController();
  final _generacion = TextEditingController();
  final _comentarios = TextEditingController();

  String _matricula = '';
  String _correo = '';
  String _grupoActual = '';

  // Programas que oferta CESSUM. El solicitado no puede ser el actual.
  static const List<String> _programas = [
    'Maestría en Educación Inclusiva',
    'Maestría en Pedagogía',
    'Maestría en Psicopedagogía',
    'Maestría en Educación',
    'Doctorado en Educación con Énfasis en Investigación',
    'Doctorado en Ciencias de la Educación',
  ];
  String? _programaSolicitado;

  String? _motivo;
  static const List<String> _motivos = [
    'Reorientación de mis objetivos profesionales',
    'El programa se ajusta mejor a mi perfil',
    'Motivos personales o de salud',
    'Motivos laborales',
    'Otro',
  ];

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
        _programaActual.text = perfil.programa;
        _generacion.text = perfil.generacion;
        _matricula = perfil.matricula;
      }
      if (correo != null && correo.isNotEmpty) _correo = correo;
    });
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : null,
      content: Text(m),
    ));
  }

  String? _falta() {
    if (_nombre.text.trim().isEmpty) return 'Falta tu nombre.';
    if (_matricula.trim().isEmpty) return 'No encontramos tu matrícula.';
    if (_programaSolicitado == null) {
      return 'Elige el programa al que deseas cambiarte.';
    }
    if (_programaSolicitado!.trim() == _programaActual.text.trim()) {
      return 'El programa solicitado es el mismo que ya cursas.';
    }
    if (_motivo == null) return 'Selecciona el motivo principal.';
    return null;
  }

  Future<void> _enviar() async {
    final falta = _falta();
    if (falta != null) {
      _aviso(falta, error: true);
      return;
    }
    setState(() => _enviando = true);
    try {
      final motivoTxt = _comentarios.text.trim().isEmpty
          ? (_motivo ?? '')
          : '${_motivo ?? ''} · ${_comentarios.text.trim()}';
      final payload = <String, dynamic>{
        'accion': 'cambio_programa_solicitar',
        'matricula': _matricula,
        'nombre': _nombre.text.trim(),
        'correo': _correo,
        'programaActual': _programaActual.text.trim(),
        'generacionActual': _generacion.text.trim(),
        'grupoActual': _grupoActual,
        'programaSolicitado': _programaSolicitado,
        'motivo': motivoTxt,
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
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
      _aviso('No se pudo enviar: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Solicitar cambio de programa'),
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
            const Text(
              'Solicitud enviada',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Recibimos tu solicitud de cambio de programa. La administración '
              'la revisará y te avisará la resolución por correo. Tu matrícula '
              'no cambia.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: cessumMuted(context)),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context),
              child: const Text('Volver'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formulario() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Aviso importante: implica empezar desde cero.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border(
                  left: BorderSide(color: cessumGold, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: cessumGold, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Cambio de programa desde el inicio',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Al cambiar de programa iniciarás desde el primer periodo del '
                  'nuevo programa. Conservas tu misma matrícula y tu historial '
                  'anterior se guarda como referencia, pero no cuenta para el '
                  'nuevo plan. La administración revisará y aplicará el cambio.',
                  style: TextStyle(fontSize: 13, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _campo('Nombre', _nombre, readOnly: true),
          _campo('Programa actual', _programaActual, readOnly: true),
          _campo('Generación', _generacion, readOnly: true),
          const SizedBox(height: 6),
          _dropdown('Programa que deseas cursar *', _programas,
              _programaSolicitado,
              (v) => setState(() => _programaSolicitado = v)),
          _dropdown('Motivo principal *', _motivos, _motivo,
              (v) => setState(() => _motivo = v)),
          const SizedBox(height: 4),
          _campo('Comentarios (opcional)', _comentarios, maxLines: 3),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _enviando ? null : _enviar,
              icon: _enviando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_enviando ? 'Enviando…' : 'Enviar solicitud'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(String label, TextEditingController c,
      {bool readOnly = false, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        readOnly: readOnly,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          filled: readOnly,
          fillColor: readOnly
              ? (cessumEsOscuro(context) ? Colors.white10 : cessumMuted(context).withValues(alpha: 0.18))
              : null,
        ),
      ),
    );
  }

  Widget _dropdown(String label, List<String> items, String? value,
      void Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'student_profile.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Alumno: documentos en línea (autoservicio). Genera y descarga al instante
/// su constancia de estudios, de inscripción o su kárdex, con folio + QR de
/// verificación. Reutiliza los endpoints existentes del Guardián.
class DocumentosOnlineScreen extends StatefulWidget {
  const DocumentosOnlineScreen({super.key});

  @override
  State<DocumentosOnlineScreen> createState() => _DocumentosOnlineScreenState();
}

class _DocumentosOnlineScreenState extends State<DocumentosOnlineScreen> {
  StudentProfile? _perfil;
  String _correo = '';
  bool _cargando = true;
  String? _error;
  String? _generando; // clave del documento en proceso

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final p = await StudentProfile.load();
      if (p == null) {
        setState(() {
          _cargando = false;
          _error = 'Completa tu perfil para generar tus documentos.';
        });
        return;
      }
      _perfil = p;
      _correo = await SessionStore.validEmail() ?? '';
    } catch (_) {
      _error = 'No se pudo cargar tu perfil.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : Colors.green));
  }

  Future<void> _generar(String clave, String accion,
      Map<String, dynamic> extra) async {
    setState(() => _generando = clave);
    try {
      final p = _perfil!;
      final payload = <String, dynamic>{
        'accion': accion,
        'matricula': p.matricula,
        'correo': _correo,
        ...extra,
      };
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (pdf.isNotEmpty && mounted) {
        await Helpers.abrirUrlExterna(pdf, context);
      }
      final folio = (data['folio'] ?? '').toString();
      _aviso(folio.isEmpty
          ? 'Documento generado.'
          : 'Documento generado (folio $folio).');
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _generando = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Documentos en línea'),
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
                      child: const Text(
                        'Genera y descarga tus documentos al instante. Cada uno '
                        'lleva folio y un código QR para verificar su autenticidad.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _cardDoc(
                      clave: 'inscripcion',
                      icono: Icons.how_to_reg,
                      titulo: 'Constancia de inscripción',
                      descripcion:
                          'Acredita tu inscripción en el ciclo escolar vigente.',
                      onTap: () => _generar(
                          'inscripcion', 'inscripcion_autoservicio', {}),
                    ),
                    _cardDoc(
                      clave: 'kardex',
                      icono: Icons.fact_check,
                      titulo: 'Kárdex (calificaciones)',
                      descripcion:
                          'Tu historial de materias y calificaciones validadas.',
                      onTap: () => _generar('kardex', 'kardex_alumno',
                          {'programa': _perfil!.programa}),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Si necesitas un documento con firma y sello para un '
                      'trámite oficial, solicítalo en control escolar o por la '
                      'Mesa de ayuda.',
                      style: TextStyle(fontSize: 11.5, color: Colors.black54),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
    );
  }

  Widget _cardDoc({
    required String clave,
    required IconData icono,
    required String titulo,
    required String descripcion,
    required VoidCallback onTap,
  }) {
    final generando = _generando == clave;
    final bloqueado = _generando != null && !generando;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: cessumRed.withValues(alpha: 0.10),
              child: Icon(icono, color: cessumRed),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(descripcion,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: generando
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download, size: 18),
                    label: Text(generando ? 'Generando…' : 'Generar y descargar'),
                    onPressed: bloqueado || generando ? null : onTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

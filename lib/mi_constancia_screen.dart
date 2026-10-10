import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

/// Constancia de estudios autoservicio: el alumno genera la suya, con folio
/// verificable. Reusa el mismo generador oficial de CESSUM.
class MiConstanciaScreen extends StatefulWidget {
  final StudentProfile? perfil;
  const MiConstanciaScreen({super.key, this.perfil});

  @override
  State<MiConstanciaScreen> createState() => _MiConstanciaScreenState();
}

class _MiConstanciaScreenState extends State<MiConstanciaScreen> {
  bool _generando = false;
  String? _folio;
  String? _pdf;
  String? _error;

  Future<void> _generar() async {
    setState(() {
      _generando = true;
      _error = null;
      _folio = null;
      _pdf = null;
    });
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'constancia_autoservicio',
                'correo': correo,
                'matricula': widget.perfil?.matricula ?? '',
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _folio = (data['folio'] ?? '').toString();
          _pdf = (data['pdf'] ?? '').toString();
        });
      } else {
        setState(() =>
            _error = (data['error'] ?? 'No se pudo generar.').toString());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No me pude conectar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _abrir() async {
    final url = _pdf;
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi constancia')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.verified, color: cessumGold, size: 52),
            const SizedBox(height: 14),
            Text(
              'Constancia de estudios',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Genera tu constancia oficial al instante. Incluye un folio '
              'único con el que CESSUM puede verificar su autenticidad.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 24),
            if (_folio == null)
              ElevatedButton.icon(
                onPressed: _generando ? null : _generar,
                icon: _generando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.description),
                label: Text(_generando
                    ? 'Generando…'
                    : 'Generar mi constancia'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: cessumRed.withValues(alpha: 0.4)),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: cessumRed, fontSize: 13)),
              ),
            ],
            if (_folio != null) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Color(0xFF1E8E3E), size: 38),
                    const SizedBox(height: 8),
                    const Text('¡Tu constancia está lista!',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 8),
                    Text('Folio: $_folio',
                        style: TextStyle(
                            fontSize: 13, color: cessumMuted(context))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _abrir,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Abrir / descargar PDF'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _generando ? null : _generar,
                icon: const Icon(Icons.refresh),
                label: const Text('Generar otra'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

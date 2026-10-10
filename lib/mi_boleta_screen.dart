import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'student_profile.dart';
import 'cessum_ui.dart';

/// Boleta de calificaciones por ciclo. El alumno elige el ciclo y obtiene la
/// vista previa en PDF (semestre, trimestre, etc.).
class MiBoletaScreen extends StatefulWidget {
  final StudentProfile? perfil;
  const MiBoletaScreen({super.key, this.perfil});

  @override
  State<MiBoletaScreen> createState() => _MiBoletaScreenState();
}

class _MiBoletaScreenState extends State<MiBoletaScreen> {
  bool _cargando = true;
  bool _generando = false;
  List<String> _ciclos = [];
  String? _ciclo;
  String? _pdf;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarCiclos();
  }

  Future<Map<String, dynamic>> _post(String accion,
      [Map<String, dynamic>? extra]) async {
    final correo = await SessionStore.validEmail() ?? '';
    final body = <String, dynamic>{
      'accion': accion,
      'correo': correo,
      'matricula': widget.perfil?.matricula ?? '',
    };
    if (extra != null) body.addAll(extra);
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 120));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargarCiclos() async {
    try {
      final data = await _post('boleta_ciclos');
      if (!mounted) return;
      if (data['ok'] == true) {
        final list = (data['ciclos'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final sugerido = (data['sugerido'] ?? '').toString();
        setState(() {
          _ciclos = list;
          _ciclo = list.contains(sugerido)
              ? sugerido
              : (list.isNotEmpty ? list.last : null);
        });
      } else {
        setState(() => _error = (data['error'] ?? 'No se pudieron cargar tus ciclos.').toString());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No me pude conectar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _verBoleta() async {
    if (_ciclo == null) return;
    setState(() {
      _generando = true;
      _error = null;
      _pdf = null;
    });
    try {
      final data = await _post('boleta_preview', {'ciclo': _ciclo});
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() => _pdf = (data['pdf'] ?? '').toString());
      } else {
        setState(() => _error = (data['error'] ?? 'No se pudo generar la boleta.').toString());
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
      appBar: AppBar(title: const Text('Mi boleta')),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 6),
                  const Icon(Icons.receipt_long, color: cessumGold, size: 50),
                  const SizedBox(height: 12),
                  Text(
                    'Boleta de calificaciones',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Elige el ciclo que quieres consultar y genera la vista '
                    'previa de tu boleta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.35),
                  ),
                  const SizedBox(height: 22),
                  if (_ciclos.isEmpty && _error == null)
                    Text(
                      'Aún no tienes calificaciones registradas.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cessumMuted(context)),
                    ),
                  if (_ciclos.isNotEmpty) ...[
                    const Text('Ciclo',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _ciclo,
                      items: _ciclos
                          .map((c) =>
                              DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: _generando
                          ? null
                          : (v) => setState(() {
                                _ciclo = v;
                                _pdf = null;
                              }),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _generando ? null : _verBoleta,
                      icon: _generando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.visibility),
                      label: Text(_generando ? 'Generando…' : 'Ver mi boleta'),
                    ),
                  ],
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
                          style:
                              const TextStyle(color: cessumRed, fontSize: 13)),
                    ),
                  ],
                  if (_pdf != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cessumGold.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: cessumGold.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Color(0xFF1E8E3E), size: 36),
                          const SizedBox(height: 8),
                          Text('Boleta lista · $_ciclo',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: _abrir,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Abrir / descargar PDF'),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

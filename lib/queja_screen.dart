// =====================================================================
//  queja_screen.dart · CESSUM · (27-sep-2026)
//  ART. 48, ACUERDO 17/11/17 — Buzón de quejas del alumno.
//  Cualquier tipo de queja, incluidas acoso escolar, acoso sexual y
//  plagio académico (Cap. XII del Reglamento). Al enviarla, llega de
//  inmediato a Vicerrectoría.
//
//  Guardián: GET queja_tipos · POST queja_registrar
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class QuejaScreen extends StatefulWidget {
  final String matricula;
  const QuejaScreen({super.key, required this.matricula});

  @override
  State<QuejaScreen> createState() => _QuejaScreenState();
}

class _QuejaScreenState extends State<QuejaScreen> {
  List<String> _tipos = [];
  String? _tipo;
  final _descripcion = TextEditingController();
  final _contra = TextEditingController();
  bool _cargandoTipos = true;
  bool _enviando = false;
  String? _folioEnviado;

  @override
  void initState() {
    super.initState();
    _cargarTipos();
  }

  @override
  void dispose() {
    _descripcion.dispose();
    _contra.dispose();
    super.dispose();
  }

  Future<void> _cargarTipos() async {
    try {
      final r = await http.get(Uri.parse('$guardianUrl?accion=queja_tipos')).timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() {
          _tipos = ((d['tipos'] as List?) ?? []).map((e) => '$e').toList();
          _tipo = _tipos.isNotEmpty ? _tipos.first : null;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _cargandoTipos = false);
  }

  Future<void> _enviar() async {
    if (_tipo == null || _descripcion.text.trim().isEmpty) {
      _aviso('Elige el tipo y describe los hechos.', error: true);
      return;
    }
    setState(() => _enviando = true);
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'queja_registrar',
                'matricula': widget.matricula,
                'correo': correo,
                'tipo': _tipo,
                'descripcion': _descripcion.text.trim(),
                'contra': _contra.text.trim(),
              }))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        setState(() => _folioEnviado = '${d['folio']}');
      } else {
        _aviso('${d['error'] ?? 'No se pudo enviar.'}', error: true);
      }
    } catch (_) {
      _aviso('No se pudo enviar. Intenta de nuevo.', error: true);
    }
    if (mounted) setState(() => _enviando = false);
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? cessumRed : Colors.green, content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(backgroundColor: cessumRed, foregroundColor: Colors.white, title: const Text('Presentar una queja')),
      body: _folioEnviado != null ? _pantallaConfirmacion() : _pantallaFormulario(),
    );
  }

  Widget _pantallaConfirmacion() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 64),
          const SizedBox(height: 16),
          Text('Tu queja quedó registrada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cessumInk(context))),
          const SizedBox(height: 8),
          Text('Folio: $_folioEnviado', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cessumRed)),
          const SizedBox(height: 12),
          Text('Administración la revisará y, de ser procedente, buscará una solución.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context),
            child: const Text('Listo'),
          ),
        ]),
      ),
    );
  }

  Widget _pantallaFormulario() {
    if (_cargandoTipos) return const Center(child: CircularProgressIndicator(color: cessumRed));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(
        'Tu queja se atiende conforme al Reglamento Escolar. Si señalas a alguien, se maneja con reserva; si de los hechos se desprende un posible delito, la institución dará aviso a las autoridades competentes.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context)),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        value: _tipo,
        decoration: const InputDecoration(labelText: 'Tipo de queja', border: OutlineInputBorder(), isDense: true),
        items: [for (final t in _tipos) DropdownMenuItem(value: t, child: Text(t))],
        onChanged: (v) => setState(() => _tipo = v),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _descripcion,
        minLines: 5,
        maxLines: 10,
        maxLength: 1500,
        decoration: const InputDecoration(labelText: 'Describe los hechos', hintText: 'Qué pasó, cuándo y dónde', border: OutlineInputBorder()),
      ),
      TextField(
        controller: _contra,
        decoration: const InputDecoration(labelText: 'Nombre de la persona señalada (opcional)', border: OutlineInputBorder(), isDense: true),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _enviando ? null : _enviar,
          icon: _enviando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
          label: const Text('Enviar queja'),
        ),
      ),
    ]);
  }
}

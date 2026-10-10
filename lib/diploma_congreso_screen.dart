import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Emisión de diplomas de congreso (COINEDU) con QR. Busca al
/// participante por su correo de registro y genera el PDF firmado.
class DiplomaCongresoScreen extends StatefulWidget {
  const DiplomaCongresoScreen({super.key});

  @override
  State<DiplomaCongresoScreen> createState() => _DiplomaCongresoScreenState();
}

class _DiplomaCongresoScreenState extends State<DiplomaCongresoScreen> {
  String _correoAdmin = '';
  String _clave = 'coinedu2026';
  final _correo = TextEditingController();
  final _nombre = TextEditingController();
  bool _cargando = false;
  String _msg = '';
  Color _msgColor = Colors.black54;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _correoAdmin = (await SessionStore.realEmail()) ?? '';
  }

  @override
  void dispose() {
    _correo.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _generar() async {
    final correo = _correo.text.trim();
    final nombre = _nombre.text.trim();
    if (correo.isEmpty && nombre.isEmpty) {
      setState(() { _msg = 'Indica el correo de registro del participante.'; _msgColor = cessumRed; });
      return;
    }
    setState(() { _cargando = true; _msg = ''; });
    try {
      var url = '$guardianUrl?accion=diploma_congreso'
          '&clave=${Uri.encodeComponent(_clave)}'
          '&actor=${Uri.encodeComponent(_correoAdmin)}';
      if (correo.isNotEmpty) url += '&correo=${Uri.encodeComponent(correo)}';
      if (nombre.isNotEmpty) url += '&nombre=${Uri.encodeComponent(nombre)}';
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        setState(() { _msg = (d['error'] ?? 'No se pudo generar.').toString(); _msgColor = cessumRed; _cargando = false; });
        return;
      }
      final pdf = (d['pdf'] ?? '').toString();
      setState(() {
        _msg = 'Diploma generado para ${d['nombre']} (folio ${d['folio']}). Abriendo PDF…';
        _msgColor = const Color(0xFF1E8E3E);
        _cargando = false;
      });
      if (pdf.isNotEmpty && mounted) Helpers.abrirUrlExterna(pdf, context);
    } catch (e) {
      setState(() { _msg = 'Error de conexión.'; _msgColor = cessumRed; _cargando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Diploma de congreso'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Congreso',
              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _clave,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'coinedu2026', child: Text('II COINEDU 2026')),
              DropdownMenuItem(value: 'coinedu2024', child: Text('I COINEDU 2024')),
            ],
            onChanged: (v) => setState(() => _clave = v ?? 'coinedu2026'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _correo,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo de registro del participante',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nombre,
            decoration: const InputDecoration(
              labelText: 'Nombre (opcional, si no tiene registro)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _cargando ? null : _generar,
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              icon: _cargando
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.workspace_premium_outlined),
              label: Text(_cargando ? 'Generando…' : 'Generar diploma'),
            ),
          ),
          if (_msg.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _msgColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_msg, style: TextStyle(color: _msgColor, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Lector de QR para verificar documentos CESSUM (constancias, actas,
/// contratos, diplomas). Escanea con la cámara o se pega el folio/URL.
/// Compatible con mobile_scanner 7.x.
class VerificadorQrScreen extends StatefulWidget {
  const VerificadorQrScreen({super.key});

  @override
  State<VerificadorQrScreen> createState() => _VerificadorQrScreenState();
}

class _VerificadorQrScreenState extends State<VerificadorQrScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  final _manual = TextEditingController();

  bool _procesando = false;
  bool _consultando = false;
  Map<String, dynamic>? _resultado;
  String _error = '';

  @override
  void dispose() {
    _scanner.dispose();
    _manual.dispose();
    super.dispose();
  }

  String? _folioDe(String raw) {
    raw = raw.trim();
    if (raw.isEmpty) return null;
    try {
      final uri = Uri.parse(raw);
      final f = uri.queryParameters['folio'];
      if (f != null && f.trim().isNotEmpty) return f.trim();
    } catch (_) {}
    if (raw.length < 60) return raw; // el propio folio
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_procesando) return;
    final codes = capture.barcodes;
    if (codes.isEmpty) return;
    final raw = codes.first.rawValue ?? '';
    final folio = _folioDe(raw);
    if (folio == null) return;
    if (mounted) setState(() => _procesando = true);
    try {
      await _scanner.stop();
    } catch (_) {}
    await _verificar(folio);
  }

  Future<void> _verificarManual() async {
    final folio = _folioDe(_manual.text);
    if (folio == null) {
      if (mounted) setState(() => _error = 'Pega un folio o la liga del QR.');
      return;
    }
    if (mounted) setState(() => _procesando = true);
    try {
      await _scanner.stop();
    } catch (_) {}
    await _verificar(folio);
  }

  Future<void> _verificar(String folio) async {
    if (mounted) setState(() { _consultando = true; _error = ''; _resultado = null; });
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=verificar_json&folio=${Uri.encodeComponent(folio)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        if (mounted) setState(() { _error = (d['error'] ?? 'No se pudo verificar.').toString(); _consultando = false; });
        return;
      }
      if (mounted) setState(() { _resultado = d; _consultando = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Error de conexión.'; _consultando = false; });
    }
  }

  Future<void> _otra() async {
    if (mounted) setState(() {
      _resultado = null;
      _error = '';
      _procesando = false;
      _manual.clear();
    });
    try {
      await _scanner.start();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Verificar documento'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: _consultando
          ? const Center(child: CircularProgressIndicator())
          : _resultado != null
              ? _vistaResultado()
              : _vistaEscaneo(),
    );
  }

  Widget _vistaEscaneo() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Apunta la cámara al código QR del documento.',
            style: TextStyle(fontSize: 13, color: cessumMuted(context))),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _scanner, onDetect: _onDetect),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('¿La cámara no funciona? Pega aquí el folio o la liga del QR:',
            style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        const SizedBox(height: 8),
        TextField(
          controller: _manual,
          decoration: const InputDecoration(
            labelText: 'Folio o liga',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _verificarManual,
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            icon: const Icon(Icons.search),
            label: const Text('Verificar'),
          ),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(_error, style: const TextStyle(color: cessumRed, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _vistaResultado() {
    final r = _resultado!;
    final encontrado = r['encontrado'] == true;
    final color = encontrado ? const Color(0xFF1E8E3E) : cessumRed;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.40), width: 1.5),
          ),
          child: Column(
            children: [
              Icon(encontrado ? Icons.verified : Icons.error_outline,
                  color: color, size: 56),
              const SizedBox(height: 10),
              Text(
                encontrado ? 'Documento auténtico' : 'Folio no encontrado',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (encontrado) ...[
                _fila('Folio', r['folio']?.toString() ?? ''),
                _fila('Tipo de documento', r['tipo']?.toString() ?? ''),
                _fila('Fecha de emisión', r['fecha']?.toString() ?? ''),
                _fila('A nombre de', r['nombre']?.toString() ?? ''),
                if ((r['programa']?.toString() ?? '').isNotEmpty)
                  _fila('Programa', r['programa'].toString()),
                _fila('Documento firmado', r['firmado'] == true ? 'Sí' : 'No'),
              ] else
                Text(
                  'El folio ${r['folio'] ?? ''} no corresponde a ningún documento '
                  'emitido por CESSUM. Verifica el código.',
                  style: TextStyle(fontSize: 13, color: cessumMuted(context)),
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _otra,
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Verificar otro'),
          ),
        ),
      ],
    );
  }

  Widget _fila(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(k, style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: cessumInk(context))),
          ),
        ],
      ),
    );
  }
}

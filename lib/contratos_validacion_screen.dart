// Pantalla de administrador: "Contratos por validar".
//
// Lista los contratos que los profesores ya firmaron y que están pendientes.
// El admin puede VER el PDF, VALIDARLO (se envía firmado al correo del profesor)
// o RECHAZARLO (con motivo, y se le avisa al profesor para que lo corrija).
//
// Acciones del Guardián:
//   GET  contrato_pendientes_listar -> {ok, contratos:[...]}
//   POST contrato_validar           -> {ok, enviado}
//   POST contrato_rechazar          -> {ok}

import 'dart:convert';

import 'fecha_esp.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class ContratosValidacionScreen extends StatefulWidget {
  const ContratosValidacionScreen({super.key});

  @override
  State<ContratosValidacionScreen> createState() =>
      _ContratosValidacionScreenState();
}

class _ContratosValidacionScreenState extends State<ContratosValidacionScreen> {
  bool _cargando = true;
  bool _procesando = false;
  List<Map<String, dynamic>> _items = [];
  String _actor = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      _actor = (await SessionStore.realEmail()) ?? '';
      final uri =
          Uri.parse('$guardianUrl?accion=contrato_pendientes_listar');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['contratos'] is List) {
        _items = (data['contratos'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _items = [];
      }
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _ver(String url) async {
    if (url.isEmpty) {
      _aviso('Este contrato no tiene PDF.', error: true);
      return;
    }
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el PDF.', error: true);
    }
  }

  Future<void> _validar(Map<String, dynamic> c) async {
    final folio = '${c['folio'] ?? ''}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Validar y enviar'),
        content: Text(
            'Se enviará el contrato firmado al correo de ${c['nombre'] ?? c['correo']}. '
            '¿Confirmas que está en los términos acordados?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Validar y enviar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final r = await _post({
        'accion': 'contrato_validar',
        'actor': _actor,
        'folio': folio,
      });
      if (r['ok'] == true) {
        _items.removeWhere((e) => '${e['folio']}' == folio);
        final enviado = r['enviado'] == true;
        _aviso(enviado
            ? 'Validado y enviado al correo del profesor.'
            : 'Validado. El correo no se pudo enviar (revisa la cuota).');
      } else {
        _aviso('${r['error'] ?? 'No se pudo validar.'}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
    if (mounted) setState(() => _procesando = false);
  }

  Future<void> _rechazar(Map<String, dynamic> c) async {
    final folio = '${c['folio'] ?? ''}';
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rechazar contrato'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Se avisará a ${c['nombre'] ?? c['correo']} para que lo corrija.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Rechazar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final r = await _post({
        'accion': 'contrato_rechazar',
        'actor': _actor,
        'folio': folio,
        'motivo': ctrl.text.trim(),
      });
      if (r['ok'] == true) {
        _items.removeWhere((e) => '${e['folio']}' == folio);
        _aviso('Contrato rechazado. Se avisó al profesor.');
      } else {
        _aviso('${r['error'] ?? 'No se pudo rechazar.'}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
    if (mounted) setState(() => _procesando = false);
  }

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : cessumGold,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contratos por validar'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _items.isEmpty
              ? _vacio()
              : Stack(
                  children: [
                    ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _tarjeta(_items[i]),
                    ),
                    if (_procesando)
                      Container(
                        color: Colors.black12,
                        child: const Center(
                          child: CircularProgressIndicator(color: cessumRed),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _vacio() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined,
                  size: 56, color: cessumMuted(context)),
              const SizedBox(height: 12),
              Text(
                'No hay contratos pendientes de validar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context)),
              ),
            ],
          ),
        ),
      );

  Widget _tarjeta(Map<String, dynamic> c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.handshake_outlined,
                    color: cessumRed, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c['nombre'] ?? ''}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cessumIsDark(context)
                            ? Colors.white
                            : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${c['correo'] ?? ''}',
                      style:
                          TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _chip('Tipo: ${c['tipo'] ?? ''}'),
              _chip('Folio: ${c['folio'] ?? ''}'),
              _chip('Firmado: ${fechaEsp(c['fecha'])}'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _ver('${c['pdfUrl'] ?? ''}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumGold,
                    side: const BorderSide(color: cessumGold),
                  ),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Ver'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _procesando ? null : () => _rechazar(c),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _procesando ? null : () => _validar(c),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Validar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
        ),
        child: Text(t,
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      );
}

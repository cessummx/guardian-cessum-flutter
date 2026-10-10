import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';

const Color _verdeOk = Color(0xFF1E8E3E);

class MisPagosDocenteScreen extends StatefulWidget {
  const MisPagosDocenteScreen({super.key});

  @override
  State<MisPagosDocenteScreen> createState() => _MisPagosDocenteScreenState();
}

class _MisPagosDocenteScreenState extends State<MisPagosDocenteScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _pagos = [];
  double _total = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = await SessionStore.validEmail() ?? '';
      if (correo.isEmpty) {
        if (mounted) setState(() {
          _cargando = false;
          _error = 'No identificamos tu correo. Vuelve a entrar con tu correo institucional.';
        });
        return;
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pagos_prof_historial',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = ((data['historial'] ?? []) as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        double t = 0;
        for (final p in lista) {
          t += (p['monto'] is num) ? (p['monto'] as num).toDouble() : 0;
        }
        if (mounted) setState(() {
          _pagos = lista;
          _total = t;
          _cargando = false;
        });
      } else {
        if (mounted) setState(() {
          _cargando = false;
          _error = data['error']?.toString() ?? 'No se pudo cargar.';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _cargando = false;
        _error = 'Error de conexión. Revisa tu internet e intenta de nuevo.';
      });
    }
  }

  /// (4-oct-2026) $12,500.00 en lugar de $12500.00.
  String _dinero(double v) {
    final partes = v.toStringAsFixed(2).split('.');
    final e = partes[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '\$$e.${partes[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis pagos'),
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error != null
              ? _vistaError()
              : _pagos.isEmpty
                  ? _vistaVacia()
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          _resumen(),
                          const SizedBox(height: 12),
                          ..._pagos.map(_card),
                        ],
                      ),
                    ),
    );
  }

  Widget _resumen() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cessumRed,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_pagos.length} pago(s) registrado(s)',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(
                '${_dinero(_total)} MXN en total',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r) {
    final pago = (r['comprobantePagoUrl'] ?? '').toString();
    final dep = (r['comprobanteDepositoUrl'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${r['materia']}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cessumRed)),
              ),
              Text('${r['montoFmt'] ?? ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _verdeOk)),
            ],
          ),
          const SizedBox(height: 2),
          Text('${r['programa']} · Gen ${r['generacion']} · Grupo ${r['grupo']}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          Text('${r['fecha']} · Folio ${r['folio']}',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (pago.startsWith('http') || dep.startsWith('http')) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (pago.startsWith('http'))
                  OutlinedButton.icon(
                    onPressed: () => Helpers.abrirUrlExterna(pago, context),
                    icon: const Icon(Icons.picture_as_pdf,
                        size: 15, color: cessumRed),
                    label: const Text('Comprobante de pago',
                        style: TextStyle(color: cessumRed, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cessumRed),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (dep.startsWith('http'))
                  OutlinedButton.icon(
                    onPressed: () => Helpers.abrirUrlExterna(dep, context),
                    icon: const Icon(Icons.receipt_long,
                        size: 15, color: cessumGold),
                    label: const Text('Depósito',
                        style: TextStyle(color: cessumGold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cessumGold),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _vistaVacia() {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        children: const [
          SizedBox(height: 40),
          SizedBox(
            height: 360,
            child: CessumEmptyState(
              icon: Icons.payments_outlined,
              title: 'Aún no tienes pagos',
              subtitle:
                  'Cuando se te realice un pago, aparecerá aquí y recibirás un correo.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 48, color: cessumFaint(context)),
            const SizedBox(height: 12),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
            const SizedBox(height: 14),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _cargar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

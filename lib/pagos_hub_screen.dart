import 'package:flutter/material.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'mi_pago_screen.dart';
import 'mi_pagos_screen.dart';
import 'payment_screen.dart';
import 'bank_data_screen.dart';
import 'convenios_alumno_screen.dart';
import 'mesa_ayuda_pagos_screen.dart';

/// Alumno: «Pagos» — (4-oct-2026) UNA SOLA PANTALLA CON PESTAÑAS.
///
/// Antes era un menú que mandaba a cuatro pantallas separadas, y dos de ellas («Cuánto debo» y «Seguimiento») pedían
/// los mismos datos y repetían el historial. Ahora todo vive aquí:
///   · Lo que debo      → cuota del mes, adeudo, recargos, descuentos y el botón para pagar (MiPagoScreen).
///   · Mis pagos        → historial completo, estado de cuenta, comprobantes y vencimientos (MiPagosScreen).
///   · Registrar pago   → formulario para subir un comprobante (PaymentScreen).
///   · Convenio         → convenios de pago: solicitarlo, ver el vigente y firmarlo (ConveniosAlumnoScreen).
///   · Datos bancarios  → cuenta y CLABE para depositar (BankDataScreen).
/// Cada pestaña es la misma pantalla de siempre en modo «embebido» (sin su barra), así que nada de su lógica cambia.
/// `pestana` permite abrir directo en una (0 a 4), por ejemplo desde un aviso de pago.
class PagosHubScreen extends StatefulWidget {
  final int pestana;
  const PagosHubScreen({super.key, this.pestana = 0});

  @override
  State<PagosHubScreen> createState() => _PagosHubScreenState();
}

class _PagosHubScreenState extends State<PagosHubScreen> {
  String _matricula = '';
  bool _perfilListo = false;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    try {
      final p = await StudentProfile.load();
      if (!mounted) return;
      setState(() {
        _matricula = (p?.matricula ?? '').trim();
        _perfilListo = true;
      });
    } catch (_) {
      if (mounted) setState(() => _perfilListo = true);
    }
  }

  static const _pestanas = <(IconData, String)>[
    (Icons.account_balance_wallet, 'Lo que debo'),
    (Icons.receipt_long, 'Mis pagos'),
    (Icons.upload_file, 'Registrar pago'),
    (Icons.handshake_outlined, 'Convenio'),
    (Icons.account_balance, 'Datos bancarios'),
  ];

  Widget _convenio() {
    if (!_perfilListo) return const Center(child: CircularProgressIndicator(color: cessumRed));
    if (_matricula.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('Completa tu perfil con tu matrícula para ver y solicitar convenios de pago.',
              textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context), height: 1.5)),
        ),
      );
    }
    return ConveniosAlumnoScreen(matricula: _matricula, embebido: true);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _pestanas.length,
      initialIndex: widget.pestana.clamp(0, _pestanas.length - 1),
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Pagos'),
          actions: [
            IconButton(
              tooltip: 'Mesa de ayuda de pagos',
              icon: const Icon(Icons.support_agent),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MesaAyudaPagosScreen())),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: cessumGold,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
            tabs: [for (final p in _pestanas) Tab(icon: Icon(p.$1, size: 20), text: p.$2)],
          ),
        ),
        body: TabBarView(
          children: [
            const MiPagoScreen(embebido: true),
            const MiPagosScreen(embebido: true),
            const PaymentScreen(embebido: true),
            _convenio(),
            const BankDataScreen(embebido: true),
          ],
        ),
      ),
    );
  }
}

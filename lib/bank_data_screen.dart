import 'package:flutter/material.dart';

import 'constants.dart';
import 'helpers.dart';
import 'cessum_ui.dart';

class BankDataScreen extends StatelessWidget {
  const BankDataScreen({super.key, this.embebido = false});
  /// (4-oct-2026) Dentro de «Pagos» (pestañas) va sin barra propia: la pone el contenedor.
  final bool embebido;


  void _volverAlMenu(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context), // (24-sep) modo oscuro
      appBar: embebido ? null : AppBar(
        title: const Text(
          'Datos de pago',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Inicio',
            onPressed: () => _volverAlMenu(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tarjeta principal con datos
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.account_balance,
                        color: cessumRed,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Transferencia o depósito',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 12),

                _DatoItem(
                  etiqueta: 'Banco',
                  valor: bancoNombre,
                  copiable: false,
                ),
                _DatoItem(
                  etiqueta: 'Beneficiario',
                  valor: bancoBeneficiario,
                  copiable: true,
                ),
                _DatoItem(
                  etiqueta: 'Número de cuenta',
                  valor: bancoCuenta,
                  copiable: true,
                ),
                _DatoItem(
                  etiqueta: 'CLABE interbancaria',
                  valor: bancoClabe,
                  copiable: true,
                ),
                _DatoItem(
                  etiqueta: 'Concepto sugerido',
                  valor: bancoConceptoSugerido,
                  copiable: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Aviso importante
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: cessumGold, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Después de realizar el pago, no olvides subir tu comprobante en el formulario de pagos correspondiente a tu generación.',
                    style: TextStyle(fontSize: 13, color: cessumInk(context)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoItem extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final bool copiable;

  const _DatoItem({
    required this.etiqueta,
    required this.valor,
    required this.copiable,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  etiqueta,
                  style: TextStyle(
                    fontSize: 12,
                    color: cessumMuted(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  valor,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (copiable)
            IconButton(
              icon: const Icon(Icons.content_copy, color: cessumRed, size: 20),
              tooltip: 'Copiar',
              onPressed: () => Helpers.copiarAlPortapapeles(
                context,
                valor,
                etiqueta,
              ),
            ),
        ],
      ),
    );
  }
}
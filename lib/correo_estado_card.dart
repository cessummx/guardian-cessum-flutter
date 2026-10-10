import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';

// =====================================================================
// Tarjeta de estado de correo para el panel admin.
//   GET correo_estado ?actor          -> { restante, encolados, notifActivo }
//   GET cola_correos_procesar         -> procesa la cola pendiente
// Muestra de un vistazo la cuota restante del día y la cola.
// =====================================================================

class CorreoEstadoCard extends StatefulWidget {
  const CorreoEstadoCard({super.key});

  @override
  State<CorreoEstadoCard> createState() => _CorreoEstadoCardState();
}

class _CorreoEstadoCardState extends State<CorreoEstadoCard> {
  bool _cargando = true;
  bool _procesando = false;
  String _actor = '';
  int _restante = -1;
  int _encolados = 0;
  bool _notif = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
    });
    _actor = (await SessionStore.realEmail()) ?? '';
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=correo_estado&actor=${Uri.encodeComponent(_actor)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('no ok');
      if (!mounted) return;
      setState(() {
        _restante = (data['restante'] ?? -1) is int
            ? data['restante'] ?? -1
            : int.tryParse('${data['restante']}') ?? -1;
        _encolados = (data['encolados'] ?? 0) is int
            ? data['encolados'] ?? 0
            : int.tryParse('${data['encolados']}') ?? 0;
        _notif = data['notifActivo'] != false;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
      });
    }
  }

  Future<void> _procesarCola() async {
    setState(() => _procesando = true);
    try {
      await http
          .get(Uri.parse('$guardianUrl?accion=cola_correos_procesar'))
          .timeout(const Duration(seconds: 90));
    } catch (_) {}
    if (mounted) setState(() => _procesando = false);
    _cargar();
  }

  Color get _colorRestante {
    if (_restante < 0) return CC.muted;
    if (_restante <= 20) return cessumRed;
    if (_restante <= 100) return CC.goldDark;
    return const Color(0xFF1E8E3E);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CC.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.mark_email_read_outlined,
                    color: cessumRed, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Correo hoy',
                    style: TextStyle(
                        color: CC.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _cargando ? null : _cargar,
                icon: _cargando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: CC.muted))
                    : const Icon(Icons.refresh, color: CC.muted, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_error)
            const Text('No se pudo consultar el estado del correo.',
                style: TextStyle(color: cessumRed, fontSize: 12))
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_restante < 0 ? '—' : '$_restante',
                          style: TextStyle(
                              color: _colorRestante,
                              fontSize: 26,
                              fontWeight: FontWeight.w800)),
                      const Text('correos restantes',
                          style: TextStyle(color: CC.muted, fontSize: 11)),
                    ],
                  ),
                ),
                Container(width: 1, height: 34, color: CC.gold.withValues(alpha: 0.3)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$_encolados',
                            style: TextStyle(
                                color: _encolados > 0 ? CC.goldDark : CC.ink,
                                fontSize: 26,
                                fontWeight: FontWeight.w800)),
                        const Text('en cola',
                            style: TextStyle(color: CC.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (!_notif && !_error) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(children: [
                Icon(Icons.notifications_off_outlined,
                    color: cessumRed, size: 16),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'Notificaciones APAGADAS: no se enviarán correos hasta encenderlas.',
                      style: TextStyle(color: cessumRed, fontSize: 11.5)),
                ),
              ]),
            ),
          ],
          if (_encolados > 0 && !_error) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed)),
                icon: _procesando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cessumRed))
                    : const Icon(Icons.send, size: 16),
                label: Text(_procesando
                    ? 'Procesando…'
                    : 'Procesar cola ($_encolados)'),
                onPressed: _procesando ? null : _procesarCola,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

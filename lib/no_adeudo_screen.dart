import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'student_profile.dart';

/// El alumno consulta su estado de pagos y solicita su constancia de no
/// adeudo. La constancia la emite administración tras aprobar la solicitud.
class NoAdeudoScreen extends StatefulWidget {
  final StudentProfile perfil;
  const NoAdeudoScreen({super.key, required this.perfil});

  @override
  State<NoAdeudoScreen> createState() => _NoAdeudoScreenState();
}

class _NoAdeudoScreenState extends State<NoAdeudoScreen> {
  Map<String, dynamic>? _solicitud;
  Map<String, dynamic>? _adeudo;
  bool _cargando = true;
  bool _enviando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$guardianUrl?accion=noadeudo_de'
          '&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _solicitud = data['solicitud'] == null
            ? null
            : Map<String, dynamic>.from(data['solicitud'] as Map);
        _adeudo = Map<String, dynamic>.from(data['adeudo'] as Map);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu estado.';
      });
    }
  }

  Future<void> _solicitar() async {
    setState(() => _enviando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'noadeudo_solicitar',
                'matricula': widget.perfil.matricula,
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Solicitud enviada. Te avisaremos al aprobarla.'),
        ));
      }
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('$e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Constancia de no adeudo',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _contenido(),
    );
  }

  Widget _contenido() {
    final adeudo = _adeudo ?? {};
    final alCorriente = adeudo['alCorriente'] == true;
    final pendientes = (adeudo['pendientes'] as List?) ?? [];
    final sol = _solicitud;
    final estatus = (sol?['estatus'] ?? '') as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // estado de pagos
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: alCorriente
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFFDECEA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: alCorriente
                    ? const Color(0xFF1E8E3E)
                    : cessumRed,
                width: 1),
          ),
          child: Row(
            children: [
              Icon(alCorriente ? Icons.verified : Icons.warning_amber_rounded,
                  color: alCorriente
                      ? const Color(0xFF1E8E3E)
                      : cessumRed,
                  size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  alCorriente
                      ? 'No tienes adeudos registrados. Puedes solicitar tu constancia.'
                      : 'Tienes ${pendientes.length} concepto(s) pendiente(s). Regulariza tu situación para que se apruebe tu constancia.',
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: alCorriente
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF8B1A1A)),
                ),
              ),
            ],
          ),
        ),
        if (pendientes.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...pendientes.map((raw) {
            final p = Map<String, dynamic>.from(raw as Map);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.payments_outlined, color: cessumRed),
                title: Text('${p['concepto']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${(p['monto'] ?? '').toString().isNotEmpty ? '\$${p['monto']} · ' : ''}'
                  'Vence: ${p['fechaLimite']} · ${p['estatus']}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 20),
        // estado de la solicitud
        if (sol != null) _estadoSolicitud(estatus, sol),
        const SizedBox(height: 12),
        // botón solicitar
        if (estatus != 'Pendiente')
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: alCorriente ? cessumRed : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (_enviando || !alCorriente) ? null : _solicitar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(estatus == 'Aprobada'
                  ? 'Solicitar una nueva'
                  : 'Solicitar mi constancia'),
            ),
          ),
        if (!alCorriente && estatus != 'Pendiente')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'El botón se habilita cuando no tengas adeudos pendientes.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Widget _estadoSolicitud(String estatus, Map<String, dynamic> sol) {
    Color color;
    IconData icono;
    String texto;
    switch (estatus) {
      case 'Aprobada':
        color = const Color(0xFF1E8E3E);
        icono = Icons.check_circle;
        texto = 'Tu constancia fue aprobada y emitida.';
        break;
      case 'Rechazada':
        color = cessumRed;
        icono = Icons.cancel;
        texto = 'Tu solicitud fue rechazada.'
            '${(sol['motivo'] ?? '').toString().isNotEmpty ? '\nMotivo: ${sol['motivo']}' : ''}';
        break;
      default:
        color = cessumGold;
        icono = Icons.hourglass_top;
        texto = 'Tu solicitud está en revisión por administración.';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Solicitud ${sol['folio']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(texto, style: const TextStyle(fontSize: 12.5, height: 1.4)),
          if (estatus == 'Aprobada' &&
              (sol['enlace'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8E3E),
                    foregroundColor: Colors.white),
                onPressed: () => Helpers.abrirUrlExterna(
                    sol['enlace'].toString(), context),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Descargar constancia (PDF)'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

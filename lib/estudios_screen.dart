import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'student_profile.dart';

/// El alumno solicita su constancia de estudios (vigencia). La emite
/// administración tras aprobar la solicitud.
class EstudiosScreen extends StatefulWidget {
  final StudentProfile perfil;
  const EstudiosScreen({super.key, required this.perfil});

  @override
  State<EstudiosScreen> createState() => _EstudiosScreenState();
}

class _EstudiosScreenState extends State<EstudiosScreen> {
  Map<String, dynamic>? _solicitud;
  Map<String, dynamic>? _vigencia;
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
      final uri = Uri.parse('$guardianUrl?accion=estudios_de'
          '&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _solicitud = data['solicitud'] == null
            ? null
            : Map<String, dynamic>.from(data['solicitud'] as Map);
        _vigencia = Map<String, dynamic>.from(data['vigencia'] as Map);
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
                'accion': 'estudios_solicitar',
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
        title: const Text('Constancia de estudios',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
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
    final vig = _vigencia ?? {};
    final vigente = vig['vigente'] == true;
    final sol = _solicitud;
    final estatus = (sol?['estatus'] ?? '') as String;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: vigente ? const Color(0xFFE8F5E9) : const Color(0xFFFDECEA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: vigente ? const Color(0xFF1E8E3E) : cessumRed),
          ),
          child: Row(
            children: [
              Icon(vigente ? Icons.verified : Icons.info_outline,
                  color: vigente ? const Color(0xFF1E8E3E) : cessumRed,
                  size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  vigente
                      ? 'Apareces como alumno vigente. Puedes solicitar tu constancia de estudios.'
                      : 'No apareces como vigente: ${vig['motivo'] ?? ''}. Comunícate con administración.',
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: vigente
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF8B1A1A)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (sol != null) _estadoSolicitud(estatus, sol),
        const SizedBox(height: 12),
        if (estatus != 'Pendiente')
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: vigente ? cessumRed : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (_enviando || !vigente) ? null : _solicitar,
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
        border: Border.all(color: color),
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

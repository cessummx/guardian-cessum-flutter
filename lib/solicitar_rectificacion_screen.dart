import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

const Color _verdeOk = Color(0xFF1E8E3E);

/// Pantalla del ALUMNO para solicitar la rectificación de una de sus
/// calificaciones. Pide un motivo detallado y, de forma opcional, la
/// calificación que el alumno considera correcta. La solicitud queda
/// registrada para Servicios Escolares y, si la materia tiene docente
/// vinculado, le llega una copia en su vista de profesor.
class SolicitarRectificacionScreen extends StatefulWidget {
  final String programa;
  final String generacion;
  final String materia;
  final String calificacionActual;
  final String matricula;
  final String nombre;
  final String grupo;
  final String tipo; // 'rectificacion' (default) o 'faltante'

  const SolicitarRectificacionScreen({
    super.key,
    required this.programa,
    required this.generacion,
    required this.materia,
    required this.calificacionActual,
    required this.matricula,
    required this.nombre,
    this.grupo = '',
    this.tipo = 'rectificacion',
  });

  @override
  State<SolicitarRectificacionScreen> createState() =>
      _SolicitarRectificacionScreenState();
}

class _SolicitarRectificacionScreenState
    extends State<SolicitarRectificacionScreen> {
  final TextEditingController _motivoCtrl = TextEditingController();
  final TextEditingController _calPropCtrl = TextEditingController();
  bool _enviando = false;
  String _correo = '';

  static const int _motivoMinimo = 20;

  @override
  void initState() {
    super.initState();
    _cargarCorreo();
  }

  Future<void> _cargarCorreo() async {
    final c = await SessionStore.validEmail();
    if (!mounted) return;
    setState(() => _correo = (c ?? '').trim());
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    _calPropCtrl.dispose();
    super.dispose();
  }

  void _aviso(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? Colors.redAccent : _verdeOk,
      content: Text(msg),
    ));
  }

  Future<void> _enviar() async {
    final motivoBase = _motivoCtrl.text.trim();
    if (motivoBase.length < _motivoMinimo) {
      _aviso(
          'Describe con detalle tu solicitud (al menos $_motivoMinimo caracteres).');
      return;
    }
    final bool esFaltante = widget.tipo == 'faltante';
    final String motivo = esFaltante
        ? '[CALIFICACIÓN FALTANTE] $motivoBase'
        : motivoBase;

    final propTxt = _calPropCtrl.text.trim().replaceAll(',', '.');
    if (propTxt.isNotEmpty) {
      final v = double.tryParse(propTxt);
      if (v == null || v < 6 || v > 10) {
        _aviso(
            'Si indicas la calificación que consideras correcta, debe ser un número entre 6 y 10.');
        return;
      }
    }

    setState(() => _enviando = true);
    try {
      final resp = await http.post(
        Uri.parse(guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'accion': 'solicitud_correccion',
          'origen': 'alumno',
          'programa': widget.programa,
          'generacion': widget.generacion,
          'grupo': widget.grupo,
          'materia': widget.materia,
          'matricula': widget.matricula,
          'nombre': widget.nombre,
          'correo': _correo,
          'calificacionPropuesta': propTxt,
          'motivo': motivo,
          'tipo': esFaltante ? 'calificacion_faltante' : 'rectificacion',
        }),
      );
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: _verdeOk),
                SizedBox(width: 8),
                Expanded(child: Text('Solicitud enviada')),
              ],
            ),
            content: Text(
              esFaltante
                  ? 'Tu solicitud de calificación quedó registrada con estatus '
                      'Pendiente. Servicios Escolares revisará tu acta y '
                      'capturará la calificación. Te avisaremos cuando esté lista.'
                  : 'Tu solicitud de rectificación quedó registrada con estatus '
                      'Pendiente. Servicios Escolares la revisará y, si el docente de '
                      'la materia está vinculado, recibirá una copia. Te avisaremos '
                      'cuando haya una resolución.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
      } else {
        _aviso('No se pudo enviar: ${data['error'] ?? 'inténtalo de nuevo.'}');
      }
    } catch (e) {
      _aviso('No se pudo enviar la solicitud. Revisa tu conexión.');
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
        elevation: 2,
        title: Text(
            widget.tipo == 'faltante'
                ? 'Solicitar calificación'
                : 'Solicitar rectificación',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Datos de la materia
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Materia',
                    style: TextStyle(
                        fontSize: 12,
                        color: cessumMuted(context),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(widget.materia,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                if (widget.tipo != 'faltante') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('Calificación actual: ',
                          style: TextStyle(fontSize: 13, color: cessumMuted(context))),
                      Text(
                        widget.calificacionActual.trim().isEmpty
                            ? '—'
                            : widget.calificacionActual,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ],
                if (widget.tipo == 'faltante') ...[
                  const SizedBox(height: 10),
                  Text(
                    'Esta materia aparece como cursada pero sin calificación '
                    'registrada. Solicita que se capture con base en tu acta.',
                    style: TextStyle(
                        fontSize: 12.5, color: cessumMuted(context), height: 1.3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          Text(
            widget.tipo == 'faltante'
                ? 'Cuéntanos cuándo cursaste esta materia'
                : 'Explica con detalle el motivo de tu solicitud',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            widget.tipo == 'faltante'
                ? 'Indica el ciclo o periodo y el grupo en que la cursaste, y '
                    'cualquier dato que ayude a ubicar tu acta (docente, fechas). '
                    'Esto agiliza la captura de tu calificación.'
                : 'Sé específico: qué crees que ocurrió, en qué evidencia te basas '
                    '(trabajos entregados, asistencia, exámenes) y por qué consideras '
                    'que la calificación debería revisarse. Una solicitud detallada '
                    'agiliza la revisión.',
            style: TextStyle(
                fontSize: 12.5, color: cessumMuted(context), height: 1.3),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _motivoCtrl,
            minLines: 5,
            maxLines: 10,
            maxLength: 1200,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText:
                  'Ej. Entregué los trabajos finales el 10 de mayo y no aparecen '
                  'considerados...',
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 8),

          if (widget.tipo != 'faltante') ...[
            const Text(
              '¿Qué calificación consideras correcta? (opcional)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 140,
              child: TextField(
                controller: _calPropCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '6 a 10',
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _enviando ? null : _enviar,
              icon: _enviando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_enviando ? 'Enviando...' : 'Enviar solicitud',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

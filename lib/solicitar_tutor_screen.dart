// ALUMNO: Solicitar tutor (director) de tesis — FIRMABLE (ago-2026).
// El alumno propone tema y justificación, acepta el compromiso de
// seguimiento y firma con su firma digital registrada. Admin asigna.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'firma_alumno_screen.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class SolicitarTutorScreen extends StatefulWidget {
  final String matricula;
  const SolicitarTutorScreen({super.key, required this.matricula});

  @override
  State<SolicitarTutorScreen> createState() => _SolicitarTutorScreenState();
}

class _SolicitarTutorScreenState extends State<SolicitarTutorScreen> {
  bool _cargando = true;
  bool _enviando = false;
  String _error = '';
  bool _tieneFirma = false;
  Map<String, dynamic>? _sol;
  final _tema = TextEditingController();
  final _just = TextEditingController();
  final _pref = TextEditingController();
  bool _acepta = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tema.dispose();
    _just.dispose();
    _pref.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'tesis_solicitud_mia',
            'matricula': widget.matricula,
          }))
          .timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _tieneFirma = d['tieneFirmaRegistrada'] == true;
        _sol = d['solicitud'] == null
            ? null
            : Map<String, dynamic>.from(d['solicitud'] as Map);
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _enviar() async {
    if (_tema.text.trim().isEmpty) {
      _snack('Describe tu tema propuesto.', ok: false);
      return;
    }
    if (!_acepta) {
      _snack('Acepta el compromiso de seguimiento para firmar.', ok: false);
      return;
    }
    setState(() => _enviando = true);
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'tesis_solicitud_crear',
                'matricula': widget.matricula,
                'tema': _tema.text.trim(),
                'justificacion': _just.text.trim(),
                'asesorPreferido': _pref.text.trim(),
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        _snack('Solicitud firmada y enviada; te avisaremos la asignación.');
        await _cargar();
      } else if ('${d['error']}' == 'SIN_FIRMA') {
        if (!mounted) return;
        final ir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Falta tu firma digital'),
            content: const Text(
                'Para firmar tu solicitud necesitas registrar primero tu '
                'firma digital (una sola vez). ¿Quieres registrarla ahora?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Después')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Registrar firma')),
            ],
          ),
        );
        if (ir == true && mounted) {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      FirmaAlumnoScreen(matricula: widget.matricula)));
          if (mounted) await _enviar();
        }
      } else {
        _snack('${d['error']}', ok: false);
      }
    } catch (e) {
      _snack('Error: $e', ok: false);
    }
    if (mounted) setState(() => _enviando = false);
  }

  /// Abre la pantalla de firma y, al volver, vuelve a consultar el estado.
  /// No envía nada: registrar la firma y mandar la solicitud son dos actos
  /// distintos y el alumno debe poder hacer el primero sin comprometerse
  /// todavía con el segundo.
  Future<void> _registrarFirma() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => FirmaAlumnoScreen(matricula: widget.matricula)));
    if (!mounted) return;
    await _cargar();
    if (!mounted) return;
    if (_tieneFirma) {
      _snack('Firma registrada. Ya puedes enviar tu solicitud.');
    }
  }

  void _snack(String m, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: ok ? const Color(0xFF1E8E3E) : cessumRed,
        content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tutor de tesis',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_sol != null)
                      _estado()
                    else ...[
                      _encabezado(),
                      const SizedBox(height: 14),
                      _formulario(),
                    ],
                  ],
                ),
    );
  }

  Widget _encabezado() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10)),
            child: Image.asset('assets/images/logo.png',
                height: 32,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.school, color: cessumRed, size: 32)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Solicita formalmente a tu director de tesis: propones tu '
              'tema, firmas tu compromiso de seguimiento y Vicerrectoría '
              'te asigna al tutor.',
              style: TextStyle(
                  color: Colors.white, fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formulario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
            controller: _tema,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Tema propuesto de tu tesis *',
                alignLabelWithHint: true,
                border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(
            controller: _just,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText:
                    'Justificación breve (por qué este tema, qué problema atiende)',
                alignLabelWithHint: true,
                border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(
            controller: _pref,
            decoration: const InputDecoration(
                labelText: 'Asesor de tu preferencia (opcional)',
                helperText:
                    'Vicerrectoría lo considerará según disponibilidad.',
                border: OutlineInputBorder(),
                isDense: true)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('COMPROMISO DE SEGUIMIENTO',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cessumGold)),
              const SizedBox(height: 4),
              const Text(
                'Al firmar me comprometo a: formalizar el convenio de '
                'hitos con mi director, entregar cada avance en la fecha '
                'comprometida, atender la retroalimentación recibida y '
                'mantener comunicación activa. El seguimiento genera '
                'recordatorios automáticos en ambos sentidos (también '
                'para la retroalimentación oportuna de mi director).',
                style: TextStyle(fontSize: 11.5, height: 1.45),
              ),
              CheckboxListTile(
                value: _acepta,
                activeColor: cessumRed,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text(
                    'He leído y acepto el compromiso; firmo con mi firma digital.',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                onChanged: (v) => setState(() => _acepta = v ?? false),
              ),
              // (ago-22) LA ADVERTENCIA NO ERA ACCIONABLE.
              // Decía que falta la firma y que "al enviar te llevaremos a
              // registrarla", así que el alumno tenía que llenar todo el
              // formulario, aceptar el compromiso y pulsar Enviar para que
              // hasta entonces apareciera un diálogo que lo mandaba a otra
              // pantalla. Un aviso que informa de un requisito debe traer la
              // forma de cumplirlo al lado.
              if (!_tieneFirma) ...[
                const Text(
                    '⚠ Aún no tienes firma digital registrada. Regístrala '
                    'aquí (una sola vez) y regresas a terminar tu solicitud.',
                    style: TextStyle(
                        fontSize: 11, height: 1.35, color: Color(0xFFE65100))),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _enviando ? null : _registrarFirma,
                    icon: const Icon(Icons.draw_outlined, size: 18),
                    label: const Text('Registrar o subir mi firma digital',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE65100),
                      side: const BorderSide(color: Color(0xFFE65100)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
              ],
              // Con firma registrada, el alumno debe poder cambiarla: una
              // firma mal escaneada queda en documentos con efectos legales.
              if (_tieneFirma) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.verified_outlined,
                        size: 15, color: Color(0xFF1E8E3E)),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('Tu firma digital ya está registrada.',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF1E8E3E))),
                    ),
                    TextButton(
                      onPressed: _enviando ? null : _registrarFirma,
                      style: TextButton.styleFrom(
                          foregroundColor: cessumRed,
                          visualDensity: VisualDensity.compact,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8)),
                      child: const Text('Cambiarla',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13)),
            onPressed: _enviando ? null : _enviar,
            icon: _enviando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.draw, size: 19),
            label: const Text('Firmar y enviar solicitud',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _estado() {
    final s = _sol!;
    final asignada = (s['estado'] ?? '') == 'Asignada';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: asignada
                ? const Color(0xFF1E8E3E).withValues(alpha: 0.5)
                : cessumGold.withValues(alpha: 0.5),
            width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(asignada ? '🎉 Director asignado' : '⏳ Solicitud en revisión',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: asignada
                      ? const Color(0xFF1E8E3E)
                      : cessumGold)),
          const SizedBox(height: 8),
          if (asignada) ...[
            Text('Tu director de tesis: ${s['asesorAsignado']}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            Text('Asignado el ${s['fechaAsignacion']}',
                style: TextStyle(
                    fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 8),
            const Text(
                'Siguiente paso: formaliza con tu director el convenio de '
                'hitos de seguimiento. Los recordatorios automáticos los '
                'acompañarán a ambos.',
                style: TextStyle(fontSize: 12, height: 1.45)),
          ] else
            const Text(
                'Tu solicitud firmada está en manos de Vicerrectoría '
                'Académica; te notificaremos por correo la asignación.',
                style: TextStyle(fontSize: 12, height: 1.45)),
          const Divider(height: 20),
          Text('Tema propuesto (${s['fecha']}):',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: cessumMuted(context))),
          Text('${s['tema']}',
              style: const TextStyle(fontSize: 12.5, height: 1.4)),
          if ((s['asesorPreferido'] ?? '').toString().isNotEmpty)
            Text('Preferencia expresada: ${s['asesorPreferido']}',
                style: TextStyle(
                    fontSize: 11.5, color: cessumMuted(context))),
        ],
      ),
    );
  }
}

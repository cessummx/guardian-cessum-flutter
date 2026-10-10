import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'auth/session_store.dart';

/// Aviso autocontenido: si el alumno NO tiene su CURP registrada, muestra un
/// recordatorio arriba de la pantalla principal con un botón para agregarla.
/// Si ya la tiene (o aún está cargando), no muestra nada.
///
/// Uso: basta con poner `const CurpAvisoCard()` al inicio de la pantalla del
/// alumno. Si ya tienes la matrícula a la mano puedes pasarla para ahorrar una
/// consulta: `CurpAvisoCard(matricula: ...)`.
///
/// Backend:
///   GET  curp_de?matricula=...   -> {ok, curp}
///   POST curp_guardar            -> {ok, curp}
/// (22-sep) La regla de la SEC (la misma del Verificador de sus plantillas):
/// fecha válida, sexo H/M, clave de estado y consonantes. Antes se aceptaba
/// cualquier combinación de 18 letras y números, y la SEC la rechazaba.
final RegExp reCurpSec = RegExp(
    r'^[A-Z][AEIOUX][A-Z]{2}\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])[HM]'
    r'(?:AS|B[CS]|C[CLMSH]|D[FG]|G[TR]|HG|JC|M[CNS]|N[ETL]|OC|PL|Q[TR]|S[PLR]|T[CSL]|VZ|YN|ZS)'
    r'[B-DF-HJ-NP-TV-Z]{3}[A-Z\d-]{2}$');

class CurpAvisoCard extends StatefulWidget {
  final String? matricula;
  const CurpAvisoCard({super.key, this.matricula});

  @override
  State<CurpAvisoCard> createState() => _CurpAvisoCardState();
}

class _CurpAvisoCardState extends State<CurpAvisoCard> {
  bool _cargando = true;
  bool _falta = false;
  bool _faltaProm = false; // (22-sep) promedio del nivel anterior, solo nuevo ingreso
  String _matricula = '';
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _revisar();
  }

  Future<void> _revisar() async {
    try {
      var mat = (widget.matricula ?? '').trim();
      if (mat.isEmpty) {
        final perfil = await StudentProfile.load();
        mat = perfil?.matricula ?? '';
      }
      if (mat.isEmpty) {
        if (mounted) setState(() => _cargando = false);
        return;
      }
      _matricula = mat;
      final uri = Uri.parse(
          '$guardianUrl?accion=curp_de&matricula=${Uri.encodeComponent(mat)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final curp = '${data['curp'] ?? ''}'.trim().toUpperCase();
      // (22-sep) También si la CURP guardada no es válida para la SEC: antes
      // el aviso solo salía con la CURP vacía.
      var faltaProm = false;
      try {
        final rp = await http
            .get(Uri.parse('$guardianUrl?accion=promedio_ingreso_de&matricula=${Uri.encodeComponent(mat)}'))
            .timeout(const Duration(seconds: 25));
        final dp = jsonDecode(rp.body) as Map<String, dynamic>;
        faltaProm = dp['ok'] == true && dp['requerido'] == true;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _falta = !reCurpSec.hasMatch(curp);
        _faltaProm = faltaProm;
        _cargando = false;
      });
    } catch (_) {
      // Ante cualquier error, no molestamos al alumno con el aviso.
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrirCaptura() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Agregar mi CURP'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escribe tu CURP (18 caracteres). La necesitamos para tu '
                'credencial, constancias y tu titulación.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 18,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
                  LengthLimitingTextInputFormatter(18),
                ],
                decoration: const InputDecoration(
                  labelText: 'CURP',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _guardando ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _guardando
                  ? null
                  : () async {
                      final curp = ctrl.text.trim().toUpperCase();
                      if (!RegExp(r'^[A-Z0-9]{18}$').hasMatch(curp)) {
                        _msg('La CURP debe tener exactamente 18 caracteres.',
                            error: true);
                        return;
                      }
                      if (!reCurpSec.hasMatch(curp)) {
                        _msg('Esa CURP no es válida. Revisa tu fecha de nacimiento, el sexo (H/M) y la clave de tu estado.',
                            error: true);
                        return;
                      }
                      setLocal(() => _guardando = true);
                      final guardado = await _guardar(curp);
                      setLocal(() => _guardando = false);
                      if (guardado && ctx.mounted) Navigator.pop(ctx, true);
                    },
              child: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _falta = false);
      _msg('¡Gracias! Tu CURP quedó registrada.');
      if (_faltaProm) await _abrirPromedio();
    }
  }

  Future<void> _abrirPromedio() async {
    final ctrl = TextEditingController();
    var guardando = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Tu promedio del nivel anterior'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'La Secretaría de Educación nos pide, para quienes inician, el promedio '
                'general con el que terminaste tu nivel anterior (licenciatura o maestría). '
                'Escríbelo como aparece en tu certificado: de 0 a 10, o de 0 a 100.',
                style: TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(
                  labelText: 'Promedio (por ejemplo 9.2)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: guardando ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: guardando
                  ? null
                  : () async {
                      final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
                      if (v == null || v <= 0 || v > 100) {
                        _msg('Escribe un número de 0 a 10 (o de 0 a 100).', error: true);
                        return;
                      }
                      setLocal(() => guardando = true);
                      var bien = false;
                      try {
                        final r = await http
                            .get(Uri.parse('$guardianUrl?accion=promedio_ingreso_guardar'
                                '&matricula=${Uri.encodeComponent(_matricula)}&promedio=$v'))
                            .timeout(const Duration(seconds: 30));
                        final d = jsonDecode(r.body) as Map<String, dynamic>;
                        bien = d['ok'] == true;
                        if (!bien) _msg('${d['error'] ?? 'No se pudo guardar.'}', error: true);
                      } catch (_) {
                        _msg('No me pude conectar. Intenta de nuevo.', error: true);
                      }
                      setLocal(() => guardando = false);
                      if (bien && ctx.mounted) Navigator.pop(ctx, true);
                    },
              child: guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() => _faltaProm = false);
      _msg('¡Gracias! Tu promedio quedó registrado.');
    }
  }

  Future<bool> _guardar(String curp) async {
    try {
      final actor = (await SessionStore.realEmail()) ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'curp_guardar',
                'matricula': _matricula,
                'curp': curp,
                'actor': actor,
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _msg('${data['error'] ?? 'No se pudo guardar.'}', error: true);
        return false;
      }
      return true;
    } catch (_) {
      _msg('No me pude conectar. Intenta de nuevo.', error: true);
      return false;
    }
  }

  void _msg(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando || (!_falta && !_faltaProm)) return const SizedBox.shrink();
    final titulo = _falta && _faltaProm
        ? 'Faltan tu CURP y tu promedio de ingreso'
        : (_falta ? 'Falta tu CURP' : 'Falta tu promedio de ingreso');
    final detalle = _falta
        ? 'Agrégala para tu credencial, constancias y titulación.'
        : 'Lo pide la Secretaría de Educación para tu registro.';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.badge_outlined, color: cessumGold, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cessumIsDark(context)
                            ? Colors.white
                            : Colors.black87)),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            onPressed: _falta ? _abrirCaptura : _abrirPromedio,
            child: Text(_falta ? 'Agregar CURP' : 'Agregar promedio'),
          ),
        ],
      ),
    );
  }
}

/// Formatea el texto a MAYÚSCULAS mientras se escribe (para la CURP).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

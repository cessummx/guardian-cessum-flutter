import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'curp_aviso.dart' show reCurpSec;

// =====================================================================
// CURP PENDIENTES (panel admin)
//   GET  validar_curp_padron ?actor  -> { total, conCurp, sinCurp,
//        invalidos, problemas:[{matricula,nombre,programa,curp,motivo}] }
//   POST curp_guardar { actor, matricula, curp } -> { ok, curp }
// Deja vacías las que faltan, las marca PENDIENTE y permite capturarlas
// aquí mismo (valida 18 caracteres).
// =====================================================================

class CurpsPendientesScreen extends StatefulWidget {
  const CurpsPendientesScreen({super.key});

  @override
  State<CurpsPendientesScreen> createState() => _CurpsPendientesScreenState();
}

class _CurpsPendientesScreenState extends State<CurpsPendientesScreen> {
  bool _cargando = true;
  String _error = '';
  String _actor = '';
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _pendientes = [];
  final Map<String, TextEditingController> _ctrls = {};
  final Set<String> _guardando = {};
  final Map<String, String> _guardadas = {}; // matricula -> curp guardada

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    // (24-sep) Correo REAL: en «Ver como profesor» el de la vista es el del profesor.
    _actor = (await SessionStore.realEmail()) ?? '';
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'validar_curp_padron',
        'actor': _actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      final probs = (data['problemas'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // "sin CURP" primero, luego mal formadas
      probs.sort((a, b) {
        int r(Map m) =>
            (m['motivo'] ?? '').toString().toLowerCase().contains('sin') ? 0 : 1;
        return r(a).compareTo(r(b));
      });
      for (final p in probs) {
        final mat = (p['matricula'] ?? '').toString();
        _ctrls.putIfAbsent(
            mat, () => TextEditingController(text: (p['curp'] ?? '').toString()));
      }
      if (!mounted) return;
      setState(() {
        _resumen = {
          'total': data['total'] ?? 0,
          'conCurp': data['conCurp'] ?? 0,
          'sinCurp': data['sinCurp'] ?? 0,
          'invalidos': data['invalidos'] ?? 0,
        };
        _pendientes = probs;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar (¿permisos de administrador?).';
      });
    }
  }

  Future<void> _guardar(String mat) async {
    final curp = (_ctrls[mat]?.text ?? '').trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{18}$').hasMatch(curp)) {
      _snack('La CURP debe tener exactamente 18 caracteres (letras y números).',
          esError: true);
      return;
    }
    // (24-sep) La misma regla de la SEC que usa el aviso del alumno: antes se
    // aceptaba cualquier combinación de 18 caracteres y la SEC la rechazaba.
    if (!reCurpSec.hasMatch(curp)) {
      _snack('Esa CURP no es válida para la SEC: revisa la fecha de nacimiento, el sexo (H/M) y la clave del estado.',
          esError: true);
      return;
    }
    setState(() => _guardando.add(mat));
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'curp_guardar',
                'actor': _actor,
                'matricula': mat,
                'curp': curp,
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _guardando.remove(mat));
      if (data['ok'] == true) {
        setState(() => _guardadas[mat] = curp);
        _snack('CURP guardada.');
      } else {
        _snack('${data['error'] ?? 'No se pudo guardar.'}', esError: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _guardando.remove(mat));
      _snack('Error de conexión.', esError: true);
    }
  }

  void _snack(String t, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: esError ? cessumRed : CC.goldDark,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('CURP pendientes'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : RefreshIndicator(
              color: cessumRed,
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error.isNotEmpty)
                    Text(_error, style: const TextStyle(color: cessumRed))
                  else ...[
                    _resumenCard(),
                    const SizedBox(height: 14),
                    if (_pendientes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Center(
                            child: Text(
                                '¡Sin pendientes! Todas las CURP están completas y válidas.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: CC.muted))),
                      )
                    else
                      ..._pendientes.map(_tarjeta),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _resumenCard() {
    Widget chip(String n, String v, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(v,
                  style: TextStyle(
                      color: c, fontSize: 20, fontWeight: FontWeight.w800)),
              Text(n,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c, fontSize: 10.5)),
            ]),
          ),
        );
    return Row(children: [
      chip('Con CURP', (_resumen['conCurp'] ?? 0).toString(),
          const Color(0xFF1E8E3E)),
      chip('Sin CURP', (_resumen['sinCurp'] ?? 0).toString(), cessumRed),
      chip('Mal formadas', (_resumen['invalidos'] ?? 0).toString(),
          CC.goldDark),
    ]);
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final mat = (p['matricula'] ?? '').toString();
    final motivo = (p['motivo'] ?? '').toString();
    final sinCurp = motivo.toLowerCase().contains('sin');
    final guardada = _guardadas[mat];
    final guardando = _guardando.contains(mat);
    final color = sinCurp ? cessumRed : CC.goldDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: guardada != null
                ? const Color(0xFF1E8E3E).withValues(alpha: 0.5)
                : CC.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((p['nombre'] ?? '').toString(),
                        style: const TextStyle(
                            color: CC.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        '$mat · ${(p['programa'] ?? '').toString()}',
                        style: const TextStyle(color: CC.muted, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: (guardada != null
                            ? const Color(0xFF1E8E3E)
                            : color)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(
                    guardada != null
                        ? 'Guardada'
                        : (sinCurp ? 'Pendiente' : 'Mal formada'),
                    style: TextStyle(
                        color:
                            guardada != null ? const Color(0xFF1E8E3E) : color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (guardada != null)
            Row(children: [
              const Icon(Icons.check_circle,
                  color: Color(0xFF1E8E3E), size: 18),
              const SizedBox(width: 6),
              Text(guardada,
                  style: const TextStyle(
                      color: CC.ink,
                      fontSize: 13,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600)),
            ])
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrls[mat],
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 18,
                    inputFormatters: [
                      UpperCaseFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    ],
                    decoration: const InputDecoration(
                      hintText: 'CURP (18 caracteres)',
                      counterText: '',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 10, vertical: 12),
                    ),
                    style: const TextStyle(letterSpacing: 1),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white),
                    onPressed: guardando ? null : () => _guardar(mat),
                    child: guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Guardar'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// Convierte lo tecleado a MAYÚSCULAS en vivo.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

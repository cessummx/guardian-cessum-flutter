import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Herramientas de datos (admin): validador de CURP, estadística
/// demográfica y exportación del padrón a Excel. Cada una consume
/// su acción del Guardián.
class ReportesDatosScreen extends StatefulWidget {
  const ReportesDatosScreen({super.key});

  @override
  State<ReportesDatosScreen> createState() => _ReportesDatosScreenState();
}

class _ReportesDatosScreenState extends State<ReportesDatosScreen> {
  String _correo = '';

  bool _curpCargando = false;
  Map<String, dynamic> _curp = {};
  String _curpError = '';

  bool _demoCargando = false;
  Map<String, dynamic> _demo = {};
  String _demoError = '';

  final _padProg = TextEditingController();
  final _padGen = TextEditingController();
  bool _padCargando = false;
  String _padMsg = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _correo = (await SessionStore.validEmail()) ?? '';
  }

  @override
  void dispose() {
    _padProg.dispose();
    _padGen.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(String accion, [Map<String, String>? extra]) async {
    var url = '$guardianUrl?accion=$accion&actor=${Uri.encodeComponent(_correo)}';
    if (extra != null) {
      extra.forEach((k, v) {
        if (v.trim().isNotEmpty) url += '&$k=${Uri.encodeComponent(v.trim())}';
      });
    }
    final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  String _t(dynamic v) => (v ?? 0).toString();

  // ---------- CURP ----------
  Future<void> _revisarCurp() async {
    setState(() { _curpCargando = true; _curpError = ''; });
    try {
      final d = await _get('validar_curp_padron');
      if (d['ok'] != true) {
        setState(() { _curpError = (d['error'] ?? 'No se pudo revisar.').toString(); _curpCargando = false; });
        return;
      }
      setState(() { _curp = d; _curpCargando = false; });
    } catch (e) {
      setState(() { _curpError = 'Error de conexión.'; _curpCargando = false; });
    }
  }

  // ---------- Demografía ----------
  Future<void> _calcularDemo() async {
    setState(() { _demoCargando = true; _demoError = ''; });
    try {
      final d = await _get('demografia_alumnado');
      if (d['ok'] != true) {
        setState(() { _demoError = (d['error'] ?? 'No se pudo calcular.').toString(); _demoCargando = false; });
        return;
      }
      setState(() { _demo = d; _demoCargando = false; });
    } catch (e) {
      setState(() { _demoError = 'Error de conexión.'; _demoCargando = false; });
    }
  }

  // ---------- Padrón ----------
  Future<void> _exportarPadron() async {
    setState(() { _padCargando = true; _padMsg = ''; });
    try {
      final d = await _get('padron_exportar', {
        'programa': _padProg.text,
        'generacion': _padGen.text,
      });
      if (d['ok'] != true) {
        setState(() { _padMsg = (d['error'] ?? 'No se pudo generar.').toString(); _padCargando = false; });
        return;
      }
      final url = (d['xlsxUrl'] ?? d['url'] ?? '').toString();
      setState(() {
        _padMsg = 'Listo: ${_t(d['total'])} alumno(s). Abriendo el archivo…';
        _padCargando = false;
      });
      if (url.isNotEmpty && mounted) Helpers.abrirUrlExterna(url, context);
    } catch (e) {
      setState(() { _padMsg = 'Error de conexión.'; _padCargando = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Reportes de datos'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tarjeta(
            icono: Icons.fact_check_outlined,
            titulo: 'Validador de CURP',
            subtitulo: 'Formato y dígito verificador de todo el padrón.',
            child: _bloqueCurp(),
          ),
          const SizedBox(height: 12),
          _tarjeta(
            icono: Icons.pie_chart_outline,
            titulo: 'Estadística demográfica',
            subtitulo: 'Género y edad del alumnado (del CURP).',
            child: _bloqueDemo(),
          ),
          const SizedBox(height: 12),
          _tarjeta(
            icono: Icons.table_view_outlined,
            titulo: 'Exportar padrón a Excel',
            subtitulo: 'Descarga el listado de alumnos en .xlsx.',
            child: _bloquePadron(),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta({
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.25)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(icono, color: cessumRed),
          title: Text(titulo,
              style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87)),
          subtitle: Text(subtitulo,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [child],
        ),
      ),
    );
  }

  Widget _botonAccion(String texto, bool cargando, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: cargando ? null : onTap,
        style: FilledButton.styleFrom(backgroundColor: cessumRed),
        icon: cargando
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.play_arrow),
        label: Text(cargando ? 'Procesando…' : texto),
      ),
    );
  }

  Widget _par(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13, color: Colors.black87))),
          Text(v, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
              color: color ?? Colors.black87)),
        ],
      ),
    );
  }

  // ---- bloques ----
  Widget _bloqueCurp() {
    final problemas = (_curp['problemas'] is List) ? _curp['problemas'] as List : const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _botonAccion('Revisar CURP', _curpCargando, _revisarCurp),
        if (_curpError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_curpError, style: const TextStyle(color: cessumRed, fontSize: 13)),
        ],
        if (_curp.isNotEmpty && _curpError.isEmpty) ...[
          const SizedBox(height: 12),
          _par('Total', _t(_curp['total'])),
          _par('Válidos', _t(_curp['validos']), color: const Color(0xFF1E8E3E)),
          _par('Inválidos', _t(_curp['invalidos']), color: cessumRed),
          _par('Sin CURP', _t(_curp['sinCurp']), color: cessumGold),
          if (problemas.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Primeros casos a corregir:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
            const SizedBox(height: 6),
            for (final p in problemas.take(30))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '• ${(p is Map ? p['nombre'] : '').toString()} '
                  '(${(p is Map ? p['matricula'] : '').toString()}) — '
                  '${(p is Map ? p['motivo'] : '').toString()}',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ),
            if (problemas.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('…y ${problemas.length - 30} más.',
                    style: const TextStyle(fontSize: 12, color: Colors.black45)),
              ),
          ],
        ],
      ],
    );
  }

  Widget _bloqueDemo() {
    final rangos = (_demo['rangos'] is Map) ? Map<String, dynamic>.from(_demo['rangos'] as Map) : {};
    final porProg = (_demo['porPrograma'] is List) ? _demo['porPrograma'] as List : const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _botonAccion('Calcular demografía', _demoCargando, _calcularDemo),
        if (_demoError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_demoError, style: const TextStyle(color: cessumRed, fontSize: 13)),
        ],
        if (_demo.isNotEmpty && _demoError.isEmpty) ...[
          const SizedBox(height: 12),
          _par('Con CURP válido', _t(_demo['conCurpValido'])),
          _par('Hombres', _t(_demo['hombres'])),
          _par('Mujeres', _t(_demo['mujeres'])),
          _par('Edad promedio', _t(_demo['edadPromedio'])),
          _par('Edad mínima / máxima', '${_t(_demo['edadMin'])} / ${_t(_demo['edadMax'])}'),
          const SizedBox(height: 8),
          const Text('Por rango de edad:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
          _par('Menos de 25', _t(rangos['menos25'])),
          _par('25 a 34', _t(rangos['de25a34'])),
          _par('35 a 44', _t(rangos['de35a44'])),
          _par('45 a 54', _t(rangos['de45a54'])),
          _par('55 o más', _t(rangos['de55omas'])),
          if (porProg.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Por programa:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
            const SizedBox(height: 4),
            for (final p in porProg)
              if (p is Map)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '• ${p['programa']}: ${_t(p['total'])} '
                    '(H ${_t(p['hombres'])} · M ${_t(p['mujeres'])} · edad ${_t(p['edadPromedio'])})',
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
          ],
        ],
      ],
    );
  }

  Widget _bloquePadron() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _padProg,
          decoration: const InputDecoration(
            labelText: 'Programa (opcional)',
            hintText: 'Ej. Maestría en Educación',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _padGen,
          decoration: const InputDecoration(
            labelText: 'Generación (opcional)',
            hintText: 'Ej. 25-1',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        _botonAccion('Generar Excel', _padCargando, _exportarPadron),
        if (_padMsg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_padMsg, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ],
    );
  }
}

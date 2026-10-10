// centro_mando_screen.dart · CESSUM · (24-sep-2026)
//
// CENTRO DE MANDO ÚNICO (fase 1 de los centros inteligentes).
// Sustituye la consulta de nueve tableros: abre con «Lo que requiere su
// decisión hoy», ordenado por impacto, y cada tarjeta lleva a la acción, no
// a otra pantalla intermedia. Arriba, tres líneas con IA para empezar el día.
// Base: GET centro_mando y centro_mando_ia (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

class CentroMandoScreen extends StatefulWidget {
  const CentroMandoScreen({super.key});

  @override
  State<CentroMandoScreen> createState() => _CentroMandoScreenState();
}

class _CentroMandoScreenState extends State<CentroMandoScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  String _generado = '';
  List<Map<String, dynamic>> _tarjetas = [];
  List<Map<String, dynamic>> _fuentes = [];

  bool _pidiendoIa = false;
  List<String> _lineasIa = [];

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
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=centro_mando'))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo armar el centro de mando.');
      if (!mounted) return;
      setState(() {
        _tarjetas = ((d['tarjetas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _fuentes = ((d['resumenBandeja'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _generado = '${d['generado'] ?? ''}';
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = (m.contains('TimeoutException') || m.contains('ClientException') || m.contains('SocketException'))
            ? 'No se pudo cargar. Revise su conexión e intente de nuevo.'
            : m;
      });
    }
  }

  Future<void> _tresLineas() async {
    setState(() => _pidiendoIa = true);
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=centro_mando_ia'))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar el resumen.');
      if (!mounted) return;
      setState(() => _lineasIa = ((d['lineas'] as List?) ?? []).map((e) => '$e').toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _pidiendoIa = false);
  }

  Color _colorUrgencia(int u) {
    if (u >= 3) return cessumRed;
    if (u == 2) return cessumGold;
    if (u == 1) return cessumMuted(context);
    return _verde;
  }

  String _textoUrgencia(int u) {
    if (u >= 3) return 'Hoy';
    if (u == 2) return 'Esta semana';
    if (u == 1) return 'Pendiente';
    return 'Al día';
  }

  @override
  Widget build(BuildContext context) {
    final urgentes = _tarjetas.where((t) => (t['urgencia'] as num? ?? 0) >= 3).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Centro de mando', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Tres líneas para hoy (IA)',
            onPressed: (_cargando || _pidiendoIa) ? null : _tresLineas,
            icon: _pidiendoIa
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
          ),
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_off_outlined, size: 44, color: cessumFaint(context)),
                      const SizedBox(height: 10),
                      Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cessumInk(context))),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _encabezado(urgentes),
                      if (_lineasIa.isNotEmpty) ...[const SizedBox(height: 12), _cajaIa()],
                      const SizedBox(height: 16),
                      Text('LO QUE REQUIERE SU DECISIÓN HOY',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
                      const SizedBox(height: 8),
                      for (final t in _tarjetas) _tarjeta(t),
                      if (_fuentes.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text('BANDEJA DE SOLICITUDES, POR TIPO',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
                        const SizedBox(height: 8),
                        _resumenBandeja(),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _encabezado(int urgentes) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          urgentes == 0 ? 'Nada urgente por ahora' : (urgentes == 1 ? '1 asunto para atender hoy' : '$urgentes asuntos para atender hoy'),
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text('Actualizado ${_generado.isEmpty ? 'ahora' : _generado}. Toque una tarjeta para ir directo a la acción.',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        if (_lineasIa.isEmpty) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.14)),
            onPressed: _pidiendoIa ? null : _tresLineas,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text(_pidiendoIa ? 'Pensando…' : 'Tres líneas para empezar el día'),
          ),
        ],
      ]),
    );
  }

  Widget _cajaIa() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 16, color: cessumGold),
          const SizedBox(width: 6),
          Text('PARA EMPEZAR EL DÍA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumInk(context))),
          const Spacer(),
          IconButton(
            tooltip: 'Copiar',
            iconSize: 18,
            onPressed: () => Helpers.copiarAlPortapapeles(context, _lineasIa.map((l) => '• $l').join('\n'), 'Resumen'),
            icon: const Icon(Icons.copy_outlined),
          ),
        ]),
        for (var i = 0; i < _lineasIa.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${i + 1}. ', style: const TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              Expanded(child: Text(_lineasIa[i], style: TextStyle(fontSize: 13.5, height: 1.4, color: cessumInk(context)))),
            ]),
          ),
      ]),
    );
  }

  Widget _tarjeta(Map<String, dynamic> t) {
    final u = (t['urgencia'] as num? ?? 0).toInt();
    final color = _colorUrgencia(u);
    final clave = '${t['pantalla'] ?? t['clave'] ?? ''}';
    final cifra = '${t['cifra'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: u == 0 ? 0.25 : 0.55), width: u >= 3 ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final ok = await abrirPantallaCentro(context, clave);
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Esta tarjeta todavía no tiene pantalla asociada.')));
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(iconoCentro('${t['clave'] ?? ''}'), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['titulo'] ?? ''}',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cessumInk(context))),
                const SizedBox(height: 2),
                Text('${t['detalle'] ?? ''}', style: TextStyle(fontSize: 12.5, height: 1.35, color: cessumMuted(context))),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(cifra, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color, height: 1)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(_textoUrgencia(u), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
              ),
            ]),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: cessumFaint(context)),
          ]),
        ),
      ),
    );
  }

  Widget _resumenBandeja() {
    final conPend = _fuentes.where((f) => (f['pendientes'] as num? ?? 0) > 0).toList()
      ..sort((a, b) => ((b['pendientes'] as num?) ?? 0).compareTo((a['pendientes'] as num?) ?? 0));
    if (conPend.isEmpty) {
      return Text('No hay solicitudes pendientes en ninguna bandeja.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context)));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in conPend)
          ActionChip(
            avatar: Icon(iconoCentro('${f['tipo'] ?? ''}'), size: 16, color: cessumRed),
            label: Text('${f['titulo']} · ${f['pendientes']}', style: const TextStyle(fontSize: 12)),
            onPressed: () => abrirPantallaCentro(context, '${f['tipo'] ?? ''}'),
          ),
      ],
    );
  }
}

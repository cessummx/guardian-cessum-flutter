// calendario_operativo_screen.dart · CESSUM · (24-sep-2026)
//
// CALENDARIO OPERATIVO DEL CICLO · fase 4 de los centros inteligentes.
// Todas las fechas críticas en una sola línea del tiempo: eventos del
// calendario institucional, inicio y cierre de cada materia (con su captura
// y acta), eventos y exámenes de grado. Los próximos 7 días se marcan, y
// cada fecha dice quién es responsable.
// Base: GET calendario_operativo (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';

class CalendarioOperativoScreen extends StatefulWidget {
  const CalendarioOperativoScreen({super.key});

  @override
  State<CalendarioOperativoScreen> createState() => _CalendarioOperativoScreenState();
}

class _CalendarioOperativoScreenState extends State<CalendarioOperativoScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  Map<String, dynamic>? _d;
  String _tipo = '';

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
      final r = await http.get(Uri.parse('$guardianUrl?accion=calendario_operativo')).timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo armar el calendario.');
      if (!mounted) return;
      setState(() {
        _d = d;
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

  List<Map<String, dynamic>> get _items => ((_d?['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Color _color(int dias, String tipo) {
    if (dias < 0) return cessumMuted(context);
    if (dias <= 7) return cessumRed;
    if (dias <= 21) return cessumGold;
    if (tipo.startsWith('Cierre')) return const Color(0xFF7B1FA2);
    if (tipo.startsWith('Inicio')) return const Color(0xFF1F5B9C);
    return _verde;
  }

  IconData _icono(String tipo) {
    if (tipo.startsWith('Inicio')) return Icons.play_circle_outline;
    if (tipo.startsWith('Cierre')) return Icons.flag_outlined;
    if (tipo.startsWith('Titulación')) return Icons.school_outlined;
    if (tipo.startsWith('Evento')) return Icons.event_outlined;
    return Icons.calendar_month_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final tipos = items.map((i) => '${i['tipo']}'.split(' · ').first).toSet().toList()..sort();
    final vis = _tipo.isEmpty ? items : items.where((i) => '${i['tipo']}'.startsWith(_tipo)).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Calendario operativo', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Calendario institucional', onPressed: () => abrirPantallaCentro(context, 'calendarioAdmin'), icon: const Icon(Icons.edit_calendar_outlined)),
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
                      Icon(Icons.calendar_month_outlined, size: 44, color: cessumFaint(context)),
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
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]), borderRadius: BorderRadius.circular(16)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_d?['proximos7'] ?? 0} fecha(s) en los próximos 7 días', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${_d?['total'] ?? 0} fechas entre la semana pasada y los próximos 60 días · ${_d?['generado'] ?? ''}', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          ChoiceChip(label: const Text('Todo'), selected: _tipo.isEmpty, onSelected: (_) => setState(() => _tipo = '')),
                          for (final t in tipos) ...[const SizedBox(width: 6), ChoiceChip(label: Text(t), selected: _tipo == t, onSelected: (_) => setState(() => _tipo = _tipo == t ? '' : t))],
                        ]),
                      ),
                      const SizedBox(height: 12),
                      if (vis.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Sin fechas en esta vista.', style: TextStyle(color: cessumMuted(context))))),
                      ..._agrupado(vis),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  /// Encabezado por día y sus filas, en orden.
  List<Widget> _agrupado(List<Map<String, dynamic>> vis) {
    final out = <Widget>[];
    String? diaPrev;
    for (final it in vis) {
      final fecha = '${it['fecha']}';
      if (diaPrev != fecha) {
        out.add(_dia(fecha, (it['dias'] as num? ?? 0).toInt()));
        diaPrev = fecha;
      }
      out.add(_fila(it));
    }
    return out;
  }

  Widget _dia(String fecha, int dias) {
    final etiqueta = dias == 0 ? 'HOY' : (dias == 1 ? 'MAÑANA' : (dias < 0 ? 'hace ${-dias} día(s)' : 'en $dias días'));
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(children: [
        Text(fecha, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: dias >= 0 && dias <= 7 ? cessumRed : cessumInk(context))),
        const SizedBox(width: 8),
        Text(etiqueta, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cessumMuted(context))),
      ]),
    );
  }

  Widget _fila(Map<String, dynamic> it) {
    final dias = (it['dias'] as num? ?? 0).toInt();
    final tipo = '${it['tipo'] ?? ''}';
    final c = _color(dias, tipo);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: 0.45))),
      child: Row(children: [
        Icon(_icono(tipo), size: 18, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${it['titulo'] ?? ''}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(context))),
            Text('$tipo · ${it['responsable'] ?? ''}${'${it['detalle'] ?? ''}'.isNotEmpty ? ' · ${it['detalle']}' : ''}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ]),
        ),
      ]),
    );
  }
}

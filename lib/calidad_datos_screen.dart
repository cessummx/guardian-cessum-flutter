// calidad_datos_screen.dart · CESSUM · (24-sep-2026)
//
// CALIDAD DE DATOS CONTINUA · fase 3 de los centros inteligentes.
// Junta en una sola pantalla los diagnósticos que hoy viven repartidos en
// Salud de los datos, Huérfanos, Duplicados, CURP, Sin maestro, SIGA y
// Anomalías. Cada categoría muestra cuántos casos hay hoy, cómo cambió
// desde el último registro diario y abre la herramienta que lo corrige.
// El registro diario lo hace el Guardián solo (a las 6:00, solo escribe
// en su hoja; no envía correos) una vez que se instala desde aquí.
// Base: GET calidad_datos y calidad_datos_instalar (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';

class CalidadDatosScreen extends StatefulWidget {
  const CalidadDatosScreen({super.key});

  @override
  State<CalidadDatosScreen> createState() => _CalidadDatosScreenState();
}

class _CalidadDatosScreenState extends State<CalidadDatosScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  Map<String, dynamic>? _d;
  bool _instalando = false;

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
      final r = await http.get(Uri.parse('$guardianUrl?accion=calidad_datos')).timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo revisar la calidad de los datos.');
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

  Future<void> _instalar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registro diario'),
        content: const Text(
          'El Guardián revisará estas ocho categorías todos los días a las 6:00 a. m. y guardará los conteos en su hoja, '
          'para ver si los problemas suben o bajan.\n\nSolo escribe en la hoja: no envía correos a nadie.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Activar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _instalando = true);
    try {
      final r = await http.get(Uri.parse('$guardianUrl?accion=calidad_datos_instalar')).timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo activar.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _verde,
          content: Text(d['yaEstaba'] == true ? 'El registro diario ya estaba activo; se guardó el conteo de hoy.' : 'Registro diario activado. Se guardó el conteo de hoy.')));
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _instalando = false);
  }

  Color _color(Map<String, dynamic> c) {
    final t = (c['total'] as num?)?.toInt();
    if (t == null) return cessumMuted(context);
    if (t == 0) return _verde;
    return '${c['gravedad']}' == 'alto' ? cessumRed : cessumGold;
  }

  @override
  Widget build(BuildContext context) {
    final cats = ((_d?['categorias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final abiertos = (_d?['frentesAbiertos'] as num?)?.toInt() ?? 0;
    final ultimo = '${_d?['ultimoRegistro'] ?? ''}';
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Calidad de datos', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Activar el registro diario',
            onPressed: (_cargando || _instalando) ? null : _instalar,
            icon: _instalando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.event_repeat_outlined),
          ),
          IconButton(tooltip: 'Revisar ahora', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.health_and_safety_outlined, size: 44, color: cessumFaint(context)),
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
                          Text(abiertos == 0 ? 'Datos limpios en las ocho categorías' : (abiertos == 1 ? '1 categoría con casos por atender' : '$abiertos categorías con casos por atender'),
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            ultimo.isEmpty
                                ? 'Revisado ${_d?['generado'] ?? ''}. Active el registro diario para ver si los casos suben o bajan.'
                                : 'Revisado ${_d?['generado'] ?? ''} · comparado con el registro del $ultimo.',
                            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      for (final c in cats) _categoria(c),
                      const SizedBox(height: 8),
                      Text(
                        'Cada categoría abre la herramienta que la corrige. Los diagnósticos son los mismos que ya calcula el Guardián; aquí solo se ven juntos y con su tendencia.',
                        style: TextStyle(fontSize: 11.5, height: 1.4, color: cessumMuted(context)),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _categoria(Map<String, dynamic> c) {
    final color = _color(c);
    final total = (c['total'] as num?)?.toInt();
    final cambio = (c['cambio'] as num?)?.toInt();
    final anterior = (c['anterior'] as num?)?.toInt();
    final muestra = ((c['muestra'] as List?) ?? []).map((e) => '$e').where((s) => s.isNotEmpty).toList();
    final error = '${c['error'] ?? ''}';
    String tendencia = '';
    Color colTend = cessumMuted(context);
    if (cambio != null) {
      if (cambio > 0) {
        tendencia = '▲ +$cambio desde el último registro';
        colTend = cessumRed;
      } else if (cambio < 0) {
        tendencia = '▼ $cambio desde el último registro';
        colTend = _verde;
      } else {
        tendencia = '= sin cambio (antes $anterior)';
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: total == 0 ? 0.25 : 0.55))),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => abrirPantallaCentro(context, '${c['pantalla'] ?? ''}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                child: Icon(iconoCentro('${c['clave'] ?? ''}'), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c['titulo'] ?? ''}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cessumInk(context))),
                  if (tendencia.isNotEmpty) Text(tendencia, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: colTend)),
                  if (error.isNotEmpty) Text('No se pudo revisar: $error', style: TextStyle(fontSize: 11.5, color: cessumRed)),
                ]),
              ),
              const SizedBox(width: 8),
              Text(total == null ? '—' : '$total', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color, height: 1)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: cessumFaint(context)),
            ]),
            if (muestra.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final m in muestra) Text('• $m', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              if (total != null && total > muestra.length) Text('… y ${total - muestra.length} más', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(context))),
            ],
          ]),
        ),
      ),
    );
  }
}

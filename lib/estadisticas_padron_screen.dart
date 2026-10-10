import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Estadísticas del padrón: alumnos por programa, generación y modalidad.
class EstadisticasPadronScreen extends StatefulWidget {
  const EstadisticasPadronScreen({super.key});

  @override
  State<EstadisticasPadronScreen> createState() =>
      _EstadisticasPadronScreenState();
}

class _EstadisticasPadronScreenState extends State<EstadisticasPadronScreen> {
  bool _cargando = true;
  String? _error;
  int _total = 0;
  int _bajas = 0;
  List<Map<String, dynamic>> _porPrograma = [];
  List<Map<String, dynamic>> _porGeneracion = [];
  List<Map<String, dynamic>> _porModalidad = [];

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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=estadisticas_padron'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      List<Map<String, dynamic>> conv(String k) =>
          ((data[k] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      setState(() {
        _total = (data['total'] ?? 0) as int;
        _bajas = (data['bajas'] ?? 0) as int;
        _porPrograma = conv('porPrograma');
        _porGeneracion = conv('porGeneracion');
        _porModalidad = conv('porModalidad');
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las estadísticas.';
      });
    }
  }

  void _copiarExcel() {
    final sb = StringBuffer();
    void bloque(String titulo, List<Map<String, dynamic>> datos) {
      sb.writeln(titulo + '\tAlumnos');
      for (final d in datos) {
        sb.writeln('${d['etiqueta']}\t${d['valor'] ?? 0}');
      }
      sb.writeln('');
    }
    sb.writeln('Total activos\t$_total');
    sb.writeln('Bajas\t$_bajas');
    sb.writeln('');
    bloque('Por programa', _porPrograma);
    bloque('Por generación', _porGeneracion);
    bloque('Por modalidad', _porModalidad);
    Helpers.copiarAlPortapapeles(context, sb.toString(), 'Tabla');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Estadísticas del padrón',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Copiar para Excel',
            onPressed: (_porPrograma.isEmpty &&
                    _porGeneracion.isEmpty &&
                    _porModalidad.isEmpty)
                ? null
                : _copiarExcel,
            icon: const Icon(Icons.grid_on),
          ),
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
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _resumen(),
                      const SizedBox(height: 16),
                      _bloque('Por programa', _porPrograma, cessumRed),
                      const SizedBox(height: 16),
                      _bloque('Por generación', _porGeneracion, cessumGold),
                      const SizedBox(height: 16),
                      _bloque('Por modalidad', _porModalidad,
                          const Color(0xFF1E8E3E)),
                    ],
                  ),
                ),
    );
  }

  Widget _resumen() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text('$_total',
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
                const Text('alumnos activos',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.black12),
          Expanded(
            child: Column(
              children: [
                Text('$_bajas',
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.black54)),
                const Text('bajas',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloque(String titulo, List<Map<String, dynamic>> datos, Color color) {
    int maximo = 1;
    for (final d in datos) {
      final v = (d['valor'] ?? 0) as int;
      if (v > maximo) maximo = v;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(titulo,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700)),
        ),
        Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: datos.isEmpty
                ? const Text('Sin datos.',
                    style: TextStyle(color: Colors.black54))
                : Column(
                    children: datos
                        .map((d) => _barra(
                              (d['etiqueta'] ?? '').toString(),
                              (d['valor'] ?? 0) as int,
                              maximo,
                              color,
                            ))
                        .toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _barra(String etiqueta, int valor, int maximo, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(etiqueta,
                    style: const TextStyle(fontSize: 12.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('$valor',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (valor / maximo).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

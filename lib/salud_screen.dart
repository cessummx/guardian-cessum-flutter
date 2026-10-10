// TABLERO DE SALUD DEL SISTEMA (22-sep-2026)
//
// La información existía repartida en una docena de rutas —latidos, jobs,
// salud de datos, pendientes de cada módulo— y nadie las consulta todas. En
// la práctica uno se enteraba de que algo dejó de correr cuando un alumno o
// un docente se quejaba.
//
// Esta pantalla no calcula nada nuevo: reúne lo que el Guardián ya calcula y
// lo pone en semáforos, con el botón que arregla cada cosa al lado.
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class SaludScreen extends StatefulWidget {
  const SaludScreen({super.key});
  @override
  State<SaludScreen> createState() => _SaludScreenState();
}

class _SaludScreenState extends State<SaludScreen> {
  bool _cargando = true;
  String _error = '';
  String _generado = '';
  bool _deCache = false;
  Map<String, dynamic> _resumen = {};
  List<dynamic> _bloques = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool refrescar = false}) async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'salud_tablero',
        if (refrescar) 'refrescar': '1',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo consultar');
      setState(() {
        _cargando = false;
        _generado = (d['generado'] ?? '').toString();
        _deCache = d['deCache'] == true;
        _resumen = Map<String, dynamic>.from((d['resumen'] as Map?) ?? {});
        _bloques = (d['bloques'] as List?) ?? [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Color _color(String estado) {
    if (estado == 'alerta') return cessumRed;
    if (estado == 'atencion') return const Color(0xFFB8860B);
    return const Color(0xFF1E7F52);
  }

  IconData _icono(String estado) {
    if (estado == 'alerta') return Icons.error_outline;
    if (estado == 'atencion') return Icons.warning_amber_rounded;
    return Icons.check_circle_outline;
  }

  /// El «arreglo» que manda el Guardián es la cola de una dirección
  /// (?accion=…). Se completa aquí con el dominio.
  void _abrirArreglo(String cola) {
    if (cola.isEmpty) return;
    final sep = cola.startsWith('?') ? '' : '?';
    final url = '$guardianUrl$sep${cola.startsWith('?') ? cola.substring(1) : cola}'
        '&lento=1';   // (8-oct) sin clave escrita: el puente (guardian.php) ya autentica
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final alerta = (_resumen['alerta'] as num?)?.toInt() ?? 0;
    final atencion = (_resumen['atencion'] as num?)?.toInt() ?? 0;
    final ok = (_resumen['ok'] as num?)?.toInt() ?? 0;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Salud del sistema'),
        actions: [
          IconButton(
            tooltip: 'Volver a medir todo',
            onPressed: _cargando ? null : () => _cargar(refrescar: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 42, color: cessumGold),
                      const SizedBox(height: 12),
                      Text(_error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: cessumRed),
                        onPressed: () => _cargar(),
                        child: const Text('Reintentar'),
                      ),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                  children: [
                    Row(children: [
                      _cifra('Alertas', alerta, cessumRed),
                      _cifra('Por revisar', atencion, const Color(0xFFB8860B)),
                      _cifra('En orden', ok, const Color(0xFF1E7F52)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      _generado.isEmpty
                          ? ''
                          : 'Medido el $_generado'
                              '${_deCache ? ' · guardado hace unos minutos; «Volver a medir» lo rehace' : ''}',
                      style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                    ),
                    const SizedBox(height: 14),
                    ..._bloques.map((b) {
                      final bl = Map<String, dynamic>.from(b as Map);
                      final puntos = (bl['puntos'] as List?) ?? [];
                      if (puntos.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 6),
                            child: Text('${bl['bloque']}',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                          ...puntos.map((p) => _punto(Map<String, dynamic>.from(p as Map))),
                          const SizedBox(height: 10),
                        ],
                      );
                    }),
                  ],
                ),
    );
  }

  Widget _cifra(String titulo, int n, Color color) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            Text(titulo, style: TextStyle(fontSize: 11.5, color: color)),
          ]),
        ),
      );

  Widget _punto(Map<String, dynamic> p) {
    final estado = (p['estado'] ?? 'ok').toString();
    final color = _color(estado);
    final arreglo = (p['arreglo'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icono(estado), color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('${p['titulo']}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                  Text('${p['valor']}',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w800, color: color)),
                ]),
                if ((p['detalle'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('${p['detalle']}',
                        style: TextStyle(
                            fontSize: 12, height: 1.35, color: cessumMuted(context))),
                  ),
                if (arreglo.isNotEmpty && estado != 'ok')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 32)),
                      onPressed: () => _abrirArreglo(arreglo),
                      icon: const Icon(Icons.build_outlined, size: 16),
                      label: const Text('Abrir el arreglo'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

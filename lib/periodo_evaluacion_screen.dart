import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';

/// Control manual del periodo de evaluación docente. El admin decide qué
/// asignaciones (docente + materia + grupo) están ABIERTAS a evaluación.
/// Solo las abiertas se piden a los alumnos y cuentan en la cobertura.
class PeriodoEvaluacionScreen extends StatefulWidget {
  const PeriodoEvaluacionScreen({super.key});

  @override
  State<PeriodoEvaluacionScreen> createState() =>
      _PeriodoEvaluacionScreenState();
}

class _PeriodoEvaluacionScreenState extends State<PeriodoEvaluacionScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  List<Map<String, dynamic>> _todas = [];
  bool _cargando = true;
  String? _error;
  String _busqueda = '';
  String _filtro = 'todas'; // todas | abiertas | cerradas
  String _correoActor = '';
  final _busCtrl = TextEditingController();
  DateTime? _ultimaCarga;

  @override
  void initState() {
    super.initState();
    _cargarActor();
    _cargar();
  }

  @override
  void dispose() {
    _busCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarActor() async {
    final c = await SessionStore.realEmail();
    if (mounted && c != null) setState(() => _correoActor = c);
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=eval_asignaciones'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _todas = ((data['asignaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
        _ultimaCarga = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las asignaciones.';
      });
    }
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : _verde,
      content: Text(m),
    ));
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _busqueda.trim().toLowerCase();
    return _todas.where((a) {
      if (_filtro == 'abiertas' && a['abierta'] != true) return false;
      if (_filtro == 'cerradas' && a['abierta'] == true) return false;
      if (q.isEmpty) return true;
      final txt = '${a['docente']} ${a['materia']} ${a['grupo']} '
              '${a['programa']} ${a['generacion']}'
          .toLowerCase();
      return txt.contains(q);
    }).toList();
  }

  Future<void> _fijar(Map<String, dynamic> a, bool abrir) async {
    // Cambio optimista en pantalla.
    setState(() => a['abierta'] = abrir);
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'eval_fijar_apertura',
              'programa': a['programa'],
              'generacion': a['generacion'],
              'grupo': a['grupo'],
              'materia': a['materia'],
              'docente': a['docente'],
              'abrir': abrir,
              'actor': _correoActor,
            }),
          )
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        setState(() => a['abierta'] = !abrir); // revertir
        _aviso('No se pudo guardar el cambio.', error: true);
      }
    } catch (_) {
      setState(() => a['abierta'] = !abrir);
      _aviso('No se pudo conectar.', error: true);
    }
  }

  Future<void> _fijarLote(bool abrir) async {
    final lista = _visibles;
    if (lista.isEmpty) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(abrir ? 'Abrir evaluación' : 'Cerrar evaluación',
            style: const TextStyle(fontSize: 16)),
        content: Text(
          '${abrir ? 'Se abrirán' : 'Se cerrarán'} ${lista.length} '
          'asignación(es) visibles a evaluación. ¿Continuar?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: abrir ? _verde : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(abrir ? 'Abrir todas' : 'Cerrar todas'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _cargando = true);
    try {
      final payloadLista = lista
          .map((a) => {
                'programa': a['programa'],
                'generacion': a['generacion'],
                'grupo': a['grupo'],
                'materia': a['materia'],
                'docente': a['docente'],
              })
          .toList();
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'eval_fijar_apertura_lote',
              'lista': payloadLista,
              'abrir': abrir,
              'actor': _correoActor,
            }),
          )
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _aviso('${data['hechos'] ?? lista.length} asignación(es) '
            '${abrir ? 'abiertas' : 'cerradas'}.');
        await _cargar();
      } else {
        _aviso('No se pudo aplicar.', error: true);
        setState(() => _cargando = false);
      }
    } catch (_) {
      _aviso('No se pudo conectar.', error: true);
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    final totalAbiertas = _todas.where((a) => a['abierta'] == true).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Periodo de evaluación',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _bannerError()
              : Column(
                  children: [
                    _encabezado(totalAbiertas),
                    Expanded(
                      child: visibles.isEmpty
                          ? Center(
                              child: Text('Sin asignaciones en este filtro.',
                                  style: TextStyle(color: cessumMuted(context))))
                          : RefreshIndicator(
                              onRefresh: _cargar,
                              child: ListView.builder(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                    12, 4, 12, 16),
                                itemCount: visibles.length,
                                itemBuilder: (ctx, i) =>
                                    _filaAsignacion(visibles[i]),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _bannerError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: cessumRed, size: 40),
            const SizedBox(height: 12),
            Text(_error ?? 'Error',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encabezado(int totalAbiertas) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solo las asignaciones ABIERTAS se les piden a los alumnos y '
            'cuentan en la cobertura. Abre las que ya terminaron o están '
            'por terminar.',
            style: TextStyle(fontSize: 12, color: cessumMuted(context)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('$totalAbiertas abiertas', _verde),
              const SizedBox(width: 8),
              _chip('${_todas.length} en total', cessumMuted(context)),
              const Spacer(),
              if (_ultimaCarga != null)
                Text(Helpers.haceTexto(_ultimaCarga),
                    style: TextStyle(
                        fontSize: 11, color: cessumFaint(context))),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _busCtrl,
            onChanged: (v) => setState(() => _busqueda = v),
            decoration: InputDecoration(
              hintText: 'Buscar docente, materia, grupo...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _filtroChip('Todas', 'todas'),
              const SizedBox(width: 6),
              _filtroChip('Abiertas', 'abiertas'),
              const SizedBox(width: 6),
              _filtroChip('Cerradas', 'cerradas'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: _verde),
                  onPressed: () => _fijarLote(true),
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Abrir visibles'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                  onPressed: () => _fijarLote(false),
                  icon: const Icon(Icons.lock, size: 18),
                  label: const Text('Cerrar visibles'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _filtroChip(String texto, String valor) {
    final sel = _filtro == valor;
    return ChoiceChip(
      label: Text(texto, style: const TextStyle(fontSize: 12)),
      selected: sel,
      onSelected: (_) => setState(() => _filtro = valor),
      selectedColor: cessumRed.withValues(alpha: 0.15),
      labelStyle: TextStyle(color: sel ? cessumRed : cessumMuted(context)),
    );
  }

  Widget _filaAsignacion(Map<String, dynamic> a) {
    final abierta = a['abierta'] == true;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 0.5,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${a['materia']}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${a['docente']}',
                      style: TextStyle(
                          fontSize: 12.5, color: cessumInk(context))),
                  const SizedBox(height: 2),
                  Text(
                    '${a['programa']}'
                    '${(a['grupo'] ?? '').toString().isNotEmpty ? ' · Grupo ${a['grupo']}' : ''}'
                    '${(a['generacion'] ?? '').toString().isNotEmpty ? ' · ${a['generacion']}' : ''}',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                Switch(
                  value: abierta,
                  activeColor: _verde,
                  onChanged: (v) => _fijar(a, v),
                ),
                Text(abierta ? 'Abierta' : 'Cerrada',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: abierta ? _verde : cessumFaint(context))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

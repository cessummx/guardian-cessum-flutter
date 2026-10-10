import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Recordatorios de pago (admin): registra vencimientos a mano; el sistema
/// avisa al alumno 3 días antes y reporta a administración los vencidos.
class VencimientosScreen extends StatefulWidget {
  const VencimientosScreen({super.key});

  @override
  State<VencimientosScreen> createState() => _VencimientosScreenState();
}

class _VencimientosScreenState extends State<VencimientosScreen> {
  List<Map<String, dynamic>> _lista = [];
  String _filtro = 'Pendiente';
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

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
          .get(Uri.parse('$guardianUrl?accion=vencimientos_listar'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _lista = (data['vencimientos'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los vencimientos.';
      });
    }
  }

  List<Map<String, dynamic>> get _visibles => _filtro == 'Todos'
      ? _lista
      : _lista.where((v) => (v['estatus'] ?? '') == _filtro).toList();

  Color _color(String estatus, int? dias) {
    if (estatus == 'Pagado') return Colors.green.shade700;
    if (estatus == 'Vencido' || (dias != null && dias < 0)) return cessumRed;
    if (dias != null && dias <= 3) return cessumGold;
    return cessumMuted(context);
  }

  Future<void> _post(Map<String, dynamic> payload, String okMsg) async {
    setState(() => _guardando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(okMsg),
        ));
      }
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<List<Map<String, String>>> _buscarAlumnos(String q) async {
    if (q.trim().length < 2) return [];
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'grupos_admin_buscar',
        'q': q.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return [];
      final lista = (data['grupos'] as List<dynamic>? ?? []);
      return lista
          .map((e) {
            final m = e as Map<String, dynamic>;
            return {
              'matricula': (m['matricula'] ?? '').toString(),
              'nombre': (m['nombre'] ?? '').toString(),
              'programa': (m['programa'] ?? '').toString(),
            };
          })
          .where((m) => (m['matricula'] ?? '').isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _nuevo() async {
    final concepto = TextEditingController(text: 'Reinscripción');
    final monto = TextEditingController();
    final fecha = TextEditingController();
    String matriculaFinal = '';
    String nombreFinal = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => AlertDialog(
          title: const Text('Nuevo vencimiento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Autocomplete<Map<String, String>>(
                  displayStringForOption: (o) =>
                      '${o['nombre']} · ${o['matricula']}',
                  optionsBuilder: (TextEditingValue value) async {
                    return await _buscarAlumnos(value.text);
                  },
                  onSelected: (o) => setSB(() {
                    matriculaFinal = o['matricula'] ?? '';
                    nombreFinal = o['nombre'] ?? '';
                  }),
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmit) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Alumno (nombre o matrícula) *',
                        border: OutlineInputBorder(),
                        isDense: true,
                        prefixIcon: Icon(Icons.search, color: cessumRed),
                        helperText: 'Escribe y elige de la lista.',
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxHeight: 240, maxWidth: 360),
                          child: ListView(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            children: options.map((o) {
                              return ListTile(
                                dense: true,
                                title: Text((o['nombre'] ?? '').toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    'Mat. ${o['matricula']} · ${o['programa']}',
                                    style: const TextStyle(fontSize: 12)),
                                onTap: () => onSelected(o),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (matriculaFinal.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: Color(0xFF1E8E3E), size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$nombreFinal · $matriculaFinal',
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E8E3E)),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: concepto,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: monto,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Monto (MXN)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fecha,
                  decoration: const InputDecoration(
                    labelText: 'Fecha límite (dd/mm/aaaa) *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                if (matriculaFinal.isEmpty || fecha.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Elige un alumno y escribe la fecha límite.'),
                  ));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _post({
      'accion': 'vencimiento_guardar',
      'matricula': matriculaFinal,
      'concepto': concepto.text.trim(),
      'monto': monto.text.trim(),
      'fechaLimite': fecha.text.trim(),
    }, 'Vencimiento registrado.');
  }

  Future<void> _eliminar(Map<String, dynamic> v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar vencimiento'),
        content: Text(
            '¿Eliminar el vencimiento de ${v['nombre']} (${v['concepto']})?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _post(
        {'accion': 'vencimiento_eliminar', 'fila': v['fila']}, 'Eliminado.');
  }

  @override
  Widget build(BuildContext context) {
    final filtros = ['Pendiente', 'Vencido', 'Todos'];
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Recordatorios de pago',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _guardando ? null : _nuevo,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: filtros.map((f) {
                final activo = _filtro == f;
                final cuantos = f == 'Todos'
                    ? _lista.length
                    : _lista.where((v) => (v['estatus'] ?? '') == f).length;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$f ($cuantos)'),
                    selected: activo,
                    selectedColor: cessumRed.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: activo ? cessumRed : cessumInk(context),
                      fontWeight:
                          activo ? FontWeight.w700 : FontWeight.w400,
                    ),
                    onSelected: (_) => setState(() => _filtro = f),
                  ),
                );
              }).toList(),
            ),
          ),
          if (_guardando) const LinearProgressIndicator(color: cessumRed),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed: _cargar,
                                child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _visibles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Sin vencimientos en este filtro. Usa "Nuevo" para registrar uno; el alumno recibirá aviso 3 días antes.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: cessumMuted(context), height: 1.5),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 10, 16, 90),
                            itemCount: _visibles.length,
                            itemBuilder: (ctx, i) {
                              final v = _visibles[i];
                              final estatus = (v['estatus'] ?? '') as String;
                              final dias = v['diasRestantes'] as int?;
                              final color = _color(estatus, dias);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 9,
                                    backgroundColor: color,
                                  ),
                                  title: Text(
                                    '${v['nombre']} (${v['matricula']})',
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    '${v['concepto']}'
                                    '${(v['monto'] ?? '').toString().isNotEmpty ? ' · \$${v['monto']}' : ''}\n'
                                    'Vence: ${v['fechaLimite']} · '
                                    '${estatus == 'Vencido' || (dias != null && dias < 0) ? 'VENCIDO' : (dias != null ? (dias == 0 ? 'vence hoy' : 'en $dias día(s)') : '')}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: color,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  isThreeLine: true,
                                  trailing: IconButton(
                                    icon: Icon(Icons.delete_outline,
                                        color: cessumFaint(context)),
                                    onPressed: _guardando
                                        ? null
                                        : () => _eliminar(v),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

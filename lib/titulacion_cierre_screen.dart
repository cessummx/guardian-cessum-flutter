import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Cierre de titulación: control de cédula profesional (trámite SEP-DGP) y
/// generador de actas de egreso por generación.
class TitulacionCierreScreen extends StatelessWidget {
  const TitulacionCierreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Cierre de titulación',
              style: TextStyle(fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: [
              Tab(icon: Icon(Icons.card_membership, size: 20), text: 'Cédulas'),
              Tab(icon: Icon(Icons.groups, size: 20), text: 'Actas de egreso'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CedulasTab(),
            _ActaEgresoTab(),
          ],
        ),
      ),
    );
  }
}

/* ---------------- Pestaña 1: Control de cédulas ---------------- */
class _CedulasTab extends StatefulWidget {
  const _CedulasTab();
  @override
  State<_CedulasTab> createState() => _CedulasTabState();
}

class _CedulasTabState extends State<_CedulasTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _lista = [];
  String _filtro = 'Todas';
  bool _cargando = true;
  bool _procesando = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

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
      final uri = Uri.parse('$guardianUrl?accion=cedulas_listar'
          '${_filtro != 'Todas' ? '&estatus=${Uri.encodeComponent(_filtro)}' : ''}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _lista = ((data['cedulas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar.';
      });
    }
  }

  Color _color(String est) {
    switch (est) {
      case 'Cédula lista':
        return const Color(0xFF1E8E3E);
      case 'En trámite SEP':
        return cessumGold;
      default:
        return Colors.black54;
    }
  }

  Future<void> _editar(Map<String, dynamic> c) async {
    String estatus = (c['cedulaEstatus'] ?? 'No iniciada').toString();
    if (!['No iniciada', 'En trámite SEP', 'Cédula lista'].contains(estatus)) {
      estatus = 'No iniciada';
    }
    final folioC = TextEditingController(text: (c['cedulaFolio'] ?? '').toString());
    final envio = TextEditingController(text: (c['cedulaEnvioSep'] ?? '').toString());
    final recibida =
        TextEditingController(text: (c['cedulaRecibida'] ?? '').toString());
    final notas = TextEditingController(text: (c['cedulaNotas'] ?? '').toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text('${c['nombre']}',
              style: const TextStyle(fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: estatus,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Estatus de cédula',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'No iniciada', child: Text('No iniciada')),
                    DropdownMenuItem(
                        value: 'En trámite SEP', child: Text('En trámite SEP')),
                    DropdownMenuItem(
                        value: 'Cédula lista', child: Text('Cédula lista')),
                  ],
                  onChanged: (v) => setS(() => estatus = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: folioC,
                  decoration: const InputDecoration(
                    labelText: 'Folio de cédula profesional',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: envio,
                  decoration: const InputDecoration(
                    labelText: 'Fecha envío a SEP/DGP',
                    hintText: 'dd/mm/aaaa',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: recibida,
                  decoration: const InputDecoration(
                    labelText: 'Fecha recibida',
                    hintText: 'dd/mm/aaaa',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notas,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                if (estatus == 'Cédula lista')
                  const Text(
                    'Al guardar como "Cédula lista" se enviará un correo de aviso al egresado.',
                    style: TextStyle(fontSize: 11.5, color: cessumRed),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'cedula_actualizar',
                'folio': c['folio'],
                'cedulaEstatus': estatus,
                'cedulaFolio': folioC.text.trim(),
                'cedulaEnvioSep': envio.text.trim(),
                'cedulaRecibida': recibida.text.trim(),
                'cedulaNotas': notas.text.trim(),
              }))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Cédula actualizada.'),
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
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtros = ['Todas', 'No iniciada', 'En trámite SEP', 'Cédula lista'];
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_procesando) const LinearProgressIndicator(color: cessumRed),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: filtros.map((f) {
              final activo = _filtro == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f, style: const TextStyle(fontSize: 12)),
                  selected: activo,
                  selectedColor: cessumRed.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: activo ? cessumRed : Colors.black87,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w400,
                  ),
                  onSelected: (_) {
                    setState(() => _filtro = f);
                    _cargar();
                  },
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _lista.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay egresados con examen aprobado en este filtro. Cuando un alumno aprueba su examen de grado, aparece aquí para tramitar su cédula.',
                      style: TextStyle(color: Colors.black54, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _lista.length,
                  itemBuilder: (ctx, i) {
                    final c = _lista[i];
                    final est = (c['cedulaEstatus'] ?? 'No iniciada').toString();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: Icon(Icons.card_membership, color: _color(est)),
                        title: Text('${c['nombre']} (${c['matricula']})',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${c['programa']} · ${c['generacion']}\n$est'
                          '${(c['cedulaFolio'] ?? '').toString().isNotEmpty ? ' · folio ${c['cedulaFolio']}' : ''}',
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: _color(est),
                              fontWeight: FontWeight.w600),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.edit, color: cessumRed),
                        onTap: _procesando ? null : () => _editar(c),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/* ---------------- Pestaña 2: Actas de egreso ---------------- */
class _ActaEgresoTab extends StatefulWidget {
  const _ActaEgresoTab();
  @override
  State<_ActaEgresoTab> createState() => _ActaEgresoTabState();
}

class _ActaEgresoTabState extends State<_ActaEgresoTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _generaciones = [];
  bool _cargando = true;
  bool _generando = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

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
          .get(Uri.parse('$guardianUrl?accion=circular_generaciones'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _generaciones = ((data['generaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar.';
      });
    }
  }

  Future<void> _generar(Map<String, dynamic> g) async {
    setState(() => _generando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'acta_egreso_generar',
                'programa': g['programa'],
                'generacion': g['generacion'],
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (!mounted) return;
      if (pdf.isNotEmpty) Helpers.abrirUrlExterna(pdf, context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text(
            'Acta generada · ${data['egresados']} egresados, ${data['titulados']} con titulación avanzada.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_generando) const LinearProgressIndicator(color: cessumRed),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
            'Genera un acta de egreso en PDF con todos los alumnos de una generación y su estatus de titulación.',
            style: TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: _generaciones.length,
            itemBuilder: (ctx, i) {
              final g = _generaciones[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.groups, color: cessumRed),
                  title: Text('${g['programa']}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      'Gen. ${g['generacion']} · ${g['alumnos']} alumno(s)',
                      style: const TextStyle(fontSize: 11.5)),
                  trailing: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact),
                    onPressed: _generando ? null : () => _generar(g),
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text('Acta', style: TextStyle(fontSize: 12)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Centro de inteligencia institucional: expediente PDF del alumno,
/// generaciones próximas a egresar y duplicados de matrícula.
class CentroInteligenciaScreen extends StatelessWidget {
  const CentroInteligenciaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Centro de inteligencia',
              style: TextStyle(fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: [
              Tab(icon: Icon(Icons.folder_shared, size: 20), text: 'Expediente'),
              Tab(icon: Icon(Icons.school, size: 20), text: 'Por egresar'),
              Tab(icon: Icon(Icons.copy_all, size: 20), text: 'Duplicados'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ExpedienteTab(),
            _EgresoTab(),
            _DuplicadosTab(),
          ],
        ),
      ),
    );
  }
}

/* ---------------- Pestaña 1: Expediente PDF ---------------- */
class _ExpedienteTab extends StatefulWidget {
  const _ExpedienteTab();
  @override
  State<_ExpedienteTab> createState() => _ExpedienteTabState();
}

class _ExpedienteTabState extends State<_ExpedienteTab>
    with AutomaticKeepAliveClientMixin {
  final _mat = TextEditingController();
  bool _generando = false;
  String? _ultimoPdf;
  String? _ultimoFolio;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _mat.dispose();
    super.dispose();
  }

  Future<void> _generar() async {
    final mat = _mat.text.trim();
    if (mat.isEmpty) return;
    setState(() {
      _generando = true;
      _ultimoPdf = null;
    });
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=expediente_pdf&matricula=${Uri.encodeComponent(mat)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _ultimoPdf = (data['pdf'] ?? '').toString();
        _ultimoFolio = (data['folio'] ?? '').toString();
      });
      if (_ultimoPdf != null && _ultimoPdf!.isNotEmpty) {
        Helpers.abrirUrlExterna(_ultimoPdf!, context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo generar: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Genera el expediente académico completo de un alumno como PDF con folio: datos, calificaciones, trámites, riesgo, titulación y pagos.',
          style: TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _mat,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _generar(),
          decoration: const InputDecoration(
            labelText: 'Matrícula del alumno',
            prefixIcon: Icon(Icons.badge),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _generando ? null : _generar,
            icon: _generando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf),
            label: Text(_generando ? 'Generando...' : 'Generar expediente PDF'),
          ),
        ),
        if (_ultimoPdf != null && _ultimoPdf!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFFE8F5E9),
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: Color(0xFF1E8E3E)),
              title: Text('Expediente generado · $_ultimoFolio',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: const Text('Toca para volver a abrir el PDF',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Helpers.abrirUrlExterna(_ultimoPdf!, context),
            ),
          ),
        ],
      ],
    );
  }
}

/* ---------------- Pestaña 2: Generaciones por egresar ---------------- */
class _EgresoTab extends StatefulWidget {
  const _EgresoTab();
  @override
  State<_EgresoTab> createState() => _EgresoTabState();
}

class _EgresoTabState extends State<_EgresoTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _gens = [];
  int _umbral = 4;
  bool _cargando = true;
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
          .get(Uri.parse('$guardianUrl?accion=generaciones_egreso&umbral=$_umbral'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _gens = ((data['generaciones'] as List?) ?? [])
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

  Color _color(int meses) {
    if (meses < 0) return cessumRed;
    if (meses == 0) return cessumRed;
    if (meses <= 2) return cessumGold;
    return const Color(0xFF1E8E3E);
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('Egresan dentro de:', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: _umbral,
                items: const [
                  DropdownMenuItem(value: 2, child: Text('2 meses')),
                  DropdownMenuItem(value: 4, child: Text('4 meses')),
                  DropdownMenuItem(value: 6, child: Text('6 meses')),
                  DropdownMenuItem(value: 12, child: Text('12 meses')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _umbral = v);
                  _cargar();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _gens.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No hay generaciones que egresen en ese plazo.',
                      style: TextStyle(color: Colors.black54),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _gens.length,
                  itemBuilder: (ctx, i) {
                    final g = _gens[i];
                    final meses = (g['mesesRestantes'] ?? 0) as int;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _color(meses).withValues(alpha: 0.15),
                          child: Icon(Icons.school, color: _color(meses)),
                        ),
                        title: Text('${g['programa']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          'Gen. ${g['generacion']} · ${g['alumnos']} alumno(s)\n${g['estado']}',
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: _color(meses),
                              fontWeight: FontWeight.w600),
                        ),
                        isThreeLine: true,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/* ---------------- Pestaña 3: Duplicados ---------------- */
class _DuplicadosTab extends StatefulWidget {
  const _DuplicadosTab();
  @override
  State<_DuplicadosTab> createState() => _DuplicadosTabState();
}

class _DuplicadosTabState extends State<_DuplicadosTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _dups = [];
  bool _cargando = true;
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
          .get(Uri.parse('$guardianUrl?accion=duplicados_matricula'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _dups = ((data['duplicados'] as List?) ?? [])
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
    if (_dups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '¡Sin duplicados! Todas las matrículas en la lista de alumnos son únicas.',
            style: TextStyle(color: Colors.black54, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _dups.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${_dups.length} matrícula(s) duplicada(s). Revisa y corrige en la lista de alumnos.',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: cessumRed),
            ),
          );
        }
        final d = _dups[i - 1];
        final registros = (d['registros'] as List?) ?? [];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: cessumRed, size: 20),
                    const SizedBox(width: 8),
                    Text('Matrícula ${d['matricula']}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${d['cantidad']} registros',
                          style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: cessumRed)),
                    ),
                  ],
                ),
                const Divider(height: 16),
                ...registros.map((raw) {
                  final r = Map<String, dynamic>.from(raw as Map);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r['nombre']}',
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(
                          '${r['programa']} · ${r['generacion']}\n${r['correo']}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54, height: 1.3),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

/// Pantalla del docente: estado de cada una de sus actas
/// (Sin capturar / En validación / Validada / Devuelta con observaciones).
/// Al tocar "Corregir" en una devuelta, regresa a captura con esa materia.
class MisActasDocenteScreen extends StatefulWidget {
  const MisActasDocenteScreen({super.key});

  @override
  State<MisActasDocenteScreen> createState() => _MisActasDocenteScreenState();
}

class _MisActasDocenteScreenState extends State<MisActasDocenteScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  String _filtro = 'Todas';

  static const _filtros = [
    'Todas',
    'Devuelta',
    'En validación',
    'Sin capturar',
    'Validada'
  ];

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
      final correo = await SessionStore.validEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_actas_docente',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _items = (data['actas'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _error = (data['error'] ?? 'No se pudo cargar').toString();
      }
    } catch (e) {
      _error = 'Error de conexión: $e';
    }
    if (mounted) setState(() => _cargando = false);
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_filtro == 'Todas') return _items;
    return _items.where((e) => (e['estatus'] ?? '') == _filtro).toList();
  }

  Color _color(String estatus) {
    switch (estatus) {
      case 'Devuelta':
        return cessumRed;
      case 'En validación':
        return cessumGold;
      case 'Validada':
        return const Color(0xFF2E7D32);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Estado de mis actas'),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _vistaLista(),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: cessumRed, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _vistaLista() {
    final lista = _filtrados;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: _filtros.map((f) {
              final sel = _filtro == f;
              final n = f == 'Todas'
                  ? _items.length
                  : _items.where((e) => (e['estatus'] ?? '') == f).length;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text('$f ($n)'),
                  selected: sel,
                  onSelected: (_) => setState(() => _filtro = f),
                  selectedColor: cessumRed.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                      fontSize: 12.5,
                      color: sel ? cessumRed : cessumInk(context),
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? Center(
                  child: Text(
                    _items.isEmpty
                        ? 'No tienes materias asignadas.'
                        : 'Sin actas en "$_filtro".',
                    style: TextStyle(color: cessumFaint(context)),
                  ),
                )
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: lista.length,
                    itemBuilder: (_, i) => _tarjeta(lista[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _tarjeta(Map<String, dynamic> e) {
    final estatus = (e['estatus'] ?? '').toString();
    final obs = (e['observaciones'] ?? '').toString();
    final c = _color(estatus);
    return Card(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${e['materia']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.withValues(alpha: 0.5)),
                  ),
                  child: Text(estatus,
                      style: TextStyle(
                          fontSize: 11, color: c, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${e['programa']} · Gen. ${e['generacion']} · Grupo ${e['grupo']}',
              style: TextStyle(color: cessumFaint(context), fontSize: 12.5),
            ),
            if (estatus == 'Devuelta' && obs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.06),
                  border: const Border(
                      left: BorderSide(color: cessumRed, width: 3)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('Observaciones: $obs',
                    style: const TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: cessumRed),
                  onPressed: () => Navigator.pop(context, e),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Corregir'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

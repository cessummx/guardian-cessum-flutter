import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Confirmaciones de recepción (admin): quién abrió/confirmó su boleta,
/// aviso de trámite o de titulación, y por qué canal (correo o app).
class VistosScreen extends StatefulWidget {
  const VistosScreen({super.key});

  @override
  State<VistosScreen> createState() => _VistosScreenState();
}

class _VistosScreenState extends State<VistosScreen> {
  List<Map<String, dynamic>> _vistos = [];
  String _filtro = 'Todos';
  final _busca = TextEditingController();
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final q = _busca.text.trim();
      final uri = Uri.parse('$guardianUrl?accion=vistos_listar&n=300'
          '${_filtro != 'Todos' ? '&tipo=${Uri.encodeComponent(_filtro)}' : ''}'
          '${q.isNotEmpty ? '&q=${Uri.encodeComponent(q)}' : ''}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _vistos = (data['vistos'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las confirmaciones.';
      });
    }
  }

  IconData _icono(String tipo) {
    switch (tipo) {
      case 'Boleta':
        return Icons.receipt_long;
      case 'Trámite':
        return Icons.description;
      case 'Titulación':
        return Icons.school;
      default:
        return Icons.visibility;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtros = ['Todos', 'Boleta', 'Trámite', 'Titulación'];
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Confirmaciones de lectura',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _busca,
              onSubmitted: (_) => _cargar(),
              decoration: InputDecoration(
                hintText: 'Buscar por quién o referencia...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _cargar),
                border: const OutlineInputBorder(),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: filtros.map((f) {
                final activo = _filtro == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(f),
                    selected: activo,
                    selectedColor: cessumRed.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      color: activo ? cessumRed : cessumInk(context),
                      fontWeight:
                          activo ? FontWeight.w700 : FontWeight.w400,
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
                    : _vistos.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Aún no hay confirmaciones. Se registran cuando el alumno toca "Confirmar que lo recibí" en su correo o abre el contenido en la app.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: cessumMuted(context), height: 1.5),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding:
                                const EdgeInsets.fromLTRB(16, 6, 16, 16),
                            itemCount: _vistos.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final v = _vistos[i];
                              final canal = (v['canal'] ?? '') as String;
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                    _icono((v['tipo'] ?? '') as String),
                                    color: cessumRed,
                                    size: 22),
                                title: Text(
                                  '${v['quien']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(
                                  '${v['tipo']} · ${v['referencia']}\n${v['fecha']}',
                                  style: const TextStyle(
                                      fontSize: 11.5, height: 1.4),
                                ),
                                isThreeLine: true,
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (canal == 'app'
                                            ? cessumGold
                                            : const Color(0xFF1E8E3E))
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    canal == 'app' ? 'En la app' : 'Por correo',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: canal == 'app'
                                          ? const Color(0xFF8A6118)
                                          : const Color(0xFF1E8E3E),
                                    ),
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

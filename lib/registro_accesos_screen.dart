import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// REGISTRO DE ACCESOS (solo administradores).
/// Muestra quién ha entrado a la app y cuándo:
///   - Pestaña "Recientes": lista de los últimos accesos (correo, nombre,
///     rol, fecha y hora).
///   - Pestaña "Conteo": cuántas veces ha entrado cada persona y su
///     último acceso.
/// Incluye buscador por nombre o correo que filtra ambas pestañas.
///
/// Consume la acción del Guardián:  GET ?accion=accesos_listar
/// Respuesta esperada:
///   { ok: true,
///     accesos: [ {fecha, correo, nombre, rol}, ... ]   (más reciente primero)
///     conteo:  [ {correo, nombre, rol, veces, ultimo}, ... ] }
class RegistroAccesosScreen extends StatefulWidget {
  const RegistroAccesosScreen({super.key});

  @override
  State<RegistroAccesosScreen> createState() => _RegistroAccesosScreenState();
}

class _RegistroAccesosScreenState extends State<RegistroAccesosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final TextEditingController _busqueda = TextEditingController();

  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _accesos = [];
  List<Map<String, dynamic>> _conteo = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tab.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'accesos_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _accesos = (data['accesos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      _conteo = (data['conteo'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // El conteo se muestra de mayor a menor número de entradas.
      _conteo.sort((a, b) {
        final va = (a['veces'] as num? ?? 0).toInt();
        final vb = (b['veces'] as num? ?? 0).toInt();
        return vb.compareTo(va);
      });
      if (mounted) setState(() => _cargando = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar el registro. Revisa tu conexión.';
        });
      }
    }
  }

  String _norm(String s) {
    s = s.toLowerCase();
    const con = 'áàäâéèëêíìïîóòöôúùüûñ';
    const sin = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
  }

  bool _coincide(Map<String, dynamic> m) {
    final q = _norm(_busqueda.text.trim());
    if (q.isEmpty) return true;
    final txt = _norm('${m['nombre']} ${m['correo']}');
    return txt.contains(q);
  }

  List<Map<String, dynamic>> get _accesosFiltrados =>
      _accesos.where(_coincide).toList();

  List<Map<String, dynamic>> get _conteoFiltrado =>
      _conteo.where(_coincide).toList();

  Color _colorRol(String rol) {
    switch (rol.trim().toLowerCase()) {
      case 'administrador':
        return cessumRed;
      case 'docente':
        return cessumGold;
      case 'alumno':
        return const Color(0xFF1E8E3E);
      default:
        return Colors.black38;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Registro de accesos'),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Recientes'),
            Tab(text: 'Conteo por persona'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      child: TextField(
                        controller: _busqueda,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o correo',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _busqueda.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _busqueda.clear();
                                    setState(() {});
                                  },
                                ),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: [_tabRecientes(), _tabConteo()],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
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

  // ===================== PESTAÑA: RECIENTES =====================

  Widget _tabRecientes() {
    final lista = _accesosFiltrados;
    if (lista.isEmpty) {
      return const Center(
        child: Text('No hay accesos registrados.',
            style: TextStyle(color: Colors.black54)),
      );
    }
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: lista.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                '${lista.length} acceso(s) mostrados (los más recientes primero).',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            );
          }
        final a = lista[i - 1];
        final rol = (a['rol'] ?? '').toString();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Icon(Icons.login, size: 20, color: _colorRol(rol)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (a['nombre'] ?? '').toString().trim().isEmpty
                          ? (a['correo'] ?? '').toString()
                          : (a['nombre'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Text((a['correo'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text((a['fecha'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                  if (rol.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _colorRol(rol).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(rol,
                          style: TextStyle(
                              fontSize: 11, color: _colorRol(rol))),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    ),
    );
  }

  // ===================== PESTAÑA: CONTEO =====================

  Widget _tabConteo() {
    final lista = _conteoFiltrado;
    if (lista.isEmpty) {
      return const Center(
        child: Text('No hay datos de conteo.',
            style: TextStyle(color: Colors.black54)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: lista.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              '${lista.length} persona(s), de la que más entra a la que menos.',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          );
        }
        final c = lista[i - 1];
        final rol = (c['rol'] ?? '').toString();
        final veces = (c['veces'] as num? ?? 0).toInt();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$veces',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: cessumRed),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (c['nombre'] ?? '').toString().trim().isEmpty
                          ? (c['correo'] ?? '').toString()
                          : (c['nombre'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Text((c['correo'] ?? '').toString(),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(
                      'Último acceso: ${(c['ultimo'] ?? '—').toString()}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              if (rol.trim().isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _colorRol(rol).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(rol,
                      style:
                          TextStyle(fontSize: 11, color: _colorRol(rol))),
                ),
            ],
          ),
        );
      },
    );
  }
}

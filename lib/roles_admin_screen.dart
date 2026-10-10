import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

/// Panel de administrador: asignar y quitar roles de administración
/// (total, soporte, control, academico, docente). Solo un rol "total" puede
/// modificar roles; el Guardián valida esto del lado del servidor.
class RolesAdminScreen extends StatefulWidget {
  const RolesAdminScreen({super.key});

  @override
  State<RolesAdminScreen> createState() => _RolesAdminScreenState();
}

class _RolesAdminScreenState extends State<RolesAdminScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _roles = [];
  List<String> _rolesValidos = const [
    'total',
    'soporte',
    'control',
    'academico',
    'docente'
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
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'roles_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _roles = ((data['roles'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final rv = (data['rolesValidos'] as List?);
        if (rv != null && rv.isNotEmpty) {
          _rolesValidos = rv.map((e) => e.toString()).toList();
        }
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar ($e)';
      });
    }
  }

  Future<void> _accion(Map<String, dynamic> body, String exito) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final actor = await SessionStore.realEmail() ?? '';
      body['actor'] = actor;
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(exito),
          backgroundColor: const Color(0xFF1E8E3E),
        ));
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'No autorizado');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  Future<void> _asignar() async {
    final correo = TextEditingController();
    String rol = _rolesValidos.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Asignar rol'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: correo,
                decoration: const InputDecoration(
                  labelText: 'Correo @cessum.mx',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: rol,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _rolesValidos
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setSt(() => rol = v ?? rol),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                if (correo.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _accion({
      'accion': 'rol_asignar',
      'correo': correo.text.trim(),
      'rol': rol,
    }, 'Rol asignado.');
  }

  Future<void> _quitar(String correo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar rol'),
        content: Text('¿Quitar el rol de administración a $correo?',
            style: const TextStyle(fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _accion(
        {'accion': 'rol_quitar', 'correo': correo}, 'Rol quitado.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Roles de administración'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        onPressed: _asignar,
        icon: const Icon(Icons.person_add),
        label: const Text('Asignar rol'),
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
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: _roles.length,
                  itemBuilder: (c, i) => _fila(_roles[i]),
                ),
    );
  }

  Widget _fila(Map<String, dynamic> r) {
    final protegido = r['protegido'] == true;
    final correo = (r['correo'] ?? '').toString();
    final rol = (r['rol'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(protegido ? Icons.shield : Icons.person,
            color: protegido ? cessumGold : cessumRed),
        title: Text(correo,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
          'Rol: $rol${protegido ? ' · superadmin (no editable)' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: protegido
            ? null
            : IconButton(
                onPressed: () => _quitar(correo),
                icon: const Icon(Icons.delete_outline, color: cessumRed),
                tooltip: 'Quitar rol',
              ),
      ),
    );
  }
}

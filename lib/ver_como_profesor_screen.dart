import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'active_profile.dart';
import 'teacher_profile.dart';
import 'teacher_menu_screen.dart';
import 'auth/session_store.dart';

/// Pantalla SOLO para administradores: elige un profesor REAL y entra al
/// portal docente viendo EXACTAMENTE lo que él ve (sus grupos, materias,
/// captura, riesgo, etc.). No toca las cuentas reales; solo activa el modo
/// "Ver como profesor". Para salir, usa el botón "Salir" del banco superior.
class VerComoProfesorScreen extends StatefulWidget {
  const VerComoProfesorScreen({super.key});

  @override
  State<VerComoProfesorScreen> createState() => _VerComoProfesorScreenState();
}

class _VerComoProfesorScreenState extends State<VerComoProfesorScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _docentes = [];
  String _filtro = '';

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
          .get(Uri.parse('$guardianUrl?accion=directorio_docentes'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      if (!mounted) return;
      setState(() {
        _docentes = ((data['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la lista de docentes.';
      });
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_filtro.trim().isEmpty) return _docentes;
    final q = _filtro.toLowerCase();
    return _docentes.where((d) {
      final n = (d['docente'] ?? '').toString().toLowerCase();
      final c = (d['correo'] ?? '').toString().toLowerCase();
      return n.contains(q) || c.contains(q);
    }).toList();
  }

  /// Construye el perfil de docente a partir del nombre del directorio,
  /// separando el título académico si el nombre lo trae al inicio.
  TeacherProfile _perfilDesdeNombre(String nombre) {
    final limpio = nombre.trim();
    for (final t in titulosAcademicos) {
      if (limpio.toLowerCase().startsWith('${t.toLowerCase()} ')) {
        return TeacherProfile(
          titulo: t,
          nombreCompleto: limpio.substring(t.length).trim(),
        );
      }
    }
    return TeacherProfile(
      titulo: 'Profe.',
      nombreCompleto: limpio.isEmpty ? 'Docente' : limpio,
    );
  }

  Future<void> _verComo(Map<String, dynamic> d) async {
    final correo = (d['correo'] ?? '').toString().trim();
    final nombre = (d['docente'] ?? '').toString().trim();

    if (correo.isEmpty || correo == '(sin correo)') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Este docente no tiene correo registrado; no se puede previsualizar su vista.'),
        backgroundColor: cessumRed,
      ));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ver como este profesor'),
        content: Text(
          'Vas a entrar al portal docente viendo EXACTAMENTE lo que ve:\n\n'
          '${nombre.isEmpty ? correo : nombre}\n$correo\n\n'
          'No modificas nada de su cuenta. Para volver a tu vista de '
          'administrador, usa el botón "Salir" de la franja superior.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ver como él'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final perfil = _perfilDesdeNombre(nombre);
    await perfil.save();
    await ActiveProfile.setActive(ProfileType.teacher);
    await SessionStore.startImpersonation(correo, nombre: perfil.saludoCompleto);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TeacherMenuScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Ver como un profesor',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
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
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: cessumGold.withValues(alpha: 0.12),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text(
                        'Elige un docente para entrar a su portal y ver tal cual '
                        'lo que él ve. No cambias nada de su cuenta.',
                        style: TextStyle(fontSize: 12.5, color: cessumInk(context)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: TextField(
                        onChanged: (v) => setState(() => _filtro = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar docente por nombre o correo',
                          isDense: true,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('${lista.length} docente(s)',
                            style: TextStyle(
                                fontSize: 12, color: cessumMuted(context))),
                      ),
                    ),
                    Expanded(
                      child: lista.isEmpty
                          ? Center(
                              child: Text('Sin coincidencias.',
                                  style: TextStyle(color: cessumMuted(context))))
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 6, 12, 24),
                              itemCount: lista.length,
                              itemBuilder: (ctx, i) => _tarjeta(lista[i]),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> d) {
    final nombre = (d['docente'] ?? '').toString();
    final correo = (d['correo'] ?? '').toString();
    final materias = (d['materias'] as List?) ?? [];
    final sinCorreo = correo.isEmpty || correo == '(sin correo)';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: sinCorreo ? null : () => _verComo(d),
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.person, color: cessumRed, size: 22),
        ),
        title: Text(nombre.isEmpty ? '(sin nombre)' : nombre,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(sinCorreo ? 'Sin correo registrado' : correo,
                style: TextStyle(
                    fontSize: 11.5,
                    color: sinCorreo ? cessumRed : cessumMuted(context))),
            const SizedBox(height: 2),
            Text('${materias.length} materia(s)',
                style: const TextStyle(
                    fontSize: 11.5,
                    color: cessumGold,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        trailing: sinCorreo
            ? Icon(Icons.block, color: cessumFaint(context), size: 20)
            : const Icon(Icons.login, color: cessumRed, size: 20),
      ),
    );
  }
}

// Pantalla de administrador: "Profesores (padrón en vivo)".
//
// Permite agregar, editar o dar de baja profesores SIN regenerar alumnos.json.
// Los cambios se reflejan al instante (el Guardián fusiona esta capa editable
// con la lista base, igual que con los alumnos).
//
// Acciones del Guardián:
//   POST profesores_listar -> {ok, profesores:[{correo,titulo,nombre}]}
//   POST profesor_guardar  -> {ok}
//   POST profesor_borrar   -> {ok}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class ProfesoresAdminScreen extends StatefulWidget {
  const ProfesoresAdminScreen({super.key});

  @override
  State<ProfesoresAdminScreen> createState() => _ProfesoresAdminScreenState();
}

class _ProfesoresAdminScreenState extends State<ProfesoresAdminScreen> {
  static const List<String> _titulos = [
    'Mtra.', 'Mtro.', 'Dr.', 'Dra.', 'Lic.', 'Ing.',
    'Profr.', 'Profra.', 'C.P.', 'Psic.',
  ];

  bool _cargando = true;
  bool _procesando = false;
  String _actor = '';
  List<Map<String, dynamic>> _profes = [];
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      _actor = (await SessionStore.realEmail()) ?? '';
      final r = await _post({'accion': 'profesores_listar', 'actor': _actor});
      if (r['ok'] == true && r['profesores'] is List) {
        _profes = (r['profesores'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _profes = [];
      }
    } catch (_) {
      _profes = [];
    }
    if (mounted) setState(() => _cargando = false);
  }

  List<Map<String, dynamic>> get _visibles {
    if (_filtro.trim().isEmpty) return _profes;
    final q = _filtro.toLowerCase();
    return _profes.where((p) {
      return '${p['nombre'] ?? ''}'.toLowerCase().contains(q) ||
          '${p['correo'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _editar({Map<String, dynamic>? prof}) async {
    final correoCtrl =
        TextEditingController(text: '${prof?['correo'] ?? ''}');
    final nombreCtrl =
        TextEditingController(text: '${prof?['nombre'] ?? ''}');
    final semblanzaCtrl =
        TextEditingController(text: '${prof?['semblanza'] ?? ''}');
    final curpCtrl =
        TextEditingController(text: '${prof?['curp'] ?? ''}');
    String escolaridad = '${prof?['escolaridad'] ?? ''}';
    String titulo = '${prof?['titulo'] ?? 'Mtra.'}';
    if (!_titulos.contains(titulo)) titulo = 'Mtra.';
    final esNuevo = prof == null;
    // En alta se ofrece enviar el correo de bienvenida.
    bool bienvenida = esNuevo;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(esNuevo ? 'Agregar profesor' : 'Editar profesor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: titulo,
                  decoration: const InputDecoration(
                      labelText: 'Título', border: OutlineInputBorder()),
                  items: _titulos
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => titulo = v ?? 'Mtra.'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: correoCtrl,
                  enabled: esNuevo, // el correo es la llave, no se cambia
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Correo (@cessum.mx)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: semblanzaCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Semblanza (para cartas y portadas)',
                      hintText: 'Breve reseña profesional del docente',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                // CURP y escolaridad: obligatorios para el exportable SIGA.
                TextField(
                  controller: curpCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      labelText: 'CURP (para SIGA)',
                      hintText: '18 caracteres',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: escolaridad.isEmpty ? null : escolaridad,
                  decoration: const InputDecoration(
                      labelText: 'Escolaridad (para SIGA)',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '1', child: Text('Licenciatura')),
                    DropdownMenuItem(value: '2', child: Text('Maestría')),
                    DropdownMenuItem(value: '3', child: Text('Doctorado')),
                    DropdownMenuItem(value: '4', child: Text('Otro')),
                  ],
                  onChanged: (v) => setLocal(() => escolaridad = v ?? ''),
                ),
                if (esNuevo) ...[
                  const SizedBox(height: 4),
                  StatefulBuilder(
                    builder: (ctx2, setB) => CheckboxListTile(
                      value: bienvenida,
                      onChanged: (v) => setB(() => bienvenida = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Enviar correo de bienvenida',
                          style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final correo = correoCtrl.text.trim().toLowerCase();
    final nombre = nombreCtrl.text.trim();
    if (correo.isEmpty || !correo.endsWith('@cessum.mx')) {
      _aviso('El correo debe terminar en @cessum.mx', error: true);
      return;
    }
    if (nombre.isEmpty) {
      _aviso('Escribe el nombre.', error: true);
      return;
    }

    setState(() => _procesando = true);
    try {
      // docente_alta escribe en la hoja Docentes (con semblanza, la que usan
      // cartas/portadas) Y hace espejo en ProfesoresOverrides, así una sola
      // pantalla mantiene ambas bases consistentes.
      final r = await _post({
        'accion': 'docente_alta',
        'actor': _actor,
        'correo': correo,
        'titulo': titulo,
        'nombre': nombre,
        'semblanza': semblanzaCtrl.text.trim(),
        'curp': curpCtrl.text.trim().toUpperCase(),
        'escolaridad': escolaridad,
        'bienvenida': (esNuevo && bienvenida) ? '1' : '0',
      });
      if (r['ok'] == true) {
        _aviso(esNuevo ? 'Profesor agregado.' : 'Profesor actualizado.');
        await _cargar();
      } else {
        _aviso('${r['error'] ?? 'No se pudo guardar.'}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
    if (mounted) setState(() => _procesando = false);
  }

  Future<void> _baja(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Dar de baja'),
        content: Text(
            '${p['nombre']} dejará de aparecer en la app. Puedes volver a '
            'agregarlo después. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Dar de baja')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final r = await _post({
        'accion': 'profesor_borrar',
        'actor': _actor,
        'correo': '${p['correo'] ?? ''}',
        'titulo': '${p['titulo'] ?? ''}',
        'nombre': '${p['nombre'] ?? ''}',
      });
      if (r['ok'] == true) {
        _aviso('Profesor dado de baja.');
        await _cargar();
      } else {
        _aviso('${r['error'] ?? 'No se pudo.'}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
    if (mounted) setState(() => _procesando = false);
  }

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : cessumGold,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lista = _visibles;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profesores'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _procesando ? null : () => _editar(),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Agregar'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o correo',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (v) => setState(() => _filtro = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Text('${lista.length} profesor(es)',
                              style: TextStyle(
                                  fontSize: 12, color: cessumMuted(context))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: lista.isEmpty
                          ? Center(
                              child: Text('Sin profesores.',
                                  style:
                                      TextStyle(color: cessumMuted(context))))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                              itemCount: lista.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _tarjeta(lista[i]),
                            ),
                    ),
                  ],
                ),
                if (_procesando)
                  Container(
                    color: cessumMuted(context).withValues(alpha: 0.18),
                    child: const Center(
                        child:
                            CircularProgressIndicator(color: cessumRed)),
                  ),
              ],
            ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final titulo = '${p['titulo'] ?? ''}'.trim();
    final nombre = '${p['nombre'] ?? ''}'.trim();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: cessumRed.withValues(alpha: 0.12),
            child: const Icon(Icons.school_outlined, color: cessumRed, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${titulo.isEmpty ? '' : '$titulo '}$nombre',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cessumIsDark(context)
                          ? Colors.white
                          : cessumInk(context)),
                ),
                const SizedBox(height: 2),
                Text('${p['correo'] ?? ''}',
                    style:
                        TextStyle(fontSize: 12, color: cessumMuted(context))),
                const SizedBox(height: 4),
                // Indicador SIGA: CURP capturada o pendiente.
                Row(
                  children: [
                    Icon(
                      (p['curp'] ?? '').toString().length == 18
                          ? Icons.check_circle
                          : Icons.error_outline,
                      size: 13,
                      color: (p['curp'] ?? '').toString().length == 18
                          ? const Color(0xFF1E8E3E)
                          : cessumGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      (p['curp'] ?? '').toString().length == 18
                          ? 'CURP para SIGA ✓'
                          : 'Falta CURP para SIGA',
                      style: TextStyle(
                        fontSize: 11,
                        color: (p['curp'] ?? '').toString().length == 18
                            ? const Color(0xFF1E8E3E)
                            : cessumGold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: _procesando ? null : () => _editar(prof: p),
            icon: const Icon(Icons.edit_outlined, color: cessumGold, size: 20),
          ),
          IconButton(
            tooltip: 'Dar de baja',
            onPressed: _procesando ? null : () => _baja(p),
            icon: const Icon(Icons.person_off_outlined,
                color: cessumRed, size: 20),
          ),
        ],
      ),
    );
  }
}

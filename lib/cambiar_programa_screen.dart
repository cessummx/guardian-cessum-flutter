// Pantalla de administrador: "Cambiar de programa o generación".
//
// En UN solo lugar: busca al alumno por matrícula, muestra su situación actual,
// y con un botón mueve las DOS capas a la vez:
//   - la base de grupos (para que materias, actas y calificaciones se muevan)
//   - el padrón (la etiqueta y el login)
//
// Acciones del Guardián:
//   POST grupos_admin_buscar -> {ok, grupos:[{fila,programa,generacion,matricula,nombre,correo,grupo}]}
//   POST alumno_mover        -> {ok, filas}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class CambiarProgramaScreen extends StatefulWidget {
  final String? matriculaInicial;
  const CambiarProgramaScreen({super.key, this.matriculaInicial});

  @override
  State<CambiarProgramaScreen> createState() => _CambiarProgramaScreenState();
}

class _CambiarProgramaScreenState extends State<CambiarProgramaScreen> {
  final _matricula = TextEditingController();
  final _generacion = TextEditingController();

  static const List<String> _gruposBase = [
    '1 - entre semana',
    '2 - sabatino',
    '1 - mixta',
  ];

  bool _buscando = false;
  bool _aplicando = false;
  String _actor = '';

  // Resultado de la búsqueda.
  List<Map<String, dynamic>> _filas = [];
  int _filaSel = -1; // índice dentro de _filas
  List<Map<String, dynamic>> _todos = []; // todas las filas devueltas
  List<Map<String, dynamic>> _alumnos = []; // alumnos distintos (matrícula+nombre)

  // Valores nuevos elegidos.
  String? _programa;
  String? _grupo;
  String? _modalidad;

  // Generaciones disponibles (para el desplegable).
  List<String> _generaciones = [];
  bool _otraGeneracion = false;

  Future<void> _cargarGeneraciones() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'generaciones_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['generaciones'] is List) {
        setState(() => _generaciones =
            (data['generaciones'] as List).map((e) => '$e').toList());
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _cargarGeneraciones();
    final mi = widget.matriculaInicial;
    if (mi != null && mi.trim().isNotEmpty) {
      _matricula.text = mi.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) => _buscar());
    }
  }

  @override
  void dispose() {
    _matricula.dispose();
    _generacion.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _buscar() async {
    final q = _matricula.text.trim();
    if (q.isEmpty) {
      _aviso('Escribe una matrícula o un nombre.', error: true);
      return;
    }
    setState(() {
      _buscando = true;
      _filas = [];
      _filaSel = -1;
      _todos = [];
      _alumnos = [];
    });
    try {
      _actor = (await SessionStore.realEmail()) ?? '';
      final r = await _post({
        'accion': 'grupos_admin_buscar',
        'q': q,
        'actor': _actor,
      });
      final lista = (r['grupos'] is List) ? r['grupos'] as List : [];
      _todos = lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Alumnos distintos por matrícula (la búsqueda puede traer varios).
      final vistos = <String>{};
      final als = <Map<String, dynamic>>[];
      for (final e in _todos) {
        final m = '${e['matricula'] ?? ''}'.trim();
        if (m.isEmpty || vistos.contains(m)) continue;
        vistos.add(m);
        als.add({'matricula': m, 'nombre': '${e['nombre'] ?? ''}'.trim()});
      }
      als.sort((a, b) =>
          '${a['nombre']}'.toLowerCase().compareTo('${b['nombre']}'.toLowerCase()));
      _alumnos = als;

      if (als.isEmpty) {
        _aviso('No encontré a nadie con ese nombre o matrícula.', error: true);
      } else if (als.length == 1) {
        _elegirAlumno(als.first['matricula'] as String);
      }
      // Si hay varios, el selector de alumno se muestra en pantalla.
    } catch (e) {
      _aviso('No se pudo buscar: $e', error: true);
    }
    if (mounted) setState(() => _buscando = false);
  }

  // Fija las filas (grupos) del alumno elegido y preselecciona la primera.
  void _elegirAlumno(String mat) {
    _filas =
        _todos.where((e) => '${e['matricula'] ?? ''}'.trim() == mat).toList();
    _filaSel = -1;
    if (_filas.isNotEmpty) _seleccionar(0);
    setState(() {});
  }

  // Al elegir una fila, precarga los valores actuales.
  void _seleccionar(int i) {
    _filaSel = i;
    final f = _filas[i];
    final prog = '${f['programa'] ?? ''}'.trim();
    _programa = _opcionesPrograma().contains(prog) ? prog : null;
    _generacion.text = '${f['generacion'] ?? ''}'.trim();
    _otraGeneracion = false;
    final g = '${f['grupo'] ?? ''}'.trim();
    _grupo = _opcionesGrupo().contains(g) ? g : null;
    setState(() {});
  }

  List<String> _opcionesPrograma() {
    final base = programasAcademicos.map((p) => p.nombre).toList();
    // Incluir el programa actual aunque no esté en la lista canónica.
    if (_filaSel >= 0) {
      final actual = '${_filas[_filaSel]['programa'] ?? ''}'.trim();
      if (actual.isNotEmpty && !base.contains(actual)) base.insert(0, actual);
    }
    return base;
  }

  List<String> _opcionesGrupo() {
    final base = List<String>.from(_gruposBase);
    if (_filaSel >= 0) {
      final actual = '${_filas[_filaSel]['grupo'] ?? ''}'.trim();
      if (actual.isNotEmpty && !base.contains(actual)) base.insert(0, actual);
    }
    return base;
  }

  List<String> _opcionesGeneracion() {
    final base = List<String>.from(_generaciones);
    final actual = _generacion.text.trim();
    if (actual.isNotEmpty && !base.contains(actual)) base.insert(0, actual);
    return base;
  }

  Future<void> _aplicar() async {
    if (_filaSel < 0) {
      _aviso('Primero busca y selecciona al alumno.', error: true);
      return;
    }
    if ((_programa ?? '').isEmpty) {
      _aviso('Elige el programa.', error: true);
      return;
    }
    if (_generacion.text.trim().isEmpty) {
      _aviso('Escribe la generación (ej. 26-1).', error: true);
      return;
    }
    if ((_grupo ?? '').isEmpty) {
      _aviso('Elige el grupo.', error: true);
      return;
    }

    final f = _filas[_filaSel];
    final resumen =
        '${_programa} · ${_generacion.text.trim()} · ${_grupo}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar cambio'),
        content: Text(
            '${f['nombre'] ?? f['matricula']} quedará en:\n\n$resumen\n\n'
            'Esto mueve sus materias y actas al nuevo programa, y actualiza '
            'su padrón. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Aplicar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _aplicando = true);
    try {
      final r = await _post({
        'accion': 'alumno_mover',
        'actor': _actor,
        'matricula': '${f['matricula']}'.trim(),
        'fila': f['fila'],
        'programa': _programa,
        'generacion': _generacion.text.trim(),
        'grupo': _grupo,
        'nombre': '${f['nombre'] ?? ''}'.trim(),
        'correo': '${f['correo'] ?? ''}'.trim().toLowerCase(),
        'modalidad': _modalidad ?? '',
      });
      if (r['ok'] == true) {
        _aviso('Listo. El cambio quedó aplicado.');
        // Refresca la vista con los nuevos valores.
        await _buscar();
      } else {
        _aviso('${r['error'] ?? 'No se pudo aplicar.'}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
    if (mounted) setState(() => _aplicando = false);
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
    final hayAlumno = _filaSel >= 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cambiar de programa o generación'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _info(),
          const SizedBox(height: 16),

          // Paso 1: buscar
          _titulo('1. Busca al alumno', Icons.search),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _matricula,
                  decoration: _dec('Matrícula o nombre'),
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _buscar(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _buscando ? null : _buscar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                  ),
                  child: _buscando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Buscar'),
                ),
              ),
            ],
          ),

          // Si la búsqueda trajo varios alumnos, elegir cuál
          if (_alumnos.length > 1) ...[
            const SizedBox(height: 14),
            Text('Se encontraron ${_alumnos.length} alumnos. Elige uno:',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
            const SizedBox(height: 6),
            ..._alumnos.map((a) {
              final m = '${a['matricula']}';
              final sel = _filas.isNotEmpty &&
                  '${_filas.first['matricula'] ?? ''}'.trim() == m;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                      sel ? Icons.check_circle : Icons.person_outline,
                      color: sel ? cessumRed : cessumFaint(context)),
                  title: Text('${a['nombre']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('Matrícula: $m',
                      style: TextStyle(
                          fontSize: 12, color: cessumMuted(context))),
                  onTap: () => _elegirAlumno(m),
                ),
              );
            }),
          ],

          // Si hay varias filas, elegir cuál
          if (_filas.length > 1) ...[
            const SizedBox(height: 14),
            Text('Este alumno tiene varios registros. Elige cuál cambiar:',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
            const SizedBox(height: 6),
            ..._filas.asMap().entries.map((e) => RadioListTile<int>(
                  value: e.key,
                  groupValue: _filaSel,
                  activeColor: cessumRed,
                  dense: true,
                  title: Text(
                    '${e.value['programa']} · ${e.value['generacion']} · ${e.value['grupo']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  onChanged: (v) => _seleccionar(v ?? 0),
                )),
          ],

          if (hayAlumno) ...[
            const SizedBox(height: 16),
            _tarjetaActual(),
            const SizedBox(height: 20),

            // Paso 2: nuevos valores
            _titulo('2. Nuevo programa / generación', Icons.swap_horiz),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _programa,
              isExpanded: true,
              decoration: _dec('Programa'),
              items: _opcionesPrograma()
                  .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _programa = v),
            ),
            const SizedBox(height: 12),
            if (!_otraGeneracion)
              DropdownButtonFormField<String>(
                initialValue:
                    _opcionesGeneracion().contains(_generacion.text.trim())
                        ? _generacion.text.trim()
                        : null,
                isExpanded: true,
                decoration: _dec('Generación'),
                items: [
                  ..._opcionesGeneracion().map((g) =>
                      DropdownMenuItem(value: g, child: Text(g))),
                  const DropdownMenuItem(
                      value: '__otra__', child: Text('➕ Otra…')),
                ],
                onChanged: (v) {
                  if (v == '__otra__') {
                    setState(() {
                      _otraGeneracion = true;
                      _generacion.clear();
                    });
                  } else {
                    setState(() => _generacion.text = v ?? '');
                  }
                },
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _generacion,
                      decoration: _dec('Generación nueva (ej. 26-2)'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Elegir de la lista',
                    onPressed: () => setState(() => _otraGeneracion = false),
                    icon: const Icon(Icons.list, color: cessumRed),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _grupo,
              isExpanded: true,
              decoration: _dec('Grupo'),
              items: _opcionesGrupo()
                  .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                  .toList(),
              onChanged: (v) => setState(() => _grupo = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _modalidad,
              isExpanded: true,
              decoration: _dec('Modalidad (opcional)'),
              items: modalidadesEstudio
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _modalidad = v),
            ),

            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _aplicando ? null : _aplicar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _aplicando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Aplicar cambio'),
              ),
            ),
          ],
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _info() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cessumRed.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: cessumRed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Un solo paso: busca al alumno, elige su nuevo programa, '
                'generación y grupo, y aplica. Se mueve todo (materias, actas y '
                'padrón) al instante.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.35, color: cessumMuted(context)),
              ),
            ),
          ],
        ),
      );

  Widget _tarjetaActual() {
    final f = _filas[_filaSel];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${f['nombre'] ?? ''}',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cessumIsDark(context) ? Colors.white : Colors.black87)),
          const SizedBox(height: 2),
          Text('Matrícula ${f['matricula'] ?? ''}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 8),
          Text('Actualmente:',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          Text(
            '${f['programa']} · ${f['generacion']} · ${f['grupo']}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cessumIsDark(context) ? Colors.white : Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _titulo(String t, IconData ic) => Row(
        children: [
          Icon(ic, size: 18, color: cessumRed),
          const SizedBox(width: 8),
          Text(t,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cessumIsDark(context) ? Colors.white : Colors.black87)),
        ],
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: cessumRed, width: 1.6),
        ),
      );
}

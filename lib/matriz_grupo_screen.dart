// matriz_grupo_screen.dart
// Concentrado de calificaciones por grupo (alumnos x materias), EDITABLE.
// Trae su PROPIO selector de grupo (programa -> generacion -> grupo), así que
// se abre desde un solo botón de menú, sin depender de otras pantallas.
//
// - Catálogo: GET  grupos                  -> { ok, catalogo:[{programa, generaciones:[{generacion, grupos:[]}]}] }
// - Matriz:   GET  matriz_grupo?programa=&generacion=&grupo=
// - Guardar:  POST calificaciones_grupo_guardar   (escribe en la base real)
//
// Uso (un botón en el menú):
//   import 'matriz_grupo_screen.dart';
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const MatrizGrupoScreen()));
// O preseleccionando un grupo:
//   MatrizGrupoScreen(programa: prog, generacion: gen, grupo: gru)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth/session_store.dart';
import 'cessum_ui.dart'; // (24-sep) colores del tema (modo oscuro)

class MatrizGrupoScreen extends StatefulWidget {
  final String? programa;
  final String? generacion;
  final String? grupo;
  const MatrizGrupoScreen({
    super.key,
    this.programa,
    this.generacion,
    this.grupo,
  });

  @override
  State<MatrizGrupoScreen> createState() => _MatrizGrupoScreenState();
}

class _MatrizGrupoScreenState extends State<MatrizGrupoScreen> {
  static const String _guardianUrl = 'https://app.cessum.mx/guardian.php';
  static const Color _rojo = Color(0xFFB11D29);
  static const Color _hueso = Color(0xFFF5F1E8);
  static const Color _oro = Color(0xFFA56B16);
  // Palabra de la fila agrupadora. 'Ciclo' sirve igual para programas
  // trimestrales y semestrales (queda 'Ciclo 1', 'Ciclo 2', ...).
  static const String _palabraPeriodo = 'Ciclo';

  // catálogo
  bool _cargandoCat = true;
  String _errorCat = '';
  // catalogo: programa -> { generacion -> [grupos] }
  final Map<String, Map<String, List<String>>> _cat = {};

  String? _programa;
  String? _generacion;
  String? _grupo;

  // matriz
  bool _cargando = false;
  String _error = '';
  List<Map<String, dynamic>> _materias = [];
  List<Map<String, dynamic>> _alumnos = [];

  @override
  void initState() {
    super.initState();
    _programa = widget.programa;
    _generacion = widget.generacion;
    _grupo = widget.grupo;
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    setState(() {
      _cargandoCat = true;
      _errorCat = '';
    });
    try {
      final resp = await http.get(Uri.parse('$_guardianUrl?accion=grupos'));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) {
        throw Exception(j['error'] ?? 'Catálogo no disponible.');
      }
      _cat.clear();
      for (final p in ((j['catalogo'] as List?) ?? [])) {
        final pm = Map<String, dynamic>.from(p as Map);
        final prog = '${pm['programa']}';
        final gens = <String, List<String>>{};
        for (final g in ((pm['generaciones'] as List?) ?? [])) {
          final gm = Map<String, dynamic>.from(g as Map);
          final gen = '${gm['generacion']}';
          final grupos =
              ((gm['grupos'] as List?) ?? []).map((e) => '$e').toList();
          gens[gen] = grupos;
        }
        _cat[prog] = gens;
      }
      if (!mounted) return;
      setState(() => _cargandoCat = false);
      if (_programa != null && _generacion != null && _grupo != null) {
        _cargarMatriz();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoCat = false;
        _errorCat = 'No se pudo cargar la lista de grupos.';
      });
    }
  }

  List<String> get _generaciones =>
      (_programa != null && _cat[_programa] != null)
          ? _cat[_programa]!.keys.toList()
          : [];

  List<String> get _grupos => (_programa != null &&
          _generacion != null &&
          _cat[_programa]?[_generacion] != null)
      ? _cat[_programa]![_generacion]!
      : [];

  Future<void> _cargarMatriz() async {
    if (_programa == null || _generacion == null || _grupo == null) return;
    setState(() {
      _cargando = true;
      _error = '';
      _materias = [];
      _alumnos = [];
    });
    try {
      final url = '$_guardianUrl?accion=matriz_grupo'
          '&programa=${Uri.encodeComponent(_programa!)}'
          '&generacion=${Uri.encodeComponent(_generacion!)}'
          '&grupo=${Uri.encodeComponent(_grupo!)}';
      final resp = await http.get(Uri.parse(url));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo cargar.');
      final mats = ((j['materias'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final als = ((j['alumnos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _materias = mats;
        _alumnos = als;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'Error: $e';
      });
    }
  }

  int _faltantesMateria(String key) {
    var n = 0;
    for (final a in _alumnos) {
      final celdas = Map<String, dynamic>.from(a['celdas'] ?? {});
      if ('${celdas[key] ?? ''}'.trim().isEmpty) n++;
    }
    return n;
  }

  Future<void> _editarCelda(
      Map<String, dynamic> alumno, Map<String, dynamic> materia) async {
    final celdas = Map<String, dynamic>.from(alumno['celdas'] ?? {});
    final key = '${materia['key']}';
    final ctrl = TextEditingController(text: '${celdas[key] ?? ''}'.trim());
    final nueva = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${materia['materia']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${alumno['nombre']}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('Matrícula: ${alumno['matricula']}',
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Calificación',
                hintText: 'Ej. 9  o  10',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _rojo, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nueva == null) return;
    await _guardar(alumno, materia, nueva);
  }

  Future<void> _guardar(Map<String, dynamic> alumno,
      Map<String, dynamic> materia, String valor) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: _rojo)),
    );
    try {
      final payload = <String, dynamic>{
        'accion': 'calificaciones_grupo_guardar',
        'programa': _programa,
        'generacion': _generacion,
        'grupo': _grupo,
        'materia': '${materia['materia']}',
        'claveMateria': '${materia['clave'] ?? ''}',
        'alumnos': [
          {
            'matricula': '${alumno['matricula']}',
            'nombre': '${alumno['nombre']}',
            'calificacion': valor,
          }
        ],
      };
      final resp = await http.post(
        Uri.parse(_guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode(payload),
      );
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (mounted) Navigator.pop(context);
      if (j['ok'] == true) {
        final celdas = Map<String, dynamic>.from(alumno['celdas'] ?? {});
        celdas['${materia['key']}'] = valor;
        setState(() => alumno['celdas'] = celdas);
        _snack('Calificación guardada en la base.', ok: true);
      } else {
        _snack('${j['error'] ?? 'No se pudo guardar.'}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Error de conexión al guardar.');
    }
  }

  Future<void> _revisarDuplicados() async {
    if (_programa == null || _generacion == null || _grupo == null) return;
    final actor = (await SessionStore.validEmail()) ?? '';
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: _rojo)),
    );
    try {
      final url = '$_guardianUrl?accion=salud_calif_preview'
          '&actor=${Uri.encodeComponent(actor)}'
          '&programa=${Uri.encodeComponent(_programa!)}'
          '&generacion=${Uri.encodeComponent(_generacion!)}'
          '&grupo=${Uri.encodeComponent(_grupo!)}';
      final resp = await http.get(Uri.parse(url));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (mounted) Navigator.pop(context);
      if (j['ok'] != true) {
        _snack('${j['error'] ?? 'No se pudo revisar.'}');
        return;
      }
      final dups = (j['duplicados'] as List?) ?? [];
      final totalFilas = (j['totalFilasBorrar'] ?? 0) as int;
      if (!mounted) return;
      _mostrarDialogoDuplicados(dups, totalFilas);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Error de conexión al revisar.');
    }
  }

  void _mostrarDialogoDuplicados(List dups, int totalFilas) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.healing, color: _rojo),
            SizedBox(width: 8),
            Text('Salud de datos'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: totalFilas == 0
              ? const Text(
                  'No se encontraron registros duplicados en este grupo. '
                  'Todo está limpio.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Se encontraron $totalFilas registro(s) duplicado(s) '
                      'en ${dups.length} caso(s).',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Se conservará el registro con calificación (o el más '
                      'reciente) y se eliminarán los sobrantes. Se hará un '
                      'respaldo automático antes de borrar.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: dups.map<Widget>((dRaw) {
                            final d = Map<String, dynamic>.from(dRaw as Map);
                            final cons =
                                Map<String, dynamic>.from(d['conservar'] ?? {});
                            final borrar = (d['borrar'] as List?) ?? [];
                            final consCal = '${cons['calificacion'] ?? '—'}';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${d['nombre']} · ${d['materia']}',
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Conserva: $consCal   ·   Elimina: '
                                    '${borrar.length} registro(s)',
                                    style: TextStyle(
                                        fontSize: 12, color: cessumMuted(context)),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          if (totalFilas > 0)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _rojo, foregroundColor: Colors.white),
              icon: const Icon(Icons.delete_sweep, size: 18),
              label: const Text('Limpiar duplicados'),
              onPressed: () {
                Navigator.pop(ctx);
                _confirmarLimpieza(totalFilas);
              },
            ),
        ],
      ),
    );
  }

  void _confirmarLimpieza(int totalFilas) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar limpieza'),
        content: Text(
          'Se eliminarán $totalFilas registro(s) duplicado(s) de la base. '
          'Se guardará un respaldo automático antes de borrar. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _rojo, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _limpiarDuplicados();
            },
            child: const Text('Sí, limpiar'),
          ),
        ],
      ),
    );
  }

  Future<void> _limpiarDuplicados() async {
    final actor = (await SessionStore.validEmail()) ?? '';
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: _rojo)),
    );
    try {
      final payload = <String, dynamic>{
        'accion': 'salud_calif_limpiar',
        'actor': actor,
        'programa': _programa,
        'generacion': _generacion,
        'grupo': _grupo,
        'confirmar': true,
      };
      final resp = await http.post(
        Uri.parse(_guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode(payload),
      );
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (mounted) Navigator.pop(context);
      if (j['ok'] == true) {
        final n = j['borradas'] ?? 0;
        _snack('Listo: $n duplicado(s) eliminado(s). Respaldo: '
            '${j['respaldo'] ?? ''}', ok: true);
        _cargarMatriz();
      } else {
        _snack('${j['error'] ?? 'No se pudo limpiar.'}');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Error de conexión al limpiar.');
    }
  }

  void _snack(String t, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t),
        backgroundColor: ok ? const Color(0xFF1E8E3E) : _rojo));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context), // (24-sep) modo oscuro
      appBar: AppBar(
        backgroundColor: _rojo,
        foregroundColor: Colors.white,
        title: const Text('Concentrado por grupo'),
        actions: [
          if (_grupo != null)
            IconButton(
              tooltip: 'Salud de datos (duplicados)',
              icon: const Icon(Icons.healing),
              onPressed: _cargando ? null : _revisarDuplicados,
            ),
          if (_grupo != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _cargando ? null : _cargarMatriz,
            ),
        ],
      ),
      body: _cargandoCat
          ? const Center(child: CircularProgressIndicator(color: _rojo))
          : _errorCat.isNotEmpty
              ? _errBox(_errorCat, _cargarCatalogo)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _selector(),
                    const Divider(height: 1),
                    Expanded(child: _cuerpo()),
                  ],
                ),
    );
  }

  Widget _selector() {
    return Container(
      color: Theme.of(context).cardColor, // (24-sep) modo oscuro
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        children: [
          _dd('Programa', _programa, _cat.keys.toList(), (v) {
            setState(() {
              _programa = v;
              _generacion = null;
              _grupo = null;
              _materias = [];
              _alumnos = [];
            });
          }),
          const SizedBox(height: 8),
          _dd('Generación', _generacion, _generaciones,
              _programa == null ? null : (v) {
            setState(() {
              _generacion = v;
              _grupo = null;
              _materias = [];
              _alumnos = [];
            });
          }),
          const SizedBox(height: 8),
          _dd('Grupo', _grupo, _grupos, _generacion == null ? null : (v) {
            setState(() => _grupo = v);
            _cargarMatriz();
          }),
        ],
      ),
    );
  }

  Widget _dd(String label, String? val, List<String> ops,
      void Function(String?)? onCh) {
    return DropdownButtonFormField<String>(
      value: val,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items:
          ops.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
      onChanged: onCh,
    );
  }

  Widget _cuerpo() {
    if (_grupo == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Elige programa, generación y grupo para ver la matriz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context))),
        ),
      );
    }
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: _rojo));
    }
    if (_error.isNotEmpty) return _errBox(_error, _cargarMatriz);
    if (_alumnos.isEmpty) {
      return const Center(child: Text('No hay alumnos en este grupo.'));
    }
    if (_materias.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aún no hay materias con calificaciones capturadas para este grupo.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Text(
            'Toca una celda para editar. En rojo = sin calificación.',
            style: TextStyle(fontSize: 12, color: cessumMuted(context)),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _tabla(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errBox(String msg, VoidCallback retry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _rojo)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _rojo, foregroundColor: Colors.white),
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabla() {
    const double wName = 200;
    const double wCel = 110;

    Widget headCell(String txt, double w, {int faltan = -1}) => Container(
          width: w,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: _rojo,
            border: Border.all(color: Colors.white, width: 0.5),
          ),
          child: Column(
            children: [
              Text(txt,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              if (faltan >= 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    faltan == 0 ? 'completa' : 'faltan $faltan',
                    style: TextStyle(
                        fontSize: 9,
                        color: faltan == 0
                            ? const Color(0xFFBFE3C6)
                            : const Color(0xFFFFD9D9)),
                  ),
                ),
            ],
          ),
        );

    final filas = <TableRow>[];
    filas.add(TableRow(children: [
      headCell('Alumno', wName),
      ..._materias.map((m) => headCell(
            '${m['materia']}',
            wCel,
            faltan: _faltantesMateria('${m['key']}'),
          )),
    ]));

    for (var r = 0; r < _alumnos.length; r++) {
      final a = _alumnos[r];
      final celdas = Map<String, dynamic>.from(a['celdas'] ?? {});
      final bg = r.isEven ? Colors.white : _hueso;
      filas.add(TableRow(children: [
        Container(
          width: wName,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          color: bg,
          child: Text('${a['nombre']}',
              style: TextStyle(fontSize: 12, color: cessumInk(context))),
        ),
        ..._materias.map((m) {
          final key = '${m['key']}';
          final val = '${celdas[key] ?? ''}'.trim();
          final falta = val.isEmpty;
          return InkWell(
            onTap: () => _editarCelda(a, m),
            child: Container(
              width: wCel,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              color: falta ? const Color(0xFFFCE4E4) : bg,
              alignment: Alignment.center,
              child: Text(
                falta ? '—' : val,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: falta ? FontWeight.w400 : FontWeight.w700,
                  color: falta ? _rojo : cessumInk(context),
                ),
              ),
            ),
          );
        }),
      ]));
    }

    final tabla = Table(
      defaultColumnWidth: const FixedColumnWidth(wCel),
      columnWidths: const {0: FixedColumnWidth(wName)},
      border: TableBorder.all(color: const Color(0xFFE0DACB), width: 0.5),
      children: filas,
    );

    // Fila superior que agrupa las columnas por ciclo. El backend ya entrega
    // las materias ordenadas por ciclo, así que los grupos quedan contiguos.
    // (Table no soporta colspan; por eso esta fila va como Row de anchos fijos
    //  y se alinea con la tabla porque las columnas son de ancho fijo.)
    final grupos = <Map<String, dynamic>>[];
    for (final m in _materias) {
      final ciclo = '${m['ciclo'] ?? ''}'.trim();
      if (grupos.isNotEmpty && grupos.last['ciclo'] == ciclo) {
        grupos.last['count'] = (grupos.last['count'] as int) + 1;
      } else {
        grupos.add({'ciclo': ciclo, 'count': 1});
      }
    }

    String etiqueta(String ciclo) {
      if (ciclo.isEmpty) return 'Sin ciclo';
      return int.tryParse(ciclo) != null
          ? '$_palabraPeriodo $ciclo'
          : ciclo;
    }

    Widget celdaGrupo(double w, String txt) => Container(
          width: w,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _oro,
            border: Border.all(color: Colors.white, width: 0.5),
          ),
          child: Text(
            txt,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        );

    final filaGrupos = Row(
      children: [
        Container(
          width: wName,
          height: 30,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _oro,
            border: Border.all(color: Colors.white, width: 0.5),
          ),
          child: const Text('Periodo',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        ...grupos.map((g) =>
            celdaGrupo(wCel * (g['count'] as int), etiqueta('${g['ciclo']}'))),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [filaGrupos, tabla],
    );
  }
}

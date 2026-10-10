import 'dart:convert';
import 'dart:html' as html; // descarga de CSV (la app es Flutter web)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'helpers.dart';
import 'selector_buscable.dart'; // (24-sep) selectores largos con búsqueda

/// Pantalla SOLO para administradores: revisar TODOS los grupos y sus
/// integrantes, clasificados por tipo (sabatino, entre semana, mixto,
/// virtual...), y armarlos/corregirlos a mano. Todo escribe en la base de
/// grupos del Guardián (la que usan captura y "mis grupos").
///
/// Funciones:
/// - Cruza con la clasificación de alumnos: los de estatus "Baja" se
///   OCULTAN del catálogo, y desde aquí se da de baja o se reactiva.
/// - El programa se elige de una lista oficial (ya no texto libre).
/// - "Corregir programa del grupo": cambia el programa de TODOS los
///   integrantes de un grupo en una sola operación.
/// - "Mover a otro grupo": cambia a un alumno de grupo en un paso.
/// - "Copiar lista": copia los integrantes en formato para pegar en Excel.
/// - Buscador del catálogo: filtra las tarjetas por programa, generación,
///   grupo, nombre o matrícula.
class AdminGruposScreen extends StatefulWidget {
  const AdminGruposScreen({super.key});

  @override
  State<AdminGruposScreen> createState() => _AdminGruposScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

/// Nombres oficiales de los programas de CESSUM. El formulario de grupos
/// solo permite estos (más la opción "Otro" para casos especiales).
const List<String> _programasOficiales = [
  'Maestría en Educación',
  'Maestría en Psicopedagogía',
  'Maestría en Pedagogía',
  'Maestría en Educación Inclusiva',
  'Doctorado en Educación con Énfasis en Investigación',
  'Doctorado en Ciencias de la Educación',
  'Licenciatura en Pedagogía',
];

const String _kOtroPrograma = 'Otro (escribir a mano)...';

class _Grupo {
  final int fila;
  String programa;
  String generacion;
  String matricula;
  String nombre;
  String correo;
  String grupo;
  _Grupo({
    required this.fila,
    required this.programa,
    required this.generacion,
    required this.matricula,
    required this.nombre,
    required this.correo,
    required this.grupo,
  });

  factory _Grupo.fromMap(Map<String, dynamic> m) => _Grupo(
        fila: int.tryParse('${m['fila']}') ?? 0,
        programa: (m['programa'] ?? '').toString(),
        generacion: (m['generacion'] ?? '').toString(),
        matricula: (m['matricula'] ?? '').toString(),
        nombre: (m['nombre'] ?? '').toString(),
        correo: (m['correo'] ?? '').toString(),
        grupo: (m['grupo'] ?? '').toString(),
      );
}

class _AdminGruposScreenState extends State<AdminGruposScreen> {
  // Modo de la pantalla.
  bool _modoCatalogo = true;

  // Catálogo (todos los grupos).
  bool _cargandoCat = true;
  String? _errorCat;
  List<_Grupo> _todos = [];
  DateTime? _ultimaCarga;
  String _tipoFiltro = 'Todos';

  // Buscador del catálogo (filtra tarjetas por texto).
  final TextEditingController _filtroCat = TextEditingController();

  // Matrículas con estatus "Baja" según la clasificación de alumnos.
  Set<String> _bajas = {};

  // Búsqueda por alumno (pestaña "Buscar alumno").
  final TextEditingController _busqueda = TextEditingController();
  bool _buscando = false;
  bool _busquedaHecha = false;
  String? _errorBusqueda;
  List<_Grupo> _resultados = [];

  bool _ocupado = false; // guardando/borrando

  @override
  void initState() {
    super.initState();
    _cargarBajas();
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    _filtroCat.dispose();
    super.dispose();
  }

  // ---------- Datos ----------
  Future<void> _cargarCatalogo() async {
    setState(() {
      _cargandoCat = true;
      _errorCat = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'grupos_admin_todos'});
      final resp = await http.get(uri).timeout(Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final lista = (data['grupos'] as List<dynamic>? ?? [])
          .map((e) => _Grupo.fromMap(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _todos = lista;
          _cargandoCat = false;
          _ultimaCarga = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargandoCat = false;
          _errorCat = 'No se pudo cargar el catálogo de grupos.';
        });
      }
    }
  }

  /// Lee la clasificación de alumnos del Guardián y guarda el conjunto de
  /// matrículas con estatus "Baja". Si falla, simplemente no se ocultan
  /// las bajas en esta carga (no bloquea la pantalla).
  Future<void> _cargarBajas() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'clasificacion_alumnos'});
      final resp = await http.get(uri).timeout(Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return;
      final lista = (data['alumnos'] as List<dynamic>? ?? []);
      final bajas = <String>{};
      for (final e in lista) {
        final m = Map<String, dynamic>.from(e as Map);
        if ((m['tipo'] ?? '').toString() == 'Baja') {
          final mat = (m['matricula'] ?? '').toString().trim();
          if (mat.isNotEmpty) bajas.add(mat);
        }
      }
      if (mounted) setState(() => _bajas = bajas);
    } catch (_) {
      // Sin conexión a la clasificación: se muestra el catálogo sin filtrar.
    }
  }

  Future<void> _buscar() async {
    final q = _busqueda.text.trim();
    if (q.isEmpty) {
      _aviso('Escribe una matrícula o un nombre.');
      return;
    }
    setState(() {
      _buscando = true;
      _errorBusqueda = null;
      _busquedaHecha = true;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(
          queryParameters: {'accion': 'grupos_admin_buscar', 'q': q});
      final resp = await http.get(uri).timeout(Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final lista = (data['grupos'] as List<dynamic>? ?? [])
          .map((e) => _Grupo.fromMap(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _resultados = lista;
          _buscando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _buscando = false;
          _errorBusqueda = 'No se pudo buscar. Revisa tu conexión.';
        });
      }
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final resp = await http
        .post(
          Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode(payload),
        )
        .timeout(Duration(seconds: 60));
    if (resp.statusCode != 200) {
      throw Exception('El servidor respondió ${resp.statusCode}.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'El Guardián reportó un error.');
    }
    if (data.containsKey('modoPrueba') || data.containsKey('guardadas')) {
      throw Exception(
          'El Guardián todavía no tiene las funciones de grupos. Sube el '
          'Code.gs actualizado y publica una versión nueva.');
    }
    return data;
  }

  Future<void> _recargar() async {
    await _cargarBajas();
    await _cargarCatalogo();
    if (_busquedaHecha && _busqueda.text.trim().isNotEmpty) await _buscar();
  }

  // ---------- Acciones ----------
  Future<void> _editarOagregar({_Grupo? base, String? grupoPrefill}) async {
    final datos = await _formulario(
      titulo: base != null ? 'Corregir inscripción' : 'Agregar a un grupo',
      base: base,
      grupoPrefill: grupoPrefill,
    );
    if (datos == null) return;
    setState(() => _ocupado = true);
    try {
      if (base != null) {
        await _post({
          'accion': 'grupos_admin_editar',
          'fila': base.fila,
          'matricula': base.matricula,
          'programa': datos['programa'],
          'generacion': datos['generacion'],
          'nombre': datos['nombre'],
          'correo': datos['correo'],
          'grupo': datos['grupo'],
        });
        // Propaga a TODAS las hojas (Padrón, Calificaciones) los datos que cambiaron,
        // para que se reflejen en el perfil y en todos los documentos.
        final _nuevos = <String, String>{
          'nombre': (datos['nombre'] ?? '').toString().trim(),
          'correo': (datos['correo'] ?? '').toString().trim(),
          'programa': (datos['programa'] ?? '').toString().trim(),
          'generacion': (datos['generacion'] ?? '').toString().trim(),
        };
        final _orig = <String, String>{
          'nombre': base.nombre.trim(),
          'correo': base.correo.trim(),
          'programa': base.programa.trim(),
          'generacion': base.generacion.trim(),
        };
        // Nombre y correo: en TODA la base (una persona = un nombre/correo).
        for (final campo in ['nombre', 'correo']) {
          final v = _nuevos[campo]!;
          if (v.isNotEmpty && v != (_orig[campo] ?? '')) {
            try {
              final uri = Uri.parse(guardianUrl).replace(queryParameters: {
                'accion': 'perfil_cambiar_dato',
                'matricula': base.matricula,
                'campo': campo,
                'valor': v,
                'aplicar': '1',
              });
              await http.get(uri).timeout(const Duration(seconds: 40));
            } catch (_) {}
          }
        }
        // Programa/generación: SOLO esta inscripción (seguro para multi-programa).
        final _progCambio = _nuevos['programa']!.isNotEmpty &&
            _nuevos['programa'] != _orig['programa'];
        final _genCambio = _nuevos['generacion']!.isNotEmpty &&
            _nuevos['generacion'] != _orig['generacion'];
        if (_progCambio || _genCambio) {
          try {
            final uri = Uri.parse(guardianUrl).replace(queryParameters: {
              'accion': 'perfil_cambiar_inscripcion',
              'matricula': base.matricula,
              'progViejo': base.programa,
              'genVieja': base.generacion,
              if (_progCambio) 'progNuevo': _nuevos['programa']!,
              if (_genCambio) 'genNuevo': _nuevos['generacion']!,
              'aplicar': '1',
            });
            await http.get(uri).timeout(const Duration(seconds: 40));
          } catch (_) {}
        }
        _aviso('Inscripción actualizada en toda la base.');
      } else {
        await _post({
          'accion': 'grupos_admin_agregar',
          'matricula': datos['matricula'],
          'programa': datos['programa'],
          'generacion': datos['generacion'],
          'nombre': datos['nombre'],
          'correo': datos['correo'],
          'grupo': datos['grupo'],
        });
        _aviso('Alumno agregado al grupo.');
      }
      await _recargar();
    } catch (e) {
      _aviso('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _eliminar(_Grupo g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quitar del grupo'),
        content: Text(
          '¿Quitar a ${g.nombre} de este grupo?\n\n'
          '${g.programa}\nGen. ${g.generacion} · Grupo ${g.grupo}\n\n'
          'No borra sus calificaciones.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    try {
      await _post({
        'accion': 'grupos_admin_eliminar',
        'fila': g.fila,
        'matricula': g.matricula,
      });
      _aviso('Inscripción quitada.');
      await _recargar();
    } catch (e) {
      _aviso('No se pudo quitar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Fija el estatus "Baja" del alumno en la clasificación (la misma base
  /// que usa la pantalla "Clasificación de alumnos"). El alumno se oculta
  /// de los grupos, pero su inscripción y calificaciones NO se borran.
  Future<void> _darDeBaja(_Grupo g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dar de baja'),
        content: Text(
          '¿Marcar a ${g.nombre} (matrícula ${g.matricula}) como BAJA?\n\n'
          'Se fija en la clasificación de alumnos y dejará de aparecer en '
          'los grupos. No borra su inscripción ni sus calificaciones; '
          'puedes reactivarlo después desde "Buscar alumno" o desde '
          'Clasificación de alumnos.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    try {
      await _post({
        'accion': 'clasificacion_fijar',
        'matricula': g.matricula,
        'tipo': 'Baja',
        'nombre': g.nombre,
      });
      _aviso('${g.nombre} quedó marcado(a) como Baja.');
      await _recargar();
    } catch (e) {
      _aviso('No se pudo dar de baja: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Quita la marca manual de Baja: el alumno vuelve a la clasificación
  /// automática y reaparece en sus grupos.
  Future<void> _reactivar(_Grupo g) async {
    setState(() => _ocupado = true);
    try {
      await _post({
        'accion': 'clasificacion_quitar',
        'matricula': g.matricula,
      });
      _aviso('${g.nombre} volvió a la clasificación automática.');
      await _recargar();
    } catch (e) {
      _aviso('No se pudo reactivar: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Mueve a un alumno a otro grupo existente en un solo paso: elige el
  /// grupo destino de una lista y se actualiza su inscripción.
  Future<void> _moverAOtroGrupo(_Grupo g) async {
    final actual = '${g.programa}||${g.generacion}||${g.grupo}';
    final destinos = <String>{};
    for (final x in _todos) {
      final k = '${x.programa}||${x.generacion}||${x.grupo}';
      if (k != actual) destinos.add(k);
    }
    final lista = destinos.toList()..sort();
    if (lista.isEmpty) {
      _aviso('No hay otros grupos a dónde mover.');
      return;
    }

    String etiqueta(String k) {
      final p = k.split('||');
      final prog = p.isNotEmpty ? p[0] : '';
      final gen = p.length > 1 ? p[1] : '';
      final grp = p.length > 2 ? p[2] : '';
      return 'Grupo ${grp.isEmpty ? '—' : grp} · Gen. $gen · $prog';
    }

    String? sel;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Mover a otro grupo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${g.nombre}\nMatrícula: ${g.matricula}\n\nGrupo actual: '
                '${g.grupo.isEmpty ? '—' : g.grupo} · Gen. ${g.generacion}',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 14),
              // (24-sep) Con búsqueda: son todos los grupos.
              CessumSelectorBuscable<String>(
                label: 'Grupo destino',
                valor: sel,
                opciones: lista,
                etiqueta: etiqueta,
                hint: 'Elige el grupo',
                onChanged: (v) => setD(() => sel = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                if (sel == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Elige el grupo destino.')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text('Mover'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || sel == null) return;
    final p = sel!.split('||');
    setState(() => _ocupado = true);
    try {
      await _post({
        'accion': 'grupos_admin_editar',
        'fila': g.fila,
        'matricula': g.matricula,
        'programa': p.isNotEmpty ? p[0] : g.programa,
        'generacion': p.length > 1 ? p[1] : g.generacion,
        'nombre': g.nombre,
        'correo': g.correo,
        'grupo': p.length > 2 ? p[2] : g.grupo,
      });
      _aviso('${g.nombre} se movió de grupo.');
      await _recargar();
    } catch (e) {
      _aviso('No se pudo mover: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// Copia la lista de integrantes al portapapeles, separada con
  /// tabuladores: al pegarla en Excel cada dato cae en su columna.
  Future<void> _copiarLista(
      String programa, String generacion, String grupo,
      List<_Grupo> integrantes) async {
    final sb = StringBuffer();
    sb.writeln('Grupo $grupo\tGen. $generacion\t$programa');
    sb.writeln('Nombre\tMatrícula\tCorreo');
    for (final g in integrantes) {
      sb.writeln('${g.nombre}\t${g.matricula}\t${g.correo}');
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    _aviso(
        'Lista copiada (${integrantes.length} alumnos). Pégala en Excel o donde la necesites.');
  }

  /// Cambia el programa de TODOS los integrantes de un grupo en una sola
  /// operación (uno por uno contra el Guardián, con barra de progreso).
  Future<void> _corregirProgramaGrupo(
      String programaActual, List<_Grupo> integrantes) async {
    String? sel;
    final otro = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Corregir programa del grupo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se cambiará el programa de los ${integrantes.length} '
                  'integrante(s) de este grupo.\n\nPrograma actual:\n'
                  '$programaActual',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: sel,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Programa correcto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [..._programasOficiales, _kOtroPrograma]
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child:
                                Text(p, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setD(() => sel = v),
                ),
                if (sel == _kOtroPrograma)
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: TextField(
                      controller: otro,
                      decoration: InputDecoration(
                        labelText: 'Escribe el programa',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                final nuevo = sel == _kOtroPrograma
                    ? otro.text.trim()
                    : (sel ?? '').trim();
                if (nuevo.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text('Elige el programa correcto.')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text('Corregir todo el grupo'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final nuevo =
        sel == _kOtroPrograma ? otro.text.trim() : (sel ?? '').trim();
    if (nuevo.isEmpty) return;

    setState(() => _ocupado = true);
    var hechos = 0;
    try {
      for (final g in integrantes) {
        await _post({
          'accion': 'grupos_admin_editar',
          'fila': g.fila,
          'matricula': g.matricula,
          'programa': nuevo,
          'generacion': g.generacion,
          'nombre': g.nombre,
          'correo': g.correo,
          'grupo': g.grupo,
        });
        hechos++;
      }
      _aviso('Programa corregido en $hechos integrante(s).');
    } catch (e) {
      _aviso(
          'Se corrigieron $hechos de ${integrantes.length}. Detalle: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
    await _recargar();
  }

  /// Corrige la GENERACIÓN de TODOS los integrantes del grupo (columna
  /// Generación del Excel), con efecto directo en la base.
  Future<void> _corregirSistemaGrupo(
      String grupoActual, List<_Grupo> integrantes) async {
    const opciones = ['1 - entre semana', '2 - sabatino', '1 - mixta'];
    String? sel =
        opciones.contains(grupoActual.trim()) ? grupoActual.trim() : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Corregir sistema del grupo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se cambiará el sistema de los ${integrantes.length} '
                  'integrante(s) de este grupo.\n\nSistema actual:\n'
                  '$grupoActual',
                  style: TextStyle(fontSize: 13, height: 1.4),
                ),
                SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: sel,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Sistema correcto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: opciones
                      .map((o) =>
                          DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) => setLocal(() => sel = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                if (sel == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Selecciona el sistema.')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text('Corregir todo el grupo'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || sel == null) return;
    final nuevo = sel!;
    if (nuevo == grupoActual.trim()) {
      _aviso('El sistema es el mismo; no se hizo ningún cambio.');
      return;
    }
    setState(() => _ocupado = true);
    var hechos = 0;
    try {
      for (final g in integrantes) {
        await _post({
          'accion': 'grupos_admin_editar',
          'fila': g.fila,
          'matricula': g.matricula,
          'programa': g.programa,
          'generacion': g.generacion,
          'nombre': g.nombre,
          'correo': g.correo,
          'grupo': nuevo,
        });
        hechos++;
      }
      _aviso('Sistema corregido en $hechos integrante(s).');
    } catch (e) {
      _aviso('Se corrigieron $hechos de ${integrantes.length}. Detalle: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
    await _recargar();
  }

  Future<void> _corregirGeneracionGrupo(
      String generacionActual, List<_Grupo> integrantes) async {
    final ctrl = TextEditingController(text: generacionActual);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Corregir generación del grupo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se cambiará la generación de los ${integrantes.length} '
                'integrante(s) de este grupo.\n\nGeneración actual:\n'
                '$generacionActual',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Generación correcta (ej. 24-1)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Escribe la generación correcta.')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text('Corregir todo el grupo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final nueva = ctrl.text.trim();
    if (nueva.isEmpty) return;
    if (nueva == generacionActual.trim()) {
      _aviso('La generación es la misma; no se hizo ningún cambio.');
      return;
    }

    setState(() => _ocupado = true);
    var hechos = 0;
    try {
      for (final g in integrantes) {
        await _post({
          'accion': 'grupos_admin_editar',
          'fila': g.fila,
          'matricula': g.matricula,
          'programa': g.programa,
          'generacion': nueva,
          'nombre': g.nombre,
          'correo': g.correo,
          'grupo': g.grupo,
        });
        hechos++;
      }
      _aviso('Generación corregida en $hechos integrante(s).');
    } catch (e) {
      _aviso(
          'Se corrigieron $hechos de ${integrantes.length}. Detalle: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
    await _recargar();
  }

  /// Revisa TODA la base cargada y reporta inconsistencias para corregirlas
  /// (matrículas/correos duplicados, campos vacíos, generaciones mal escritas,
  /// correos no institucionales, matrículas no numéricas). Todo en el cliente.
  void _revisarSaludDatos() {
    String etq(_Grupo g) =>
        '${g.nombre.isEmpty ? "(sin nombre)" : g.nombre} · mat ${g.matricula.isEmpty ? "—" : g.matricula} · ${g.programa} ${g.generacion} ${g.grupo}';

    final porMat = <String, List<_Grupo>>{};
    final porCorreo = <String, List<_Grupo>>{};
    for (final g in _todos) {
      final m = g.matricula.trim();
      if (m.isNotEmpty) (porMat[m] ??= []).add(g);
      final c = g.correo.trim().toLowerCase();
      if (c.isNotEmpty) (porCorreo[c] ??= []).add(g);
    }

    final hallazgos = <String, List<String>>{};

    final dupM = <String>[];
    porMat.forEach((mat, gs) {
      if (gs.length > 1) {
        dupM.add('Matrícula $mat aparece ${gs.length} veces: ' +
            gs
                .map((g) => g.nombre.isEmpty ? "(sin nombre)" : g.nombre)
                .join(' / '));
      }
    });
    hallazgos['Matrículas duplicadas'] = dupM;

    final dupC = <String>[];
    porCorreo.forEach((cor, gs) {
      if (gs.length > 1) {
        dupC.add('$cor en ${gs.length} registros: ' +
            gs
                .map((g) => g.nombre.isEmpty ? "(sin nombre)" : g.nombre)
                .join(' / '));
      }
    });
    hallazgos['Correos duplicados'] = dupC;

    final vac = <String>[];
    for (final g in _todos) {
      final faltan = <String>[];
      if (g.programa.trim().isEmpty) faltan.add('programa');
      if (g.generacion.trim().isEmpty) faltan.add('generación');
      if (g.matricula.trim().isEmpty) faltan.add('matrícula');
      if (g.nombre.trim().isEmpty) faltan.add('nombre');
      if (g.correo.trim().isEmpty) faltan.add('correo');
      if (g.grupo.trim().isEmpty) faltan.add('grupo');
      if (faltan.isNotEmpty) vac.add('${etq(g)} → falta: ${faltan.join(", ")}');
    }
    hallazgos['Campos vacíos'] = vac;

    final reGen = RegExp(r'^\d{2}-\d[A-Za-z]?$');
    final genMal = <String>[];
    for (final g in _todos) {
      final gen = g.generacion.trim();
      if (gen.isNotEmpty && !reGen.hasMatch(gen)) {
        genMal.add('${etq(g)} → generación "$gen"');
      }
    }
    hallazgos['Generaciones con formato raro'] = genMal;

    final correoMal = <String>[];
    for (final g in _todos) {
      final c = g.correo.trim().toLowerCase();
      if (c.isNotEmpty && !c.endsWith('@cessum.mx')) {
        correoMal.add('${etq(g)} → $c');
      }
    }
    hallazgos['Correos no @cessum.mx'] = correoMal;

    final reMat = RegExp(r'^\d+$');
    final matMal = <String>[];
    for (final g in _todos) {
      final m = g.matricula.trim();
      if (m.isNotEmpty && !reMat.hasMatch(m)) {
        matMal.add('${etq(g)} → matrícula "$m"');
      }
    }
    hallazgos['Matrículas no numéricas'] = matMal;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _SaludDatosReporte(total: _todos.length, hallazgos: hallazgos),
      ),
    );
  }

  /// Renombra la etiqueta del grupo de TODOS los integrantes (columna Grupo
  /// del Excel). La modalidad mostrada (Sabatino, Mixto, etc.) se deduce de
  /// este texto, así que renombrar el grupo corrige también su clasificación.
  Future<void> _renombrarGrupo(
      String grupoActual, List<_Grupo> integrantes) async {
    final ctrl = TextEditingController(text: grupoActual);
    // Número del grupo (lo que va antes del guion o espacio), para sugerencias.
    final num = RegExp(r'^\s*([^\s-]+)').firstMatch(grupoActual)?.group(1) ??
        grupoActual.trim();
    // Opciones válidas según la regla real de CESSUM (la modalidad "mixta"
    // viene de la hoja de inscripción; los No Escolarizados los define el número):
    //   No Esc 1 = entre semana · No Esc 2 = sabatino · Mixta 1 = mixta.
    final numNorm = num.trim();
    final sugerencias = <String>[
      if (numNorm == '1') ...['1 - entre semana', '1 - mixta'],
      if (numNorm == '2') '2 - sabatino',
      if (numNorm != '1' && numNorm != '2') numNorm,
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Renombrar grupo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se cambiará la etiqueta de grupo de los '
                '${integrantes.length} integrante(s) en la base (Excel).\n\n'
                'La modalidad que muestra la app (Sabatino, Mixto, '
                'Entre semana, Virtual) se deduce de este texto.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 14),
              TextField(
                controller: ctrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Etiqueta del grupo',
                  hintText: 'Elige una opción abajo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              SizedBox(height: 8),
              Text('Elige la etiqueta correcta (no se puede escribir a mano):',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: sugerencias
                    .map((s) => ActionChip(
                          label: Text(s,
                              style: TextStyle(fontSize: 12)),
                          onPressed: () => ctrl.text = s,
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (ctrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Escribe la nueva etiqueta del grupo.')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text('Renombrar todo el grupo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final nuevo = ctrl.text.trim();
    if (nuevo.isEmpty || nuevo == grupoActual.trim()) return;

    setState(() => _ocupado = true);
    var hechos = 0;
    try {
      for (final g in integrantes) {
        await _post({
          'accion': 'grupos_admin_editar',
          'fila': g.fila,
          'matricula': g.matricula,
          'programa': g.programa,
          'generacion': g.generacion,
          'nombre': g.nombre,
          'correo': g.correo,
          'grupo': nuevo,
        });
        hechos++;
      }
      _aviso('Grupo renombrado en $hechos integrante(s).');
    } catch (e) {
      _aviso(
          'Se renombraron $hechos de ${integrantes.length}. Detalle: $e');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
    await _recargar();
  }

  Future<Map<String, String>?> _formulario({
    required String titulo,
    _Grupo? base,
    String? grupoPrefill,
  }) async {
    final matricula = TextEditingController(text: base?.matricula ?? '');
    final generacion = TextEditingController(text: base?.generacion ?? '');
    final grupo =
        TextEditingController(text: base?.grupo ?? grupoPrefill ?? '');
    final nombre = TextEditingController(text: base?.nombre ?? '');
    final correo = TextEditingController(text: base?.correo ?? '');

    // Programa: lista oficial. Si el registro trae un programa que no está
    // en la lista (p. ej. mal capturado), se preselecciona "Otro" con el
    // texto original para que el admin lo vea y lo corrija.
    String? programaSel;
    final programaOtro = TextEditingController();
    final progBase = (base?.programa ?? '').trim();
    if (progBase.isNotEmpty) {
      final match = _programasOficiales.firstWhere(
        (p) => _norm(p) == _norm(progBase),
        orElse: () => '',
      );
      if (match.isNotEmpty) {
        programaSel = match;
      } else {
        programaSel = _kOtroPrograma;
        programaOtro.text = progBase;
      }
    }

    Widget campo(TextEditingController c, String etq, {TextInputType? tipo}) {
      return Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: tipo,
          decoration: InputDecoration(
            labelText: etq,
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
    }

    final cBusca = TextEditingController();
    List<_Grupo> resBusca = [];
    bool buscandoB = false;
    Future<void> buscarAlumno(StateSetter setD) async {
      final q = cBusca.text.trim();
      if (q.isEmpty) return;
      setD(() => buscandoB = true);
      try {
        final uri = Uri.parse(guardianUrl)
            .replace(queryParameters: {'accion': 'grupos_admin_buscar', 'q': q});
        final resp = await http.get(uri).timeout(const Duration(seconds: 30));
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final lista = (data['grupos'] as List<dynamic>? ?? [])
            .map((e) => _Grupo.fromMap(e as Map<String, dynamic>))
            .toList();
        final vistos = <String>{};
        final unicos = <_Grupo>[];
        for (final g in lista) {
          if (g.matricula.isNotEmpty && vistos.add(g.matricula)) unicos.add(g);
        }
        setD(() {
          resBusca = unicos;
          buscandoB = false;
        });
      } catch (_) {
        setD(() => buscandoB = false);
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(titulo),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Se guarda en la base de grupos del Guardián.',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                  ),
                ),
                SizedBox(height: 12),
                if (base == null) ...[
                  TextField(
                    controller: cBusca,
                    decoration: InputDecoration(
                      labelText: 'Buscar alumno (nombre o matrícula)',
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: buscandoB
                          ? Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : IconButton(
                              icon: Icon(Icons.arrow_forward),
                              onPressed: () => buscarAlumno(setD)),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => buscarAlumno(setD),
                  ),
                  if (resBusca.isNotEmpty)
                    Container(
                      constraints: BoxConstraints(maxHeight: 180),
                      margin: EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: resBusca
                            .map((g) => ListTile(
                                  dense: true,
                                  title: Text(g.nombre),
                                  subtitle:
                                      Text('${g.matricula} \u00b7 ${g.programa}'),
                                  onTap: () => setD(() {
                                    matricula.text = g.matricula;
                                    nombre.text = g.nombre;
                                    correo.text = g.correo;
                                    if (g.generacion.isNotEmpty) {
                                      generacion.text = g.generacion;
                                    }
                                    final match = _programasOficiales.firstWhere(
                                        (p) => _norm(p) == _norm(g.programa),
                                        orElse: () => '');
                                    if (match.isNotEmpty) {
                                      programaSel = match;
                                    } else if (g.programa.isNotEmpty) {
                                      programaSel = _kOtroPrograma;
                                      programaOtro.text = g.programa;
                                    }
                                    resBusca = [];
                                    cBusca.text = '';
                                  }),
                                ))
                            .toList(),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('o captura manual',
                            style: TextStyle(
                                fontSize: 11, color: cessumMuted(context))),
                      ),
                      Expanded(child: Divider()),
                    ]),
                  ),
                ],
                campo(matricula, 'Matrícula', tipo: TextInputType.number),
                campo(nombre, 'Nombre completo'),
                campo(correo, 'Correo institucional'),
                Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: DropdownButtonFormField<String>(
                    value: programaSel,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Programa',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [..._programasOficiales, _kOtroPrograma]
                        .map((p) => DropdownMenuItem(
                              value: p,
                              child:
                                  Text(p, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setD(() => programaSel = v),
                  ),
                ),
                if (programaSel == _kOtroPrograma)
                  campo(programaOtro, 'Programa (texto libre)'),
                campo(generacion, 'Generación'),
                Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Builder(builder: (_) {
                    final actual = grupo.text.trim();
                    const estandar = [
                      '1 - entre semana',
                      '1 - mixta',
                      '2 - sabatino'
                    ];
                    final ops = <String>[
                      if (actual.isNotEmpty && !estandar.contains(actual)) actual,
                      ...estandar,
                    ];
                    return DropdownButtonFormField<String>(
                      value: ops.contains(actual) ? actual : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Grupo',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: ops
                          .map((o) => DropdownMenuItem(
                                value: o,
                                child:
                                    Text(o, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setD(() => grupo.text = v ?? ''),
                    );
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                final progFinal = programaSel == _kOtroPrograma
                    ? programaOtro.text.trim()
                    : (programaSel ?? '').trim();
                if (matricula.text.trim().isEmpty || progFinal.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(
                          'La matrícula y el programa son obligatorios.')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    final progFinal = programaSel == _kOtroPrograma
        ? programaOtro.text.trim()
        : (programaSel ?? '').trim();
    return {
      'matricula': matricula.text.trim(),
      'programa': progFinal,
      'generacion': generacion.text.trim(),
      'grupo': grupo.text.trim(),
      'nombre': nombre.text.trim(),
      'correo': correo.text.trim(),
    };
  }

  // ======================= HERRAMIENTAS NUEVAS =======================

  String _normB(String s) {
    s = s.toLowerCase();
    const a = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const b = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  bool _esBaja(_Grupo g) => g.grupo.trim().toUpperCase() == 'BAJA';
  bool _esActivo(_Grupo g) => g.grupo.trim().isNotEmpty && !_esBaja(g);

  /// 1) Buscar alumno por nombre o matrícula y ver su ficha.
  void _buscarAlumno() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSt) {
          final q = _normB(ctrl.text);
          final res = q.isEmpty
              ? <_Grupo>[]
              : _todos
                  .where((g) =>
                      _normB(g.nombre).contains(q) ||
                      g.matricula.toLowerCase().contains(q))
                  .take(40)
                  .toList();
          return AlertDialog(
            title: Text('Buscar alumno'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    onChanged: (_) => setSt(() {}),
                    decoration: InputDecoration(
                      labelText: 'Nombre o matrícula',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  SizedBox(height: 10),
                  Flexible(
                    child: q.isEmpty
                        ? Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Escribe para buscar…',
                                style: TextStyle(color: cessumMuted(context))))
                        : res.isEmpty
                            ? Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('Sin coincidencias.',
                                    style: TextStyle(color: cessumMuted(context))))
                            : ListView(
                                shrinkWrap: true,
                                children: res.map((g) {
                                  final baja = _esBaja(g);
                                  return Card(
                                    margin: EdgeInsets.symmetric(
                                        vertical: 3),
                                    child: ListTile(
                                      dense: true,
                                      leading: Icon(
                                          baja
                                              ? Icons.person_off
                                              : Icons.person,
                                          color:
                                              baja ? Colors.grey : cessumRed),
                                      title: Text(g.nombre,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13)),
                                      subtitle: Text(
                                        'Mat. ${g.matricula}\n${g.programa} · ${g.generacion} · '
                                        '${baja ? "BAJA" : g.grupo}\n${g.correo}',
                                        style: TextStyle(fontSize: 11.5),
                                      ),
                                      isThreeLine: true,
                                      trailing: Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: baja
                                              ? Colors.grey.shade300
                                              : Color(0xFFDFF3E3),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(baja ? 'Baja' : 'Activo',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: baja
                                                    ? cessumMuted(context)
                                                    : Color(0xFF1E8E3E),
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cerrar')),
            ],
          );
        });
      },
    );
  }

  /// 2) Resumen por programa: activos / bajas / total.
  void _resumenPrograma() {
    final mapa = <String, List<int>>{}; // programa -> [activos, bajas, total]
    for (final g in _todos) {
      final p = g.programa.trim().isEmpty ? '(sin programa)' : g.programa.trim();
      final m = mapa.putIfAbsent(p, () => [0, 0, 0]);
      if (_esBaja(g)) {
        m[1]++;
      } else if (_esActivo(g)) {
        m[0]++;
      }
      m[2]++;
    }
    final progs = mapa.keys.toList()..sort();
    var tA = 0, tB = 0, tT = 0;
    for (final m in mapa.values) {
      tA += m[0];
      tB += m[1];
      tT += m[2];
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Resumen por programa'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _filaResumen('Programa', 'Activos', 'Bajas', 'Total',
                    encabezado: true),
                Divider(height: 8),
                ...progs.map((p) => _filaResumen(p, '${mapa[p]![0]}',
                    '${mapa[p]![1]}', '${mapa[p]![2]}')),
                Divider(height: 8),
                _filaResumen('TOTAL', '$tA', '$tB', '$tT', encabezado: true),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _filaResumen(String a, String b, String c, String d,
      {bool encabezado = false}) {
    final st = TextStyle(
        fontSize: 12.5,
        fontWeight: encabezado ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(a, style: st)),
          Expanded(
              flex: 2,
              child: Text(b, style: st, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text(c, style: st, textAlign: TextAlign.right)),
          Expanded(
              flex: 2,
              child: Text(d, style: st, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  /// 3) Exportar a Excel/CSV (descarga en el navegador).
  void _exportarCSV() {
    final progs = <String>{
      for (final g in _todos)
        if (g.programa.trim().isNotEmpty) g.programa.trim()
    }.toList()
      ..sort();
    String alcance = 'TODOS';
    bool soloActivos = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: Text('Exportar a Excel/CSV'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Programa:', style: TextStyle(fontSize: 12.5)),
              DropdownButton<String>(
                isExpanded: true,
                value: alcance,
                items: [
                  DropdownMenuItem(
                      value: 'TODOS', child: Text('Todos los programas')),
                  ...progs.map((p) =>
                      DropdownMenuItem(value: p, child: Text(p))),
                ],
                onChanged: (v) => setSt(() => alcance = v ?? 'TODOS'),
              ),
              SizedBox(height: 6),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: soloActivos,
                onChanged: (v) => setSt(() => soloActivos = v ?? true),
                title: Text('Solo activos (excluir bajas)',
                    style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancelar')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              icon: Icon(Icons.download),
              label: Text('Descargar'),
              onPressed: () {
                final filas = _todos.where((g) {
                  if (alcance != 'TODOS' && g.programa.trim() != alcance) {
                    return false;
                  }
                  if (soloActivos && !_esActivo(g)) return false;
                  return true;
                }).toList()
                  ..sort((x, y) {
                    final c = x.programa.compareTo(y.programa);
                    if (c != 0) return c;
                    final c2 = x.generacion.compareTo(y.generacion);
                    if (c2 != 0) return c2;
                    return x.nombre.compareTo(y.nombre);
                  });
                if (filas.isEmpty) {
                  Navigator.pop(ctx);
                  _aviso('No hay alumnos que exportar con ese filtro.');
                  return;
                }
                final sb = StringBuffer();
                sb.writeln(
                    'Programa,Generación,Matrícula,Nombre,Correo,Grupo,Estatus');
                for (final g in filas) {
                  sb.writeln([
                    g.programa,
                    g.generacion,
                    g.matricula,
                    g.nombre,
                    g.correo,
                    g.grupo,
                    _esBaja(g) ? 'Baja' : 'Activo',
                  ].map(_csv).join(','));
                }
                final etq = alcance == 'TODOS'
                    ? 'todos'
                    : _normB(alcance).replaceAll(' ', '_');
                _descargarCsv(sb.toString(), 'CESSUM_$etq.csv');
                Navigator.pop(ctx);
                _aviso('Se exportaron ${filas.length} alumno(s).');
              },
            ),
          ],
        );
      }),
    );
  }

  String _csv(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  void _descargarCsv(String contenido, String nombre) {
    final bytes = utf8.encode('\uFEFF$contenido'); // BOM: acentos OK en Excel
    final blob = html.Blob(<dynamic>[bytes], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', nombre)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// 4) Revertir baja: reactivar un alumno marcado BAJA por error.
  void _revertirBajas() {
    showDialog(
      context: context,
      builder: (ctx) {
        final bajas = _todos.where(_esBaja).toList()
          ..sort((a, b) => a.nombre.compareTo(b.nombre));
        bool cambios = false;
        return StatefulBuilder(builder: (ctx, setSt) {
          return AlertDialog(
            title: Text('Revertir baja (${bajas.length})'),
            content: SizedBox(
              width: 480,
              child: bajas.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No hay alumnos marcados como BAJA.'))
                  : ListView(
                      shrinkWrap: true,
                      children: bajas.map((g) {
                        return Card(
                          margin: EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            dense: true,
                            title: Text(g.nombre,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            subtitle: Text(
                                'Mat. ${g.matricula} · ${g.programa} ${g.generacion}',
                                style: TextStyle(fontSize: 11.5)),
                            trailing: TextButton.icon(
                              icon: Icon(Icons.restore, size: 18),
                              label: Text('Reactivar'),
                              onPressed: () async {
                                final destino = await _elegirGrupoDestino(ctx);
                                if (destino == null) return;
                                try {
                                  await _post({
                                    'accion': 'grupos_admin_editar',
                                    'fila': g.fila,
                                    'matricula': g.matricula,
                                    'grupo': destino,
                                  });
                                  cambios = true;
                                  setSt(() => bajas.remove(g));
                                  _aviso('${g.nombre} reactivado en "$destino".');
                                } catch (e) {
                                  _aviso('No se pudo reactivar: $e');
                                }
                              },
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (cambios) _recargar();
                },
                child: Text('Cerrar'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<String?> _elegirGrupoDestino(BuildContext ctx) {
    return showDialog<String>(
      context: ctx,
      builder: (c) => SimpleDialog(
        title: Text('Reactivar en…'),
        children: [
          for (final gr in const [
            '1 - entre semana',
            '2 - sabatino',
            'Mixta',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, gr),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(gr),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, null),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Cancelar', style: TextStyle(color: cessumFaint(context))),
            ),
          ),
        ],
      ),
    );
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: 3)),
    );
  }

  // ---------- Clasificación ----------
  String _norm(String s) {
    s = s.toLowerCase();
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
  }

  // Deduce el tipo de un grupo a partir del programa y la etiqueta del grupo.
  String _tipoGrupo(String programa, String grupo) {
    final t = _norm('$programa $grupo');
    if (t.contains('sabat') || t.contains('sabado')) return 'Sabatino';
    if (t.contains('entre semana') ||
        t.contains('vesper') ||
        t.contains('matut') ||
        t.contains('nocturn')) {
      return 'Entre semana';
    }
    if (t.contains('mixt')) return 'Mixto';
    if (t.contains('virtual') ||
        t.contains('linea') ||
        t.contains('online') ||
        t.contains('escolarizad')) {
      return 'Virtual';
    }
    return 'Otro';
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Grupos'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Más herramientas',
            icon: Icon(Icons.build_outlined),
            onSelected: (v) {
              switch (v) {
                case 'buscar':
                  _buscarAlumno();
                  break;
                case 'resumen':
                  _resumenPrograma();
                  break;
                case 'exportar':
                  _exportarCSV();
                  break;
                case 'revertir':
                  _revertirBajas();
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'buscar',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.person_search_outlined),
                    title: Text('Buscar alumno')),
              ),
              PopupMenuItem(
                value: 'resumen',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.pie_chart_outline),
                    title: Text('Resumen por programa')),
              ),
              PopupMenuItem(
                value: 'exportar',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.download_outlined),
                    title: Text('Exportar a Excel/CSV')),
              ),
              PopupMenuItem(
                value: 'revertir',
                child: ListTile(
                    dense: true,
                    leading: Icon(Icons.restore_outlined),
                    title: Text('Revertir baja')),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Sincronizar bajas',
            icon: Icon(Icons.person_off_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => _SincronizarBajasReporte()),
              );
              if (mounted) _recargar();
            },
          ),
          IconButton(
            tooltip: 'Salud de datos',
            icon: Icon(Icons.fact_check_outlined),
            onPressed: _todos.isEmpty ? null : _revisarSaludDatos,
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _ocupado ? null : _recargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _ocupado ? null : () => _editarOagregar(),
        icon: Icon(Icons.person_add),
        label: Text('Agregar a grupo'),
      ),
      body: Column(
        children: [
          _selectorModo(),
          if (_ocupado) const LinearProgressIndicator(color: cessumRed),
          if (_ultimaCarga != null)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  Helpers.haceTexto(_ultimaCarga),
                  style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
                ),
              ),
            ),
          Expanded(child: _modoCatalogo ? _vistaCatalogo() : _vistaBuscar()),
        ],
      ),
    );
  }

  Widget _selectorModo() {
    Widget boton(String txt, IconData ic, bool activo, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: activo ? cessumRed : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(ic,
                    size: 18, color: activo ? cessumRed : cessumFaint(context)),
                SizedBox(width: 6),
                Text(
                  txt,
                  style: TextStyle(
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
                    color: activo ? cessumRed : cessumMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: cessumEsOscuro(context) ? Theme.of(context).cardColor : Colors.white,
      child: Row(
        children: [
          boton('Todos los grupos', Icons.groups, _modoCatalogo,
              () => setState(() => _modoCatalogo = true)),
          boton('Buscar alumno', Icons.search, !_modoCatalogo,
              () => setState(() => _modoCatalogo = false)),
        ],
      ),
    );
  }

  // ===== Catálogo =====
  Widget _vistaCatalogo() {
    if (_cargandoCat) {
      return Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_errorCat != null) {
      return _error(_errorCat!, _cargarCatalogo);
    }
    if (_todos.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text('No hay grupos en la base todavía.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context))),
        ),
      );
    }

    // Agrupar por programa + generación + grupo, OCULTANDO a los alumnos
    // con estatus "Baja" y aplicando el filtro de texto del buscador.
    final q = _norm(_filtroCat.text.trim());
    final grupos = <String, List<_Grupo>>{};
    var ocultosPorBaja = 0;
    for (final g in _todos) {
      if (_bajas.contains(g.matricula.trim())) {
        ocultosPorBaja++;
        continue;
      }
      if (_tipoFiltro != 'Todos' &&
          _tipoGrupo(g.programa, g.grupo) != _tipoFiltro) {
        continue;
      }
      if (q.isNotEmpty) {
        final txt = _norm(
            '${g.programa} ${g.generacion} ${g.grupo} ${g.nombre} ${g.matricula}');
        if (!txt.contains(q)) continue;
      }
      final k = '${g.programa}||${g.generacion}||${g.grupo}';
      grupos.putIfAbsent(k, () => []).add(g);
    }
    final claves = grupos.keys.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: TextField(
            controller: _filtroCat,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'Filtrar grupos (ej. 25-2, sabatino, doctorado, nombre...)',
              prefixIcon: Icon(Icons.filter_list),
              suffixIcon: _filtroCat.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _filtroCat.clear();
                        setState(() {});
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: cessumEsOscuro(context) ? const Color(0xFF211F1D) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
        ),
        _chipsClasificacion(),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${claves.length} grupo(s) · ${grupos.values.fold<int>(0, (a, b) => a + b.length)} integrante(s)'
              '${ocultosPorBaja > 0 ? '  ·  $ocultosPorBaja baja(s) oculta(s)' : ''}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context)),
            ),
          ),
        ),
        Expanded(
          child: claves.isEmpty
              ? Center(
                  child: Text('Ningún grupo coincide con el filtro.',
                      style: TextStyle(color: cessumMuted(context))))
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _recargar,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 90),
                    children: claves
                        .map((k) => _tarjetaGrupo(k, grupos[k]!))
                        .toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _chipsClasificacion() {
    final tipos = <String>{'Todos'};
    for (final g in _todos) {
      tipos.add(_tipoGrupo(g.programa, g.grupo));
    }
    final orden = ['Todos', 'Sabatino', 'Entre semana', 'Mixto', 'Virtual', 'Otro'];
    final lista = orden.where(tipos.contains).toList();
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: lista.map((t) {
          final sel = _tipoFiltro == t;
          return Padding(
            padding: EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(t),
              selected: sel,
              selectedColor: cessumRed,
              labelStyle: TextStyle(
                color: sel ? Colors.white : cessumInk(context),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              onSelected: (_) => setState(() => _tipoFiltro = t),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _colorTipo(String tipo) {
    switch (tipo) {
      case 'Sabatino':
        return cessumGold;
      case 'Entre semana':
        return Color(0xFF1565C0);
      case 'Mixto':
        return Color(0xFF6A1B9A);
      case 'Virtual':
        return _verdeOk;
      default:
        return cessumFaint(context);
    }
  }

  Widget _tarjetaGrupo(String clave, List<_Grupo> integrantes) {
    final partes = clave.split('||');
    final programa = partes.isNotEmpty ? partes[0] : '';
    final generacion = partes.length > 1 ? partes[1] : '';
    final grupo = partes.length > 2 ? partes[2] : '';
    final tipo = _tipoGrupo(programa, grupo);
    final cTipo = _colorTipo(tipo);
    integrantes.sort((a, b) => a.nombre.compareTo(b.nombre));

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cessumEsOscuro(context) ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: EdgeInsets.only(bottom: 6),
        title: Text(
          'Grupo ${grupo.isEmpty ? '—' : grupo}'
          '${generacion.isNotEmpty ? '  ·  Gen. $generacion' : ''}',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cTipo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(tipo,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cTipo)),
              ),
              Text('${integrantes.length} integrante(s)',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              if (programa.isNotEmpty)
                Text(programa,
                    style:
                        TextStyle(fontSize: 12, color: cessumMuted(context))),
            ],
          ),
        ),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 2, 14, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 4,
                runSpacing: 0,
                children: [
                  TextButton.icon(
                    onPressed: () => _editarOagregar(grupoPrefill: grupo),
                    icon: Icon(Icons.person_add_alt,
                        size: 18, color: cessumRed),
                    label: Text('Agregar a este grupo',
                        style: TextStyle(color: cessumRed, fontSize: 13)),
                  ),
                  TextButton.icon(
                    onPressed: _ocupado
                        ? null
                        : () =>
                            _corregirProgramaGrupo(programa, integrantes),
                    icon: Icon(Icons.edit_note,
                        size: 18, color: cessumGold),
                    label: Text('Corregir programa del grupo',
                        style: TextStyle(color: cessumGold, fontSize: 13)),
                  ),
                  TextButton.icon(
                    onPressed: _ocupado
                        ? null
                        : () =>
                            _corregirGeneracionGrupo(generacion, integrantes),
                    icon: Icon(Icons.event_repeat,
                        size: 18, color: cessumGold),
                    label: Text('Corregir generación del grupo',
                        style: TextStyle(color: cessumGold, fontSize: 13)),
                  ),
                  TextButton.icon(
                    onPressed: _ocupado
                        ? null
                        : () => _corregirSistemaGrupo(grupo, integrantes),
                    icon: Icon(Icons.swap_horiz,
                        size: 18, color: cessumGold),
                    label: Text('Corregir sistema del grupo',
                        style: TextStyle(color: cessumGold, fontSize: 13)),
                  ),
                  TextButton.icon(
                    onPressed: _ocupado
                        ? null
                        : () => _renombrarGrupo(grupo, integrantes),
                    icon: Icon(Icons.drive_file_rename_outline,
                        size: 18, color: cessumRed),
                    label: Text('Renombrar grupo',
                        style: TextStyle(color: cessumRed, fontSize: 13)),
                  ),
                  TextButton.icon(
                    onPressed: () => _copiarLista(
                        programa, generacion, grupo, integrantes),
                    icon: Icon(Icons.copy_all,
                        size: 18, color: cessumMuted(context)),
                    label: Text('Copiar lista',
                        style:
                            TextStyle(color: cessumMuted(context), fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cessumMuted(context).withValues(alpha: 0.18)),
          ...integrantes.map((g) => _renglonIntegrante(g)),
        ],
      ),
    );
  }

  Widget _renglonIntegrante(_Grupo g) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 14),
      title: Text(g.nombre.isEmpty ? '(sin nombre)' : g.nombre,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text('Matrícula: ${g.matricula}',
          style: TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.drive_file_move_outline,
                size: 19, color: Color(0xFF1565C0)),
            tooltip: 'Mover a otro grupo',
            onPressed: () => _moverAOtroGrupo(g),
          ),
          IconButton(
            icon: Icon(Icons.person_off_outlined,
                size: 19, color: cessumMuted(context)),
            tooltip: 'Dar de baja',
            onPressed: () => _darDeBaja(g),
          ),
          IconButton(
            icon: Icon(Icons.edit, size: 19, color: cessumGold),
            tooltip: 'Corregir',
            onPressed: () => _editarOagregar(base: g),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 19, color: cessumRed),
            tooltip: 'Quitar',
            onPressed: () => _eliminar(g),
          ),
        ],
      ),
    );
  }

  // ===== Buscar alumno =====
  Widget _vistaBuscar() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _busqueda,
                  keyboardType: TextInputType.text,
                  onSubmitted: (_) => _buscar(),
                  decoration: InputDecoration(
                    hintText: 'Matrícula o nombre del alumno',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: cessumEsOscuro(context) ? const Color(0xFF211F1D) : Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _buscando ? null : _buscar,
                  child: Text('Buscar'),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _cuerpoBusqueda()),
      ],
    );
  }

  Widget _cuerpoBusqueda() {
    if (_buscando) {
      return Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_errorBusqueda != null) return _error(_errorBusqueda!, _buscar);
    if (!_busquedaHecha) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Busca a un alumno por matrícula o nombre para ver y corregir su '
            'inscripción. Los alumnos dados de baja aparecen aquí con la '
            'etiqueta BAJA y se pueden reactivar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumMuted(context), height: 1.4),
          ),
        ),
      );
    }
    if (_resultados.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No encontramos a nadie con esa matrícula o nombre.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumMuted(context), height: 1.4),
          ),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 90),
      children: _resultados.map(_tarjetaResultado).toList(),
    );
  }

  Widget _tarjetaResultado(_Grupo g) {
    final tipo = _tipoGrupo(g.programa, g.grupo);
    final esBaja = _bajas.contains(g.matricula.trim());
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumEsOscuro(context) ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: esBaja ? cessumRed : cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(g.nombre.isEmpty ? '(sin nombre)' : g.nombre,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context))),
              ),
              if (esBaja)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('BAJA',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: cessumRed)),
                ),
            ],
          ),
          Text('Matrícula: ${g.matricula}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          SizedBox(height: 8),
          _linea('Programa', g.programa),
          _linea('Generación', g.generacion),
          _linea('Grupo', '${g.grupo}  ($tipo)'),
          if (g.correo.isNotEmpty) _linea('Correo', g.correo),
          Divider(height: 18),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              esBaja
                  ? TextButton.icon(
                      onPressed: () => _reactivar(g),
                      icon: Icon(Icons.undo, size: 16, color: _verdeOk),
                      label: Text('Reactivar',
                          style: TextStyle(color: _verdeOk, fontSize: 13)),
                    )
                  : TextButton.icon(
                      onPressed: () => _darDeBaja(g),
                      icon: Icon(Icons.person_off_outlined,
                          size: 16, color: cessumMuted(context)),
                      label: Text('Dar de baja',
                          style:
                              TextStyle(color: cessumMuted(context), fontSize: 13)),
                    ),
              TextButton.icon(
                onPressed: () => _moverAOtroGrupo(g),
                icon: Icon(Icons.drive_file_move_outline,
                    size: 16, color: Color(0xFF1565C0)),
                label: Text('Mover',
                    style:
                        TextStyle(color: Color(0xFF1565C0), fontSize: 13)),
              ),
              OutlinedButton.icon(
                onPressed: () => _editarOagregar(base: g),
                icon: Icon(Icons.edit, size: 16, color: cessumRed),
                label: Text('Editar',
                    style: TextStyle(color: cessumRed, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cessumRed),
                  minimumSize: Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 20, color: cessumRed),
                tooltip: 'Quitar del grupo',
                onPressed: () => _eliminar(g),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linea(String etq, String valor) {
    if (valor.trim().isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text('$etq:',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          ),
          Expanded(
            child: Text(valor,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cessumInk(context))),
          ),
        ],
      ),
    );
  }

  Widget _error(String msg, VoidCallback reintentar) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            SizedBox(height: 12),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context), height: 1.4)),
            SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: reintentar,
              icon: Icon(Icons.refresh),
              label: Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla de reporte de "Salud de datos": muestra las inconsistencias
/// detectadas en la base de grupos, agrupadas por tipo y expandibles.
class _SaludDatosReporte extends StatelessWidget {
  final int total;
  final Map<String, List<String>> hallazgos;
  const _SaludDatosReporte({required this.total, required this.hallazgos});

  @override
  Widget build(BuildContext context) {
    final totalProblemas =
        hallazgos.values.fold<int>(0, (a, b) => a + b.length);
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Salud de datos'),
      ),
      body: ListView(
        padding: EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    totalProblemas == 0
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: totalProblemas == 0
                        ? Color(0xFF1E8E3E)
                        : cessumGold,
                    size: 30,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      totalProblemas == 0
                          ? 'Revisé $total registros y no encontré problemas.'
                          : 'Revisé $total registros y encontré $totalProblemas posible(s) problema(s).',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 4),
          ...hallazgos.entries.map((e) => _categoria(e.key, e.value)),
          Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Para corregir, vuelve a Grupos y usa "Corregir programa del grupo", '
              '"Corregir generación del grupo" o el lápiz de cada integrante.',
              style: TextStyle(fontSize: 12, color: cessumMuted(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoria(String titulo, List<String> casos) {
    final ok = casos.isEmpty;
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok ? Color(0xFF1E8E3E) : cessumRed,
        ),
        title: Text(titulo,
            style:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(ok ? 'Sin problemas' : '${casos.length} caso(s)',
            style: TextStyle(
                color: ok ? Color(0xFF1E8E3E) : cessumRed,
                fontSize: 12)),
        children: ok
            ? []
            : casos
                .map((c) => ListTile(
                      dense: true,
                      leading: Icon(Icons.chevron_right, size: 18),
                      title:
                          Text(c, style: TextStyle(fontSize: 12.5)),
                    ))
                .toList(),
      ),
    );
  }
}

/// Pantalla "Sincronizar bajas": muestra la vista previa del cruce entre el
/// Formulario de Baja y la base, y permite aplicar las bajas seguras.
class _SincronizarBajasReporte extends StatefulWidget {
  const _SincronizarBajasReporte();
  @override
  State<_SincronizarBajasReporte> createState() =>
      _SincronizarBajasReporteState();
}

class _SincronizarBajasReporteState extends State<_SincronizarBajasReporte> {
  bool _cargando = true;
  bool _aplicando = false;
  String? _error;
  List<Map<String, dynamic>> _seguras = [];
  List<Map<String, dynamic>> _revisar = [];
  bool _aplicado = false;

  @override
  void initState() {
    super.initState();
    _cargar(false);
  }

  Future<void> _cargar(bool aplicar) async {
    setState(() {
      if (aplicar) {
        _aplicando = true;
      } else {
        _cargando = true;
      }
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'bajas_sincronizar',
        if (aplicar) 'aplicar': '1',
      });
      final resp = await http.get(uri).timeout(Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      setState(() {
        _seguras = (data['seguras'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _revisar = (data['revisar'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _aplicado = data['aplicado'] == true;
      });
    } catch (e) {
      setState(() => _error = 'No se pudo sincronizar: $e');
    } finally {
      setState(() {
        _cargando = false;
        _aplicando = false;
      });
    }
  }

  Future<void> _aplicar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Aplicar bajas'),
        content: Text(
            'Se marcarán como BAJA ${_seguras.length} alumno(s) cuya baja '
            'coincide con su generación actual. Los casos "para revisar" NO '
            'se tocan. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              child: Text('Aplicar',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (ok == true) await _cargar(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Sincronizar bajas'),
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? _vistaError()
              : _contenido(),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: cessumFaint(context)),
              SizedBox(height: 12),
              Text(_error ?? '', textAlign: TextAlign.center),
              SizedBox(height: 16),
              ElevatedButton(
                  onPressed: () => _cargar(false),
                  child: Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _contenido() {
    return Column(
      children: [
        if (_aplicado)
          Container(
            width: double.infinity,
            color: Color(0xFF1E8E3E),
            padding: EdgeInsets.all(12),
            child: Text('Listo: se aplicaron ${_seguras.length} baja(s).',
                style: TextStyle(color: Colors.white)),
          ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(12),
            children: [
              _bloque(
                'Bajas seguras (coinciden con su generación)',
                _seguras,
                cessumRed,
                Icons.check_circle_outline,
              ),
              SizedBox(height: 8),
              _bloque(
                'Para revisar (posible reinscripción — no se tocan)',
                _revisar,
                cessumGold,
                Icons.help_outline,
              ),
            ],
          ),
        ),
        if (!_aplicado && _seguras.isNotEmpty)
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _aplicando ? null : _aplicar,
                  icon: _aplicando
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(Icons.person_off),
                  label: Text(_aplicando
                      ? 'Aplicando…'
                      : 'Marcar BAJA a ${_seguras.length} seguro(s)'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bloque(
      String titulo, List<Map<String, dynamic>> items, Color color, IconData ic) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ic, color: color, size: 20),
                SizedBox(width: 6),
                Expanded(
                  child: Text('$titulo  (${items.length})',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              ],
            ),
            Divider(),
            if (items.isEmpty)
              Padding(
                padding: EdgeInsets.all(8),
                child: Text('Ninguno.',
                    style: TextStyle(color: cessumMuted(context), fontSize: 12.5)),
              )
            else
              ...items.map((m) => Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            (m['nombre'] ?? '').toString().isEmpty
                                ? '(sin nombre)'
                                : m['nombre'].toString(),
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                            'Mat. ${m['matricula']} · ${m['programa']} ${m['generacion']} ${m['grupo']}'
                            '${(m['tipo'] ?? '').toString().isNotEmpty ? " · baja ${m['tipo']}" : ""}',
                            style: TextStyle(
                                fontSize: 11.5, color: cessumMuted(context))),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

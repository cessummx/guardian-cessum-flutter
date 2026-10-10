import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'selector_buscable.dart';

/// Admin: promover a un alumno a otro programa (p. ej. de maestría a
/// doctorado) conservando la MISMA matrícula. El backend archiva el kardex
/// de la maestría como historial y deja el avance limpio para el nuevo
/// programa, y actualiza su perfil.
class CambioProgramaScreen extends StatefulWidget {
  const CambioProgramaScreen({super.key});

  @override
  State<CambioProgramaScreen> createState() => _CambioProgramaScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _CambioProgramaScreenState extends State<CambioProgramaScreen> {
  final _nuevoPrograma = TextEditingController();
  final _nuevaGeneracion = TextEditingController();
  String? _progSel;
  String? _genSel;
  String? _grupoSel;

  // (1-oct-2026) Programas y generaciones: antes eran listas fijas en este
  // archivo (sin las generaciones 23-1/23-2, por ejemplo) — ahora salen de
  // generaciones_listar, la misma fuente real que usa el resto de la app.
  List<String> _programasOficiales = [];
  List<String> _generacionesComunes = [];
  bool _cargandoCatalogos = true;

  // (1-oct-2026) Catálogo de grupo destino: las categorías reales que
  // aplican al programa elegido, con cuántos alumnos ya tiene cada una en
  // la generación destino. Se recarga cada vez que cambia programa o
  // generación destino.
  List<Map<String, dynamic>> _gruposDisponibles = [];
  bool _cargandoGrupos = false;

  // Buscador propio: el Autocomplete de Flutter hacia la peticion dentro de su
  // optionsBuilder y, si algo fallaba, _buscarAlumnos devolvia [] en silencio:
  // no salian opciones ni aviso. Aqui se ve el estado (buscando / sin
  // resultados / error) y la lista se dibuja en la pantalla, no en un overlay.
  final TextEditingController _busca = TextEditingController();
  Timer? _debounce;
  List<Map<String, String>> _resultados = [];
  bool _buscando = false;
  String? _errorBusca;

  String _matricula = '';
  String _nombre = '';
  String _progActual = '';
  String _genActual = '';
  String _grupoActual = '';
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargarCatalogos();
  }

  Future<void> _cargarCatalogos() async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=generaciones_listar'))
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _programasOficiales =
              ((data['programas'] as List?) ?? []).map((e) => '$e').toList();
          _generacionesComunes =
              ((data['generaciones'] as List?) ?? []).map((e) => '$e').toList();
          _cargandoCatalogos = false;
        });
      } else {
        setState(() => _cargandoCatalogos = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoCatalogos = false);
    }
  }

  // (1-oct-2026) Carga (o recarga) las categorías de grupo que aplican al
  // programa destino, marcando cuántos alumnos ya tiene cada una en la
  // generación destino. Se llama cada vez que cambian programa o
  // generación destino; limpia la selección previa si ya no aplica.
  Future<void> _cargarGruposDisponibles() async {
    if (_progSel == null) {
      setState(() {
        _gruposDisponibles = [];
        _grupoSel = null;
      });
      return;
    }
    setState(() => _cargandoGrupos = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'grupos_catalogo',
        'programa': _progSel!,
        if (_genSel != null) 'generacion': _genSel!,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        final lista = ((data['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _gruposDisponibles = lista;
          // Si el grupo que tenía elegido ya no está en la lista nueva
          // (cambió de programa), se limpia en vez de dejar algo inválido.
          if (_grupoSel != null &&
              !lista.any((g) => g['grupo'] == _grupoSel)) {
            _grupoSel = null;
          }
          _cargandoGrupos = false;
        });
      } else {
        setState(() {
          _gruposDisponibles = [];
          _cargandoGrupos = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _gruposDisponibles = [];
          _cargandoGrupos = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busca.dispose();
    _nuevoPrograma.dispose();
    _nuevaGeneracion.dispose();
    super.dispose();
  }

  void _alTeclear(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _resultados = [];
        _errorBusca = null;
        _buscando = false;
      });
      return;
    }
    setState(() => _buscando = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final r = await _buscarAlumnos(v);
      if (!mounted) return;
      setState(() {
        _resultados = r;
        _buscando = false;
      });
    });
  }

  Future<List<Map<String, String>>> _buscarAlumnos(String q) async {
    if (q.trim().length < 2) return [];
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'grupos_admin_buscar',
        'q': q.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        if (mounted) {
          setState(() => _errorBusca =
              (data['error'] ?? 'El servidor no devolvió resultados.').toString());
        }
        return [];
      }
      if (mounted) setState(() => _errorBusca = null);
      return ((data['grupos'] as List<dynamic>? ?? [])).map((e) {
        final m = e as Map<String, dynamic>;
        return {
          'matricula': (m['matricula'] ?? '').toString(),
          'nombre': (m['nombre'] ?? '').toString(),
          'programa': (m['programa'] ?? '').toString(),
          'generacion': (m['generacion'] ?? '').toString(),
          'grupo': (m['grupo'] ?? '').toString(),
        };
      }).where((m) => (m['matricula'] ?? '').isNotEmpty).toList();
    } catch (e) {
      if (mounted) {
        setState(() => _errorBusca = 'No me pude conectar para buscar.');
      }
      return [];
    }
  }

  void _elegirAlumno(Map<String, String> o) {
    setState(() {
      _matricula = o['matricula'] ?? '';
      _nombre = o['nombre'] ?? '';
      _progActual = o['programa'] ?? '';
      _genActual = o['generacion'] ?? '';
      _grupoActual = o['grupo'] ?? '';
      _busca.text = '${o['nombre']} · ${o['matricula']}';
      _resultados = [];
    });
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // Para comparar programa destino vs actual sin que un acento o una
  // mayúscula distinta esconda que en realidad son el mismo.
  String _normaTexto(String s) {
    s = s.toLowerCase().trim();
    const a = 'áàäâéèëêíìïîóòöôúùüûñ';
    const b = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s;
  }

  Future<void> _promover() async {
    if (_matricula.isEmpty) {
      _aviso('Primero elige al alumno.');
      return;
    }
    if (_nuevoPrograma.text.trim().isEmpty ||
        _nuevaGeneracion.text.trim().isEmpty) {
      _aviso('Escribe el programa y la generación destino.');
      return;
    }
    // (1-oct-2026) Destino = origen: esto archivaría el kárdex actual del
    // alumno sin necesidad. El backend ya lo bloquea, pero avisar aquí
    // evita que se arme el diálogo de confirmación para nada.
    if (_normaTexto(_nuevoPrograma.text.trim()) == _normaTexto(_progActual) &&
        _nuevaGeneracion.text.trim() == _genActual) {
      _aviso('El programa y la generación destino son los mismos que ya tiene '
          'el alumno. Para cambiar solo de grupo, usa "Mover grupo".');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cambio de programa'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_nombre · $_matricula',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text('De: $_progActual'
                  '${_genActual.isNotEmpty ? " · Gen. $_genActual" : ""}',
                  style: const TextStyle(color: Colors.black54)),
              Text('A: ${_nuevoPrograma.text.trim()} · '
                  'Gen. ${_nuevaGeneracion.text.trim()}',
                  style: const TextStyle(
                      color: cessumRed, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              const Text(
                'Su avance de la maestría se guardará como HISTORIAL y el '
                'avance del nuevo programa empezará limpio. Conserva la misma '
                'matrícula. Esta acción se puede consultar después.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Promover'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _enviando = true);
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'alumno_promover',
              'actor': correo,
              'matricula': _matricula,
              'nuevoPrograma': _nuevoPrograma.text.trim(),
              'nuevaGeneracion': _nuevaGeneracion.text.trim(),
              'nuevoGrupo': _grupoSel ?? '',
            }),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        setState(() => _enviando = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Listo'),
            content: Text(
                '$_nombre cambió a ${_nuevoPrograma.text.trim()}. '
                'Su avance anterior quedó guardado como historial.'),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(ctx);
                  _resetear();
                },
                child: const Text('Aceptar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _enviando = false);
      _aviso('No se pudo promover: $e'.replaceAll('Exception: ', ''));
    }
  }

  void _resetear() {
    setState(() {
      _matricula = '';
      _nombre = '';
      _progActual = '';
      _genActual = '';
      _grupoActual = '';
      _nuevoPrograma.clear();
      _nuevaGeneracion.clear();
      _progSel = null;
      _genSel = null;
      _grupoSel = null;
      _gruposDisponibles = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Cambio de programa'),
      ),
      body: _enviando
          ? const Center(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: cessumRed),
                SizedBox(height: 12),
                Text('Procesando…'),
              ],
            ))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Promueve a un alumno a otro programa (por ejemplo, de '
                    'maestría a doctorado) con la misma matrícula. Su avance '
                    'de la maestría se conserva como historial y el nuevo '
                    'programa empieza limpio.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.black54, height: 1.35),
                  ),
                ),
                _seccion('Alumno'),
                TextField(
                  controller: _busca,
                  onChanged: _alTeclear,
                  decoration: InputDecoration(
                    labelText: 'Buscar por nombre o matrícula *',
                    hintText: 'Escribe al menos 2 letras',
                    prefixIcon: const Icon(Icons.search, color: cessumRed),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _buscando
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cessumRed),
                            ),
                          )
                        : (_busca.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() {
                                  _busca.clear();
                                  _resultados = [];
                                  _errorBusca = null;
                                  _matricula = '';
                                }),
                              )
                            : null),
                  ),
                ),
                if (_errorBusca != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_errorBusca!,
                        style: const TextStyle(
                            color: cessumRed, fontSize: 12)),
                  ),
                // Sin resultados: se dice, en vez de dejar el campo mudo.
                if (!_buscando &&
                    _errorBusca == null &&
                    _resultados.isEmpty &&
                    _matricula.isEmpty &&
                    _busca.text.trim().length >= 2)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Sin coincidencias. Prueba con la matrícula o con menos palabras.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                if (_resultados.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _resultados.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final o = _resultados[i];
                        return ListTile(
                          dense: true,
                          title: Text((o['nombre'] ?? '').toString(),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13.5)),
                          subtitle: Text(
                            'Mat. ${o['matricula']} · ${o['programa']} · ${o['generacion']}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          onTap: () => _elegirAlumno(o),
                        );
                      },
                    ),
                  ),
                if (_matricula.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.check_circle,
                              color: _verdeOk, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('$_nombre · $_matricula',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            'Actual: $_progActual'
                            '${_genActual.isNotEmpty ? " · Gen. $_genActual" : ""}'
                            '${_grupoActual.isNotEmpty ? " · $_grupoActual" : ""}',
                            style: const TextStyle(
                                fontSize: 12.5, color: Colors.black54)),
                      ],
                    ),
                  ),
                ],
                _seccion('Programa destino'),
                if (_cargandoCatalogos)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CessumSelectorBuscable<String>(
                      label: 'Nuevo programa *',
                      valor: _progSel,
                      opciones: _programasOficiales,
                      etiqueta: (p) => p,
                      onChanged: (v) {
                        setState(() {
                          _progSel = v;
                          _nuevoPrograma.text = v ?? '';
                        });
                        _cargarGruposDisponibles();
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: CessumSelectorBuscable<String>(
                      label: 'Nueva generación *',
                      valor: _genSel,
                      opciones: _generacionesComunes,
                      etiqueta: (g) => g,
                      onChanged: (v) {
                        setState(() {
                          _genSel = v;
                          _nuevaGeneracion.text = v ?? '';
                        });
                        _cargarGruposDisponibles();
                      },
                    ),
                  ),
                ],
                // (1-oct-2026) Nuevo grupo: desplegable con las categorías
                // reales (_grupoCanonico_), no texto libre. Se recarga al
                // cambiar programa o generación destino, y muestra cuántos
                // alumnos ya tiene cada categoría en esa generación.
                if (_progSel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _cargandoGrupos
                        ? const LinearProgressIndicator()
                        : CessumSelectorBuscable<String>(
                            label: 'Nuevo grupo (opcional)',
                            valor: _grupoSel,
                            opciones: _gruposDisponibles
                                .map((g) => g['grupo'] as String)
                                .toList(),
                            etiqueta: (g) {
                              final item = _gruposDisponibles
                                  .firstWhere((e) => e['grupo'] == g);
                              final n = (item['alumnos'] as num?) ?? 0;
                              return n > 0 ? '$g · $n alumno(s)' : g;
                            },
                            textoNinguno: 'Conservar el grupo actual del alumno',
                            onChanged: (v) => setState(() => _grupoSel = v),
                          ),
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _promover,
                    icon: const Icon(Icons.school),
                    label: const Text('Promover / cambiar de programa'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _seccion(String t) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed)),
    );
  }

}

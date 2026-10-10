import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Clasificación de alumnos: Activo, Baja, Egresado, Titulado.
/// Activo y Egresado se calculan solos; Baja se detecta de la base y de las
/// solicitudes validadas; Titulado es manual. El admin puede sobreescribir
/// cualquier alumno y volver al cálculo automático.
class ClasificacionAlumnosScreen extends StatefulWidget {
  const ClasificacionAlumnosScreen({super.key});

  @override
  State<ClasificacionAlumnosScreen> createState() =>
      _ClasificacionAlumnosScreenState();
}

const Map<String, Color> _colores = {
  'Activo': Color(0xFF1E8E3E),
  'Baja': cessumRed,
  'Egresado': cessumGold,
  'Titulado': Color(0xFF1A73C2),
};

class _ClasificacionAlumnosScreenState
    extends State<ClasificacionAlumnosScreen> {
  final TextEditingController _busqueda = TextEditingController();
  bool _cargando = true;
  DateTime? _ultimaCarga;
  String? _error;
  List<Map<String, dynamic>> _todos = [];
  Map<String, int> _conteo = {};
  String _filtro = 'Todos';

  static const List<String> _tipos = ['Activo', 'Baja', 'Egresado', 'Titulado'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
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
          .replace(queryParameters: {'accion': 'clasificacion_alumnos'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _todos = (data['alumnos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final c = Map<String, dynamic>.from(data['conteo'] as Map? ?? {});
      _conteo = c.map((k, v) => MapEntry(k, (v as num).toInt()));
      if (mounted) {
        setState(() {
          _cargando = false;
          _ultimaCarga = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar. Revisa tu conexión.';
        });
      }
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
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

  List<Map<String, dynamic>> get _filtrados {
    final q = _norm(_busqueda.text.trim());
    return _todos.where((a) {
      if (_filtro != 'Todos' && a['tipo'] != _filtro) return false;
      if (q.isEmpty) return true;
      final txt = _norm(
          '${a['nombre']} ${a['matricula']} ${a['programa']} ${a['generacion']}');
      return txt.contains(q);
    }).toList();
  }

  Future<void> _post(Map<String, dynamic> body, String okMsg) async {
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso(okMsg);
      await _cargar();
    } catch (_) {
      _aviso('No se pudo completar la acción.');
    }
  }

  Future<void> _cambiar(Map<String, dynamic> a) async {
    final esManual = a['origen'] == 'manual';
    final eleccion = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${a['nombre']}\nMatrícula: ${a['matricula']}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            ..._tipos.map((t) => ListTile(
                  leading: Icon(Icons.circle, color: _colores[t], size: 14),
                  title: Text('Marcar como $t'),
                  trailing: a['tipo'] == t
                      ? const Icon(Icons.check, color: Colors.black45)
                      : null,
                  onTap: () => Navigator.pop(context, t),
                )),
            if (esManual)
              ListTile(
                leading: const Icon(Icons.auto_mode, color: Colors.black54),
                title: const Text('Volver al cálculo automático'),
                onTap: () => Navigator.pop(context, '__auto__'),
              ),
            // (ago-21) POR PROGRAMA, PARA QUIEN CURSÓ MÁS DE UNO.
            //
            // El estatus de arriba es UNO por alumno. Con quien egresó de la
            // maestría y sigue en el doctorado, marcarlo «Egresado» dice que
            // egresó del doctorado —su programa vigente— y eso es falso.
            // Aquí se registra por programa: egresado de uno, activo en otro.
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.school_outlined, color: cessumGold),
              title: const Text('Estatus por programa',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Para quien cursó más de un programa: egresado de uno y '
                  'activo en otro.',
                  style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(context, '__porPrograma__'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (eleccion == null) return;
    if (eleccion == '__porPrograma__') {
      await _porPrograma(a);
      return;
    }
    if (eleccion == '__auto__') {
      await _post(
          {'accion': 'clasificacion_quitar', 'matricula': a['matricula']},
          'Volvió a clasificación automática.');
    } else {
      await _post({
        'accion': 'clasificacion_fijar',
        'matricula': a['matricula'],
        'tipo': eleccion,
        'nombre': a['nombre'],
      }, 'Marcado como $eleccion.');
    }
  }

  /// Muestra los programas del alumno y deja fijar el estatus de cada uno.
  ///
  /// El estatus general no se toca: sigue siendo el del programa vigente, y
  /// todo lo que hoy depende de él sigue igual. Esto es historial, no
  /// reemplazo.
  Future<void> _porPrograma(Map<String, dynamic> a) async {
    Map<String, dynamic>? datos;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'historial_programa',
            'matricula': '${a['matricula']}',
          }))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) datos = d;
    } catch (_) {}

    if (!mounted) return;
    if (datos == null) {
      _aviso('No se pudo leer su historial.');
      return;
    }
    final progs = (datos['programas'] as List?) ?? [];
    if (progs.isEmpty) {
      _aviso('No se le encontró ningún programa.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text('${a['nombre']}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              Text(
                  progs.length > 1
                      ? 'Cursó ${progs.length} programas. Cada uno con su propio estatus.'
                      : 'Un solo programa registrado.',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black54)),
            ]),
          ),
          const Divider(height: 1),
          ...progs.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final sinRegistrar = '${m['estatus']}' == '(sin registrar)';
            return ListTile(
              title: Text('${m['programa']}',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  sinRegistrar
                      ? '${m['porQue'] ?? 'Sin registrar'}'
                      : '${m['estatus']}${m['fuente'] == 'deducido' ? ' (deducido)' : ''}',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: sinRegistrar ? cessumRed : Colors.black54)),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () async {
                Navigator.pop(context);
                await _fijarPrograma(
                    a,
                    '${m['programa']}',
                    ((datos!['estatusPosibles'] as List?) ?? [])
                        .map((x) => '$x')
                        .toList());
              },
            );
          }),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  Future<void> _fijarPrograma(
      Map<String, dynamic> a, String programa, List<String> opciones) async {
    final elegido = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(programa,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const Divider(height: 1),
          ...opciones.map((o) => ListTile(
                leading: Icon(Icons.circle,
                    size: 14, color: _colores[o] ?? Colors.black45),
                title: Text('Marcar como $o'),
                onTap: () => Navigator.pop(context, o),
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (elegido == null) return;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'historial_programa_fijar',
            'matricula': '${a['matricula']}',
            'programa': programa,
            'estatus': elegido,
            'actor': 'vicerrectoria@cessum.mx',
          }))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      _aviso('${d['nota'] ?? d['error'] ?? ''}');
      if (d['ok'] == true) await _cargar();
    } catch (e) {
      if (mounted) _aviso('No se pudo guardar.');
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Clasificación de alumnos'),
        actions: [
          IconButton(
              onPressed: _filtrados.isEmpty ? null : _copiarExcel,
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copiar para Excel'),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _contenido(),
    );
  }

  /// Copia la lista filtrada en formato tabular (TSV) para pegar en Excel.
  void _copiarExcel() {
    final lista = _filtrados;
    if (lista.isEmpty) return;
    final b = StringBuffer()
      ..writeln('Tipo\tMatrícula\tNombre\tPrograma\tGeneración\tModalidad');
    for (final a in lista) {
      b.writeln([
        a['tipo'] ?? '',
        a['matricula'] ?? '',
        a['nombre'] ?? '',
        a['programa'] ?? '',
        a['generacion'] ?? '',
        a['modalidad'] ?? '',
      ].join('\t'));
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Clasificación (${lista.length})');
  }

  Widget _contenido() {
    final lista = _filtrados;
    return Column(
      children: [
        if (_ultimaCarga != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                Helpers.haceTexto(_ultimaCarga),
                style: const TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _busqueda,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o matrícula',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              _chip('Todos', _todos.length),
              ..._tipos.map((t) => _chip(t, _conteo[t] ?? 0)),
            ],
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? const Center(
                  child: Text('Sin alumnos en este filtro.',
                      style: TextStyle(color: Colors.black54)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _tarjeta(lista[i]),
                ),
        ),
      ],
    );
  }

  Widget _chip(String etiqueta, int n) {
    final activo = _filtro == etiqueta;
    final color = _colores[etiqueta] ?? cessumRed;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(
        label: Text('$etiqueta ($n)'),
        selected: activo,
        selectedColor: color,
        labelStyle: TextStyle(
            color: activo ? Colors.white : Colors.black87, fontSize: 13),
        backgroundColor: Colors.white,
        onSelected: (_) => setState(() => _filtro = etiqueta),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final tipo = (a['tipo'] ?? '').toString();
    final color = _colores[tipo] ?? Colors.black54;
    final manual = a['origen'] == 'manual';
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((a['nombre'] ?? '').toString().isEmpty
                    ? 'Matrícula ${a['matricula']}'
                    : a['nombre'].toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.black87)),
                const SizedBox(height: 2),
                Text(
                    '${a['matricula']}  ·  ${a['programa']}'
                    '${a['generacion'].toString().isNotEmpty ? '  ·  ${a['generacion']}' : ''}',
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.black54)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(tipo,
                          style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text(manual ? 'manual' : 'automático',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black38)),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _cambiar(a),
            child: const Text('Cambiar'),
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
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 14),
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
}

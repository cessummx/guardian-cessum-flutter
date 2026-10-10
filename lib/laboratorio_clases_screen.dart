// ===========================================================================
//  LABORATORIO DE CLASES (8-oct-2026)
//  ---------------------------------------------------------------------------
//  Entorno de práctica para que CUALQUIER docente genere presentaciones y
//  planeaciones de CUALQUIER materia del catálogo institucional (no solo las
//  que tiene asignadas), pensado para un taller/convocatoria con varios
//  profesores a la vez.
//
//  Lo que lo distingue del flujo normal de «Material didáctico»:
//    · La materia se elige de todo el catálogo (misma fuente que usa la
//      convocatoria docente: docsol_catalogo, el plan de estudios real),
//      no de «Mis materias» del docente.
//    · No se arma ligado a un grupo real: usa un marcador "Laboratorio" en
//      generación y grupo, así que el botón «Colocar en el aula» de los
//      generadores no encuentra ninguna, y nada se coloca de verdad.
//    · Lo que se genere aquí entra IGUAL que siempre al Banco de
//      presentaciones (diapo_banco ya muestra todo, venga de donde venga).
//    · Las planeaciones de aquí pasan por la MISMA validación de
//      Vicerrectoría que una planeación real antes de poder aparecer en el
//      Banco de Planeaciones — no es una vía corta.
// ===========================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'generador_diapositivas_screen.dart';
import 'planeacion_didactica_screen.dart';

class LaboratorioClasesScreen extends StatefulWidget {
  const LaboratorioClasesScreen({super.key});
  @override
  State<LaboratorioClasesScreen> createState() => _LaboratorioClasesScreenState();
}

class _LaboratorioClasesScreenState extends State<LaboratorioClasesScreen> {
  int _paso = 0; // 0 programa · 1 materia · 2 elegir qué crear
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _programas = []; // {programa, nivel, asignaturas:[{clave,nombre,ciclo,fines,contenido}]}
  Map<String, dynamic>? _programaSel;
  Map<String, dynamic>? _materiaSel;

  final _filtroPrograma = TextEditingController();
  final _filtroMateria = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
  }

  @override
  void dispose() {
    _filtroPrograma.dispose();
    _filtroMateria.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _comoListaMapas(dynamic l) {
    if (l is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final x in l) {
      if (x is Map) out.add(Map<String, dynamic>.from(x));
    }
    return out;
  }

  Future<void> _cargarCatalogo() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=docsol_catalogo'
              '&z=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo cargar el catálogo de materias.');
      if (!mounted) return;
      setState(() {
        _programas = _comoListaMapas(j['catalogo']);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  List<Map<String, dynamic>> get _programasFiltrados {
    final q = _filtroPrograma.text.trim().toLowerCase();
    if (q.isEmpty) return _programas;
    return _programas.where((p) => '${p['programa'] ?? ''}'.toLowerCase().contains(q)).toList();
  }

  List<Map<String, dynamic>> get _materiasFiltradas {
    final asigs = _comoListaMapas(_programaSel?['asignaturas']);
    final q = _filtroMateria.text.trim().toLowerCase();
    if (q.isEmpty) return asigs;
    return asigs.where((m) => '${m['nombre'] ?? ''}'.toLowerCase().contains(q)).toList();
  }

  Map<String, String> _grupoLaboratorio() {
    return {
      'programa': '${_programaSel?['programa'] ?? ''}',
      'materia': '${_materiaSel?['nombre'] ?? ''}',
      'clave': '${_materiaSel?['clave'] ?? ''}',
      'generacion': 'Laboratorio',
      'grupo': 'Laboratorio',
    };
  }

  void _crearPresentacion() {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => GeneradorDiapositivasScreen(grupoInicial: _grupoLaboratorio())));
  }

  void _crearPlaneacion() {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => PlaneacionDidacticaScreen(grupoInicial: _grupoLaboratorio())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Laboratorio de clases'),
      ),
      body: SafeArea(
        child: Column(children: [
          _banner(),
          Expanded(child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error.isNotEmpty
                  ? _errorView()
                  : _paso == 0
                      ? _pasoPrograma()
                      : _paso == 1
                          ? _pasoMateria()
                          : _pasoElegirQueCrear()),
        ]),
      ),
    );
  }

  Widget _banner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3E3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.science_outlined, color: cessumGold.computeLuminance() > 0.6 ? Colors.black87 : cessumGold),
        const SizedBox(width: 10),
        const Expanded(child: Text(
          'Aquí puedes practicar con CUALQUIER materia del catálogo, no solo las tuyas. '
          'Nada de lo que generes aquí se coloca en un aula real. Las presentaciones se suman '
          'al Banco de presentaciones; las planeaciones pasan primero por la validación de '
          'Vicerrectoría antes de entrar al Banco de Planeaciones.',
          style: TextStyle(fontSize: 12.5, height: 1.35),
        )),
      ]),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _cargarCatalogo, child: const Text('Reintentar')),
        ]),
      ),
    );
  }

  Widget _pasoPrograma() {
    final lista = _programasFiltrados;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          controller: _filtroPrograma,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar programa…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _filtroPrograma.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _filtroPrograma.clear()),
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: lista.isEmpty
            ? const Center(child: Text('No hay programas que coincidan con la búsqueda.'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final p = lista[i];
                  final n = _comoListaMapas(p['asignaturas']).length;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.school_outlined, color: cessumRed),
                      title: Text('${p['programa'] ?? ''}'),
                      subtitle: Text('${p['nivel'] ?? ''} · $n materia(s)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() {
                        _programaSel = p;
                        _materiaSel = null;
                        _filtroMateria.clear();
                        _paso = 1;
                      }),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _pasoMateria() {
    final lista = _materiasFiltradas;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() { _paso = 0; }),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text('${_programaSel?['programa'] ?? ''}'),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          controller: _filtroMateria,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar materia…',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _filtroMateria.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _filtroMateria.clear()),
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: lista.isEmpty
            ? const Center(child: Text('No hay materias que coincidan con la búsqueda.'))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: lista.length,
                itemBuilder: (_, i) {
                  final m = lista[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.menu_book_outlined, color: cessumGold),
                      title: Text('${m['nombre'] ?? ''}'),
                      subtitle: Text('${m['clave'] ?? ''}'
                          '${('${m['ciclo'] ?? ''}'.isNotEmpty) ? ' · ciclo ${m['ciclo']}' : ''}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() {
                        _materiaSel = m;
                        _paso = 2;
                      }),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _pasoElegirQueCrear() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() { _paso = 1; }),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text('${_materiaSel?['nombre'] ?? ''}'),
            ),
          ),
          const SizedBox(height: 8),
          Text('${_programaSel?['programa'] ?? ''}',
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          Text('${_materiaSel?['nombre'] ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 28),
          SizedBox(
            width: 320,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _crearPresentacion,
              icon: const Icon(Icons.slideshow_outlined),
              label: const Text('Crear presentación'),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 320,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed, side: const BorderSide(color: cessumRed),
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _crearPlaneacion,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Crear planeación'),
            ),
          ),
        ]),
      ),
    );
  }
}

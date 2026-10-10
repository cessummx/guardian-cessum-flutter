// =====================================================================
//  CORREGIR GRUPO DE ALUMNO (4-oct-2026) · caso Katya Lissette Ramírez.
//  Para reingresos o altas que quedaron en el grupo equivocado (por
//  ejemplo, sabatino registrado en «1 - entre semana»).
//  1. Buscar al alumno (matrícula o nombre).
//  2. Elegir el grupo destino (solo los que existen en su programa y
//     generación).
//  3. Vista previa: materias en curso y futuras que tendrá, y aulas del
//     grupo anterior que quedarán por revisar.
//  4. Confirmar: lo mueve de grupo (arrastrando el override de padrón para
//     que no se revierta) y lo inscribe en Moodle en sus aulas vigentes.
//  No envía correos. Rutas: grupos_admin_buscar · alumno_corregir_grupo.
// =====================================================================
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const Color _verde = Color(0xFF1E7B34);
const Color _ambar = Color(0xFFB7791F);

class CorregirGrupoAlumnoScreen extends StatefulWidget {
  const CorregirGrupoAlumnoScreen({super.key});
  @override
  State<CorregirGrupoAlumnoScreen> createState() => _CorregirGrupoAlumnoScreenState();
}

class _CorregirGrupoAlumnoScreenState extends State<CorregirGrupoAlumnoScreen> {
  final _buscar = TextEditingController();
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  String _errorBusqueda = '';

  Map<String, dynamic>? _elegido;       // fila de la base de Grupos
  List<String> _grupos = [];
  String _destino = '';
  Map<String, dynamic>? _previa;
  Map<String, dynamic>? _hecho;
  bool _trabajando = false;
  String _error = '';

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  Future<Map<String, dynamic>> _get(Map<String, String> q, {int segundos = 90}) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: {...q, 'actor': await _actor()});
    final r = await http.get(uri).timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _hacerBusqueda() async {
    final q = _buscar.text.trim();
    if (q.length < 3) {
      setState(() => _errorBusqueda = 'Escribe al menos 3 caracteres (matrícula o parte del nombre).');
      return;
    }
    setState(() { _buscando = true; _errorBusqueda = ''; _resultados = []; _limpiarSeleccion(); });
    try {
      final d = await _get({'accion': 'grupos_admin_buscar', 'q': q});
      if (!mounted) return;
      final lista = ((d['grupos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _buscando = false;
        if (d['ok'] != true) {
          _errorBusqueda = '${d['error'] ?? 'No se pudo buscar.'}';
        } else {
          _resultados = lista;
          if (lista.isEmpty) _errorBusqueda = 'Nadie coincide con «$q».';
        }
      });
    } catch (_) {
      if (mounted) setState(() { _buscando = false; _errorBusqueda = 'No se pudo buscar (conexión). Intenta de nuevo.'; });
    }
  }

  void _limpiarSeleccion() {
    _elegido = null; _grupos = []; _destino = ''; _previa = null; _hecho = null; _error = '';
  }

  Future<void> _elegir(Map<String, dynamic> fila) async {
    final grupo = '${fila['grupo'] ?? ''}';
    if (grupo.toUpperCase().contains('BAJA')) {
      setState(() { _limpiarSeleccion(); _error = 'Esa inscripción está dada de baja. Si reingresó, búscala en su programa nuevo.'; });
      return;
    }
    setState(() { _limpiarSeleccion(); _elegido = fila; _trabajando = true; });
    try {
      final d = await _get({'accion': 'alumno_corregir_grupo', 'matricula': '${fila['matricula']}', 'programa': '${fila['programa']}'});
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        if (d['ok'] != true) {
          _error = '${d['error'] ?? 'No se pudo leer su grupo.'}';
        } else {
          _grupos = ((d['gruposDisponibles'] as List?) ?? []).map((e) => '$e').toList();
          if (_grupos.isEmpty) _error = 'Su programa y generación no tienen otro grupo al cual moverlo.';
        }
      });
    } catch (_) {
      if (mounted) setState(() { _trabajando = false; _error = 'No se pudieron leer los grupos (conexión).'; });
    }
  }

  Future<void> _verPrevia(String destino) async {
    final f = _elegido;
    if (f == null) return;
    setState(() { _destino = destino; _previa = null; _hecho = null; _error = ''; _trabajando = true; });
    try {
      final d = await _get({'accion': 'alumno_corregir_grupo', 'matricula': '${f['matricula']}', 'programa': '${f['programa']}', 'grupo': destino});
      if (!mounted) return;
      setState(() { _trabajando = false; if (d['ok'] == true) { _previa = d; } else { _error = '${d['error'] ?? 'No se pudo preparar la vista previa.'}'; } });
    } catch (_) {
      if (mounted) setState(() { _trabajando = false; _error = 'No se pudo preparar la vista previa (conexión).'; });
    }
  }

  Future<void> _confirmar() async {
    final f = _elegido, p = _previa;
    if (f == null || p == null) return;
    final al = Map<String, dynamic>.from((p['alumno'] as Map?) ?? {});
    final aulas = ((p['materiasQueTendra'] as List?) ?? []).where((e) => '${(e as Map)['courseid'] ?? ''}'.isNotEmpty).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cambio de grupo'),
        content: Text('${al['nombre']} (${al['matricula']})\n'
            '${al['programa']} · ${al['generacion']}\n\n'
            'De «${al['grupoActual']}» a «${al['grupoDestino']}».\n'
            'Se le inscribirá en $aulas aula(s) de Moodle.\n\n'
            'No se envía ningún correo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cambiar de grupo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _trabajando = true; _error = ''; });
    try {
      final d = await _get({'accion': 'alumno_corregir_grupo', 'matricula': '${f['matricula']}', 'programa': '${f['programa']}',
        'grupo': _destino, 'confirmar': '1'}, segundos: 180);
      if (!mounted) return;
      setState(() { _trabajando = false; if (d['ok'] == true) { _hecho = d; } else { _error = '${d['error'] ?? 'No se pudo hacer el cambio.'}'; } });
    } catch (_) {
      if (mounted) setState(() { _trabajando = false; _error = 'La conexión se cortó; el cambio pudo haberse hecho. Vuelve a buscar al alumno para revisar su grupo.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(backgroundColor: cessumRed, foregroundColor: Colors.white, title: const Text('Corregir grupo de alumno')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
          Text('Para alumnos que quedaron en el grupo equivocado (por ejemplo, un reingreso sabatino registrado entre semana). '
              'Lo mueve de grupo y lo inscribe en sus aulas vigentes de Moodle. No envía correos.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4)),
          const SizedBox(height: 12),
          _paso1(),
          if (_elegido != null) ...[const SizedBox(height: 12), _paso2()],
          if (_previa != null && _hecho == null) ...[const SizedBox(height: 12), _paso3()],
          if (_hecho != null) ...[const SizedBox(height: 12), _resultado()],
          if (_error.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error, style: const TextStyle(color: cessumRed, fontWeight: FontWeight.w600))),
        ]),
        if (_trabajando) Container(color: Colors.black12, child: const Center(child: CircularProgressIndicator(color: cessumRed))),
      ]),
    );
  }

  Widget _tarjeta(String titulo, List<Widget> hijos) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: cessumRed)),
            const SizedBox(height: 10),
            ...hijos,
          ]),
        ),
      );

  Widget _paso1() => _tarjeta('1. Busca al alumno', [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _buscar,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _hacerBusqueda(),
              decoration: const InputDecoration(labelText: 'Matrícula o nombre', isDense: true, prefixIcon: Icon(Icons.search)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: _buscando ? null : _hacerBusqueda,
            child: const Text('Buscar'),
          ),
        ]),
        if (_buscando) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(color: cessumRed)),
        if (_errorBusqueda.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 10), child: Text(_errorBusqueda, style: const TextStyle(color: cessumRed))),
        ..._resultados.map((r) {
          final sel = _elegido != null && '${_elegido!['matricula']}' == '${r['matricula']}' && '${_elegido!['programa']}' == '${r['programa']}';
          final baja = '${r['grupo'] ?? ''}'.toUpperCase().contains('BAJA');
          return Card(
            margin: const EdgeInsets.only(top: 8),
            color: sel ? cessumRed.withValues(alpha: 0.07) : null,
            child: ListTile(
              dense: true,
              onTap: () => _elegir(r),
              title: Text('${r['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${r['matricula']} · ${r['programa']} · ${r['generacion']} · ${r['grupo']}',
                  style: TextStyle(fontSize: 12, color: baja ? _ambar : cessumMuted(context))),
              trailing: Icon(sel ? Icons.check_circle : Icons.chevron_right, color: sel ? cessumRed : cessumMuted(context)),
            ),
          );
        }),
      ]);

  Widget _paso2() => _tarjeta('2. Elige el grupo correcto', [
        Text('${_elegido!['nombre']} · grupo actual: «${_elegido!['grupo']}»', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in _grupos)
            ChoiceChip(
              label: Text(g),
              selected: _destino == g,
              selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: _trabajando ? null : (_) => _verPrevia(g),
            ),
        ]),
      ]);

  Widget _materia(Map<String, dynamic> m, {bool tachada = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(tachada ? Icons.remove_circle_outline : Icons.class_outlined, size: 18, color: tachada ? _ambar : _verde),
          const SizedBox(width: 8),
          Expanded(child: Text('${m['materia']} · ${m['docente'] ?? ''}\n${m['dia'] ?? ''} ${m['hora'] ?? ''}'
              '${'${m['courseid'] ?? ''}'.isEmpty ? ' · sin aula registrada' : ' · aula ${m['courseid']}'}',
              style: const TextStyle(fontSize: 12.5, height: 1.4))),
        ]),
      );

  Widget _paso3() {
    final p = _previa!;
    final al = Map<String, dynamic>.from((p['alumno'] as Map?) ?? {});
    final nuevas = ((p['materiasQueTendra'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final viejas = ((p['aulasDelGrupoAnterior'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final sinAula = ((p['sinAula'] as List?) ?? []).map((e) => '$e').toList();
    if (p['yaEstaEnElGrupo'] == true) {
      return _tarjeta('3. Vista previa', [Text('${p['nota']}', style: const TextStyle(fontSize: 13, height: 1.4))]);
    }
    return _tarjeta('3. Vista previa', [
      Text('De «${al['grupoActual']}» a «${al['grupoDestino']}»', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      const Text('Materias en curso y futuras que tendrá:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (nuevas.isEmpty) Text('Su grupo nuevo no tiene materias vigentes registradas.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      ...nuevas.map((m) => _materia(m)),
      if (sinAula.isNotEmpty)
        Text('Sin aula registrada en la Agenda: ${sinAula.join(', ')}. No se le podrá inscribir ahí hasta que se registre.',
            style: const TextStyle(fontSize: 12, color: _ambar)),
      if (viejas.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Aulas de su grupo anterior (se revisan a mano después):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...viejas.map((m) => _materia(m, tachada: true)),
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
          onPressed: _trabajando ? null : _confirmar,
          icon: const Icon(Icons.swap_horiz),
          label: Text('Cambiar a «${al['grupoDestino']}»'),
        ),
      ),
    ]);
  }

  Widget _resultado() {
    final d = _hecho!;
    final inscrita = ((d['inscritaEnMoodle'] as List?) ?? []).map((e) => '$e').toList();
    final fallos = ((d['fallosMoodle'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final quitar = ((d['quitarAMano'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _verde.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(14), border: Border.all(color: _verde.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.check_circle, color: _verde), SizedBox(width: 8), Text('Cambio hecho', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _verde))]),
        const SizedBox(height: 8),
        Text('${d['nota'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.4)),
        if (d['overrideSincronizado'] == true)
          Text('El override de padrón también se actualizó: el cambio no se revierte.', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        if (inscrita.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Inscrito en Moodle: ${inscrita.join(', ')}', style: const TextStyle(fontSize: 12.5))),
        ...fallos.map((x) => Text('No se pudo inscribir en ${x['materia']}: ${x['error']}', style: const TextStyle(fontSize: 12.5, color: cessumRed))),
        if (quitar.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Revisa estas aulas del grupo anterior y quítalo de los participantes:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ...quitar.map((x) => TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cessumRed, padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                onPressed: () => html.window.open('${x['curso']}', '_blank'),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text('${x['materia']}'),
              )),
        ],
        const SizedBox(height: 8),
        Text('Pídele que cierre sesión en la app y vuelva a entrar.', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
      ]),
    );
  }
}

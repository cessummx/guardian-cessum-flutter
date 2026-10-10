// =====================================================================
//  CAMBIAR MATRÍCULA DE ALUMNO (5-oct-2026) · lo pidió Sistemas.
//  La función ya existía en el Guardián (alumno_cambiar_matricula) pero
//  solo se podía usar por URL. Aquí:
//  1. Buscar al alumno (matrícula o nombre).
//  2. Escribir la matrícula nueva (8 dígitos; el Guardián verifica que
//     nadie más la use).
//  3. Vista previa: qué filas son suyas y se mueven (base de Grupos, su
//     ajuste de padrón, el libro principal, pagos de reinscripción y
//     bajas), cuáles son de otra persona con la misma matrícula y no se
//     tocan, y cuáles son dudosas y se revisan a mano. Las bitácoras no
//     se reescriben: son el historial.
//  4. Confirmar: hace el cambio y queda en la auditoría.
//  Solo Rectoría y Vicerrectoría. Moodle no usa la matrícula (identifica
//  por correo), así que no se toca. No envía correos.
// =====================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const Color _verde = Color(0xFF1E7B34);
const Color _ambar = Color(0xFFB7791F);

class CambiarMatriculaAlumnoScreen extends StatefulWidget {
  const CambiarMatriculaAlumnoScreen({super.key});
  @override
  State<CambiarMatriculaAlumnoScreen> createState() => _CambiarMatriculaAlumnoScreenState();
}

class _CambiarMatriculaAlumnoScreenState extends State<CambiarMatriculaAlumnoScreen> {
  final _buscar = TextEditingController();
  final _nueva = TextEditingController();
  List<Map<String, dynamic>> _resultados = [];
  bool _buscando = false;
  String _errorBusqueda = '';

  Map<String, dynamic>? _elegido;
  Map<String, dynamic>? _previa;
  Map<String, dynamic>? _hecho;
  bool _trabajando = false;
  String _error = '';

  @override
  void dispose() {
    _buscar.dispose();
    _nueva.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  Future<Map<String, dynamic>> _get(Map<String, String> q, {int segundos = 120}) async {
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
    setState(() {
      _buscando = true;
      _errorBusqueda = '';
      _resultados = [];
      _limpiar();
    });
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

  void _limpiar() {
    _elegido = null;
    _previa = null;
    _hecho = null;
    _error = '';
    _nueva.clear();
  }

  void _elegir(Map<String, dynamic> fila) {
    final correo = '${fila['correo'] ?? ''}'.trim().toLowerCase();
    setState(() {
      _limpiar();
      if (!correo.contains('@cessum.mx')) {
        _error = 'Esa inscripción no tiene correo institucional. El cambio de matrícula lo necesita para no tocar '
            'registros de otra persona: primero corrige su correo.';
        return;
      }
      _elegido = fila;
    });
  }

  String get _vieja => '${_elegido?['matricula'] ?? ''}'.trim().replaceAll(RegExp(r'\.0+$'), '');
  String get _correo => '${_elegido?['correo'] ?? ''}'.trim().toLowerCase();

  Future<void> _verPrevia() async {
    final nueva = _nueva.text.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(nueva)) {
      setState(() => _error = 'La matrícula nueva debe tener 8 dígitos.');
      return;
    }
    if (nueva == _vieja) {
      setState(() => _error = 'La matrícula nueva es igual a la actual.');
      return;
    }
    setState(() { _previa = null; _hecho = null; _error = ''; _trabajando = true; });
    try {
      final d = await _get({'accion': 'alumno_cambiar_matricula', 'vieja': _vieja, 'nueva': nueva, 'correo': _correo});
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        if (d['ok'] == true) {
          _previa = d;
        } else {
          _error = '${d['error'] ?? 'No se pudo preparar la vista previa.'}';
        }
      });
    } catch (_) {
      if (mounted) setState(() { _trabajando = false; _error = 'No se pudo preparar la vista previa (conexión).'; });
    }
  }

  Future<void> _confirmar() async {
    final p = _previa;
    if (p == null) return;
    final nueva = _nueva.text.trim();
    final grupos = ((p['baseGruposSuyas'] as List?) ?? []).length;
    final otras = ((p['otrasFilasQueSeMueven'] as List?) ?? []).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar cambio de matrícula'),
        content: Text('${p['persona'] ?? ''}\n\n'
            'De $_vieja a $nueva.\n\n'
            'Se cambian $grupos fila(s) de la base de Grupos, '
            '${'${p['overrideSuyo'] ?? ''}'.startsWith('fila') ? 'su ajuste de padrón' : 'ningún ajuste de padrón'} '
            'y $otras fila(s) más de los libros.\n'
            'Lo de otra persona con la misma matrícula no se toca. Las bitácoras se conservan como historial.\n\n'
            'No se envía ningún correo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cambiar matrícula'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _trabajando = true; _error = ''; });
    try {
      final d = await _get({'accion': 'alumno_cambiar_matricula', 'vieja': _vieja, 'nueva': nueva, 'correo': _correo, 'frase': 'MOVER'},
          segundos: 300);
      if (!mounted) return;
      setState(() {
        _trabajando = false;
        if (d['ok'] == true) {
          _hecho = d;
        } else {
          _error = '${d['error'] ?? 'No se pudo hacer el cambio.'}';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _trabajando = false;
          _error = 'La conexión se cortó; el cambio pudo haberse hecho. Busca al alumno por su matrícula nueva para revisarlo antes de repetir.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(backgroundColor: cessumRed, foregroundColor: Colors.white, title: const Text('Cambiar matrícula de alumno')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
          Text('Cambia la matrícula de un alumno en todo el sistema: su fila de la base de Grupos, su ajuste de padrón, '
              'el libro principal, pagos de reinscripción y bajas. Primero muestra qué cambiaría. Si otra persona comparte '
              'la matrícula, lo suyo no se toca. Moodle no se afecta (identifica por correo). No envía correos.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4)),
          const SizedBox(height: 12),
          _paso1(),
          if (_elegido != null) ...[const SizedBox(height: 12), _paso2()],
          if (_previa != null && _hecho == null) ...[const SizedBox(height: 12), _paso3()],
          if (_hecho != null) ...[const SizedBox(height: 12), _resultado()],
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error, style: const TextStyle(color: cessumRed, fontWeight: FontWeight.w600, height: 1.4)),
            ),
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
          final sel = _elegido != null && _elegido!['fila'] == r['fila'];
          final baja = '${r['grupo'] ?? ''}'.toUpperCase().contains('BAJA');
          return Card(
            margin: const EdgeInsets.only(top: 8),
            color: sel ? cessumRed.withValues(alpha: 0.07) : null,
            child: ListTile(
              dense: true,
              onTap: () => _elegir(r),
              title: Text('${r['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${r['matricula']} · ${r['programa']} · ${r['generacion']} · ${r['grupo']}\n${r['correo'] ?? 'sin correo'}',
                  style: TextStyle(fontSize: 12, height: 1.35, color: baja ? _ambar : cessumMuted(context))),
              isThreeLine: true,
              trailing: Icon(sel ? Icons.check_circle : Icons.chevron_right, color: sel ? cessumRed : cessumMuted(context)),
            ),
          );
        }),
      ]);

  Widget _paso2() => _tarjeta('2. Matrícula nueva', [
        Text('${_elegido!['nombre']} · matrícula actual: $_vieja\n$_correo',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _nueva,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
              onChanged: (_) => setState(() { _previa = null; _hecho = null; _error = ''; }),
              onSubmitted: (_) => _verPrevia(),
              decoration: const InputDecoration(labelText: 'Matrícula nueva (8 dígitos)', isDense: true, prefixIcon: Icon(Icons.badge_outlined)),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: _trabajando ? null : _verPrevia,
            child: const Text('Ver qué cambiaría'),
          ),
        ]),
        const SizedBox(height: 6),
        Text('El Guardián verifica que nadie más use la matrícula nueva.', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ]);

  Widget _linea(IconData i, Color c, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.4))),
        ]),
      );

  Widget _paso3() {
    final p = _previa!;
    final grupos = ((p['baseGruposSuyas'] as List?) ?? []).map((e) => '$e').toList();
    final otraPersona = ((p['baseGruposDeLaOtraPersona'] as List?) ?? []).map((e) => '$e').toList();
    final mover = ((p['otrasFilasQueSeMueven'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final dudosas = ((p['filasDudosasQueNoSeTocan'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final ajenas = (p['filasDeLaOtraPersona'] as num?)?.toInt() ?? 0;
    final ov = '${p['overrideSuyo'] ?? ''}';
    return _tarjeta('3. Revisa y confirma', [
      Text('${p['persona'] ?? ''}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      Text('${p['vieja']} → ${p['nueva']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: cessumRed)),
      const SizedBox(height: 10),
      const Text('Se cambia', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      for (final g in grupos) _linea(Icons.check_circle_outline, _verde, 'Base de Grupos · $g'),
      if (ov.startsWith('fila')) _linea(Icons.check_circle_outline, _verde, 'Su ajuste de padrón · $ov'),
      for (final m in mover)
        _linea(Icons.check_circle_outline, _verde, '${m['hoja']} · fila ${m['fila']}${'${m['muestra'] ?? ''}'.isNotEmpty ? '\n${m['muestra']}' : ''}'),
      if (grupos.isEmpty && !ov.startsWith('fila') && mover.isEmpty) _linea(Icons.info_outline, _ambar, 'No se encontraron filas suyas para cambiar.'),
      if (otraPersona.isNotEmpty || ajenas > 0 || '${p['overrideDeLaOtraPersona'] ?? 'no tiene'}' != 'no tiene') ...[
        const SizedBox(height: 8),
        const Text('No se toca (es de otra persona con la misma matrícula)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        for (final o in otraPersona) _linea(Icons.person_outline, cessumMuted(context), o),
        if ('${p['overrideDeLaOtraPersona'] ?? 'no tiene'}' != 'no tiene')
          _linea(Icons.person_outline, cessumMuted(context), 'Ajuste de padrón · ${p['overrideDeLaOtraPersona']}'),
        if (ajenas > 0) _linea(Icons.person_outline, cessumMuted(context), '$ajenas fila(s) más de los libros'),
      ],
      if (dudosas.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('Dudosas: no se tocan, revísalas a mano', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: _ambar)),
        const SizedBox(height: 4),
        for (final m in dudosas)
          _linea(Icons.help_outline, _ambar, '${m['hoja']} · fila ${m['fila']}${'${m['muestra'] ?? ''}'.isNotEmpty ? '\n${m['muestra']}' : ''}'),
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
          onPressed: _trabajando ? null : _confirmar,
          icon: const Icon(Icons.swap_horiz),
          label: const Text('Cambiar matrícula', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
    ]);
  }

  Widget _resultado() {
    final d = _hecho!;
    return _tarjeta('Listo', [
      _linea(Icons.verified, _verde, 'La matrícula quedó cambiada: ${d['vieja']} → ${d['nueva']}.'),
      _linea(Icons.logout, _ambar,
          'Pídele a la alumna o al alumno que cierre sesión en la app y vuelva a entrar: la app guarda su perfil anterior con la matrícula vieja.'),
      if (((d['filasDudosasQueNoSeTocan'] as List?) ?? []).isNotEmpty)
        _linea(Icons.help_outline, _ambar, 'Quedaron filas dudosas sin tocar: revísalas a mano (están en la vista previa).'),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _buscar.text = '${d['nueva']}';
          _hacerBusqueda();
        }),
        icon: const Icon(Icons.search),
        label: const Text('Buscarla con la matrícula nueva'),
      ),
    ]);
  }
}

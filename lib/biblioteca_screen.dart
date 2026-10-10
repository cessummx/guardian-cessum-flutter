// =====================================================================
//  biblioteca_screen.dart · CESSUM · App CESSUM
//  BIBLIOTECA DE BLOQUES (5-oct-2026).
//
//  Sesiones de planeaciones VALIDADAS y presentaciones terminadas de todos
//  los docentes de CESSUM (los ven todos: decisión de Vicerrectoría).
//  · Buscar (sin acentos), filtrar por tipo, ver el bloque completo.
//  · Sesión de planeación: «Usar en mi sesión» (adenda de su planeación:
//    sus diapositivas y materiales ya la toman) o «Adaptar con IA» (queda
//    como propuesta para aceptar o descartar en su planeación).
//  · Presentación: «Copiar a mis presentaciones» (proyecto propio en su
//    generador; de ahí se coloca en el aula como siempre).
//  · El autor siempre acreditado; cada uso suma. Vicerrectoría destaca o retira.
//  Rutas (POST): biblioteca_buscar · biblioteca_bloque · biblioteca_usar ·
//  biblioteca_curar · planea_mis · (GET) mis_grupos.
// =====================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';

const Color _verde = Color(0xFF1E8E3E);

class BibliotecaScreen extends StatefulWidget {
  /// Si viene de una planeación: la sesión destino ya está elegida.
  final String? destinoPlaneacionId;
  final int? destinoSesion;
  final String? destinoMateria;
  final String? consultaInicial;
  final String? tipoInicial; // '' | planeacion_sesion | presentacion
  const BibliotecaScreen({super.key, this.destinoPlaneacionId, this.destinoSesion, this.destinoMateria, this.consultaInicial, this.tipoInicial});

  @override
  State<BibliotecaScreen> createState() => _BibliotecaScreenState();
}

class _BibliotecaScreenState extends State<BibliotecaScreen> {
  String _correo = '';
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _bloques = [];
  bool _puedeCurar = false;
  late final TextEditingController _q = TextEditingController(text: widget.consultaInicial ?? '');
  late String _tipo = widget.tipoInicial ?? '';
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int seg = 90}) async {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({...body, 'correo': _correo, 'actor': _correo}))
        .timeout(Duration(seconds: seg));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _iniciar() async {
    _correo = (await SessionStore.validEmail()) ?? '';
    await _buscar();
  }

  Future<void> _buscar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final j = await _post({'accion': 'biblioteca_buscar', 'q': _q.text.trim(), 'tipo': _tipo, 'materia': widget.destinoMateria ?? ''});
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo buscar.');
      if (!mounted) return;
      setState(() {
        _bloques = ((j['bloques'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _puedeCurar = j['puedeCurar'] == true;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  void _aviso(String t, {bool ok = true}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: ok ? _verde : cessumRed, content: Text(t)));

  // ───────────────────────────────────────────── ELEGIR CON BUSCADOR
  Future<Map<String, dynamic>?> _elegirDeLista(String titulo, List<Map<String, dynamic>> items, String Function(Map<String, dynamic>) etiqueta,
      String Function(Map<String, dynamic>) detalle) {
    final buscar = TextEditingController();
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final q = buscar.text.trim().toLowerCase();
          final vis = items.where((x) => q.isEmpty || '${etiqueta(x)} ${detalle(x)}'.toLowerCase().contains(q)).toList();
          return AlertDialog(
            title: Text(titulo),
            content: SizedBox(
              width: 520,
              height: 420,
              child: Column(children: [
                TextField(
                  controller: buscar,
                  autofocus: true,
                  onChanged: (_) => setD(() {}),
                  decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Buscar…', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: vis.isEmpty
                      ? const Center(child: Text('Nada coincide.'))
                      : ListView(children: [
                          for (final x in vis)
                            ListTile(dense: true, title: Text(etiqueta(x)), subtitle: Text(detalle(x)), onTap: () => Navigator.pop(ctx, x)),
                        ]),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
          );
        },
      ),
    );
  }

  Future<int?> _elegirSesion(int total, {String titulo = '¿En qué sesión?'}) => showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(title: Text(titulo), children: [
          for (var i = 1; i <= (total < 1 ? 12 : total); i++) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, i), child: Text('Sesión $i')),
        ]),
      );

  // ───────────────────────────────────────────── USAR UN BLOQUE
  Future<void> _usarSesion(Map<String, dynamic> b, {required bool adaptar}) async {
    var idPlan = widget.destinoPlaneacionId ?? '';
    var ses = widget.destinoSesion ?? 0;
    if (idPlan.isEmpty || ses < 1) {
      final j = await _post({'accion': 'planea_mis'});
      final planes = ((j['planeaciones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((p) => ((p['versiones'] as num?) ?? 0) > 0).toList();
      if (planes.isEmpty) {
        _aviso('Primero necesitas una planeación tuya generada: el bloque se usa en una de sus sesiones.', ok: false);
        return;
      }
      if (!mounted) return;
      final p = await _elegirDeLista('¿En cuál de tus planeaciones?', planes, (x) => '${x['materia']}', (x) => 'Grupo ${x['grupo']} · ${x['sesiones']} sesiones · ${x['creado']}');
      if (p == null || !mounted) return;
      final n = await _elegirSesion(int.tryParse('${p['sesiones']}') ?? 0);
      if (n == null) return;
      idPlan = '${p['id']}';
      ses = n;
    }
    setState(() => _ocupado = true);
    try {
      final r = await _post({'accion': 'biblioteca_usar', 'id': '${b['id']}', 'idPlaneacion': idPlan, 'sesion': '$ses', if (adaptar) 'modo': 'adaptar'}, seg: 300);
      if (!mounted) return;
      _aviso('${r['ok'] == true ? r['nota'] : r['error']}', ok: r['ok'] == true);
      if (r['ok'] == true) {
        await _buscar();
        if (mounted && widget.destinoPlaneacionId != null) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _aviso('$e', ok: false);
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _copiarPresentacion(Map<String, dynamic> b) async {
    List<Map<String, dynamic>> grupos = [];
    try {
      final r = await http.get(Uri.parse('$guardianUrl?accion=mis_grupos&correo=${Uri.encodeComponent(_correo)}')).timeout(const Duration(seconds: 45));
      grupos = ((jsonDecode(r.body)['grupos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    if (!mounted) return;
    if (grupos.isEmpty) {
      _aviso('No encontré materias asignadas a tu nombre para copiarla.', ok: false);
      return;
    }
    final g = await _elegirDeLista('¿Para qué materia?', grupos, (x) => '${x['materia']}', (x) => '${x['programa']} · ${x['generacion']} · Grupo ${x['grupo']}');
    if (g == null || !mounted) return;
    final n = await _elegirSesion(12);
    if (n == null) return;
    setState(() => _ocupado = true);
    try {
      final r = await _post({'accion': 'biblioteca_usar', 'id': '${b['id']}', 'programa': '${g['programa'] ?? ''}', 'generacion': '${g['generacion'] ?? ''}',
        'grupo': '${g['grupo'] ?? ''}', 'materia': '${g['materia'] ?? ''}', 'clave': '${g['clave'] ?? ''}', 'sesion': '$n'});
      if (!mounted) return;
      _aviso('${r['ok'] == true ? r['nota'] : r['error']}', ok: r['ok'] == true);
      if (r['ok'] == true) await _buscar();
    } catch (e) {
      if (mounted) _aviso('$e', ok: false);
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _curar(Map<String, dynamic> b, String operacion) async {
    // La operación va en «operacion»: «accion» es el nombre de la ruta.
    final r = await _post({'accion': 'biblioteca_curar', 'id': '${b['id']}', 'operacion': operacion});
    if (!mounted) return;
    _aviso(r['ok'] == true ? 'Listo.' : '${r['error']}', ok: r['ok'] == true);
    await _buscar();
  }

  // ───────────────────────────────────────────── VISTA PREVIA
  Future<void> _verBloque(Map<String, dynamic> b) async {
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)));
    Map<String, dynamic> j;
    try {
      j = await _post({'accion': 'biblioteca_bloque', 'id': '${b['id']}'});
    } catch (e) {
      j = {'ok': false, 'error': '$e'};
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (j['ok'] != true) {
      _aviso('${j['error'] ?? 'No se pudo abrir.'}', ok: false);
      return;
    }
    final c = Map<String, dynamic>.from((j['contenido'] as Map?) ?? {});
    final esSesion = b['tipo'] == 'planeacion_sesion';
    final destino = widget.destinoSesion;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${b['tema']}'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b['materia']} · ${b['programa']} · de ${b['docente']}', style: TextStyle(fontSize: 12.5, color: cessumMuted(ctx))),
              const SizedBox(height: 10),
              if (esSesion) ...[
                if ('${c['criterioLogro'] ?? ''}'.isNotEmpty) Text('Criterio de logro: ${c['criterioLogro']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
                for (final k in const ['inicio', 'desarrollo', 'cierre']) ..._momento(ctx, k, Map<String, dynamic>.from((c[k] as Map?) ?? {})),
              ] else ...[
                for (final l in ((c['lineas'] as List?) ?? [])) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('$l', style: const TextStyle(fontSize: 12.5, height: 1.4))),
              ],
              if (_puedeCurar) ...[
                const Divider(height: 24),
                Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: () { Navigator.pop(ctx); _curar(b, 'destacar'); }, child: const Text('Destacar')),
                  OutlinedButton(onPressed: () { Navigator.pop(ctx); _curar(b, 'normal'); }, child: const Text('Quitar destacado')),
                  OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: cessumRed), onPressed: () { Navigator.pop(ctx); _curar(b, 'retirar'); }, child: const Text('Retirar')),
                ]),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          if (esSesion) ...[
            OutlinedButton.icon(
              onPressed: () { Navigator.pop(ctx); _usarSesion(b, adaptar: true); },
              icon: const Icon(Icons.auto_fix_high, size: 17),
              label: Text(destino != null ? 'Adaptar con IA a mi sesión $destino' : 'Adaptar con IA'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () { Navigator.pop(ctx); _usarSesion(b, adaptar: false); },
              icon: const Icon(Icons.download_done, size: 17),
              label: Text(destino != null ? 'Usar en mi sesión $destino' : 'Usar en mi planeación'),
            ),
          ] else
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () { Navigator.pop(ctx); _copiarPresentacion(b); },
              icon: const Icon(Icons.copy_all, size: 17),
              label: const Text('Copiar a mis presentaciones'),
            ),
        ],
      ),
    );
  }

  List<Widget> _momento(BuildContext ctx, String k, Map<String, dynamic> m) {
    if (m.isEmpty) return [];
    final abr = ((m['abridores'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final txt = '${m['actividad'] ?? m['descripcion'] ?? m['que'] ?? ''}';
    return [
      const SizedBox(height: 10),
      Text('${k.toUpperCase()} · ${m['minutos'] ?? 0} min', style: const TextStyle(fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: Color(0xFF8A5F10))),
      if (txt.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(txt, style: const TextStyle(fontSize: 12.5, height: 1.4))),
      for (final a in abr)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('${(a['nivel'] as num? ?? 0) >= 4 ? '◆' : '◇'} ${a['texto'] ?? ''}${a['nivel'] != null ? ' (nivel ${a['nivel']})' : ''}',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: (a['nivel'] as num? ?? 0) >= 4 ? cessumRed : cessumInk(ctx))),
        ),
    ];
  }

  // ───────────────────────────────────────────── PANTALLA
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Biblioteca de bloques', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (widget.destinoSesion != null)
            Text('Para tu sesión ${widget.destinoSesion}${widget.destinoMateria != null ? ' de ${widget.destinoMateria}' : ''}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _buscar(),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).cardColor,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _buscar),
              hintText: 'Tema, materia, docente… (por ejemplo «evaluación formativa»)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 14), children: [
            for (final t in const [('', 'Todo'), ('planeacion_sesion', 'Sesiones de planeación'), ('presentacion', 'Presentaciones')])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(t.$2),
                  selected: _tipo == t.$1,
                  selectedColor: cessumRed.withValues(alpha: 0.15),
                  onSelected: (_) { setState(() => _tipo = t.$1); _buscar(); },
                ),
              ),
          ]),
        ),
        if (_ocupado) const LinearProgressIndicator(color: cessumRed),
        Expanded(
          child: _cargando
              ? const CessumSkeletonList(count: 5)
              : _error.isNotEmpty
                  ? CessumEmptyState(icon: Icons.cloud_off_rounded, title: 'No se pudo buscar', subtitle: _error)
                  : _bloques.isEmpty
                      ? const CessumEmptyState(icon: Icons.local_library_outlined, title: 'Nada por aquí todavía',
                          subtitle: 'La biblioteca se llena sola con las sesiones de planeaciones validadas y las presentaciones terminadas.')
                      : ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 24), children: [for (final b in _bloques) _tarjeta(b)]),
        ),
      ]),
    );
  }

  Widget _tarjeta(Map<String, dynamic> b) {
    final esSesion = b['tipo'] == 'planeacion_sesion';
    final dest = b['estado'] == 'destacado', ret = b['estado'] == 'retirado';
    return Opacity(
      opacity: ret ? 0.5 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: dest ? BorderSide(color: cessumGold.withValues(alpha: 0.7)) : BorderSide.none),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _ocupado ? null : () => _verBloque(b),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(esSesion ? Icons.event_note_outlined : Icons.slideshow_outlined, color: cessumRed),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (dest) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.star, size: 16, color: cessumGold)),
                    Expanded(child: Text('${b['tema']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                  ]),
                  Text('${b['materia']} · ${b['programa']}${(b['sesion'] ?? 0) != 0 ? ' · sesión ${b['sesion']}' : ''}',
                      style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                  const SizedBox(height: 4),
                  Text('${b['resumen'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, height: 1.35)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 10, children: [
                    Text('de ${b['docente']}${b['propio'] == true ? ' (tuya)' : ''}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                    if ((b['nivel'] ?? 0) != 0) Text('nivel ${b['nivel']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                    if (b['pct'] != null) Text('${b['pct']} % complejas', style: const TextStyle(fontSize: 11.5, color: _verde, fontWeight: FontWeight.w600)),
                    Text('${b['usos'] ?? 0} uso(s)', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                    if (ret) const Text('retirado', style: TextStyle(fontSize: 11.5, color: cessumRed, fontWeight: FontWeight.w700)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

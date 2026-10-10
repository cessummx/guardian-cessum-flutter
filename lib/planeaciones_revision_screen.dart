// planeaciones_revision_screen.dart
// ---------------------------------------------------------------------------
// (10-sep-2026) VICERRECTORÍA: revisar y dictaminar planeaciones didácticas.
//
// Las rutas planea_revision_listar y planea_dictaminar llevaban tiempo
// construidas y NUNCA tuvieron pantalla: el docente entregaba, el correo
// llegaba, y del otro lado no había dónde abrirla. Es el mismo hueco que
// tuvo la asistencia por grupo — la ruta calculaba bien y nadie podía verla.
//
// Tres decisiones posibles, y la del medio es la que importa:
//   · VALIDAR — queda en el expediente y habilita al docente para generar
//     presentaciones de esas sesiones.
//   · DEVOLVER CON OBSERVACIONES — el backend EXIGE que se escriban; una
//     devolución sin motivo no le sirve a nadie y aquí se dice así.
//   · REABRIR — deshace un dictamen anterior sin escribirle al docente.
//
// (3-oct-2026) ABRIR LA PLANEACIÓN ANTES DE DICTAMINAR. La tarjeta solo mostraba quién entregó y los botones de decidir: nunca hubo
// cómo leer lo entregado. Ahora cada tarjeta trae «Leer» (pestaña de lectura), «PDF» (cuadro de impresión para guardar) y «Word»,
// con el mismo documento que ve el docente en «Mis planeaciones». Abre la versión que se entregó. Si el docente subió su propio
// archivo, se abre ese archivo.
// ---------------------------------------------------------------------------

import 'dart:convert';
import 'dart:html' as html; // abrir el archivo propio del docente

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'planeacion_documento.dart';

// (8-oct-2026) Antes del dictamen se construían listas con
// `.map((x) => Map<String, dynamic>.from(x as Map))`: si un solo elemento llegaba nulo o con
// otra forma (p. ej. un chequeo a medio escribir), ese cast tronaba y tumbaba toda la pantalla
// en pleno dictamen. Esta versión descarta en silencio el elemento que no es un mapa, en vez
// de tronar por su culpa.
List<Map<String, dynamic>> _comoListaMapas(dynamic l) {
  if (l is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final x in l) {
    if (x is Map) out.add(Map<String, dynamic>.from(x));
  }
  return out;
}

class PlaneacionesRevisionScreen extends StatefulWidget {
  const PlaneacionesRevisionScreen({super.key});

  @override
  State<PlaneacionesRevisionScreen> createState() =>
      _PlaneacionesRevisionScreenState();
}

class _PlaneacionesRevisionScreenState
    extends State<PlaneacionesRevisionScreen> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _entregas = [];
  Map<String, dynamic> _resumen = {};
  String _filtro = 'pendientes';
  final TextEditingController _buscar = TextEditingController();
  // (8-oct-2026) Antes era un solo String: si se dictaminaba el folio A y, mientras esa
  // llamada seguía en vuelo, se tocaba el folio B, el valor se pisaba y al terminar A se
  // limpiaba también el estado "ocupado" de B — reactivando sus botones con su propia
  // llamada todavía pendiente, y permitiendo un doble dictamen sobre el mismo folio.
  // Con un conjunto, cada folio lleva su propio estado de "ocupado".
  final Set<String> _ocupados = {};
  String _abriendo = ''; // folio cuya planeación se está bajando para leerla

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse('$guardianUrl?accion=planea_revision_listar'
          '&actor=${Uri.encodeComponent(correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo cargar la lista.');
      }
      if (!mounted) return;
      setState(() {
        _entregas = ((data['entregas'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _resumen = Map<String, dynamic>.from(
            (data['resumen'] as Map?) ?? const {});
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

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: cessumRed,
    ));
  }

  /// Abre la planeación entregada. modo: 'leer' (pestaña de lectura) · 'pdf' (impresión → Guardar como PDF) · 'word'.
  Future<void> _abrir(Map<String, dynamic> e, String modo) async {
    if ('${e['origen']}' == 'propia') {
      final u = '${e['archivo'] ?? ''}'.trim();
      if (u.isEmpty) {
        _aviso('Esta entrega no trae el archivo del docente.');
        return;
      }
      html.window.open(u, '_blank');
      return;
    }
    final id = '${e['idPlaneacion'] ?? ''}'.trim();
    if (id.isEmpty) {
      _aviso('Esta entrega no trae el identificador de la planeación generada.');
      return;
    }
    setState(() => _abriendo = '${e['folio'] ?? ''}');
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final ver = '${e['version'] ?? ''}'.trim();
      final sufijoVersion = ver.isNotEmpty ? '&version=${Uri.encodeComponent(ver)}' : '';
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=planea_obtener&id=${Uri.encodeComponent(id)}'
              '$sufijoVersion&actor=${Uri.encodeComponent(correo)}'))
          .timeout(const Duration(seconds: 60));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['ok'] != true || j['planeacion'] == null) {
        throw Exception(j['error'] ?? 'No se pudo abrir la planeación.');
      }
      final ctx = Map<String, dynamic>.from((j['contexto'] as Map?) ?? {});
      final cuerpo = documentoPlaneacion(
        contexto: ctx,
        planeacion: Map<String, dynamic>.from(j['planeacion'] as Map),
        docente: '${j['docente'] ?? ''}',
        modeloVersion: '${j['modeloVersion'] ?? ''}',
      );
      if (modo == 'word') {
        descargarWord(cuerpo, ctx);
      } else {
        final abierta =
            modo == 'pdf' ? imprimirPdf(cuerpo, ctx) : abrirDocumento(cuerpo, ctx);
        if (!abierta) {
          _aviso('El navegador bloqueó la ventana. Permite las ventanas emergentes '
              'de app.cessum.mx e inténtalo de nuevo.');
        }
      }
    } catch (ex) {
      _aviso('$ex'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _abriendo = '');
    }
  }

  // Sin acentos y por palabras: escribir «metodologia 25-4» encuentra igual.
  String _norm(String t) {
    const con = 'áéíóúüñÁÉÍÓÚÜÑ';
    const sin = 'aeiouunAEIOUUN';
    var r = t.toLowerCase();
    for (var i = 0; i < con.length; i++) {
      r = r.replaceAll(con[i], sin[i].toLowerCase());
    }
    return r.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _norm(_buscar.text);
    return _entregas.where((e) {
      final est = '${e['estado'] ?? ''}'.toLowerCase();
      if (_filtro == 'pendientes' && est != 'entregada') return false;
      if (_filtro == 'validadas' && !est.contains('valid')) return false;
      if (_filtro == 'observadas' && !est.contains('observ')) return false;
      if (q.isEmpty) return true;
      final heno = _norm('${e['materia']} ${e['docente']} ${e['programa']} '
          '${e['generacion']} ${e['grupo']} ${e['clave']} ${e['folio']}');
      return q.split(' ').every(heno.contains);
    }).toList();
  }

  int _cuenta(String estadoParcial) => _entregas
      .where((e) =>
          '${e['estado'] ?? ''}'.toLowerCase().contains(estadoParcial))
      .length;

  Future<void> _dictaminar(
      Map<String, dynamic> e, String decision, String observaciones) async {
    final folio = '${e['folio'] ?? ''}';
    if (_ocupados.contains(folio)) return; // (8-oct-2026) ya hay un dictamen de este folio en vuelo
    setState(() => _ocupados.add(folio));
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'accion': 'planea_dictaminar',
                'actor': correo,
                'folio': folio,
                'decision': decision,
                'observaciones': observaciones,
              }))
          .timeout(const Duration(seconds: 300));   // (5-oct-2026) al validar también coloca los productos en el aula
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo dictaminar.');
      }
      if (!mounted) return;
      setState(() => _ocupados.remove(folio));
      // (5-oct-2026) Al validar, los productos se colocan solos en el aula con su rúbrica: se muestra qué pasó.
      if (decision == 'validar' && data['aula'] is Map) {
        await _mostrarResultadoAula(e, Map<String, dynamic>.from(data['aula'] as Map), alValidar: true);
        await _cargar();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(decision == 'validar'
              ? 'Planeación validada. Se le avisó al docente.'
              : decision == 'observar'
                  ? 'Devuelta con observaciones. Se le avisó al docente.'
                  : 'Dictamen reabierto. No se le escribió al docente.'),
        ),
      );
      await _cargar();
    } catch (err) {
      if (!mounted) return;
      setState(() => _ocupados.remove(folio));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$err'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _pedirObservaciones(Map<String, dynamic> e) async {
    final ctrl = TextEditingController(text: '${e['observaciones'] ?? ''}');
    final texto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Devolver con observaciones'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El docente va a recibir este texto tal cual. Sé concreto: qué '
              'hay que ajustar y en qué sesión.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 6,
              maxLength: 1200,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    'Ej. En las sesiones 2 y 4 el desarrollo no tiene abridores '
                    'de nivel 4; la evaluación de la sesión 6 no corresponde al '
                    'propósito declarado.',
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
                backgroundColor: cessumGold, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Devolver'),
          ),
        ],
      ),
    );
    ctrl.dispose(); // (8-oct-2026) antes no se destruía: fuga en cada "Devolver con observaciones"
    if (texto == null) return;
    if (texto.length < 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Hay que escribir las observaciones: una devolución sin motivo '
              'no le sirve al docente.'),
        ),
      );
      return;
    }
    await _dictaminar(e, 'observar', texto);
  }

  /* (5-oct-2026) PRODUCTOS AL AULA. Cada producto de la planeación validada como tarea de Moodle, en su semana, con su
     rúbrica. Vista previa primero; las semanas protegidas se saltan; si la materia tiene varias aulas, se elige una. */
  Future<Map<String, dynamic>> _productosAulaLlamar(Map<String, dynamic> e, {bool confirmar = false, String courseId = '', bool desbloquear = false}) async {
    final correo = await SessionStore.realEmail() ?? '';
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'accion': 'planea_productos_aula', 'actor': correo, 'folio': '${e['folio'] ?? ''}',
              if (confirmar) 'confirmar': '1', if (courseId.isNotEmpty) 'courseId': courseId, if (desbloquear) 'desbloquear': '1',
            }))
        .timeout(const Duration(seconds: 300));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _mostrarResultadoAula(Map<String, dynamic> e, Map<String, dynamic> a, {bool alValidar = false}) async {
    final prods = _comoListaMapas(a['productos']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(alValidar ? 'Planeación validada' : 'Productos en el aula'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (alValidar) const Text('Se le avisó al docente.', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (a['ok'] != true)
                Text(
                    'Los productos NO se colocaron en el aula: ${a['error'] ?? ''}\n\n'
                    'Puedes colocarlos después con «Productos al aula» en esta planeación.',
                    style: const TextStyle(height: 1.45, color: Color(0xFFB7791F)))
              else ...[
                Text('${a['colocados'] ?? 0} producto(s) en el aula ${a['courseId']} con su rúbrica:', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final p in prods)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${p['estado'] == 'omitida' ? '⏸' : (p['estado'] == 'error' ? '✗' : '✓')} ${p['titulo']} · semana ${p['semana']}'
                      '${'${p['rubrica'] ?? ''}'.isNotEmpty ? ' · rúbrica ${p['rubrica']}' : ''}'
                      '${'${p['motivo'] ?? ''}'.isNotEmpty ? '\n   ${p['motivo']}' : ''}',
                      style: const TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
  }

  Future<void> _productosAula(Map<String, dynamic> e) async {
    final folio = '${e['folio'] ?? ''}';
    if (_ocupados.contains(folio)) return; // (8-oct-2026) ya hay una operación de este folio en vuelo
    setState(() => _ocupados.add(folio));
    var courseId = '';
    Map<String, dynamic> prev;
    try {
      prev = await _productosAulaLlamar(e);
      if (prev['ambiguo'] == true && mounted) {
        setState(() => _ocupados.remove(folio));
        final cursos = ((prev['cursos'] as List?) ?? []).map((x) => '$x').toList();
        final elegido = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('¿En qué aula?'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('${e['materia']} tiene ${cursos.length} aulas en Moodle. Elige la de este grupo:', style: const TextStyle(fontSize: 13)),
              ),
              for (final c in cursos) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, c), child: Text('Aula $c')),
            ],
          ),
        );
        if (elegido == null) return;
        courseId = elegido;
        setState(() => _ocupados.add(folio));
        prev = await _productosAulaLlamar(e, courseId: courseId);
      }
    } catch (err) {
      prev = {'ok': false, 'error': '$err'};
    }
    if (!mounted) return;
    setState(() => _ocupados.remove(folio));
    if (prev['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('${prev['error'] ?? 'No se pudo preparar.'}')));
      return;
    }
    final prods = _comoListaMapas(prev['productos']);
    var desbloquear = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Productos al aula'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cada producto se crea como tarea en el aula ${prev['courseId']}, en su semana, con su rúbrica. '
                    'Si ya existía, se actualiza (no se duplica).', style: const TextStyle(fontSize: 13, height: 1.45)),
                const SizedBox(height: 10),
                for (final p in prods)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${p['permitido'] == true || desbloquear ? '•' : '⏸'} ${p['titulo']} · semana ${p['semana']} · ${p['ponderacion']} % · ${p['criterios']} criterio(s)'
                      '${p['permitido'] != true && !desbloquear ? '\n   ${p['motivo']}' : ''}',
                      style: const TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                if (prods.any((p) => p['permitido'] != true))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: desbloquear,
                    onChanged: (v) => setD(() => desbloquear = v ?? false),
                    title: const Text('Colocar también en las semanas protegidas', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Esas semanas tienen material puesto a mano por el docente.', style: TextStyle(fontSize: 11.5)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Colocar en el aula'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ocupados.add(folio));
    Map<String, dynamic> res;
    try {
      res = await _productosAulaLlamar(e, confirmar: true, courseId: courseId, desbloquear: desbloquear);
    } catch (err) {
      res = {'ok': false, 'error': '$err'};
    }
    if (!mounted) return;
    setState(() => _ocupados.remove(folio));
    await _mostrarResultadoAula(e, res);
  }

  Future<void> _verLoQueCorrigen() async {
    // (8-oct-2026) Se guarda el Navigator ANTES del await: si esta pantalla se desmonta mientras
    // la llamada está en vuelo, `mounted` sería false y el diálogo de carga (no descartable por
    // el usuario) se quedaba abierto para siempre. Se cierra con el Navigator guardado, sin
    // depender del `mounted` de esta pantalla.
    final nav = Navigator.of(context);
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)));
    Map<String, dynamic> d;
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'planea_aprendizaje_institucional', 'actor': correo}))
          .timeout(const Duration(seconds: 150));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      d = {'ok': false, 'error': '$e'};
    }
    if (nav.mounted && nav.canPop()) nav.pop();
    if (!mounted) return;
    final pat = _comoListaMapas(d['patrones']);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lo que corrigen los docentes'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (d['ok'] != true)
                Text('${d['error'] ?? 'No se pudo leer.'}')
              else ...[
                Text(
                  (d['comparaciones'] ?? 0) == 0
                      ? '${d['nota'] ?? 'Todavía ningún docente ha subido su versión ajustada.'}'
                      : 'De ${d['comparaciones']} versión(es) ajustada(s) por ${d['docentes']} docente(s), esto es lo que más le corrigen al generador:',
                  style: const TextStyle(fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 10),
                for (final p in pat)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p['patron']}  ·  ${p['veces']} vez/veces', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Qué cambiar en el generador: ${p['sugerencia']}', style: const TextStyle(fontSize: 12.5, height: 1.4)),
                    ]),
                  ),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
  }

  /// (5-oct-2026) Dictamen asistido: semáforo, chequeos, re-entrega y borrador; la decisión vuelve aquí.
  Future<void> _preDictamen(Map<String, dynamic> e) async {
    final r = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => _PreDictamenScreen(entrega: e)));
    if (r == null || !mounted) return;
    await _dictaminar(e, '${r['decision']}', '${r['texto'] ?? ''}');
  }

  Future<void> _confirmarValidar(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validar esta planeación'),
        content: Text(
          'Queda incorporada al expediente de ${e['materia']} y el docente '
          'podrá generar presentaciones de esas sesiones.\n\n'
          'Se le avisa por correo.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Validar'),
          ),
        ],
      ),
    );
    if (ok == true) await _dictaminar(e, 'validar', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planeaciones por revisar'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          // (5-oct-2026) Lo que los docentes le corrigen al generador, a partir de sus versiones ajustadas.
          IconButton(
              tooltip: 'Lo que corrigen los docentes',
              onPressed: _verLoQueCorrigen,
              icon: const Icon(Icons.insights_outlined)),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _cajaError()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                    children: [
                      _cabecera(),
                      const SizedBox(height: 12),
                      _buscador(),
                      const SizedBox(height: 10),
                      _chips(),
                      const SizedBox(height: 14),
                      if (_visibles.isEmpty) _vacio(),
                      ..._visibles.map(_tarjeta),
                    ],
                  ),
                ),
    );
  }

  Widget _cajaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 40, color: cessumMuted(context)),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      );

  Widget _cabecera() {
    final pend = _resumen['pendientes'] ?? _cuenta('entregada');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        Icon(Icons.fact_check_outlined, color: cessumRed, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$pend pendiente${pend == 1 ? '' : 's'} de dictamen',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              'La planeación validada es uno de los tres requisitos para el '
              'pago del docente, junto con el contrato y el acta.',
              style: TextStyle(
                  fontSize: 12, height: 1.35, color: cessumMuted(context)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buscador() => TextField(
        controller: _buscar,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Buscar por materia, docente, programa o folio',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _buscar.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _buscar.clear()),
                ),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _chips() => Wrap(spacing: 8, children: [
        _chip('Pendientes', 'pendientes', _cuenta('entregada')),
        _chip('Con observaciones', 'observadas', _cuenta('observ')),
        _chip('Validadas', 'validadas', _cuenta('valid')),
        _chip('Todas', 'todas', _entregas.length),
      ]);

  Widget _chip(String texto, String valor, int n) {
    final activo = _filtro == valor;
    return ChoiceChip(
      label: Text('$texto ($n)', style: const TextStyle(fontSize: 12.5)),
      selected: activo,
      selectedColor: cessumRed.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: activo ? cessumRed : cessumMuted(context),
        fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
          color: activo ? cessumRed.withValues(alpha: 0.45) : cessumMuted(context).withValues(alpha: 0.18)),
      onSelected: (_) => setState(() => _filtro = valor),
    );
  }

  Widget _vacio() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Icon(Icons.inbox_outlined, size: 40, color: cessumMuted(context)),
          const SizedBox(height: 10),
          Text(
            _buscar.text.trim().isNotEmpty
                ? 'Ninguna coincide con «${_buscar.text.trim()}».'
                : _filtro == 'pendientes'
                    ? 'No hay planeaciones esperando dictamen.'
                    : 'No hay planeaciones en este estado.',
            style: TextStyle(color: cessumMuted(context)),
            textAlign: TextAlign.center,
          ),
        ]),
      );

  Widget _tarjeta(Map<String, dynamic> e) {
    final estado = '${e['estado'] ?? ''}'.toLowerCase();
    final pendiente = estado == 'entregada';
    final validada = estado.contains('valid');
    final obs = '${e['observaciones'] ?? ''}'.trim();
    final folio = '${e['folio'] ?? ''}';
    final ocupada = _ocupados.contains(folio);
    final abriendo = _abriendo == folio;
    final propia = '${e['origen']}' == 'propia';

    final color = validada
        ? Colors.green.shade700
        : estado.contains('observ')
            ? cessumGold
            : cessumRed;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text('${e['materia'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Text(
                validada
                    ? 'Validada'
                    : estado.contains('observ')
                        ? 'Con observaciones'
                        : 'Pendiente',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${e['programa'] ?? ''} · Gen. ${e['generacion'] ?? ''} · '
            'Grupo ${e['grupo'] ?? ''}',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 3),
          Text(
            '${e['docente'] ?? ''} · ${e['entregada'] ?? ''}',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 3),
          Text(
            'Folio ${e['folio'] ?? ''} · '
            '${'${e['origen']}' == 'ia' ? 'generada con el asistente' : 'documento del docente'}',
            style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
          ),
          if (obs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.08), // (24-sep) modo oscuro
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Observaciones',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cessumGold)),
                  const SizedBox(height: 4),
                  Text(obs,
                      style: const TextStyle(fontSize: 12.5, height: 1.4)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // (3-oct) Leer lo entregado ANTES de decidir.
          if (abriendo)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else if (propia)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Abrir el archivo del docente'),
                onPressed: () => _abrir(e, 'leer'),
              ),
            )
          else
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('Leer'),
                  onPressed: () => _abrir(e, 'leer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('PDF'),
                  onPressed: () => _abrir(e, 'pdf'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Word'),
                  onPressed: () => _abrir(e, 'word'),
                ),
              ),
            ]),
          const SizedBox(height: 10),
          if (ocupada)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: LinearProgressIndicator(minHeight: 3),
            )
          else if (pendiente) ...[
            // (5-oct-2026) Primero el pre-dictamen; Validar y Devolver siguen a mano debajo.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cessumGold, padding: const EdgeInsets.symmetric(vertical: 12)),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Pre-dictamen: revisar contra la norma'),
                onPressed: () => _preDictamen(e),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Validar'),
                  onPressed: () => _confirmarValidar(e),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumGold,
                      side: BorderSide(color: cessumGold)),
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Devolver'),
                  onPressed: () => _pedirObservaciones(e),
                ),
              ),
            ]),
          ]
          else
            // Reabrir NO le escribe al docente: es para corregir un dictamen
            // propio, no para avisarle que cambió de opinión.
            Wrap(spacing: 8, runSpacing: 4, children: [
              // (5-oct-2026) Los productos de una planeación validada, como tareas del aula con su rúbrica.
              // (8-oct-2026) Comparación en minúsculas, igual que el resto de los chequeos de estado
              // del archivo (ver _cuenta/_visibles): antes, si el backend mandaba "Validada" con
              // mayúscula, el botón simplemente no aparecía.
              if ('${e['estado'] ?? ''}'.toLowerCase() == 'validada' && '${e['origen'] ?? ''}'.toLowerCase() == 'ia')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                  icon: const Icon(Icons.assignment_turned_in_outlined, size: 18),
                  label: const Text('Productos al aula'),
                  onPressed: () => _productosAula(e),
                ),
              TextButton.icon(
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Reabrir dictamen'),
                onPressed: () => _dictaminar(e, 'reabrir', ''),
              ),
            ]),
        ]),
      ),
    );
  }
}

// =====================================================================
//  (5-oct-2026) DICTAMEN ASISTIDO. Antes de decidir, Vicerrectoría ve:
//  · un semáforo y los chequeos contra la norma institucional (exactos en
//    las planeaciones generadas; leídos por la IA en las propias);
//  · en una re-entrega, qué cambió y si cada observación anterior se atendió;
//  · un borrador del dictamen, editable, que se envía con el mismo dictamen
//    de siempre. Nada se envía solo.
//  Ruta: GET planea_predictamen&folio=…&actor=…[&regenerar=1]
// =====================================================================
class _PreDictamenScreen extends StatefulWidget {
  final Map<String, dynamic> entrega;
  const _PreDictamenScreen({required this.entrega});
  @override
  State<_PreDictamenScreen> createState() => _PreDictamenScreenState();
}

class _PreDictamenScreenState extends State<_PreDictamenScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  final TextEditingController _borrador = TextEditingController();
  // (8-oct-2026) Para detectar si el revisor cambió de decisión respecto a la sugerida sin
  // tocar el texto: el borrador que trae la IA está escrito para LA DECISIÓN SUGERIDA, no
  // para cualquier otra. Si el revisor decide lo contrario y no edita nada, el texto no sirve
  // para esa decisión (p. ej. una nota de reconocimiento no es una observación de devolución).
  String _borradorOriginal = '';

  static const Color _verde = Color(0xFF1E7B34);
  static const Color _ambar = Color(0xFFB7791F);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _borrador.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool regenerar = false}) async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'planea_predictamen',
        'folio': '${widget.entrega['folio'] ?? ''}',
        'actor': correo,
        if (regenerar) 'regenerar': '1',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 170));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo preparar el pre-dictamen.');
      if (!mounted) return;
      setState(() {
        _d = d;
        _borrador.text = '${d['borrador'] ?? ''}';
        _borradorOriginal = _borrador.text;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Color _colorEstado(String e) => e == 'falla' ? cessumRed : (e == 'aviso' ? _ambar : _verde);
  IconData _iconoEstado(String e) => e == 'falla' ? Icons.cancel : (e == 'aviso' ? Icons.error_outline : Icons.check_circle);

  Widget _semaforo() {
    final s = '${_d['semaforo'] ?? ''}';
    final c = s == 'rojo' ? cessumRed : (s == 'amarillo' ? _ambar : _verde);
    final sug = _d['decisionSugerida'] == 'validar' ? 'Validar' : 'Devolver con observaciones';
    final t = s == 'rojo'
        ? 'Tiene incumplimientos de la norma'
        : (s == 'amarillo' ? 'Cumple lo esencial, con detalles por atender' : 'Cumple la norma institucional');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.4))),
      child: Row(children: [
        Container(width: 18, height: 18, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 2),
            Text('Sugerencia: $sug${_d['deCache'] == true ? ' · calculado el ${_d['generado'] ?? ''}' : ''}',
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
          ]),
        ),
      ]),
    );
  }

  Widget _seccion(String titulo, IconData icono, List<Widget> hijos) => Card(
        margin: const EdgeInsets.only(top: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icono, size: 19, color: cessumRed),
              const SizedBox(width: 8),
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            ...hijos,
          ]),
        ),
      );

  Widget _reentrega() {
    final cambios = Map<String, dynamic>.from((_d['cambios'] as Map?) ?? {});
    final atencion = _comoListaMapas(_d['atencion']);
    final ses = ((cambios['sesionesCambiadas'] as List?) ?? []).map((x) => '$x').toList();
    return _seccion('Re-entrega: qué se le pidió y qué cambió', Icons.history, [
      Text('Observaciones anteriores', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumMuted(context))),
      const SizedBox(height: 4),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Text('${_d['observacionesAnteriores'] ?? ''}', style: const TextStyle(fontSize: 12.5, height: 1.45)),
      ),
      if (cambios.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          'Desde la versión ${cambios['desdeVersion']}: '
          '${ses.isEmpty ? 'ninguna sesión cambió' : 'cambiaron la(s) sesión(es) ${ses.join(', ')}'}'
          '${cambios['productosCambiaron'] == true ? ' · cambiaron los productos' : ''}'
          '${cambios['dosificacionCambio'] == true ? ' · cambió la dosificación' : ''}'
          '${cambios['encuadreCambio'] == true ? ' · cambió el encuadre' : ''}.',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
      for (final a in atencion) ...[
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            a['estado'] == 'atendida' ? Icons.check_circle : (a['estado'] == 'parcial' ? Icons.timelapse : Icons.cancel),
            size: 18,
            color: a['estado'] == 'atendida' ? _verde : (a['estado'] == 'parcial' ? _ambar : cessumRed),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${a['observacion'] ?? ''} ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: '(${a['estado'] ?? ''}) — ${a['evidencia'] ?? ''}'),
            ]), style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ),
        ]),
      ],
    ]);
  }

  // (8-oct-2026) "Volver a analizar" sobrescribía `_borrador.text` sin avisar: si el revisor ya
  // había editado el texto a mano, esa edición se perdía sin aviso. Ahora, si el texto actual se
  // alejó del que trajo la IA, se pide confirmación antes de reemplazarlo.
  Future<void> _confirmarRegenerar() async {
    if (_borrador.text.trim() == _borradorOriginal.trim()) {
      await _cargar(regenerar: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Volver a analizar?'),
        content: const Text(
            'Ya editaste el texto del borrador a mano. Volver a analizar lo reemplaza con uno nuevo '
            'y pierdes lo que escribiste. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Volver a analizar'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _cargar(regenerar: true);
  }

  Future<void> _decidir(String decision) async {
    final texto = _borrador.text.trim();
    if (decision == 'observar' && texto.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escribe las observaciones: una devolución sin motivo no le sirve al docente.')));
      return;
    }
    final validar = decision == 'validar';
    // (8-oct-2026) El revisor decidió lo contrario de lo que sugirió la IA y no tocó el
    // borrador: ese texto fue escrito para la otra decisión (p. ej. una nota de reconocimiento
    // para validar) y no sirve para esta. Se pide que lo escriba o lo edite antes de continuar,
    // en vez de enviarlo tal cual al docente.
    final sugerida = '${_d['decisionSugerida'] ?? ''}';
    if (sugerida.isNotEmpty && decision != sugerida && texto == _borradorOriginal && texto.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(validar
          ? 'Este texto se escribió para devolver la planeación, no para validarla. Bórralo o escribe la nota que corresponde antes de validar.'
          : 'Este texto es la nota de reconocimiento que sugirió la IA, no una observación. Escribe qué debe corregir el docente antes de devolver.')));
      return;
    }
    // Al validar, el borrador viaja como nota solo si la sugerencia era validar (si era observar, el texto son observaciones).
    final nota = validar ? (_d['decisionSugerida'] == 'validar' ? texto : '') : texto;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(validar ? 'Validar esta planeación' : 'Devolver con observaciones'),
        content: Text(
          validar
              ? 'Queda en el expediente de ${widget.entrega['materia']} y se le avisa por correo al docente${nota.isNotEmpty ? ', con la nota de reconocimiento' : ''}.'
                  '${_d['semaforo'] == 'rojo' ? '\n\nOjo: el pre-dictamen encontró incumplimientos de la norma.' : ''}'
              : 'El docente recibirá por correo el texto del borrador tal como está ahora.',
          style: const TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: validar ? cessumRed : cessumGold, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(validar ? 'Validar' : 'Devolver'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, {'decision': decision, 'texto': nota});
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entrega;
    final chequeos = _comoListaMapas(_d['chequeos']);
    final fortalezas = ((_d['fortalezas'] as List?) ?? []).map((x) => '$x').toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pre-dictamen', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('${e['materia']} · ${e['docente']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          IconButton(tooltip: 'Volver a analizar', onPressed: _cargando ? null : _confirmarRegenerar, icon: const Icon(Icons.refresh)),
        ],
      ),
      bottomNavigationBar: (_cargando || _error.isNotEmpty)
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, -3))],
                ),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: cessumGold, side: BorderSide(color: cessumGold), padding: const EdgeInsets.symmetric(vertical: 13)),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Devolver con este texto'),
                      onPressed: () => _decidir('observar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Validar'),
                      onPressed: () => _decidir('validar'),
                    ),
                  ),
                ]),
              ),
            ),
      body: _cargando
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: cessumRed),
                  const SizedBox(height: 14),
                  Text('Revisando la planeación contra la norma institucional…\nPuede tardar hasta un minuto.',
                      textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context), height: 1.45)),
                ]),
              ),
            )
          : _error.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: [
                  _semaforo(),
                  if (_d['reentrega'] == true) _reentrega(),
                  _seccion(
                      _d['origen'] == 'propia' ? 'Revisión contra la norma (leída por la IA del archivo del docente)' : 'Revisión contra la norma',
                      Icons.fact_check_outlined, [
                    for (final c in chequeos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(_iconoEstado('${c['estado']}'), size: 19, color: _colorEstado('${c['estado']}')),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${c['titulo']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              Text('${c['detalle']}', style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.35)),
                            ]),
                          ),
                        ]),
                      ),
                  ]),
                  if (fortalezas.isNotEmpty)
                    _seccion('Fortalezas', Icons.thumb_up_alt_outlined, [
                      for (final f in fortalezas) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('+ $f', style: const TextStyle(fontSize: 12.5, height: 1.4))),
                    ]),
                  _seccion('Borrador del dictamen (editable)', Icons.edit_note, [
                    Text(
                      _d['decisionSugerida'] == 'validar'
                          ? 'Nota de reconocimiento para el docente. Si validas, viaja en el correo de validación.'
                          : 'Observaciones para el docente. Si devuelves, las recibe tal cual por correo.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _borrador,
                      minLines: 8,
                      maxLines: 20,
                      maxLength: 4000,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ]),
                ]),
    );
  }
}

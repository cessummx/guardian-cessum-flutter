// =====================================================================
//  mis_planeaciones_screen.dart · CESSUM · Aula CESSUM
//  VER MIS PLANEACIONES — estatus, versiones y documento.
//
//  El docente entrega su planeación y hasta ahora no tenía dónde ver qué
//  pasó con ella. Aquí ve el estatus de cada una —en revisión, validada,
//  con observaciones—, las observaciones completas cuando se la devuelven,
//  y puede abrirla en una ventana para leerla o descargarla.
//
//  Importa por una razón concreta: la planeación validada es uno de los
//  TRES requisitos para el pago, junto con el contrato firmado y el acta.
//  Si el docente no puede ver en qué estado está la suya, se entera de que
//  faltaba cuando el pago no llega.
//
//  Backend: POST planea_mis_entregas
// =====================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as html; // abrir el documento propio en Drive

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'planeacion_didactica_screen.dart';
import 'planeacion_documento.dart';

// (8-oct-2026) Antes varias listas se castaban con `.map((e) => Map<String, dynamic>.from(e as Map))`
// sin protección: un elemento mal formado en «observaciones» tronaba toda la pantalla en vez de
// solo omitirse. Ahora se descarta en silencio lo que no tenga forma de mapa.
List<Map<String, dynamic>> _comoListaMapas(dynamic l) {
  if (l is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final x in l) {
    if (x is Map) out.add(Map<String, dynamic>.from(x));
  }
  return out;
}

class MisPlaneacionesScreen extends StatefulWidget {
  const MisPlaneacionesScreen({super.key});
  @override
  State<MisPlaneacionesScreen> createState() => _MisPlaneacionesScreenState();
}

class _MisPlaneacionesScreenState extends State<MisPlaneacionesScreen> {
  bool _cargando = true;
  String _error = '';
  String _correo = '';
  List<Map<String, dynamic>> _entregas = [];
  // (5-oct-2026) Qué sigue: los tres requisitos de pago por materia y el siguiente paso.
  List<Map<String, dynamic>> _semaforo = [];
  String _bajando = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'planea_mis_entregas', 'correo': _correo, 'actor': _correo}))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo cargar.');
      if (!mounted) return;
      setState(() {
        _entregas = _comoListaMapas(j['entregas']);
        _cargando = false;
      });
      _cargarSemaforo();
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  /* (5-oct-2026) «QUÉ SIGUE». Por materia: planeación validada, contrato firmado y acta validada (las mismas verificaciones
     que usa el aviso de pago), y el siguiente paso. Con observaciones: primero las de la norma, y un botón que abre la
     planeación con esas observaciones ya escritas para corregirla con IA. */
  Future<void> _cargarSemaforo() async {
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'planea_mi_semaforo', 'correo': _correo, 'actor': _correo}))
          .timeout(const Duration(seconds: 90));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['ok'] == true && mounted) {
        setState(() => _semaforo = _comoListaMapas(j['materias']));
      }
    } catch (_) {}
  }

  Widget _luz(String t, bool ok, {bool espera = false}) {
    final c = ok ? const Color(0xFF1E8E3E) : (espera ? const Color(0xFFB7791F) : cessumRed);
    return Container(
      margin: const EdgeInsets.only(right: 6, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? Icons.check_circle : (espera ? Icons.schedule : Icons.cancel), size: 14, color: c),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }

  Future<void> _corregir(Map<String, dynamic> m) async {
    // (8-oct-2026) Cast defensivo: antes `(m['requisitos'] as Map)['planeacion'] as Map` tronaba
    // de golpe si «requisitos» venía ausente/nulo (por ejemplo un registro viejo con otra forma).
    final requisitos = Map<String, dynamic>.from((m['requisitos'] as Map?) ?? {});
    final rp = Map<String, dynamic>.from((requisitos['planeacion'] as Map?) ?? {});
    final obs = _comoListaMapas(m['observaciones']);
    // (8-oct-2026) Si una observación no trae texto, se omite en vez de escribir "null" literal.
    final textos = [
      for (final o in obs)
        if ('${o['texto'] ?? ''}'.trim().isNotEmpty) '${o['texto']}'.trim(),
    ];
    final retro = 'Atiende estas observaciones de Vicerrectoría:\n' +
        [for (var i = 0; i < textos.length; i++) '${i + 1}. ${textos[i]}'].join('\n');
    // (8-oct-2026) Si la planeación no trae su id (registro viejo con otra forma), no se abre
    // «a corregir» una planeación que no se puede resolver: se avisa en vez de navegar a ciegas.
    final idPlaneacion = '${rp['idPlaneacion'] ?? ''}';
    if (idPlaneacion.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se encontró el identificador de esta planeación: no se puede abrir para corregirla desde aquí.')));
      }
      return;
    }
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PlaneacionDidacticaScreen(
                abrirId: idPlaneacion, abrirMateria: '${m['materia']}', abrirGrupo: '${m['grupo']}', retroInicial: retro)));
    if (mounted) _cargar();
  }

  Widget _seccionQueSigue() {
    if (_semaforo.isEmpty) return const SizedBox.shrink();
    final listas = _semaforo.where((m) => m['completos'] == 3).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Qué sigue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cessumInk(context))),
      const SizedBox(height: 2),
      Text('Para el pago de cada materia se necesitan tres cosas: planeación validada, contrato firmado y acta validada. '
          '$listas de ${_semaforo.length} materia(s) ya las tienen.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4)),
      const SizedBox(height: 10),
      for (final m in _semaforo) _tarjetaSemaforo(m),
      const SizedBox(height: 8),
      Text('Mis entregas', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: cessumInk(context))),
      const SizedBox(height: 8),
    ]);
  }

  Widget _tarjetaSemaforo(Map<String, dynamic> m) {
    final rq = Map<String, dynamic>.from((m['requisitos'] as Map?) ?? {});
    final pl = Map<String, dynamic>.from((rq['planeacion'] as Map?) ?? {});
    final sig = Map<String, dynamic>.from((m['siguiente'] as Map?) ?? {});
    final accion = '${sig['accion'] ?? ''}';
    final obs = _comoListaMapas(m['observaciones']);
    final urgente = ['corregir', 'planear', 'contrato', 'acta'].contains(accion);
    final estPl = '${pl['estado'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: accion == 'listo' ? const Color(0xFF1E8E3E).withValues(alpha: 0.4) : (urgente ? cessumRed.withValues(alpha: 0.35) : Colors.transparent))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m['materia']}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          Text('${m['programa']} · ${m['generacion']} · Grupo ${m['grupo']}${m['terminada'] == true ? ' · terminó ${m['termino']}' : ''}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          Wrap(children: [
            _luz(estPl == 'validada' ? 'Planeación validada' : (estPl == 'entregada' ? 'Planeación en revisión' : (estPl == 'con observaciones' ? 'Planeación con observaciones' : 'Sin planeación')),
                pl['ok'] == true, espera: estPl == 'entregada'),
            _luz((rq['contrato'] as Map?)?['ok'] == true ? 'Contrato firmado' : 'Contrato sin firmar', (rq['contrato'] as Map?)?['ok'] == true),
            _luz((rq['acta'] as Map?)?['ok'] == true ? 'Acta validada' : (m['terminada'] == true ? 'Acta pendiente' : 'Acta al terminar'),
                (rq['acta'] as Map?)?['ok'] == true, espera: m['terminada'] != true),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(accion == 'listo' ? Icons.verified : Icons.arrow_forward, size: 17, color: accion == 'listo' ? const Color(0xFF1E8E3E) : cessumRed),
            const SizedBox(width: 6),
            Expanded(child: Text('${sig['texto'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4))),
          ]),
          if (accion == 'corregir' && obs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Atiende primero las marcadas «norma»: son las que impiden la validación.', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 4),
            for (var i = 0; i < obs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. ', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  if (obs[i]['prioridad'] == 'alta')
                    Container(
                      margin: const EdgeInsets.only(right: 6, top: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: const Text('norma', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cessumRed)),
                    ),
                  Expanded(
                    child: Text('${obs[i]['texto']}${((obs[i]['sesiones'] as List?) ?? []).isNotEmpty ? ' (sesión ${(obs[i]['sesiones'] as List).join(', ')})' : ''}',
                        style: const TextStyle(fontSize: 12.5, height: 1.4)),
                  ),
                ]),
              ),
            const SizedBox(height: 6),
            if (pl['origen'] == 'propia')
              Text('Tu planeación es un archivo propio: corrígelo y vuelve a entregarlo desde «Nueva planeación».',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)))
            else if (((pl['versionesRestantes'] as num?) ?? 0) <= 0)
              Text('Ya usaste las 3 versiones con IA: descarga la planeación en Word, corrígela y entrégala como archivo propio.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)))
            else
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () => _corregir(m),
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text('Corregir con IA usando estas observaciones (te quedan ${pl['versionesRestantes']} versión/es)'),
              ),
          ],
          if (accion == 'planear') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => PlaneacionDidacticaScreen(grupoInicial: {
                      'materia': m['materia'], 'programa': m['programa'], 'generacion': m['generacion'], 'grupo': m['grupo']})));
                if (mounted) _cargar();
              },
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('Planear esta materia'),
            ),
          ],
        ]),
      ),
    );
  }

  /// ¿Hay algo que abrir? Las propias son un enlace de Drive; las generadas
  /// con el asistente se arman aquí mismo.
  bool _tieneDoc(Map<String, dynamic> e) => '${e['origen']}' == 'propia'
      ? '${e['archivo'] ?? ''}'.isNotEmpty
      : '${e['idPlaneacion'] ?? ''}'.isNotEmpty;

  /// Las propias abren su documento en Drive. Las generadas se reconstruyen
  /// en la app: se piden los datos al Guardián y se arma el Word o el PDF
  /// aquí mismo, sin pestañas intermedias.
  Future<void> _abrir(Map<String, dynamic> e, {required bool pdf}) async {
    if ('${e['origen']}' == 'propia') {
      final u = '${e['archivo'] ?? ''}';
      if (u.isNotEmpty) html.window.open(u, '_blank');
      return;
    }
    final id = '${e['idPlaneacion'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _bajando = id);
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=planea_obtener&id=${Uri.encodeComponent(id)}'
              '&actor=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 45));
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
      if (pdf) {
        // (2-oct) imprimirPdf avisa si el navegador bloqueó la ventana; antes no decía nada.
        final abierta = imprimirPdf(cuerpo, ctx);
        if (!abierta && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El navegador bloqueó la ventana del PDF. Permite las ventanas emergentes '
                'de app.cessum.mx e inténtalo de nuevo.'),
            backgroundColor: cessumRed,
          ));
        }
      } else {
        descargarWord(cuerpo, ctx);
      }
    } catch (ex) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$ex'.replaceFirst('Exception: ', '')),
          backgroundColor: cessumRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _bajando = '');
    }
  }

  // La ficha completa en ventana emergente: el docente ve todo el detalle
  // sin salir de la lista, y desde ahí abre o descarga.
  void _verDetalle(Map<String, dynamic> e) {
    final est = '${e['estado']}';
    final col = _color(est);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              decoration: BoxDecoration(
                color: col,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_etiqueta(est),
                        style: const TextStyle(color: Colors.white70, fontSize: 10.5, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${e['materia']}',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ]),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _dato('Programa', '${e['programa'] ?? ''}'),
                  _dato('Generación y grupo',
                      '${e['generacion'] ?? ''}${'${e['grupo'] ?? ''}'.isNotEmpty ? ' · Grupo ${e['grupo']}' : ''}'),
                  _dato('Folio', '${e['folio'] ?? ''}'),
                  _dato('Enviada', '${e['entregada'] ?? ''}'),
                  _dato('Origen', '${e['origen']}' == 'propia'
                      ? 'Documento propio que subiste'
                      : 'Generada con el asistente'
                          '${(e['versiones'] ?? 0) != 0 ? ' · ${e['versiones']} versión(es)' : ''}'),
                  if (e['pctComplejas'] != null)
                    _dato('Interacciones complejas',
                        '${e['pctComplejas']} % del tiempo'
                        '${(e['pctComplejas'] is num && (e['pctComplejas'] as num) < 40) ? '  ·  bajo el mínimo de 40 %' : ''}'),
                  if ('${e['modeloVersion'] ?? ''}'.isNotEmpty)
                    // (10-sep) «SESUM» no era un nombre institucional y salía
                    // impreso en la planeación validada que ve el docente.
                    _dato('Modelo', 'CESSUM ${e['modeloVersion']}'),
                  if ('${e['firma'] ?? ''}'.isNotEmpty)
                    _dato('Firmada por', '${e['firma']}'),
                  if ('${e['revisor'] ?? ''}'.isNotEmpty)
                    _dato('Revisó', '${e['revisor']}'
                        '${'${e['dictaminada'] ?? ''}'.isNotEmpty ? ' · ${e['dictaminada']}' : ''}'),

                  if ('${e['observaciones'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('OBSERVACIONES DE VICERRECTORÍA',
                        style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: cessumRed)),
                    const SizedBox(height: 5),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: cessumGold.withValues(alpha: 0.08),
                        border: Border.all(color: CC.goldBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${e['observaciones']}',
                          style: const TextStyle(fontSize: 13, height: 1.5)),
                    ),
                  ],

                  const SizedBox(height: 14),
                  _queSigue(est),
                ]),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: cessumMuted(context).withValues(alpha: 0.18))),
              ),
              child: Row(children: [
                if (_tieneDoc(e)) ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13)),
                      onPressed: () { Navigator.pop(context); _abrir(e, pdf: false); },
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: Text('${e['origen']}' == 'propia' ? 'Abrir' : 'Word'),
                    ),
                  ),
                  if ('${e['origen']}' != 'propia') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: cessumRed, side: BorderSide(color: cessumRed),
                            padding: const EdgeInsets.symmetric(vertical: 13)),
                        onPressed: () { Navigator.pop(context); _abrir(e, pdf: true); },
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                        label: const Text('PDF'),
                      ),
                    ),
                  ],
                ] else
                  Expanded(child: Text('Sin documento adjunto',
                      style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))),
                if (est == 'con observaciones') ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed, side: BorderSide(color: cessumRed),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13)),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const PlaneacionDidacticaScreen()));
                    },
                    child: const Text('Corregir'),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _dato(String k, String v) => v.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 132, child: Text(k,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumGold))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13, height: 1.4))),
          ]),
        );

  // Qué tiene que hacer el docente ahora. Un estatus sin acción deja a la
  // persona mirando una etiqueta sin saber si le toca algo.
  Widget _queSigue(String est) {
    String t; Color c;
    if (est == 'validada') {
      t = 'Tu planeación está validada. Queda en el expediente del curso y cubre uno de los '
          'tres requisitos para el pago, junto con el contrato firmado y el acta de calificaciones.';
      c = const Color(0xFF1E8E3E);
    } else if (est == 'con observaciones') {
      t = 'Vicerrectoría te devolvió la planeación para ajustes. Corrígela y vuelve a enviarla: '
          'la nueva sustituye a esta. Mientras no esté validada, no cubre el requisito para el pago.';
      c = cessumRed;
    } else {
      t = 'Tu planeación está en la bandeja de Vicerrectoría esperando dictamen. No tienes que hacer '
          'nada por ahora; te avisaremos por correo cuando esté revisada.';
      c = cessumGold;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        border: Border.all(color: c.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(t, style: TextStyle(fontSize: 12.5, height: 1.5, color: cessumInk(context))),
    );
  }

  Color _color(String est) => est == 'validada'
      ? const Color(0xFF1E8E3E)
      : est == 'con observaciones' ? cessumRed : cessumGold;

  String _etiqueta(String est) => est == 'validada'
      ? 'VALIDADA'
      : est == 'con observaciones' ? 'CON OBSERVACIONES' : 'EN REVISIÓN';

  @override
  Widget build(BuildContext context) {
    final conObs = _entregas.where((e) => '${e['estado']}' == 'con observaciones').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis planeaciones'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const PlaneacionDidacticaScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Nueva planeación'),
      ),
      // Armar el documento pide los datos al Guardián: puede tardar unos
      // segundos, y sin aviso el docente vuelve a tocar el botón.
      body: (_cargando || _bajando.isNotEmpty)
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                if (_bajando.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Preparando el documento…',
                      style: TextStyle(fontSize: 13.5, color: cessumMuted(context))),
                ],
              ]),
            )
          : _error.isNotEmpty
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cessumRed))))
              : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), children: [
                  _seccionQueSigue(),   // (5-oct-2026) los tres requisitos de pago y el siguiente paso
                  if (conObs > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.07),
                        border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        conObs == 1
                            ? 'Una de tus planeaciones fue devuelta con observaciones. Corrígela y vuelve a enviarla.'
                            : '$conObs de tus planeaciones fueron devueltas con observaciones.',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF8E141D)),
                      ),
                    ),
                  if (_entregas.isEmpty) _vacio() else ..._entregas.map(_tarjeta),
                ]),
    );
  }

  Widget _vacio() => Column(children: [
        const SizedBox(height: 40),
        Icon(Icons.menu_book_outlined, size: 52, color: cessumGold.withValues(alpha: 0.45)),
        const SizedBox(height: 14),
        const Text('Todavía no has entregado ninguna planeación',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'La planeación didáctica validada es uno de los tres requisitos para el pago, junto con el '
            'contrato firmado y el acta de calificaciones. Puedes hacerla con el asistente, descargar '
            'la plantilla ya precargada con los datos de tu asignatura, o subir la que ya tengas.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: cessumMuted(context)),
          ),
        ),
      ]);

  Widget _tarjeta(Map<String, dynamic> e) {
    final est = '${e['estado']}';
    final col = _color(est);
    final pct = e['pctComplejas'];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: col.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: () => _verDetalle(e),
        child: Row(children: [
          Container(width: 5, height: 96, color: col),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text('${e['materia']}',
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                    child: Text(_etiqueta(est),
                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: col)),
                  ),
                ]),
                const SizedBox(height: 3),
                Text('${e['programa'] ?? ''} · ${e['generacion'] ?? ''} · Grupo ${e['grupo'] ?? ''}',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                const SizedBox(height: 5),
                Row(children: [
                  Text('Folio ${e['folio']} · ${e['entregada']}',
                      style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                  if (pct is num) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: (pct >= 40 ? const Color(0xFF1E8E3E) : cessumRed).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$pct % complejas',
                          style: TextStyle(fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: pct >= 40 ? const Color(0xFF1E8E3E) : cessumRed)),
                    ),
                  ],
                ]),
                if ('${e['observaciones'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('${e['observaciones']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.35, color: cessumRed)),
                ],
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(Icons.chevron_right, color: cessumMuted(context)),
          ),
        ]),
      ),
    );
  }
}

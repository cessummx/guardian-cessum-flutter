// FINANZAS INSTITUCIONALES · estados de cuenta bancarios (22-sep-2026)
//
// Rectoría, Vicerrectoría y Administración y Finanzas suben aquí, mes tras
// mes, el estado de cuenta de BBVA ya desbloqueado.
//
// CÓMO SE LEE
// El Guardián no puede extraer texto de un PDF, así que el PDF se lee AQUÍ, en
// el navegador, con pdf.js. Los montos salen del texto del PDF —exactos, sin
// inteligencia artificial de por medio— y se comprueban contra el resumen del
// propio banco: número de abonos y cargos, sus totales y el saldo final. Si no
// cuadra al centavo, no se sube. El Guardián vuelve a comprobarlo antes de
// guardar. La IA solo interpreta lo que ya está verificado.
import 'dart:convert';
import 'dart:math' as math;   // (23-sep) simulador
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'finanzas_graficas.dart';   // (23-sep) gráficas propias, sin librerías nuevas

const _kPdfJs = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
const _kPdfWorker =
    'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';

/// Correos con acceso. El Guardián hace la misma comprobación.
const kFinanzasCorreos = [
  'vicerrectoria@cessum.mx',
  'rectoria@cessum.mx',
  'administracion@cessum.mx',
  'contacto@cessum.mx',   // (23-sep) Ángel: decisiones de finanzas
];

class FinanzasScreen extends StatefulWidget {
  const FinanzasScreen({super.key});
  @override
  State<FinanzasScreen> createState() => _FinanzasScreenState();
}

class _FinanzasScreenState extends State<FinanzasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 8, vsync: this);   // (23-sep) Tablero, Mes, Histórico, Estadística, Proyección, Alertas, Movimientos, Asistente
  String _actor = '';
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _res = {};
  List<dynamic> _hist = [];
  // (23-sep) Inteligencia financiera: se pide al abrir la pestaña y se refresca al recargar.
  Map<String, dynamic>? _intel;
  bool _cargandoIntel = false;
  String _errorIntel = '';
  Map<String, dynamic>? _estad;   // (23-sep) estadística de toda la historia
  // (23-sep) Simulador de proyección
  Map<String, dynamic>? _sim;
  bool _cargandoSim = false;
  String _errorSim = '';
  int _simH = 36;
  final Map<String, double> _p = {};
  final _cSaldo = TextEditingController();
  String _simIa = '';
  bool _simIaCargando = false;
  String? _periodo;
  bool _leyendo = false;
  String _estadoSubida = '';
  String? _claveBbva;   // (23-sep) contraseña de los PDF: solo en memoria, durante la sesión
  List<dynamic> _movs = [];
  int _movsTotal = 0;
  final _cBuscar = TextEditingController();
  String _tipoMov = '';
  final List<Map<String, String>> _chat = [];
  final _cPregunta = TextEditingController();
  bool _pensando = false;
  bool _asistTotal = false;   // (23-sep) Asistente: false = el mes elegido · true = toda la historia
  static const int _kTabAsistente = 7;   // Tablero, Mes, Histórico, Estadística, Proyección, Alertas, Movimientos, ASISTENTE

  @override
  void initState() {
    super.initState();
    // (23-sep) Los botones de carga se ocultan en el Asistente: tapaban el
    // cuadro de escribir y el botón de enviar.
    _tabs.addListener(_alCambiarPestana);
    _iniciar();
  }

  void _alCambiarPestana() {
    if (!_tabs.indexIsChanging && mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    _cBuscar.dispose();
    _cPregunta.dispose();
    _cSaldo.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    // (24-sep) Correo REAL: en «Ver como profesor» el de la vista es el del profesor.
    _actor = ((await SessionStore.realEmail()) ?? '').trim().toLowerCase();
    await _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp) async {
    final r = await http
        .get(Uri.parse(guardianUrl)
            .replace(queryParameters: {...qp, 'actor': _actor}))
        .timeout(const Duration(seconds: 90));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({...body, 'actor': _actor}))
        .timeout(const Duration(seconds: 150));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar({String? periodo}) async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await _get({
        'accion': 'finanzas_resumen',
        if (periodo != null) 'periodo': periodo,
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      final h = await _get({'accion': 'finanzas_historico'});
      if (!mounted) return;
      setState(() {
        _res = r;
        _intel = null;   // (23-sep) con datos nuevos, el análisis se vuelve a calcular
        _estad = null;
        _sim = null;   // la base del simulador también se recalcula
        _hist = (h['historico'] as List?) ?? [];
        _periodo = r['periodo'] as String?;
        _cargando = false;
      });
      await _cargarMovs();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e';
      });
    }
  }

  Future<void> _cargarMovs() async {
    if (_periodo == null) return;
    try {
      final r = await _get({
        'accion': 'finanzas_movimientos',
        'periodo': _periodo!,
        'q': _cBuscar.text.trim(),
        if (_tipoMov.isNotEmpty) 'tipo': _tipoMov,
      });
      if (!mounted || r['ok'] != true) return;
      setState(() {
        _movs = (r['movimientos'] as List?) ?? [];
        _movsTotal = (r['total'] as num?)?.toInt() ?? _movs.length;
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------- lector
  Future<void> _cargarScript(String src) async {
    final s = html.ScriptElement()
      ..src = src
      ..async = false;
    html.document.head!.append(s);
    await s.onLoad.first.timeout(const Duration(seconds: 40));
  }

  Future<void> _asegurarLector() async {
    if (js_util.getProperty(html.window, 'pdfjsLib') == null) {
      await _cargarScript(_kPdfJs);
      // El «worker» se carga también como script: así pdf.js trabaja en la
      // misma página y no depende de crear un proceso desde otro dominio.
      await _cargarScript(_kPdfWorker);
      final lib = js_util.getProperty(html.window, 'pdfjsLib');
      final opts = js_util.getProperty(lib, 'GlobalWorkerOptions');
      js_util.setProperty(opts, 'workerSrc', _kPdfWorker);
    }
    if (js_util.getProperty(html.window, 'cessumLeerEstadoBBVA') == null) {
      final s = html.ScriptElement()..text = _kLectorBBVA;
      html.document.head!.append(s);
    }
  }

  /* (23-sep) LECTURA CON CONTRASEÑA. Si el PDF la pide, se pregunta una vez
     por sesión y se reintenta; si es incorrecta, se vuelve a preguntar. */
  Future<Map<String, dynamic>> _leerPdf(Uint8List bytes) async {
    await _asegurarLector();
    final lib = js_util.getProperty(html.window, 'pdfjsLib');
    for (var intento = 0; intento < 3; intento++) {
      final prom = js_util.callMethod(
          html.window, 'cessumLeerEstadoBBVA', [lib, bytes, _claveBbva ?? '']);
      final res = await js_util.promiseToFuture(prom);
      final txt = js_util.callMethod(
          js_util.getProperty(html.window, 'JSON'), 'stringify', [res]) as String;
      final d = jsonDecode(txt) as Map<String, dynamic>;
      if (d['error'] != 'CONTRASENA') return d;
      final c = await _pedirClave(incorrecta: d['incorrecta'] == true && (_claveBbva ?? '').isNotEmpty);
      if (c == null) return {'ok': false, 'error': 'Sin contraseña no se puede abrir el PDF.'};
      _claveBbva = c;
    }
    return {'ok': false, 'error': 'La contraseña no abrió el PDF.'};
  }

  Future<String?> _pedirClave({bool incorrecta = false}) {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(incorrecta ? 'Contraseña incorrecta' : 'Contraseña de los PDF',
            style: const TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'BBVA protege los estados de cuenta con el RFC en mayúsculas, sin homoclave. '
              'Se usa solo en este navegador y mientras la pantalla esté abierta; no se guarda.',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder()),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim().isEmpty ? null : v.trim()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, ctl.text.trim().isEmpty ? null : ctl.text.trim()),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );
  }

  /// Cuenta tomada del nombre del PDF de BBVA («0120887013_202608.pdf»):
  /// es exacta, a diferencia del texto del PDF.
  String _cuentaDeNombre(String nombre) {
    final m = RegExp(r'^(\d{6,})_\d{6}\.pdf$', caseSensitive: false).firstMatch(nombre.trim());
    return m == null ? '' : m.group(1)!;
  }

  Future<Uint8List> _bytesDeArchivo(html.File f) async {
    final reader = html.FileReader()..readAsArrayBuffer(f);
    await reader.onLoad.first;
    final raw = reader.result;
    return raw is Uint8List ? raw : (raw as ByteBuffer).asUint8List();
  }

  Future<void> _subir() async {
    final input = html.FileUploadInputElement()
      ..accept = '.pdf,application/pdf'
      ..multiple = true;   // (23-sep) uno o varios
    input.click();
    await input.onChange.first;
    final fs = input.files ?? const <html.File>[];
    if (fs.isEmpty) return;
    if (fs.length > 1) {
      await _procesarLote([
        for (final f in fs)
          _ItemLote(f.name, _cuentaDeNombre(f.name), () => _bytesDeArchivo(f)),
      ]);
      return;
    }
    final f = fs.first;
    setState(() {
      _leyendo = true;
      _estadoSubida = 'Leyendo ${f.name}…';
    });
    try {
      final bytes = await _bytesDeArchivo(f);
      final d = await _leerPdf(bytes);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo leer el PDF.');
      if (!mounted) return;
      setState(() => _leyendo = false);
      final ok = await _confirmarLectura(d);
      if (ok != true) return;
      setState(() {
        _leyendo = true;
        _estadoSubida = 'Guardando y clasificando los movimientos…';
      });
      final cta = _cuentaDeNombre(f.name);
      final g = await _post({
        'accion': 'finanzas_estado_guardar',
        'banco': d['banco'],
        'cuenta': cta.isNotEmpty ? cta : d['cuenta'],
        'periodo': d['periodo'],
        'resumen': d['resumen'],
        'movimientos': d['movimientos'],
      });
      if (g['ok'] != true) throw Exception(g['error'] ?? 'No se guardó.');
      if (!mounted) return;
      setState(() => _leyendo = false);
      _aviso('${g['nota'] ?? 'Guardado.'}');
      await _cargar(periodo: '${g['periodo']}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _leyendo = false);
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  /* (23-sep) TRAER DEL CORREO. El Guardián corre como contacto@cessum.mx, a
     donde BBVA manda los estados de cuenta: lista los PDF que hay y la
     pantalla los procesa sin descargarlos a mano. */
  Future<void> _traerDeGmail() async {
    setState(() {
      _leyendo = true;
      _estadoSubida = 'Buscando los estados de cuenta en el correo…';
    });
    Map<String, dynamic> r = const {};
    try {
      r = await _get({'accion': 'finanzas_bbva_lista'});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'No se pudo leer el correo.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _leyendo = false);
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _leyendo = false);
    final lista = List<Map<String, dynamic>>.from(
        (r['lista'] as List).map((x) => Map<String, dynamic>.from(x as Map)));
    if (lista.isEmpty) {
      _aviso('No encontré estados de cuenta de BBVA en el correo.', error: true);
      return;
    }
    final cuentas = Map<String, dynamic>.from(r['cuentas'] as Map);
    final pend = lista.where((x) => x['yaCargado'] != true).toList();
    final eleccion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estados de cuenta en el correo', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${lista.length} estados de cuenta, de ${r['desde']} a ${r['hasta']}.',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final c in cuentas.entries)
              Text('Cuenta ${c.key}: ${c.value} meses', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Text('Ya cargados: ${lista.length - pend.length} · Faltan: ${pend.length}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            const Text(
                'Cada uno se guarda solo si cuadra al centavo con el resumen del banco. '
                'Tarda unos segundos por estado de cuenta; no cierre la pantalla.',
                style: TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          if (pend.length < lista.length)
            TextButton(onPressed: () => Navigator.pop(ctx, 'todos'), child: const Text('Volver a cargar todos')),
          if (pend.isNotEmpty)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, 'faltan'),
              child: Text('Cargar los ${pend.length} que faltan'),
            ),
        ],
      ),
    );
    if (eleccion == null) return;
    final elegidos = eleccion == 'todos' ? lista : pend;
    await _procesarLote([
      for (final x in elegidos)
        _ItemLote('${x['cuenta']} · ${x['periodo']}', '${x['cuenta']}', () async {
          final p = await _get({'accion': 'finanzas_bbva_pdf', 'id': '${x['id']}', 'nombre': '${x['nombre']}'});
          if (p['ok'] != true) throw Exception(p['error'] ?? 'No se pudo tomar el PDF del correo.');
          return base64Decode('${p['b64']}');
        }),
    ]);
  }

  /* (23-sep) PROCESAMIENTO EN LOTE. Uno por uno, esperando cada respuesta: el
     que cuadra al centavo se guarda solo; el que no, se omite y queda en el
     reporte. Al final, el resumen y la pantalla actualizada. */
  Future<void> _procesarLote(List<_ItemLote> items) async {
    final guardados = <String>[], omitidos = <String>[];
    String ultimoPeriodo = '';
    setState(() => _leyendo = true);
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (!mounted) return;
      setState(() => _estadoSubida = 'Procesando ${i + 1} de ${items.length}: ${it.etiqueta}');
      try {
        final bytes = await it.cargar();
        final d = await _leerPdf(bytes);
        if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo leer.');
        final v = Map<String, dynamic>.from(d['verificacion'] as Map);
        if (v['cuadra'] != true) throw Exception('no cuadra con el resumen del banco');
        final g = await _post({
          'accion': 'finanzas_estado_guardar',
          'banco': d['banco'],
          'cuenta': it.cuenta.isNotEmpty ? it.cuenta : d['cuenta'],
          'periodo': d['periodo'],
          'resumen': d['resumen'],
          'movimientos': d['movimientos'],
        });
        if (g['ok'] != true) throw Exception(g['error'] ?? 'no se guardó');
        ultimoPeriodo = '${g['periodo']}';
        guardados.add('${it.etiqueta} · ${g['movimientos']} movimientos');
      } catch (e) {
        omitidos.add('${it.etiqueta}: ${'$e'.replaceFirst('Exception: ', '')}');
        if ('$e'.contains('Sin contraseña')) break;   // canceló la contraseña: no insistir con el resto
      }
    }
    if (!mounted) return;
    setState(() => _leyendo = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(omitidos.isEmpty ? 'Listo' : 'Terminado, con pendientes',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Guardados y verificados: ${guardados.length} de ${items.length}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1E7F52))),
              if (omitidos.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('No se guardaron (${omitidos.length}):',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: cessumRed)),
                for (final o in omitidos) Text('• $o', style: const TextStyle(fontSize: 12.5)),
              ],
            ]),
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    await _cargar(periodo: ultimoPeriodo.isEmpty ? null : ultimoPeriodo);
  }

  Future<bool?> _confirmarLectura(Map<String, dynamic> d) {
    final r = Map<String, dynamic>.from(d['resumen'] as Map);
    final v = Map<String, dynamic>.from(d['verificacion'] as Map);
    final cuadra = v['cuadra'] == true;
    final per = Map<String, dynamic>.from(d['periodo'] as Map);
    String c(dynamic x) => _m(((x as num?) ?? 0) / 100);
    Widget fila(String a, String b, {bool neg = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(fontSize: 13))),
            Text(b,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: neg ? cessumRed : null)),
          ]),
        );
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cuadra ? 'Estado de cuenta leído' : 'La lectura no cuadra',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            fila('Cuenta', '${d['cuenta']}'),
            fila('Periodo', '${per['desde']} al ${per['hasta']}'),
            fila('Saldo inicial', c(r['saldoInicial'])),
            fila('Abonos (${v['abonosN']} de ${r['abonosN']})', c(v['abonosTotal'])),
            fila('Cargos (${v['cargosN']} de ${r['cargosN']})', c(v['cargosTotal']), neg: true),
            fila('Saldo final', c(r['saldoFinal'])),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (cuadra ? const Color(0xFF1E7F52) : cessumRed)
                    .withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                  cuadra
                      ? 'Cuadra al centavo con el resumen del banco: ${(d['movimientos'] as List).length} movimientos.'
                      : 'Lo leído no coincide con el resumen del banco, así que no se puede subir. Revise que sea el PDF completo del estado de cuenta de BBVA, sin páginas faltantes.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: cuadra ? const Color(0xFF1E7F52) : cessumRed)),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(cuadra ? 'Cancelar' : 'Cerrar')),
          if (cuadra)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
        ],
      ),
    );
  }

  Future<void> _descartar(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar alerta', style: TextStyle(fontSize: 16)),
        content: Text('«${a['titulo']}» dejará de aparecer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await _get({
        'accion': 'finanzas_alerta_descartar',
        'llave': '${a['llave']}',
        'titulo': '${a['titulo']}',
      });
      if (r['ok'] != true) throw Exception(r['error']);
      await _cargar(periodo: _periodo);
    } catch (e) {
      _aviso('$e', error: true);
    }
  }

  Future<void> _preguntar([String? texto]) async {
    final q = (texto ?? _cPregunta.text).trim();
    if (q.isEmpty || _pensando) return;
    final total = _asistTotal;
    setState(() {
      _chat.add({'de': 'yo', 'texto': q, 'alcance': total ? 'Toda la historia' : 'Mes: ${_mes(_periodo)}'});
      _pensando = true;
      _cPregunta.clear();
    });
    try {
      final r = await _post({
        'accion': 'finanzas_asistente',
        'pregunta': q,
        'periodo': _periodo,
        'alcance': total ? 'total' : 'mes',   // (23-sep)
      });
      if (!mounted) return;
      setState(() {
        _chat.add({
          'de': 'ia',
          'texto': r['ok'] == true
              ? '${r['respuesta']}'
              : 'No pude responder: ${r['error'] ?? 'sin respuesta'}'
        });
        _pensando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chat.add({'de': 'ia', 'texto': 'No pude responder: $e'});
        _pensando = false;
      });
    }
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: error ? cessumRed : const Color(0xFF1E7F52),
        content: Text(t)));
  }

  // --------------------------------------------------------------- formato
  static String _m(dynamic v) {
    final x = (v is num ? v : num.tryParse('$v') ?? 0).toDouble();
    final s = x.abs().toStringAsFixed(2).split('.');
    final e = s[0], b = StringBuffer();
    for (var i = 0; i < e.length; i++) {
      if (i > 0 && (e.length - i) % 3 == 0) b.write(',');
      b.write(e[i]);
    }
    return '${x < 0 ? '-' : ''}\$$b.${s[1]}';
  }

  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];
  static String _mes(String? p) {
    if (p == null || p.length < 7) return p ?? '';
    final m = int.tryParse(p.substring(5, 7)) ?? 0;
    return m >= 1 && m <= 12 ? '${_meses[m - 1]} ${p.substring(0, 4)}' : p;
  }

  // ----------------------------------------------------------------- vista
  @override
  Widget build(BuildContext context) {
    final periodos = ((_res['periodos'] as List?) ?? []).map((e) => '$e').toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Finanzas · estados de cuenta'),
        actions: [
          if (periodos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DropdownButton<String>(
                value: periodos.contains(_periodo) ? _periodo : null,
                dropdownColor: cessumRed,
                underline: const SizedBox.shrink(),
                iconEnabledColor: Colors.white,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                items: periodos.reversed
                    .map((p) => DropdownMenuItem(value: p, child: Text(_mes(p))))
                    .toList(),
                onChanged: (p) => _cargar(periodo: p),
              ),
            ),
          IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : () => _cargar(periodo: _periodo),
              icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Tablero'),
            Tab(text: 'Mes'),
            Tab(text: 'Histórico'),
            Tab(text: 'Estadística'),
            Tab(text: 'Proyección'),
            Tab(text: 'Alertas'),
            Tab(text: 'Movimientos'),
            Tab(text: 'Asistente'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == _kTabAsistente ? null : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (!_leyendo)
          FloatingActionButton.extended(
            heroTag: 'finGmail',
            backgroundColor: Colors.white,
            foregroundColor: cessumRed,
            onPressed: _traerDeGmail,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('Traer del correo'),
          ),
        if (!_leyendo) const SizedBox(height: 10),
        FloatingActionButton.extended(
        heroTag: 'finSubir',
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _leyendo ? null : _subir,
        icon: _leyendo
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file),
        label: Text(_leyendo ? _estadoSubida : 'Subir estado de cuenta'),
      ),
      ]),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? _centro(_error, Icons.error_outline)
              : (_res['vacio'] == true)
                  ? _centro(
                      'Todavía no hay estados de cuenta. Tráigalos del correo o suba los PDF de BBVA, con o sin contraseña, con los botones de abajo.',
                      Icons.account_balance)
                  : TabBarView(controller: _tabs, children: [
                      _vistaTablero(),
                      _vistaResumen(),
                      _vistaHistoricoComp(),
                      _vistaEstadistica(),
                      _vistaProyeccion(),
                      _vistaAlertas(),
                      _vistaMovimientos(),
                      _vistaAsistente(),
                    ]),
    );
  }

  Widget _centro(String t, IconData i) => Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 44, color: cessumGold),
            const SizedBox(height: 12),
            Text(t, textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget _tarjeta(Widget hijo, {EdgeInsets? margin}) => Container(
        margin: margin ?? const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withValues(alpha: 0.25)),
        ),
        child: hijo,
      );

  Widget _cifra(String titulo, dynamic v, Color color, {String? pie}) =>
      Expanded(
        child: _tarjeta(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              const SizedBox(height: 4),
              Text(_m(v),
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: color)),
              if (pie != null)
                Text(pie,
                    style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ]),
            margin: const EdgeInsets.only(right: 8, bottom: 10)),
      );

  String? _comparado(String campo) {
    final a = _res['anterior'];
    final e = _res['estado'];
    if (a == null || e == null) return null;
    final prev = ((a as Map)[campo] as num?)?.toDouble() ?? 0;
    final ahora = ((e as Map)[campo] as num?)?.toDouble() ?? 0;
    if (prev == 0) return null;
    final pct = ((ahora / prev - 1) * 100).round();
    return '${pct >= 0 ? '+' : ''}$pct % vs ${_mes('${a['periodo']}')}';
  }

  Widget _barras(List<Map<String, dynamic>> filas, Color color) {
    final max = filas.fold<double>(
        0, (m, f) => ((f['total'] as num?)?.toDouble() ?? 0) > m ? (f['total'] as num).toDouble() : m);
    return Column(
        children: filas.map((f) {
      final v = (f['total'] as num?)?.toDouble() ?? 0;
      final subs = ((f['subs'] as List?) ?? []);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('${f['categoria'] ?? f['nombre']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            Text(_m(v), style: const TextStyle(fontSize: 13)),
          ]),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: max > 0 ? v / max : 0,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          if (subs.isNotEmpty && subs.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                  subs
                      .take(4)
                      .map((s) => '${s['sub']}: ${_m(s['total'])}')
                      .join(' · '),
                  style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ),
        ]),
      );
    }).toList());
  }

  Widget _vistaResumen() {
    final e = Map<String, dynamic>.from((_res['estado'] as Map?) ?? {});
    final cats = ((_res['categorias'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    final eg = cats.where((c) => c['tipo'] == 'Egreso').toList();
    final ing = cats.where((c) => c['tipo'] == 'Ingreso').toList();
    final topE = ((_res['topEgresos'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    final nAl = ((_res['alertas'] as List?) ?? []).length;
    final neto = ((e['ingresos'] as num?) ?? 0) - ((e['egresos'] as num?) ?? 0);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 90), children: [
      Text(_mes(_periodo),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Row(children: [
        _cifra('Ingresos', e['ingresos'], const Color(0xFF1E7F52), pie: _comparado('ingresos')),
        _cifra('Egresos', e['egresos'], cessumRed, pie: _comparado('egresos')),
      ]),
      Row(children: [
        _cifra('Resultado del mes', neto, neto >= 0 ? const Color(0xFF1E7F52) : cessumRed),
        _cifra('Saldo al cierre', e['saldoFinal'], cessumGold,
            pie: 'Comisiones: ${_m(e['comisiones'])}'),
      ]),
      if (nAl > 0)
        _tarjeta(Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB8860B)),
          const SizedBox(width: 10),
          Expanded(child: Text('$nAl alerta(s) para revisar este mes.')),
          TextButton(onPressed: () => _tabs.animateTo(5), child: const Text('Ver')),   // Alertas: Tablero, Mes, Histórico, Estadística, Proyección, ALERTAS
        ])),
      _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('¿En qué se fue el dinero?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        _barras(eg, cessumRed),
      ])),
      _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('¿De dónde entró?',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        _barras(ing, const Color(0xFF1E7F52)),
      ])),
      _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('A quién se le pagó más',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        _barras(topE, cessumGold),
      ])),
    ]);
  }

  /* ======================================================================
     (23-sep) ANÁLISIS · Tablero, Histórico, Estadística y Proyección.
     Todo lo calcula el Guardián (finanzas_inteligencia y finanzas_estadistica)
     sobre TODA la historia, sin traspasos entre cuentas propias. Aquí solo se
     presenta. Las dos consultas se hacen juntas al abrir cualquiera de estas
     pestañas y se vuelven a hacer al recargar.
     ====================================================================== */
  Future<void> _cargarAnalisis() async {
    if (_cargandoIntel) return;
    setState(() {
      _cargandoIntel = true;
      _errorIntel = '';
    });
    try {
      final rs = await Future.wait([
        _get({'accion': 'finanzas_inteligencia'}),
        _get({'accion': 'finanzas_estadistica'}),
      ]);
      final a = rs[0], b = rs[1];
      if (a['ok'] != true && a['vacio'] != true) throw Exception(a['error'] ?? 'Error');
      if (b['ok'] != true) throw Exception(b['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _intel = a;
        _estad = b;
        _cargandoIntel = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoIntel = false;
        _errorIntel = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /// Mientras no hay análisis: dispara la carga y muestra la espera o el error.
  Widget? _esperaAnalisis() {
    if (_intel != null && _estad != null) return null;
    if (!_cargandoIntel && _errorIntel.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cargarAnalisis());
    }
    if (_errorIntel.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_errorIntel, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                setState(() => _errorIntel = '');
                _cargarAnalisis();
              },
              child: const Text('Reintentar'),
            ),
          ]),
        ),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: cessumRed),
        const SizedBox(height: 12),
        Text('Analizando toda la historia…', style: TextStyle(color: cessumMuted(context))),
      ]),
    );
  }

  static const Color _verde = Color(0xFF1E7F52);
  static const Color _ambar = Color(0xFFB7791F);
  static const Color _oro = Color(0xFF9C7A2B);

  String _pct(dynamic v) => v == null ? '—' : '${((v as num) * 100).round()}%';
  String _num(dynamic v) => v == null ? '—' : '$v';
  List<double?> _lista(dynamic l) =>
      (l as List? ?? const []).map((x) => x == null ? null : (x as num).toDouble()).toList();
  Map<String, dynamic> _mapa(dynamic m) => Map<String, dynamic>.from((m as Map?) ?? const {});
  List<Map<String, dynamic>> _maps(dynamic l) =>
      (l as List? ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();

  Widget _kpi(String titulo, String valor, {String? pie, Color? color}) => SizedBox(
        width: 172,
        child: _tarjeta(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 4),
            Text(valor, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
            if (pie != null) ...[
              const SizedBox(height: 2),
              Text(pie, style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ],
          ]),
          margin: EdgeInsets.zero,
        ),
      );

  Widget _titulo(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sub, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            ),
        ]),
      );

  Widget _queSignifica(String t) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lightbulb_outline, size: 16, color: _oro),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5))),
        ]),
      );

  Widget _dato(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: 12, color: cessumMuted(context)))),
          Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _tablaHorizontal(List<String> cabeza, List<List<String>> filas, {int? resaltarCol}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 34,
        dataRowMinHeight: 30,
        dataRowMaxHeight: 36,
        columnSpacing: 18,
        horizontalMargin: 8,
        headingTextStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
        dataTextStyle: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
        columns: [for (final c in cabeza) DataColumn(label: Text(c))],
        rows: [
          for (final f in filas)
            DataRow(cells: [
              for (var i = 0; i < f.length; i++)
                DataCell(Text(f[i],
                    style: TextStyle(fontWeight: i == 0 || i == resaltarCol ? FontWeight.w700 : null))),
            ]),
        ],
      ),
    );
  }

  String _pValor(dynamic p) {
    if (p == null) return '—';
    final v = (p as num).toDouble();
    return v < 0.001 ? '< 0.001' : v.toStringAsFixed(3);
  }

  /* ------------------------------ TABLERO ------------------------------ */
  Widget _vistaTablero() {
    final espera = _esperaAnalisis();
    if (espera != null) return espera;
    final d = _intel!;
    if (d['vacio'] == true) {
      return _centro('Todavía no hay estados de cuenta para analizar.', Icons.insights);
    }
    final e = _estad!;
    final ind = _mapa(d['indicadores']);
    final alu = _mapa(d['alumnos']);
    final car = _mapa(d['cartera']);
    final recs = _maps(d['recomendaciones']);
    final anom = _maps(d['anomalias']);
    final top = _maps(d['topEgresos']);
    final ant = _mapa(car['porAntiguedad']);
    final porProg = _mapa(alu['porPrograma']);
    final ser = _mapa(e['series']);
    final per = (ser['periodos'] as List? ?? const []).map((x) => '$x').toList();
    final et = per.map(finEtiqueta).toList();
    final margen = ind['margen12'] as num?;
    final crec = ind['crecimientoAnual'] as num?;
    final meses = ind['mesesDeOperacion'] as num?;
    final tasa = car['tasaCobranza6'] as num?;
    final eq = alu['equilibrioAlumnos'] as num?;
    final act = alu['activos'] as num?;
    final maxAnt = ant.values.fold<double>(
        1, (m, v) => ((v as num).toDouble() > m) ? v.toDouble() : m);
    Color nivelColor(String n) => n == 'alta' ? cessumRed : (n == 'media' ? _ambar : _verde);

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargarAnalisis,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
        const Text('Tablero financiero', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(
            '${e['desdeNombre']} a ${e['hastaNombre']} · ${e['meses']} meses de estados de cuenta, sin traspasos entre cuentas propias, '
            'cruzados con el padrón y los vencimientos del Guardián · ${d['generado']}',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _kpi('Saldo en bancos', _m(ind['saldo']), pie: 'Al cierre de ${e['hastaNombre']}'),
          _kpi('Resultado del año', _m(ind['resultado12']),
              color: ((ind['resultado12'] as num?) ?? 0) >= 0 ? _verde : cessumRed,
              pie: 'Ingresos − egresos, 12 meses'),
          _kpi('Margen', _pct(margen), color: (margen ?? 0) >= 0 ? _verde : cessumRed),
          _kpi('Crecimiento de ingresos', _pct(crec),
              color: crec == null ? null : (crec >= 0 ? _verde : cessumRed),
              pie: 'Contra los 12 meses previos'),
          _kpi('Meses de operación', meses == null ? '—' : '$meses',
              color: meses == null ? null : (meses < 2 ? cessumRed : (meses < 4 ? _ambar : _verde)),
              pie: 'Con el saldo, sin ingresos nuevos'),
          _kpi('Egreso mensual típico', _m(ind['egresoMensualBase']), pie: 'Mediana de 6 meses'),
          _kpi('Alumnos activos', _num(act), pie: 'Padrón del Guardián'),
          _kpi('Ingreso por alumno', _m(alu['ingresoPorAlumno']), pie: 'Al mes, promedio de 3 meses'),
          _kpi('Punto de equilibrio', eq == null ? '—' : '$eq alumnos',
              color: (eq != null && act != null && eq > act) ? cessumRed : _verde,
              pie: 'Para cubrir el egreso típico'),
          _kpi('Cobranza', _pct(tasa),
              color: tasa == null ? null : (tasa < 0.8 ? cessumRed : (tasa < 0.9 ? _ambar : _verde)),
              pie: 'Pagado / vencido, 6 meses'),
          _kpi('Cartera vencida', _m(car['vencido']), color: cessumRed,
              pie: '${car['alumnosConAdeudo']} alumnos'),
          _kpi('Programado a cobrar', _m(car['comprometido6']), pie: 'Próximos 6 meses'),
        ]),
        if (recs.isNotEmpty) ...[
          _titulo('Qué hacer', 'Reglas explícitas sobre sus datos, de lo más urgente a lo menos'),
          ...recs.map((r) => _tarjeta(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: BoxDecoration(color: nivelColor('${r['nivel']}'), shape: BoxShape.circle)),
                Expanded(child: Text('${r['texto']}', style: const TextStyle(fontSize: 13.5))),
              ]))),
        ],
        _titulo('Ingresos y egresos, toda la historia', 'Cada punto es un mes'),
        _tarjeta(FinGraficaLineas(
          etiquetas: et,
          rangos: true,
          series: [
            FinSerie('Ingresos', _verde, _lista(ser['ingresos'])),
            FinSerie('Egresos', cessumRed, _lista(ser['egresos'])),
          ],
        )),
        _titulo('Saldo en bancos', 'Suma de las cuentas al cierre de cada mes'),
        _tarjeta(FinGraficaLineas(
          etiquetas: et,
          rangos: true,
          series: [FinSerie('Saldo', _oro, _lista(ser['saldo']), grosor: 2.6)],
          alto: 180,
        )),
        _titulo('Cartera vencida por antigüedad', 'Hoja Vencimientos del Guardián, solo alumnos activos'),
        _tarjeta(Column(children: [
          for (final k in ['1-30', '31-60', '61-90', '+90'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 78, child: Text('$k días', style: const TextStyle(fontSize: 12.5))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (((ant[k] as num?) ?? 0).toDouble() / maxAnt).clamp(0.0, 1.0),
                      minHeight: 9,
                      backgroundColor: cessumRed.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(cessumRed),
                    ),
                  ),
                ),
                SizedBox(
                    width: 110,
                    child: Text(_m(ant[k]), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
              ]),
            ),
          if (((car['carteraDeBajas'] as num?) ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Además, ${_m(car['carteraDeBajas'])} vencidos de alumnos dados de baja.',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            ),
        ])),
        if (anom.isNotEmpty) ...[
          _titulo('Gastos fuera de lo normal', 'Último mes contra la mediana de los 6 anteriores'),
          ...anom.map((a) => _tarjeta(Row(children: [
                Expanded(child: Text('${a['categoria']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${_m(a['mes'])} · habitual ${_m(a['habitual'])}${a['veces'] == null ? '' : ' · ×${a['veces']}'}',
                    style: const TextStyle(fontSize: 12.5)),
              ]))),
        ],
        _titulo('A dónde se va el dinero', 'Principales destinatarios de los últimos 12 meses'),
        _tarjeta(Column(children: [
          for (final t in top) _dato('${t['nombre']}', _m(t['total'])),
          const SizedBox(height: 6),
          Text(
              'Honorarios docentes del año: ${_m(ind['honorarios12'])} (${_pct(ind['pesoHonorarios'])} de los egresos) · '
              'Comisiones bancarias: ${_m(ind['comisiones12'])} · Traspasos entre cuentas propias excluidos: ${_m(ind['traspasos12'])}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ])),
        if (porProg.isNotEmpty) ...[
          _titulo('Alumnos activos por programa'),
          _tarjeta(Column(children: [
            for (final en in (porProg.entries.toList()
              ..sort((a, b) => (b.value as num).compareTo(a.value as num))))
              _dato(en.key, '${en.value}'),
          ])),
        ],
      ]),
    );
  }

  /* ------------------------------ HISTÓRICO ------------------------------ */
  Widget _vistaHistoricoComp() {
    final espera = _esperaAnalisis();
    if (espera != null) return espera;
    final e = _estad!;
    if (e['insuficiente'] == true) {
      return _centro('Se necesitan al menos 3 meses de estados de cuenta para el comparativo.', Icons.timeline);
    }
    final ser = _mapa(e['series']);
    final per = (ser['periodos'] as List? ?? const []).map((x) => '$x').toList();
    final et = per.map(finEtiqueta).toList();
    final anios = _maps(e['porAnio']);
    final matriz = _maps(e['matriz']);
    final cats = _maps(e['categorias']);
    final ing = _lista(ser['ingresos']), egr = _lista(ser['egresos']), res = _lista(ser['resultado']);
    final aniosTxt = anios.map((a) => '${a['anio']}').toList();

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargarAnalisis,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
        const Text('Comparativo histórico', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('Del primer estado de cuenta (${e['desdeNombre']}) al último (${e['hastaNombre']}): ${e['meses']} meses.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        _titulo('Resultado de cada mes', 'Ingresos − egresos. Arriba de la línea gruesa: mes con ganancia; abajo: con pérdida.'),
        _tarjeta(FinGraficaLineas(
          etiquetas: et,
          rangos: true,
          series: [FinSerie('Resultado', _oro, res, grosor: 2.4)],
          alto: 200,
        )),
        _titulo('Año contra año',
            'Promedio MENSUAL de cada año, para comparar parejo aunque un año tenga menos meses cargados'),
        _tarjeta(FinGraficaBarras(
          grupos: aniosTxt,
          series: [
            FinSerie('Ingreso mensual', _verde, anios.map((a) => (a['ingresoMensual'] as num?)?.toDouble()).toList()),
            FinSerie('Egreso mensual', cessumRed, anios.map((a) => (a['egresoMensual'] as num?)?.toDouble()).toList()),
          ],
        )),
        _tarjeta(_tablaHorizontal(
          ['Año', 'Meses', 'Ingresos', 'Egresos', 'Resultado', 'Margen', 'Ingreso mensual', 'vs. año previo', 'Saldo al cierre'],
          [
            for (final a in anios)
              [
                '${a['anio']}${a['completo'] == true ? '' : ' *'}',
                '${a['meses']}',
                _m(a['ingresos']),
                _m(a['egresos']),
                _m(a['resultado']),
                _pct(a['margen']),
                _m(a['ingresoMensual']),
                a['variacionIngresoMensual'] == null
                    ? '—'
                    : '${((a['variacionIngresoMensual'] as num) >= 0) ? '+' : ''}${_pct(a['variacionIngresoMensual'])}',
                _m(a['saldoFinal']),
              ],
          ],
          resaltarCol: 4,
        )),
        Text('* Año incompleto: compare con la columna «Ingreso mensual», no con los totales.',
            style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        _titulo('Ingresos por mes y año', 'Más intenso = mes con más ingresos. Toque una celda para ver la cifra.'),
        _tarjeta(FinMapaCalor(
          filas: matriz.map((m) => '${m['anio']}').toList(),
          valores: matriz.map((m) => _lista(m['ingresos'])).toList(),
        )),
        _titulo('Resultado por mes y año', 'Verde: ganancia · rojo: pérdida'),
        _tarjeta(FinMapaCalor(
          filas: matriz.map((m) => '${m['anio']}').toList(),
          valores: matriz.map((m) => _lista(m['resultado'])).toList(),
          divergente: true,
        )),
        if (cats.isNotEmpty) ...[
          _titulo('En qué se gasta, año por año', 'Las 8 categorías de egreso más grandes de toda la historia'),
          _tarjeta(_tablaHorizontal(
            ['Categoría', ...aniosTxt, 'Total', '% del gasto'],
            [
              for (final c in cats)
                [
                  '${c['categoria']}',
                  for (final y in aniosTxt) _m(_mapa(c['porAnio'])[y]),
                  _m(c['total']),
                  _pct(c['participacion']),
                ],
            ],
          )),
        ],
        _titulo('Mes con mes', 'Toque un mes para ver su detalle en la pestaña «Mes»'),
        ...List.generate(per.length, (k) {
          final i = per.length - 1 - k;
          final r = res[i] ?? 0;
          return InkWell(
            onTap: () {
              _cargar(periodo: per[i]);
              _tabs.animateTo(1);
            },
            child: _tarjeta(
              Row(children: [
                SizedBox(width: 118, child: Text(_mes(per[i]), style: const TextStyle(fontWeight: FontWeight.w700))),
                Expanded(
                    child: Text('Ingresos ${_m(ing[i])} · Egresos ${_m(egr[i])}',
                        style: TextStyle(fontSize: 12, color: cessumMuted(context)))),
                Text(_m(r),
                    style: TextStyle(fontWeight: FontWeight.w800, color: r >= 0 ? _verde : cessumRed)),
              ]),
              margin: const EdgeInsets.only(bottom: 6),
            ),
          );
        }),
      ]),
    );
  }

  /* ------------------------------ ESTADÍSTICA ------------------------------ */
  Widget _vistaEstadistica() {
    final espera = _esperaAnalisis();
    if (espera != null) return espera;
    final e = _estad!;
    if (e['insuficiente'] == true) {
      return _centro('Se necesitan al menos 3 meses de estados de cuenta para la estadística.', Icons.functions);
    }
    final des = _mapa(e['descriptiva']);
    final dI = _mapa(des['ingresos']), dE = _mapa(des['egresos']), dR = _mapa(des['resultado']);
    final ten = _mapa(e['tendencia']);
    final tI = _mapa(ten['ingresos']), tE = _mapa(ten['egresos']);
    final w = e['comparacion12'] == null ? null : _mapa(e['comparacion12']);
    final an = e['anova'] == null ? null : _mapa(e['anova']);
    final co = e['correlacion'] == null ? null : _mapa(e['correlacion']);
    final ati = _maps(e['atipicos']);
    final est = _maps(e['estacional']);
    String cv(dynamic x) => x == null ? '—' : '${(((x as num) * 100)).toStringAsFixed(1)}%';
    List<String> fila(String k, String Function(Map<String, dynamic>) f) => [k, f(dI), f(dE), f(dR)];

    Widget prueba(String titulo, List<Widget> datos, String significado, {bool? significativa}) => _tarjeta(
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
              if (significativa != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (significativa ? _verde : Colors.grey).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(significativa ? 'Significativo' : 'No significativo',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: significativa ? _verde : Colors.grey)),
                ),
            ]),
            const SizedBox(height: 6),
            ...datos,
            _queSignifica(significado),
          ]),
        );

    final textoWelch = w == null
        ? ''
        : (w['significativa'] == true
            ? 'El ingreso mensual promedio del último año (${_m(w['recientePromedio'])}) es ${((w['diferencia'] as num) >= 0) ? 'mayor' : 'menor'} '
                'que el del año anterior (${_m(w['previoPromedio'])}), y la diferencia es real, no efecto del azar (p = ${_pValor(w['p'])}). '
                'Tamaño del efecto: ${w['efecto']}.'
            : 'El último año promedió ${_m(w['recientePromedio'])} al mes y el anterior ${_m(w['previoPromedio'])}. '
                'La diferencia (${_pct(w['variacion'])}) no alcanza a ser estadísticamente significativa (p = ${_pValor(w['p'])}): '
                'con la variación normal entre meses, todavía no se puede afirmar que el cambio sea sostenido. Tamaño del efecto: ${w['efecto']}.');
    final textoAnova = an == null
        ? ''
        : (an['significativa'] == true
            ? 'Los ingresos SÍ dependen del mes del año (p = ${_pValor(an['p'])}): el mes explica el ${_pct(an['eta2'])} de la variación. '
                'Conviene planear gastos grandes y metas de cobranza con esta estacionalidad.'
            : 'No hay evidencia de que los ingresos dependan del mes del año (p = ${_pValor(an['p'])}): los altibajos no siguen un patrón fijo de calendario.');
    final textoCorr = co == null
        ? ''
        : 'La relación entre lo que entra y lo que sale cada mes es ${co['fuerza']} (r = ${co['r']}). '
            '${co['significativa'] == true ? 'Es estadísticamente significativa (p = ${_pValor(co['p'])}): cuando entran más ingresos, ${((co['r'] as num) > 0) ? 'también se gasta más' : 'se gasta menos'}.' : 'No es estadísticamente significativa (p = ${_pValor(co['p'])}): el gasto no se mueve al ritmo de los ingresos.'}';

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargarAnalisis,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
        const Text('Estadística', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('${e['meses']} meses, de ${e['desdeNombre']} a ${e['hastaNombre']}. Nivel de significancia: 5 %.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        _titulo('Descriptiva', 'Cómo se comportan los meses'),
        _tarjeta(_tablaHorizontal(
          ['Medida', 'Ingresos', 'Egresos', 'Resultado'],
          [
            fila('Total', (m) => _m(m['total'])),
            fila('Media mensual', (m) => _m(m['media'])),
            fila('Mediana', (m) => _m(m['mediana'])),
            fila('Desviación estándar', (m) => _m(m['desviacion'])),
            fila('Coef. de variación', (m) => cv(m['cv'])),
            fila('Cuartil 1 (25 %)', (m) => _m(m['q1'])),
            fila('Cuartil 3 (75 %)', (m) => _m(m['q3'])),
            fila('Mínimo', (m) => '${_m(m['minimo'])} · ${m['mesMinimo']}'),
            fila('Máximo', (m) => '${_m(m['maximo'])} · ${m['mesMaximo']}'),
          ],
        )),
        _queSignifica(
            'En ${e['mesesPositivos']} de ${e['meses']} meses el resultado fue positivo. El coeficiente de variación de los ingresos '
            '(${cv(dI['cv'])}) indica qué tan predecibles son: debajo de 15 % es estable; arriba de 30 %, muy variable. '
            'La mitad de los meses los ingresos estuvieron entre ${_m(dI['q1'])} y ${_m(dI['q3'])}.'),
        _titulo('Inferencial', '¿Los cambios son reales o azar? Cada prueba dice qué significa'),
        prueba(
          'Tendencia de los ingresos',
          [
            _dato('Cambio promedio por mes', _m(tI['pendienteMensual'])),
            _dato('Intervalo de confianza 95 %', '${_m(tI['icInf'])} a ${_m(tI['icSup'])}'),
            _dato('Cambio anualizado', _m(tI['cambioAnual'])),
            _dato('R² · t · valor p', '${_num(tI['r2'])} · ${_num(tI['t'])} · ${_pValor(tI['p'])}'),
          ],
          '${ten['interpretacionIngresos']}',
          significativa: tI['significativa'] == true,
        ),
        prueba(
          'Tendencia de los egresos',
          [
            _dato('Cambio promedio por mes', _m(tE['pendienteMensual'])),
            _dato('Intervalo de confianza 95 %', '${_m(tE['icInf'])} a ${_m(tE['icSup'])}'),
            _dato('R² · t · valor p', '${_num(tE['r2'])} · ${_num(tE['t'])} · ${_pValor(tE['p'])}'),
          ],
          '${ten['interpretacionEgresos']}',
          significativa: tE['significativa'] == true,
        ),
        if (w != null)
          prueba(
            'Último año contra el anterior (t de Welch)',
            [
              _dato('Ingreso mensual, últimos 12 meses', _m(w['recientePromedio'])),
              _dato('Ingreso mensual, 12 meses previos', _m(w['previoPromedio'])),
              _dato('Diferencia', '${_m(w['diferencia'])} (${_pct(w['variacion'])})'),
              _dato('t · g.l. · valor p', '${_num(w['t'])} · ${_num(w['gl'])} · ${_pValor(w['p'])}'),
              _dato('d de Cohen (tamaño del efecto)', '${_num(w['d'])} · ${w['efecto']}'),
            ],
            textoWelch,
            significativa: w['significativa'] == true,
          ),
        if (an != null)
          prueba(
            'Estacionalidad (ANOVA de un factor)',
            [
              _dato('F · g.l. · valor p', '${_num(an['F'])} · ${an['gl1']}, ${an['gl2']} · ${_pValor(an['p'])}'),
              _dato('η² (variación que explica el mes)', _pct(an['eta2'])),
            ],
            textoAnova,
            significativa: an['significativa'] == true,
          ),
        if (est.isNotEmpty)
          _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ingreso promedio por mes del año',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            FinGraficaBarras(
              grupos: est.map((x) => '${x['mes']}').toList(),
              series: [FinSerie('Ingreso promedio', _verde, est.map((x) => (x['promedio'] as num?)?.toDouble()).toList())],
              alto: 180,
              mostrarValores: false,
            ),
          ])),
        if (co != null)
          prueba(
            'Relación ingresos–egresos (r de Pearson)',
            [_dato('r · valor p', '${_num(co['r'])} · ${_pValor(co['p'])}')],
            textoCorr,
            significativa: co['significativa'] == true,
          ),
        _titulo('Meses atípicos', 'Más de 2 desviaciones estándar lejos de su tendencia (z > 2)'),
        if (ati.isEmpty)
          _tarjeta(const Text('Ningún mes se sale de lo esperado.', style: TextStyle(fontSize: 13)))
        else
          ...ati.map((a) => _tarjeta(
                Row(children: [
                  Expanded(
                      child: Text('${a['serie']} · ${a['mes']}',
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text('${_m(a['valor'])} (esperado ${_m(a['esperado'])}) · z = ${a['z']}',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: ((a['z'] as num) > 0) == ('${a['serie']}' == 'Ingresos') ? _verde : cessumRed)),
                ]),
                margin: const EdgeInsets.only(bottom: 6),
              )),
        const SizedBox(height: 10),
        Text(
            'Métodos: regresión lineal por mínimos cuadrados con prueba t para la pendiente; t de Welch para dos muestras con varianzas distintas; '
            'ANOVA de un factor sobre ingresos sin tendencia; correlación de Pearson; puntuaciones z sobre los residuos. '
            'Valores p exactos con las distribuciones t y F.',
            style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ]),
    );
  }

  /* ======================================================================
     (23-sep) PROYECCIÓN · simulador con horizonte de hasta 60 meses,
     ligado con Admisiones y con recomendación de IA. El cálculo corre aquí,
     en el navegador, para que cada cambio de supuesto se vea al instante.
     La base (alumnos actuales con su calendario real de Vencimientos,
     tamaño histórico de las generaciones, embudo de Admisiones, saldo y
     egreso típico) la da el Guardián: finanzas_simulador_base.
     ====================================================================== */
  Future<void> _cargarSim() async {
    if (_cargandoSim) return;
    setState(() {
      _cargandoSim = true;
      _errorSim = '';
    });
    try {
      final r = await _get({'accion': 'finanzas_simulador_base', 'horizonte': '60'});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _sim = r;
        _cargandoSim = false;
        if (_p.isEmpty) _parametrosIniciales(r);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoSim = false;
        _errorSim = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _parametrosIniciales(Map<String, dynamic> b) {
    final co = _mapa(b['cohortes']);
    final tar = _mapa(b['tarifas']);
    double prom(String t, double def) {
      final v = (_mapa(co[t])['promedioReciente'] as num?)?.toDouble() ?? 0;
      return v > 0 ? v : def;
    }

    double cuota(String t, double def) => ((_mapa(tar[t])['cuota'] as num?) ?? def).toDouble();
    final cob = (b['cobranza'] as num?)?.toDouble();
    _p
      ..['meN'] = prom('ME', 45).clamp(0, 300).roundToDouble()
      ..['posN'] = prom('POS', 110).clamp(0, 500).roundToDouble()
      ..['licN'] = prom('LIC', 8).clamp(0, 200).roundToDouble()
      ..['crec'] = 0
      ..['meC'] = cuota('ME', 2850)
      ..['posC'] = cuota('POS', 1450)
      ..['licC'] = cuota('LIC', 1850)
      ..['cob'] = ((cob ?? 0.9) * 100).clamp(50, 100).roundToDouble()
      ..['des'] = 1.0
      ..['egG'] = 5
      ..['var'] = 30
      ..['tit'] = 40
      ..['titC'] = 9000
      ..['inv'] = 0
      ..['invM'] = 12
      ..['saldo'] = ((b['saldo'] as num?) ?? 0).toDouble();
    _cSaldo.text = (_p['saldo'] ?? 0).round().toString();
  }

  String _perSim(int k) {
    final ini = '${_sim!['inicio']}';
    final y0 = int.parse(ini.substring(0, 4)), m0 = int.parse(ini.substring(5, 7));
    final t = (m0 - 1) + k;
    return '${y0 + t ~/ 12}-${(t % 12 + 1).toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _simular() {
    final b = _sim!;
    final hz = _simH;
    final act = _mapa(b['actuales']);
    final ingAct = _lista(act['ingreso']);
    final aluAct = (act['alumnos'] as List? ?? const []).map((x) => (x as num).toDouble()).toList();
    final tar = _mapa(b['tarifas']);
    final insc = ((tar['inscripcion'] as num?) ?? 450).toDouble();
    final reins = ((tar['reinscripcion'] as num?) ?? 350).toDouble();
    final cob = _p['cob']! / 100, des = _p['des']! / 100, g = _p['egG']! / 100, vr = _p['var']! / 100;
    final titP = _p['tit']! / 100, titC = _p['titC']!;
    final colAct = List<double>.filled(hz, 0), colNue = List<double>.filled(hz, 0);
    final otros = List<double>.filled(hz, 0), tit = List<double>.filled(hz, 0), alu = List<double>.filled(hz, 0);
    double sobrev(int k) => math.pow(1 - des, k).toDouble();

    // Alumnos actuales, con su calendario real (dejan de pagar al terminar su plan).
    for (var k = 0; k < hz; k++) {
      final base = k < ingAct.length ? (ingAct[k] ?? 0.0) : 0.0;
      colAct[k] = base * sobrev(k) * cob;
      alu[k] += (k < aluAct.length ? aluAct[k] : 0.0) * sobrev(k);
      if (k > 0 && k < aluAct.length && aluAct[k - 1] > aluAct[k] && k + 3 < hz) {
        tit[k + 3] += (aluAct[k - 1] - aluAct[k]) * sobrev(k) * titP * titC;
      }
    }
    // Generaciones nuevas.
    void cohorte(int k0, double n, double cuota, int meses, int reinsCada) {
      if (k0 >= hz || n <= 0) return;
      otros[k0 > 0 ? k0 - 1 : 0] += n * insc;
      for (var j = 0; j < meses && k0 + j < hz; j++) {
        final s = sobrev(j);
        colNue[k0 + j] += n * s * cuota * cob;
        alu[k0 + j] += n * s;
        if (j > 0 && reinsCada > 0 && j % reinsCada == 0) otros[k0 + j] += n * s * reins * cob;
      }
      final kf = k0 + meses + 3;
      if (kf < hz) tit[kf] += n * sobrev(meses) * titP * titC;
    }

    for (var k = 1; k < hz; k++) {
      final mc = int.parse(_perSim(k).substring(5, 7));
      final f = math.pow(1 + _p['crec']! / 100, k ~/ 12).toDouble();
      if (mc == 1 || mc == 4 || mc == 7 || mc == 10) cohorte(k, _p['meN']! * f, _p['meC']!, 12, 3);
      if (mc == 1 || mc == 7) cohorte(k, _p['posN']! * f, _p['posC']!, 24, 6);
      if (mc == 9) cohorte(k, _p['licN']! * f, _p['licC']!, 36, 4);
    }
    // Egresos: parte fija (crece con la inflación) + parte variable (proporcional a las colegiaturas).
    final egBase = ((b['egresoBase'] as num?) ?? 0).toDouble();
    final c0 = colAct.isNotEmpty ? colAct[0] + colNue[0] : 0.0;
    final fijo = math.max(egBase * 0.3, egBase - vr * c0);
    final ingresos = <double>[], egresos = <double>[], saldo = <double>[];
    var s = _p['saldo']!;
    for (var k = 0; k < hz; k++) {
      final ing = colAct[k] + colNue[k] + otros[k] + tit[k];
      var eg = fijo * math.pow(1 + g, k / 12).toDouble() + vr * (colAct[k] + colNue[k]);
      if (_p['inv']! > 0 && k == (_p['invM']!.round() - 1).clamp(0, hz - 1).toInt()) eg += _p['inv']!;
      ingresos.add(ing);
      egresos.add(eg);
      s += ing - eg;
      saldo.add(s);
    }
    var iMin = 0, negativos = 0, primerNeg = -1;
    for (var k = 0; k < hz; k++) {
      if (saldo[k] < saldo[iMin]) iMin = k;
      if (saldo[k] < 0) {
        negativos++;
        if (primerNeg < 0) primerNeg = k;
      }
    }
    final porAnio = <Map<String, dynamic>>[];
    for (var k = 0; k < hz; k++) {
      final y = _perSim(k).substring(0, 4);
      if (porAnio.isEmpty || porAnio.last['anio'] != y) {
        porAnio.add({'anio': y, 'meses': 0, 'ingresos': 0.0, 'egresos': 0.0});
      }
      final a = porAnio.last;
      a['meses'] = (a['meses'] as int) + 1;
      a['ingresos'] = (a['ingresos'] as double) + ingresos[k];
      a['egresos'] = (a['egresos'] as double) + egresos[k];
      a['saldo'] = saldo[k];
      a['alumnos'] = alu[k].round();
    }
    for (final a in porAnio) {
      a['resultado'] = (a['ingresos'] as double) - (a['egresos'] as double);
    }
    return {
      'periodos': [for (var k = 0; k < hz; k++) _perSim(k)],
      'ingresos': ingresos, 'egresos': egresos, 'saldo': saldo, 'alumnos': alu,
      'colAct': colAct, 'colNue': colNue,
      'iMin': iMin, 'negativos': negativos, 'primerNeg': primerNeg, 'porAnio': porAnio,
    };
  }

  Widget _deslizador(String etiqueta, String clave, double min, double max, int div, String Function(double) fmt,
      {String? ayuda}) {
    final v = (_p[clave] ?? min).clamp(min, max).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(etiqueta, style: const TextStyle(fontSize: 12.5))),
          Text(fmt(v), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        if (ayuda != null) Text(ayuda, style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
        Slider(
          value: v,
          min: min,
          max: max,
          divisions: div,
          activeColor: cessumRed,
          onChanged: (x) => setState(() {
            _p[clave] = x;
            _simIa = '';
          }),
        ),
      ]),
    );
  }

  Future<void> _pedirIaSim(Map<String, dynamic> r) async {
    if (_simIaCargando) return;
    setState(() {
      _simIaCargando = true;
      _simIa = '';
    });
    String mm(double v) => finMoneda(v);
    final per = (r['periodos'] as List).cast<String>();
    final saldo = (r['saldo'] as List).cast<double>();
    final alu = (r['alumnos'] as List).cast<double>();
    final porAnio = (r['porAnio'] as List).cast<Map<String, dynamic>>();
    try {
      final g = await _post({
        'accion': 'finanzas_simulador_ia',
        'escenario': {
          'horizonte': _simH,
          'inicio': '${_sim!['inicio']}',
          'Inscritos por generación · Maestría en Educación (4 al año)': _p['meN']!.round(),
          'Inscritos por generación · otros posgrados (2 al año)': _p['posN']!.round(),
          'Inscritos por generación · Licenciatura (1 al año)': _p['licN']!.round(),
          'Crecimiento anual de inscripciones': '${_p['crec']!.round()}%',
          'Colegiaturas (ME / posgrados / licenciatura)': '${mm(_p['meC']!)} / ${mm(_p['posC']!)} / ${mm(_p['licC']!)}',
          'Cobranza efectiva': '${_p['cob']!.round()}%',
          'Deserción mensual': '${_p['des']!.toStringAsFixed(1)}%',
          'Crecimiento anual del gasto fijo': '${_p['egG']!.round()}%',
          'Costo variable (% de colegiaturas)': '${_p['var']!.round()}%',
          'Titulación': '${_p['tit']!.round()}% de egresados a ${mm(_p['titC']!)}',
          'Inversión única': _p['inv']! > 0 ? '${mm(_p['inv']!)} en ${_mes(per[(_p['invM']!.round() - 1).clamp(0, per.length - 1).toInt()])}' : 'ninguna',
        },
        'resultados': {
          'saldoInicial': _p['saldo'],
          'saldoFinal': saldo.last,
          'saldoMinimo': saldo[r['iMin'] as int],
          'mesMinimo': _mes(per[r['iMin'] as int]),
          'mesesNegativos': r['negativos'],
          'primerMesNegativo': (r['primerNeg'] as int) >= 0 ? _mes(per[r['primerNeg'] as int]) : '',
          'alumnosInicio': alu.first.round(),
          'alumnosFinal': alu.last.round(),
          'porAnio': [
            for (final a in porAnio)
              {
                'anio': a['anio'],
                'ingresos': a['ingresos'],
                'egresos': a['egresos'],
                'resultado': a['resultado'],
                'saldo': a['saldo'],
                'alumnos': a['alumnos'],
              }
          ],
        },
      });
      if (!mounted) return;
      setState(() {
        _simIaCargando = false;
        _simIa = g['ok'] == true ? '${g['respuesta']}' : 'No pude responder: ${g['error'] ?? 'sin respuesta'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _simIaCargando = false;
        _simIa = 'No pude responder: $e';
      });
    }
  }

  Widget _vistaProyeccion() {
    if (_sim == null) {
      if (!_cargandoSim && _errorSim.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _cargarSim());
      }
      if (_errorSim.isNotEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_errorSim, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () {
                  setState(() => _errorSim = '');
                  _cargarSim();
                },
                child: const Text('Reintentar'),
              ),
            ]),
          ),
        );
      }
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: cessumRed),
          const SizedBox(height: 12),
          Text('Preparando el simulador: alumnos, calendarios de pago y admisiones…',
              style: TextStyle(color: cessumMuted(context))),
        ]),
      );
    }
    final b = _sim!;
    final r = _simular();
    final per = (r['periodos'] as List).cast<String>();
    final et = per.map(finEtiqueta).toList();
    final saldo = (r['saldo'] as List).cast<double>();
    final ing = (r['ingresos'] as List).cast<double>();
    final egr = (r['egresos'] as List).cast<double>();
    final alu = (r['alumnos'] as List).cast<double>();
    final colAct = (r['colAct'] as List).cast<double>();
    final colNue = (r['colNue'] as List).cast<double>();
    final porAnio = (r['porAnio'] as List).cast<Map<String, dynamic>>();
    final iMin = r['iMin'] as int, neg = r['negativos'] as int, pNeg = r['primerNeg'] as int;
    final act = _mapa(b['actuales']);
    final adm = _mapa(b['admisiones']);
    final admOk = adm['ok'] == true;
    final convCerr = (adm['conversionCerrados'] as num?)?.toDouble();
    final convTot = (adm['conversionTotal'] as num?)?.toDouble();
    final conv = (convCerr != null && convCerr > 0) ? convCerr : convTot;
    final gasto = _mapa(adm['gasto']);
    final cpi = (gasto['costoPorInscrito'] as num?)?.toDouble();
    String cnt(double v) => v.round().toString();
    String pesos(double v) => finMoneda(v);

    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
      const Text('Proyección y simulador', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 2),
      Text(
          'Mueva los supuestos y todo se recalcula al instante. Los alumnos actuales se proyectan con su calendario real de pagos '
          '(${act['conCalendario']} con calendario en Vencimientos${((act['sinCalendario'] as num?) ?? 0) > 0 ? ', ${act['sinCalendario']} estimados a 12 meses' : ''}). '
          'Arranca en ${_mes('${b['inicio']}')}, el mes siguiente al último estado de cuenta.',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        for (final hz in const [12, 24, 36, 60])
          ChoiceChip(
            label: Text(hz == 12 ? '1 año' : '${hz ~/ 12} años'),
            selected: _simH == hz,
            selectedColor: cessumRed.withValues(alpha: 0.15),
            onSelected: (_) => setState(() {
              _simH = hz;
              _simIa = '';
            }),
          ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _kpi('Saldo al final', pesos(saldo.last), color: saldo.last >= 0 ? _verde : cessumRed, pie: _mes(per.last)),
        _kpi('Mes más apretado', pesos(saldo[iMin]), color: saldo[iMin] >= 0 ? _ambar : cessumRed, pie: _mes(per[iMin])),
        _kpi('Meses en rojo', '$neg', color: neg == 0 ? _verde : cessumRed,
            pie: pNeg >= 0 ? 'Desde ${_mes(per[pNeg])}' : 'El saldo nunca es negativo'),
        _kpi('Alumnos activos', '${alu.first.round()} → ${alu.last.round()}', pie: 'Del inicio al final'),
        _kpi('Ingresos del horizonte', pesos(ing.fold(0.0, (a, x) => a + x))),
        _kpi('Egresos del horizonte', pesos(egr.fold(0.0, (a, x) => a + x))),
      ]),
      _titulo('Saldo, ingresos y egresos', 'Pase el ratón o el dedo sobre la gráfica · toque la leyenda para ocultar una serie'),
      _tarjeta(FinGraficaLineas(
        etiquetas: et,
        series: [
          FinSerie('Saldo', _oro, saldo, grosor: 2.8),
          FinSerie('Ingresos', _verde, ing),
          FinSerie('Egresos', cessumRed, egr),
        ],
        alto: 260,
      )),
      _titulo('De dónde vienen las colegiaturas', 'Los alumnos actuales se van graduando; las generaciones nuevas los sustituyen'),
      _tarjeta(FinGraficaLineas(
        etiquetas: et,
        series: [
          FinSerie('Alumnos actuales', const Color(0xFF2B6CB0), colAct),
          FinSerie('Generaciones nuevas', _verde, colNue),
        ],
        alto: 200,
      )),
      _titulo('Alumnos activos proyectados'),
      _tarjeta(FinGraficaLineas(
        etiquetas: et,
        series: [FinSerie('Alumnos', const Color(0xFF6B46C1), alu, grosor: 2.6)],
        alto: 170,
        formato: cnt,
      )),
      _tarjeta(_tablaHorizontal(
        ['Año', 'Meses', 'Ingresos', 'Egresos', 'Resultado', 'Saldo al cierre', 'Alumnos al cierre'],
        [
          for (final a in porAnio)
            [
              '${a['anio']}',
              '${a['meses']}',
              pesos(a['ingresos'] as double),
              pesos(a['egresos'] as double),
              pesos(a['resultado'] as double),
              pesos(a['saldo'] as double),
              '${a['alumnos']}',
            ],
        ],
        resaltarCol: 5,
      )),
      _titulo('Supuestos', 'Los valores iniciales salen de sus datos: padrón, vencimientos, estados de cuenta y convocatoria vigente'),
      _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Admisiones · generaciones nuevas', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        _deslizador('Maestría en Educación, por generación', 'meN', 0, 200, 200, cnt, ayuda: '4 generaciones al año: enero, abril, julio y octubre'),
        _deslizador('Otros posgrados, por generación', 'posN', 0, 400, 400, cnt, ayuda: '2 generaciones al año: enero y julio (todas las maestrías y doctorados)'),
        _deslizador('Licenciatura, por generación', 'licN', 0, 120, 120, cnt, ayuda: '1 generación al año: septiembre'),
        _deslizador('Crecimiento anual de inscripciones', 'crec', -30, 50, 80, (v) => '${v.round()}%'),
        const Divider(),
        const Text('Precios', style: TextStyle(fontWeight: FontWeight.w800)),
        _deslizador('Colegiatura Maestría en Educación', 'meC', 1500, 5000, 70, pesos),
        _deslizador('Colegiatura promedio otros posgrados', 'posC', 900, 3500, 52, pesos),
        _deslizador('Colegiatura Licenciatura', 'licC', 1000, 4000, 60, pesos),
        const Divider(),
        const Text('Cobranza y permanencia', style: TextStyle(fontWeight: FontWeight.w800)),
        _deslizador('Cobranza efectiva', 'cob', 50, 100, 50, (v) => '${v.round()}%', ayuda: 'De cada peso que vence, cuánto se cobra'),
        _deslizador('Deserción mensual', 'des', 0, 5, 50, (v) => '${v.toStringAsFixed(1)}%'),
        const Divider(),
        const Text('Gasto', style: TextStyle(fontWeight: FontWeight.w800)),
        _deslizador('Crecimiento anual del gasto fijo', 'egG', 0, 20, 20, (v) => '${v.round()}%', ayuda: 'Inflación, sueldos, rentas'),
        _deslizador('Costo variable', 'var', 0, 70, 70, (v) => '${v.round()}% de las colegiaturas', ayuda: 'Honorarios docentes y lo que crece con la matrícula'),
        const Divider(),
        const Text('Titulación', style: TextStyle(fontWeight: FontWeight.w800)),
        _deslizador('Egresados que se titulan', 'tit', 0, 100, 20, (v) => '${v.round()}%'),
        _deslizador('Costo promedio de titulación', 'titC', 5000, 16000, 22, pesos),
        const Divider(),
        const Text('Inversión única (terreno, obra, equipo)', style: TextStyle(fontWeight: FontWeight.w800)),
        _deslizador('Monto', 'inv', 0, 10000000, 200, pesos),
        _deslizador('Mes', 'invM', 1, _simH.toDouble(), _simH - 1, (v) => _mes(per[(v.round() - 1).clamp(0, per.length - 1).toInt()])),
        const Divider(),
        Row(children: [
          const Expanded(child: Text('Saldo inicial (las cuentas)', style: TextStyle(fontSize: 12.5))),
          SizedBox(
            width: 150,
            child: TextField(
              controller: _cSaldo,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(isDense: true, prefixText: '\$ '),
              onSubmitted: (t) => setState(() {
                _p['saldo'] = double.tryParse(t.replaceAll(',', '')) ?? _p['saldo']!;
                _simIa = '';
              }),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _p.clear();
              _parametrosIniciales(b);
              _simIa = '';
            }),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Volver a los valores de sus datos'),
          ),
        ),
      ])),
      _titulo('Admisiones', 'El embudo en vivo del panel de admisiones, sin datos personales'),
      if (!admOk)
        _tarjeta(Text(
            'No se pudo consultar Admisiones: ${adm['error'] ?? 'sin respuesta'}. Revise que el Code.gs de Admisiones esté publicado en su versión nueva.',
            style: const TextStyle(fontSize: 12.5)))
      else ...[
        Wrap(spacing: 10, runSpacing: 10, children: [
          _kpi('Prospectos', '${adm['total']}', pie: 'Registrados en el panel'),
          _kpi('Inscritos', '${adm['inscritos']}', color: _verde),
          _kpi('Conversión', conv == null ? '—' : '${(conv * 100).toStringAsFixed(1)}%',
              pie: convCerr != null ? 'De los casos ya cerrados' : 'Del total'),
          _kpi('Últimos 90 días', '${_mapa(adm['ultimos90'])['total']} → ${_mapa(adm['ultimos90'])['inscritos']}',
              pie: 'Prospectos → inscritos'),
          _kpi('Costo por inscrito', cpi == null ? '—' : pesos(cpi),
              pie: (gasto['total'] as num? ?? 0) > 0 ? 'Publicidad: ${pesos((gasto['total'] as num).toDouble())}' : 'Sin gasto registrado'),
        ]),
        const SizedBox(height: 10),
        _tarjeta(FinGraficaBarras(
          grupos: [for (final e in _mapa(adm['porEtapa']).keys) e],
          series: [
            FinSerie('Prospectos', const Color(0xFF2B6CB0),
                [for (final v in _mapa(adm['porEtapa']).values) (v as num).toDouble()]),
          ],
          alto: 170,
          formato: cnt,
        )),
        _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Lo que exige este escenario a Admisiones', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final f in [
            ['Maestría en Educación', _p['meN']!],
            ['Otros posgrados', _p['posN']!],
            ['Licenciatura', _p['licN']!],
          ])
            _dato(
                '${f[0]}: ${(f[1] as double).round()} inscritos por generación',
                conv == null || conv <= 0
                    ? '—'
                    : '${((f[1] as double) / conv).ceil()} prospectos${cpi == null ? '' : ' · ${pesos((f[1] as double) * cpi)} de publicidad'}'),
          const SizedBox(height: 4),
          Text('Prospectos = inscritos ÷ conversión real del embudo. Publicidad = inscritos × costo por inscrito registrado.',
              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ])),
        _tarjeta(_tablaHorizontal(
          ['Programa', 'Prospectos', 'Interesados', 'En documentos', 'Inscritos'],
          [
            for (final e in _mapa(adm['porPrograma']).entries)
              [
                e.key,
                '${_mapa(e.value)['total']}',
                '${_mapa(_mapa(e.value)['porEtapa'])['Interesado'] ?? 0}',
                '${_mapa(_mapa(e.value)['porEtapa'])['Documentos en proceso'] ?? 0}',
                '${_mapa(_mapa(e.value)['porEtapa'])['Inscrito'] ?? 0}',
              ],
          ],
        )),
      ],
      _titulo('¿Qué hacemos?', 'La IA recibe este escenario, sus resultados y el embudo de admisiones, y propone un plan con cifras'),
      _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: _simIaCargando ? null : () => _pedirIaSim(r),
          icon: _simIaCargando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_awesome),
          label: Text(_simIaCargando ? 'Analizando el escenario…' : 'Recomendación para este escenario'),
        ),
        if (_simIa.isNotEmpty) ...[
          const SizedBox(height: 12),
          SelectableText(_simIa, style: const TextStyle(fontSize: 13.5, height: 1.5)),
        ],
      ])),
      ..._pronosticoEstadistico(),
    ]);
  }

  /// Pronóstico estadístico de ingresos (tendencia + estacionalidad, banda del 95 %).
  List<Widget> _pronosticoEstadistico() {
    if (_estad == null) {
      if (!_cargandoIntel && _errorIntel.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _cargarAnalisis());
      }
      return [
        _titulo('Pronóstico estadístico de ingresos'),
        _tarjeta(Text(_errorIntel.isNotEmpty ? _errorIntel : 'Calculando…', style: const TextStyle(fontSize: 12.5))),
      ];
    }
    final e = _estad!;
    if (e['insuficiente'] == true) return const [];
    final ser = _mapa(e['series']);
    final per = (ser['periodos'] as List? ?? const []).map((x) => '$x').toList();
    final ingH = _lista(ser['ingresos']);
    final pro = _maps(e['pronostico']);
    final ini = per.length > 24 ? per.length - 24 : 0;
    final etq = [...per.sublist(ini).map(finEtiqueta), ...pro.map((p) => finEtiqueta('${p['periodo']}'))];
    final nH = per.length - ini;
    final real = <double?>[...ingH.sublist(ini), ...List<double?>.filled(pro.length, null)];
    final pron = <double?>[
      ...List<double?>.filled(nH - 1, null),
      ingH.isNotEmpty ? ingH.last : null,
      ...pro.map((p) => (p['ingreso'] as num?)?.toDouble()),
    ];
    final inf = <double?>[...List<double?>.filled(nH, null), ...pro.map((p) => (p['inf'] as num?)?.toDouble())];
    final sup = <double?>[...List<double?>.filled(nH, null), ...pro.map((p) => (p['sup'] as num?)?.toDouble())];
    return [
      _titulo('Pronóstico estadístico de ingresos',
          'Referencia independiente del simulador: solo mira la historia (tendencia + estacionalidad), sin supuestos de admisiones'),
      _tarjeta(FinGraficaLineas(
        etiquetas: etq,
        series: [
          FinSerie('Ingreso real', _verde, real),
          FinSerie('Pronóstico', _verde, pron, punteada: true),
        ],
        bandaInf: inf,
        bandaSup: sup,
        nombreBanda: 'Intervalo 95 %',
        corte: nH,
        alto: 230,
      )),
      _queSignifica('${e['pronosticoMetodo']} Si el simulador proyecta ingresos muy por encima de esta franja, sus supuestos de admisiones son optimistas '
          'frente a lo que la historia ha mostrado.'),
    ];
  }

  Widget _vistaAlertas() {
    final al = ((_res['alertas'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    if (al.isEmpty) {
      return _centro('Sin alertas este mes.', Icons.verified_outlined);
    }
    Color col(String n) => n == 'alta'
        ? cessumRed
        : n == 'media'
            ? const Color(0xFFB8860B)
            : const Color(0xFF3B6EA5);
    return ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
        children: al
            .map((a) => _tarjeta(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: col('${a['nivel']}').withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('${a['nivel']}'.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: col('${a['nivel']}'))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('${a['titulo']}',
                                style: const TextStyle(fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 6),
                      Text('${a['detalle']}', style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('${a['sugerencia']}',
                          style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                            onPressed: () => _descartar(a),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Descartar')),
                      ),
                    ])))
            .toList());
  }

  Widget _vistaMovimientos() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: TextField(
          controller: _cBuscar,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar por nombre, concepto o categoría',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onSubmitted: (_) => _cargarMovs(),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          for (final t in const [['', 'Todos'], ['Ingreso', 'Ingresos'], ['Egreso', 'Egresos']])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(t[1]),
                selected: _tipoMov == t[0],
                onSelected: (_) {
                  setState(() => _tipoMov = t[0]);
                  _cargarMovs();
                },
              ),
            ),
          const Spacer(),
          Text('$_movsTotal', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
          itemCount: _movs.length,
          itemBuilder: (_, i) {
            final m = Map<String, dynamic>.from(_movs[i] as Map);
            final ing = m['tipo'] == 'Ingreso';
            final v = ing ? m['abono'] : m['cargo'];
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                    '${(m['contraparte'] ?? '').toString().isNotEmpty ? m['contraparte'] : m['desc']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${m['fecha']} · ${m['cat']}${(m['sub'] ?? '').toString().isNotEmpty ? ' / ${m['sub']}' : ''}\n${m['desc']}',
                    style: const TextStyle(fontSize: 11.5)),
                isThreeLine: true,
                trailing: Text('${ing ? '+' : '-'}${_m(v)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ing ? const Color(0xFF1E7F52) : cessumRed)),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _vistaAsistente() {
    final sugeridas = _asistTotal
        ? const [
            'Elabora el informe financiero de toda la historia',
            '¿Cómo han evolucionado los ingresos y egresos año con año?',
            '¿Qué tendencias son estadísticamente significativas?',
            '¿Cuáles han sido nuestros meses más difíciles y por qué?',
            '¿Qué gastos crecieron más en todo el periodo?',
          ]
        : const [
            'Elabora el informe financiero del mes',
            '¿En qué se nos va el dinero?',
            '¿Qué gastos podemos recortar o eficientar?',
            'Compara este mes con el anterior',
          ];
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.all(14), children: [
          if (_chat.isEmpty) ...[
            Text(
                _asistTotal
                    ? 'Pregunte sobre TODA la historia: el asistente recibe los totales de cada mes y de cada año, las categorías del periodo completo y la estadística descriptiva e inferencial.'
                    : 'Pregunte sobre ${_mes(_periodo)}. El asistente responde con los movimientos ya verificados de ese mes. Para el periodo completo, elija «Toda la historia» abajo.',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
            const SizedBox(height: 10),
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sugeridas
                    .map((s) => ActionChip(label: Text(s), onPressed: () => _preguntar(s)))
                    .toList()),
          ],
          ..._chat.map((c) {
            final yo = c['de'] == 'yo';
            return Align(
              alignment: yo ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxWidth: 680),
                decoration: BoxDecoration(
                  color: yo ? cessumRed.withValues(alpha: 0.08) : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cessumGold.withValues(alpha: 0.25)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (yo && (c['alcance'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${c['alcance']}',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: cessumMuted(context))),
                    ),
                  SelectableText('${c['texto']}', style: const TextStyle(fontSize: 13.5, height: 1.45)),
                ]),
              ),
            );
          }),
          if (_pensando)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Analizando…'),
              ]),
            ),
        ]),
      ),
      SafeArea(
        child: Padding(
          // (23-sep) Sin el margen derecho de 90: en esta pestaña ya no hay botones flotantes encima.
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              ChoiceChip(
                label: Text('Mes: ${_mes(_periodo)}'),
                selected: !_asistTotal,
                selectedColor: cessumRed.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _asistTotal = false),
              ),
              ChoiceChip(
                label: const Text('Toda la historia'),
                selected: _asistTotal,
                selectedColor: cessumRed.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _asistTotal = true),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
            Expanded(
              child: TextField(
                controller: _cPregunta,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Escriba su pregunta',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onSubmitted: (_) => _preguntar(),
              ),
            ),
            IconButton(
                onPressed: _pensando ? null : () => _preguntar(),
                icon: const Icon(Icons.send, color: cessumRed)),
          ]),
          ]),
        ),
      ),
    ]);
  }
}

/// Lector de estados de cuenta BBVA (Maestra PYME). Probado contra el estado de
/// agosto de 2026: 479 movimientos, cuadra al centavo con el resumen del banco.
const String _kLectorBBVA = r'''
/* Lector de estados de cuenta BBVA (Maestra PYME) para CESSUM.
   Recibe pdfjsLib y los bytes del PDF; devuelve movimientos y resumen.
   Los montos se manejan en CENTAVOS enteros: nada de decimales flotantes. */
async function cessumLeerEstadoBBVA(pdfjsLib, bytes, clave) {
  var MESES = { ENE: 1, FEB: 2, MAR: 3, ABR: 4, MAY: 5, JUN: 6, JUL: 7, AGO: 8, SEP: 9, OCT: 10, NOV: 11, DIC: 12 };
  var MONTO = /^[\d,]+\.\d{2}$/;
  var PIE = ['Estimado Cliente', 'Su Estado de Cuenta ha sido', 'También le informamos', 'el cual puede consultarlo',
    'Con BBVA adelante', 'La GAT Real', 'BBVA MEXICO, S.A.', 'Av. Paseo de la Reforma'];
  function cent(s) { return parseInt(String(s).replace(/[^\d]/g, ''), 10); }
  /* (23-sep) Los PDF de BBVA llegan con contraseña (el RFC sin homoclave).
     pdf.js los abre si se le da; si falta o es incorrecta, se avisa aparte
     para que la pantalla la pida. */
  var doc;
  try {
    doc = await pdfjsLib.getDocument({ data: bytes, disableFontFace: true, password: clave || undefined }).promise;
  } catch (eDoc) {
    if (eDoc && eDoc.name === 'PasswordException') return { ok: false, error: 'CONTRASENA', incorrecta: eDoc.code === 2 };
    throw eDoc;
  }
  var paginas = [];
  for (var n = 1; n <= doc.numPages; n++) {
    var pg = await doc.getPage(n), vp = pg.getViewport({ scale: 1 }), tc = await pg.getTextContent();
    var its = [];
    tc.items.forEach(function (it) {
      if (!it.str || !it.str.trim()) return;
      var x0 = it.transform[4], top = vp.height - it.transform[5];
      its.push({ s: it.str, x0: x0, x1: x0 + it.width, top: top });
    });
    // Renglones: mismo 'top' (±1.5). Dentro del renglón, de izquierda a derecha.
    its.sort(function (a, b) { return a.top - b.top || a.x0 - b.x0; });
    var lineas = [];
    its.forEach(function (it) {
      var L = lineas.length ? lineas[lineas.length - 1] : null;
      if (L && Math.abs(L.top - it.top) < 1.5) L.items.push(it); else lineas.push({ top: it.top, items: [it] });
    });
    lineas.forEach(function (L) {
      L.items.sort(function (a, b) { return a.x0 - b.x0; });
      // Texto del renglón: sin espacio entre tramos pegados (p. ej. «Liquidaci» «ó» «n»).
      var t = '', prev = null;
      L.items.forEach(function (it) { t += (prev && it.x0 - prev.x1 > 1.2 ? ' ' : '') + it.s; prev = it; });
      L.texto = t.replace(/\s+/g, ' ').trim();
    });
    paginas.push(lineas);
  }
  var todo = paginas.map(function (ls) { return ls.map(function (l) { return l.texto; }).join('\n'); }).join('\n');
  function busca(re) { var m = todo.match(re); return m; }
  var mPer = busca(/DEL (\d{2})\/(\d{2})\/(\d{4}) AL (\d{2})\/(\d{2})\/(\d{4})/);
  if (!mPer) return { ok: false, error: 'No reconocí el periodo del estado de cuenta. ¿Es un estado de cuenta BBVA?' };
  var anio = parseInt(mPer[6], 10), mesFin = parseInt(mPer[5], 10);
  var mCta = busca(/No\. (?:de )?Cuenta\s+(\d{10})/);
  var num = function (re) { var m = busca(re); return m ? cent(m[m.length - 1]) : null; };
  var mAb = busca(/Dep[oó]sitos \/ Abonos \(\+\)\s+(\d+)\s+([\d,]+\.\d{2})/);
  var mCa = busca(/Retiros \/ Cargos \(-\)\s+(\d+)\s+([\d,]+\.\d{2})/);
  var resumen = {
    saldoInicial: num(/Saldo de Liquidaci[oó]n Inicial\s+([\d,]+\.\d{2})/),
    abonosN: mAb ? parseInt(mAb[1], 10) : null, abonosTotal: mAb ? cent(mAb[2]) : null,
    cargosN: mCa ? parseInt(mCa[1], 10) : null, cargosTotal: mCa ? cent(mCa[2]) : null,
    saldoFinal: num(/Saldo Final \(\+\)\s+([\d,]+\.\d{2})/),
    comisiones: num(/Total Comisiones\s+([\d,]+\.\d{2})/)
  };
  var movs = [], fin = false;
  function fecha(dm) {
    var p = dm.split('/'), d = parseInt(p[0], 10), m = MESES[p[1]] || 0;
    var a = m > mesFin ? anio - 1 : anio;   // enero de un corte de diciembre, etc.
    return a + '-' + ('0' + m).slice(-2) + '-' + ('0' + d).slice(-2);
  }
  for (var pi = 0; pi < paginas.length && !fin; pi++) {
    var ls = paginas[pi], cols = null, topHdr = 0;
    ls.forEach(function (L) {
      var c = L.items.filter(function (i) { return i.s === 'CARGOS'; })[0];
      var a = L.items.filter(function (i) { return i.s === 'ABONOS'; })[0];
      if (c && a) { cols = { cargos: c.x1, abonos: a.x1 }; topHdr = L.top; }
    });
    if (!cols) continue;   // página sin tabla de movimientos
    for (var li = 0; li < ls.length; li++) {
      var L = ls[li];
      if (L.top <= topHdr) continue;
      if (/Total de Movimientos/i.test(L.texto)) { fin = true; break; }
      if (PIE.some(function (p) { return L.texto.indexOf(p) >= 0; })) continue;
      var izq = L.items.filter(function (i) { return !(MONTO.test(i.s) && i.x0 > 350); });
      var tIzq = '', pr = null;
      izq.forEach(function (it) { tIzq += (pr && it.x0 - pr.x1 > 1.2 ? ' ' : '') + it.s; pr = it; });
      tIzq = tIzq.replace(/\s+/g, ' ').trim();
      var mF = tIzq.match(/^(\d{2}\/[A-Z]{3}) (\d{2}\/[A-Z]{3}) (\S+) ?(.*)$/);
      if (mF && L.items[0].x0 < 40) {
        var mv = { fecha: fecha(mF[1]), fechaLiq: fecha(mF[2]), cod: mF[3], desc: mF[4].trim(), det: [],
          cargo: 0, abono: 0, saldo: null, pagina: pi + 1 };
        L.items.forEach(function (it) {
          if (!(MONTO.test(it.s) && it.x0 > 350)) return;
          var v = cent(it.s);
          if (Math.abs(it.x1 - cols.cargos) < 25) mv.cargo = v;
          else if (Math.abs(it.x1 - cols.abonos) < 25) mv.abono = v;
          else if (it.x1 < cols.abonos + 100) mv.saldo = v;   // saldo de operación
        });
        movs.push(mv);
      } else if (movs.length && L.items[0].x0 >= 40 && L.items[0].x0 < 370 && tIzq) {
        movs[movs.length - 1].det.push(tIzq);
      }
    }
  }
  movs.forEach(function (m) { m.det = m.det.join(' | ').substring(0, 400); });
  /* (8-oct) «APERTURA DE CUENTA» (cod C98) del primer mes de cada cuenta no es dinero y no trae monto: no es un movimiento. */
  movs = movs.filter(function (m) { return !(m.cod === 'C98' && !m.abono && !m.cargo); });
  var ab = movs.filter(function (m) { return m.abono > 0; }), ca = movs.filter(function (m) { return m.cargo > 0; });
  var sAb = ab.reduce(function (s, m) { return s + m.abono; }, 0), sCa = ca.reduce(function (s, m) { return s + m.cargo; }, 0);
  var ver = { abonosN: ab.length, abonosTotal: sAb, cargosN: ca.length, cargosTotal: sCa,
    sinMonto: movs.filter(function (m) { return !m.abono && !m.cargo; }).length };
  ver.cuadra = resumen.abonosN === ver.abonosN && resumen.abonosTotal === sAb &&
    resumen.cargosN === ver.cargosN && resumen.cargosTotal === sCa && ver.sinMonto === 0 &&
    resumen.saldoInicial !== null && resumen.saldoFinal !== null &&
    resumen.saldoInicial + sAb - sCa === resumen.saldoFinal;
  return { ok: true, banco: 'BBVA', cuenta: mCta ? mCta[1] : '',
    periodo: { desde: mPer[3] + '-' + mPer[2] + '-' + mPer[1], hasta: mPer[6] + '-' + mPer[5] + '-' + mPer[4] },
    resumen: resumen, verificacion: ver, movimientos: movs };
}
''';

/// (23-sep) Un estado de cuenta por procesar en lote: de un archivo o del correo.
class _ItemLote {
  final String etiqueta;
  final String cuenta;
  final Future<Uint8List> Function() cargar;
  _ItemLote(this.etiqueta, this.cuenta, this.cargar);
}

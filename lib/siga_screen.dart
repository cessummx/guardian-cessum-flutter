// siga_screen.dart
// (ago-6) CABINA SIGA — los 5 exportables para la SEC Sonora desde la app,
// sin URLs a mano. Selector de ciclo+carga, generación de cada Excel o del
// paquete completo, AUDITORÍA integral (qué falta para exportar sin
// errores), captura de equivalencias generación→ciclo/carga y de periodos
// faltantes, y bitácora. Todo llama al módulo SIGA ya existente en Code.gs.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';   // (5-oct-2026) reloj del panel de exportación
import 'dart:convert';

import 'constants.dart';
import 'helpers.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'siga_pendientes_screen.dart';
import 'siga_diagnostico_screen.dart';   // (23-sep) diagnóstico interpretado
import 'siga_bitacora_screen.dart';
import 'siga_equivalencias_screen.dart';   // (23-sep) Cabina única: aquí se llega a Equivalencias

class SigaScreen extends StatefulWidget {
  final String actor; // correo del admin
  const SigaScreen({super.key, required this.actor});

  @override
  State<SigaScreen> createState() => _SigaScreenState();
}

class _SigaScreenState extends State<SigaScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _ciclos = [];
  /// Tipo de periodo y materias por periodo de la opción elegida. Viajan en
  /// cada llamada para que el archivo salga con el corte correcto.
  String _tipoPeriodo = '';
  String _ultimas = '';
  Map<String, dynamic>? _faltantes;
  List<Map<String, dynamic>> _huecos = [];
  bool _cargandoFaltantes = false;
  /// Ubicar cada materia por la FECHA en que se cursó, no por el arranque de
  /// su generación: un alumno de la 25-2 siguió cursando en 2026 y sus
  /// materias pertenecen a este reporte.
  bool _porFecha = true;
  /// En Alumnos van solo los que fueron calificados en el periodo y siguen
  /// activos. Se aplica también a Carga y Calificaciones para que los tres
  /// archivos hablen del mismo conjunto de gente.
  bool _soloCursando = true;
  /// (22-sep) Reporte de INICIO de periodo: Alumnos y Carga horaria salen de
  /// las asignaciones (lo que empieza a cursarse), no de calificaciones, que
  /// al inicio todavía no existen. Es lo que la SEC pide al arrancar el ciclo.
  bool _inicio = false;
  Map<String, dynamic>? _listo;
  bool _cargandoListo = false;
  bool _verTodos = false;
  String? _resolviendo;
  String _ciclo = '';
  String _carga = '';
  // (ago-27) Programa. La SEC valida un programa a la vez: mandarle el
  // paquete con todos obliga a la revisora a separar lo que no le toca, y a
  // rebotar el archivo completo por errores de un programa que ni siquiera
  // está revisando.
  String _programa = '';
  bool _trabajando = false;
  /// (ago-12) Qué tarea larga está corriendo, para deshabilitar solo su botón.
  /// `_trabajando` ya existía como booleano para otra cosa; reusarlo con un
  /// texto rompía la compilación.
  String? _tarea;
  Map<String, dynamic>? _auditoria;
  Map<String, dynamic>? _paquete;
  final Map<String, Map<String, dynamic>> _resultados = {};
  /// (5-oct-2026) Exportación en curso: qué se genera, desde cuándo y en qué fase. Mientras exista, se ve el panel con la barra.
  Map<String, dynamic>? _progreso;

  static const _formatos = [
    ['Alumnos', 'siga_alumnos_excel', Icons.people],
    ['Oferta educativa', 'siga_oferta_excel', Icons.menu_book],
    ['Docentes', 'siga_docentes_excel', Icons.school],
    ['Carga horaria', 'siga_carga_excel', Icons.schedule],
    ['Calificaciones', 'siga_calif_excel', Icons.grading],
  ];

  @override
  void initState() {
    super.initState();
    _cargarCiclos();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp) async {
    // (23-sep) SIGA cerrado: toda consulta dice quién la hace.
    final q = {...qp};
    q.putIfAbsent('actor', () => widget.actor);
    final r = await http
        .get(Uri.parse(guardianUrl).replace(queryParameters: q))
        .timeout(const Duration(minutes: 4));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Map<String, String> _qpFiltro(String accion) {
    final qp = {'accion': accion};
    if (_ciclo.isNotEmpty) qp['ciclo'] = _ciclo;
    if (_carga.isNotEmpty) qp['carga'] = _carga;
    // Viaja con TODAS las llamadas, por la misma razón que el tipo de
    // periodo: lo que se audita tiene que ser lo que se exporta.
    if (_programa.isNotEmpty) qp['programa'] = _programa;
    if (_inicio) qp['origen'] = 'asignaciones';
    // (ago-9) El tipo de periodo y las materias por periodo viajan con TODAS
    // las llamadas —auditoría, Excel y paquete— para que lo que se audita sea
    // exactamente lo que se exporta. Si solo viajaran en el paquete, la
    // auditoría diría "sin errores" sobre un conjunto distinto al entregado.
    if (_tipoPeriodo.isNotEmpty) qp['tipoPeriodo'] = _tipoPeriodo;
    if (_ultimas.isNotEmpty) qp['ultimas'] = _ultimas;
    // (ago-12) ESTOS DOS NO VIAJABAN, y por eso el archivo de Alumnos salía
    // con el padrón completo —603— aunque el backend ya supiera acotarlo.
    // Van encendidos por omisión porque es el criterio correcto: se reporta
    // lo que se cursó en el periodo, no la generación que lo llevaba.
    if (_porFecha) qp['porFecha'] = '1';
    if (_soloCursando) qp['soloCursando'] = '1';
    return qp;
  }

  Future<void> _cargarCiclos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final d = await _get({'accion': 'siga_ciclos_listar'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _ciclos = ((d['ciclos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (_ciclos.isNotEmpty) {
          _ciclo = '${_ciclos.first['ciclo']}';
          _carga = '${_ciclos.first['carga']}';
          _tipoPeriodo = '${_ciclos.first['tipoPeriodo'] ?? ''}';
          _ultimas = '${_ciclos.first['materiasPorPeriodo'] ?? ''}';
        }
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error =
            'No se pudo cargar el SIGA. Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  Future<void> _auditar() async {
    setState(() {
      _trabajando = true;
      _auditoria = null;
    });
    try {
      final d = await _get(_qpFiltro('siga_auditoria'));
      if (!mounted) return;
      setState(() => _auditoria = d);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  /* (5-oct-2026) EXPORTAR SIN QUE «NO PASE NADA».
     Antes: la pantalla esperaba la respuesta (hasta minutos) y luego intentaba abrir el Excel en una pestaña nueva. El navegador bloquea
     las pestañas que se abren solas cuando ya pasó el clic, así que el archivo se generaba y la persona no veía nada. Además el proxy
     cortaba a los 120 s. Ahora: se pide en SEGUNDO PLANO (siga_excel_pedir), se consulta cada 4 s (siga_excel_estado) con un panel
     de progreso a la vista, y al terminar aparecen BOTONES para descargar o abrir (un botón sí lo permite el navegador). Si el segundo
     plano no está disponible, Apps Script puede devolver el Excel ya generado en la misma respuesta. */
  Future<Map<String, dynamic>> _exportar(String nombre, String que) async {
    setState(() {
      _trabajando = true;
      _progreso = {'nombre': nombre, 'inicio': DateTime.now(), 'fase': 'Preparando el archivo…'};
    });
    Map<String, dynamic>? res;
    // El reloj del panel avanza cada segundo, también si se genera por la vía directa.
    final reloj = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && _progreso != null) setState(() {}); });
    try {
      final p = await _get({..._qpFiltro('siga_excel_pedir'), 'que': que});
      if (p['ok'] == true && p['enProceso'] == true) {
        final id = '${p['id']}';
        final limite = DateTime.now().add(const Duration(minutes: 10));
        while (mounted && DateTime.now().isBefore(limite)) {
          await Future.delayed(const Duration(seconds: 4));
          if (!mounted) break;
          setState(() => _progreso?['fase'] = 'Generando el archivo en el servidor…');
          final e = await _get({'accion': 'siga_excel_estado', 'id': id});
          if (e['enProceso'] == true) continue;
          res = e['resultado'] is Map
              ? Map<String, dynamic>.from(e['resultado'] as Map)
              : {'ok': false, 'error': '${e['error'] ?? 'No se pudo generar el archivo.'}'};
          break;
        }
        res ??= {
          'ok': false,
          'error': 'Está tardando más de lo normal, pero se sigue generando. Búscalo en tu Google Drive en unos minutos: aparece como el archivo más reciente.'
        };
      } else {
        // Apps Script puede haber generado el archivo directamente cuando no hubo disparador.
        // Usar su resultado (también si es error) evita iniciar una segunda exportación.
        res = p;
      }
    } catch (e) {
      res = {'ok': false, 'error': 'Se perdió la conexión mientras se generaba. Si ya pasó un rato, revisa tu Google Drive: puede haberse generado igual.'};
    }
    reloj.cancel();
    if (mounted) setState(() { _trabajando = false; _progreso = null; });
    return res ?? {'ok': false, 'error': 'No se pudo generar el archivo.'};
  }

  Widget _panelProgreso() {
    final p = _progreso!;
    final seg = DateTime.now().difference(p['inicio'] as DateTime).inSeconds;
    final t = '${seg ~/ 60}:${(seg % 60).toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.hourglass_top, color: Color(0xFF8A5F10), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Generando «${p['nombre']}»', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        const ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(4)),
          child: LinearProgressIndicator(minHeight: 7, color: cessumRed, backgroundColor: Color(0x22B11D29)),
        ),
        const SizedBox(height: 8),
        Text('${p['fase']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Suele tardar de 1 a 3 minutos. Espera aquí: al terminar aparecen los botones para descargarlo. '
          'Si cierras esta pantalla, el archivo se sigue generando y aparece en tu Google Drive como el más reciente.',
          style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context)),
        ),
      ]),
    );
  }

  Widget _botonesArchivo(Map<String, dynamic> d) => Wrap(spacing: 6, children: [
        if ('${d['xlsxUrl'] ?? ''}'.isNotEmpty)
          TextButton.icon(
            onPressed: () => Helpers.abrirUrlExterna('${d['xlsxUrl']}', context),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Descargar Excel', style: TextStyle(fontSize: 12)),
          ),
        if ('${d['verUrl'] ?? ''}'.isNotEmpty)
          TextButton.icon(
            onPressed: () => Helpers.abrirUrlExterna('${d['verUrl']}', context),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Abrir en Google Sheets', style: TextStyle(fontSize: 12)),
          ),
      ]);

  Future<void> _generar(String nombre, String accion) async {
    final que = accion.replaceFirst('siga_', '').replaceFirst('_excel', '');
    {
      final d = await _exportar(nombre, que);
      if (!mounted) return;
      setState(() => _resultados[nombre] = d);
      if (d['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: const Color(0xFF1E8E3E),
            content: Text('«$nombre» listo. Usa los botones de su renglón para descargarlo.')));
      } else if (d['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, duration: const Duration(seconds: 8), content: Text('${d['error']}')));
      }
    }
  }

  // (2-oct-2026) Etiqueta legible del ciclo·carga ACTUALMENTE seleccionado
  // en el dropdown de arriba — la misma que arma el backend para la lista.
  // "Sin filtro" si no hay ninguno elegido (combo "||", exporta histórico
  // completo). Se usa tanto en el diálogo de confirmación como en la
  // tarjeta de resultado, para que nunca quede ambiguo qué se generó.
  String _etiquetaCicloActual() {
    if (_ciclo.isEmpty && _carga.isEmpty) return 'Todos (sin filtro) — histórico completo';
    final sel = _ciclos.firstWhere(
        (c) =>
            '${c['ciclo']}' == _ciclo &&
            '${c['carga']}' == _carga &&
            '${c['tipoPeriodo'] ?? ''}' == _tipoPeriodo,
        orElse: () => <String, dynamic>{});
    return '${sel['etiqueta'] ?? '$_ciclo · carga $_carga'}';
  }

  // (2-oct-2026) CANDADO CONTRA EL ERROR REAL QUE YA PASÓ: generar el
  // paquete de un ciclo·carga distinto al que se venía auditando, sin
  // darse cuenta porque el selector queda lejos del botón en una pantalla
  // larga. Ahora, antes de disparar la generación (que sube un Excel real
  // a Drive, no es un "modo prueba"), se muestra justo lo que se va a
  // exportar y hay que confirmarlo explícitamente.
  Future<void> _generarPaquete() async {
    final etiqueta = _etiquetaCicloActual();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar paquete a generar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se van a generar los 5 Excel para:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(etiqueta,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            ),
            if (_programa.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Programa: $_programa', style: const TextStyle(fontSize: 12)),
            ],
            const SizedBox(height: 10),
            const Text('¿Es el periodo correcto? Revisa el selector arriba si no.',
                style: TextStyle(fontSize: 11.5, color: Colors.black54)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E8E3E)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _paquete = null);
    // (5-oct-2026) En segundo plano y con el panel de progreso; al terminar, el botón «Abrir carpeta en Drive» en su tarjeta.
    final d = await _exportar('Paquete completo (5 Excel)', 'paquete');
    if (!mounted) return;
    setState(() => _paquete = d);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: d['ok'] == true ? const Color(0xFF1E8E3E) : cessumRed,
        duration: const Duration(seconds: 8),
        content: Text(d['ok'] == true ? 'Paquete listo. Ábrelo con el botón «Abrir carpeta en Drive».' : '${d['error'] ?? 'No se pudo generar el paquete.'}')));
  }

  Future<void> _erroresExcel() async {
    setState(() => _trabajando = true);
    try {
      final d = await _get(_qpFiltro('siga_errores_excel'));
      if (!mounted) return;
      if (d['ok'] == true && '${d['xlsxUrl'] ?? ''}'.isNotEmpty) {
        // (5-oct-2026) Botón «Abrir»: una pestaña abierta sola, después de esperar, la bloquea el navegador.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 20),
            content: const Text('Reporte de errores listo.'),
            action: SnackBarAction(label: 'Abrir', onPressed: () => Helpers.abrirUrlExterna('${d['xlsxUrl']}', context))));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(d['ok'] == true ? 'Sin errores que reportar 🎉' : 'Error: ${d['error']}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _equivalencias() async {
    setState(() => _trabajando = true);
    Map<String, dynamic>? d;
    try {
      d = await _get({'accion': 'siga_equivalencias_listar'});
    } catch (_) {}
    if (mounted) setState(() => _trabajando = false);
    if (!mounted || d == null) return;
    final filas = ((d['equivalencias'] as List?) ?? (d['filas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: cessumRed,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                const Expanded(
                  child: Text('Equivalencias generación → ciclo / carga',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Expanded(
              child: filas.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'Aún no hay equivalencias capturadas. Usa '
                          '"Capturar equivalencia" para dar de alta la '
                          'primera (ej. Gen 26-1 → 2026-2027, carga 1).'))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final f in filas)
                          ListTile(
                            dense: true,
                            title: Text(
                                '${f['programa'] ?? ''} · Gen ${f['generacion'] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(
                                'Ciclo ${f['cicloEscolar'] ?? f['ciclo'] ?? '—'} · carga ${f['noCarga'] ?? f['carga'] ?? '—'}',
                                style: const TextStyle(fontSize: 11.5)),
                            trailing: IconButton(
                              icon: const Icon(Icons.edit,
                                  size: 17, color: cessumGold),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _capturarEquivalencia(previa: f);
                              },
                            ),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _capturarEquivalencia();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Capturar equivalencia'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _capturarEquivalencia({Map<String, dynamic>? previa}) async {
    final progCtrl =
        TextEditingController(text: '${previa?['programa'] ?? ''}');
    final genCtrl =
        TextEditingController(text: '${previa?['generacion'] ?? ''}');
    final cicloCtrl = TextEditingController(
        text: '${previa?['cicloEscolar'] ?? previa?['ciclo'] ?? ''}');
    final cargaCtrl = TextEditingController(
        text: '${previa?['noCarga'] ?? previa?['carga'] ?? ''}');
    String tipoP = '${previa?['tipoPeriodo'] ?? '4'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setD) => AlertDialog(
          title: const Text('Equivalencia SIGA',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: progCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Programa (nombre oficial completo)')),
              TextField(
                  controller: genCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Generación (ej. 26-1)')),
              TextField(
                  controller: cicloCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Ciclo escolar (AAAA-AAAA)')),
              TextField(
                  controller: cargaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'No. de carga (1, 2, 3…)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: tipoP,
                decoration:
                    const InputDecoration(labelText: 'Tipo de periodo'),
                items: const [
                  DropdownMenuItem(value: '1', child: Text('Bimestre')),
                  DropdownMenuItem(value: '2', child: Text('Trimestre')),
                  DropdownMenuItem(value: '3', child: Text('Cuatrimestre')),
                  DropdownMenuItem(value: '4', child: Text('Semestral')),
                  DropdownMenuItem(value: '5', child: Text('Anual')),
                ],
                onChanged: (v) => setD(() => tipoP = v ?? '4'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _trabajando = true);
    try {
      final d = await _get({
        'accion': 'siga_equivalencia_guardar',
        'actor': widget.actor,
        'programa': progCtrl.text.trim(),
        'generacion': genCtrl.text.trim(),
        'cicloEscolar': cicloCtrl.text.trim(),
        'noCarga': cargaCtrl.text.trim(),
        'tipoPeriodo': tipoP,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(d['ok'] == true
              ? '✅ Equivalencia guardada'
              : 'Error: ${d['error']}')));
      if (d['ok'] == true) _cargarCiclos();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Future<void> _capturarPeriodo(Map<String, dynamic> m) async {
    final perCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${m['materia'] ?? m['clave']}',
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: perCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Periodo del plan (1-9)',
              helperText: 'Semestre o trimestre en que se cursa'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || perCtrl.text.trim().isEmpty) return;
    try {
      final d = await _get({
        'accion': 'siga_periodo_guardar',
        'actor': widget.actor,
        'programa': '${m['programa'] ?? ''}',
        'clave': '${m['clave'] ?? ''}',
        'materia': '${m['materia'] ?? ''}',
        'periodo': perCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(d['ok'] == true
              ? '✅ Periodo guardado'
              : 'Error: ${d['error']}')));
      if (d['ok'] == true) _auditar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('SIGA · Exportables SEC',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Alumnos sin CURP o sin promedio de ingreso',
            icon: const Icon(Icons.badge_outlined),
            onPressed: _ciclo.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SigaPendientesScreen(
                          ciclo: _ciclo,
                          carga: _carga,
                          inicio: _inicio,
                          programa: _programa,
                        ),
                      ),
                    ),
          ),
          // (23-sep) Esta cabina no llevaba al diagnóstico ni a la bitácora.
          IconButton(
            tooltip: 'Diagnóstico: qué impide subir y cómo resolverlo',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: _ciclo.isEmpty
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SigaDiagnosticoScreen(
                          ciclo: _ciclo,
                          carga: _carga,
                          tipoPeriodo: _tipoPeriodo,
                          inicio: _inicio,
                        ),
                      ),
                    ),
          ),
          IconButton(
            tooltip: 'Equivalencias: a qué ciclo y carga pertenece cada generación',
            icon: const Icon(Icons.event_note),
            onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SigaEquivalenciasScreen()))
                .then((_) => _cargarCiclos()),
          ),
          IconButton(
            tooltip: 'Bitácora de exportaciones',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SigaBitacoraScreen())),
          ),
          IconButton(
              onPressed: _cargarCiclos,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _selector(),
                    const SizedBox(height: 14),
                    _criteriosCorte(),
                    _semaforoEntrega(),
                    _cuadroDecision(),
                    _botonera(),
                    if (_progreso != null) _panelProgreso(),   // (5-oct-2026) barra mientras se genera
                    const SizedBox(height: 14),
                    _tarjetaFormatos(),
                    if (_paquete != null) _tarjetaPaquete(),
                    if (_auditoria != null) _tarjetaAuditoria(),
                  ],
                ),
    );
  }

  /// (ago-9) CUADRO DE DECISIÓN. Antes los huecos estaban repartidos entre la
  /// auditoría, el validador y el diagnóstico de claves, y cada uno se
  /// resolvía editando hojas a mano. Aquí se ven juntos, ordenados por lo que
  /// BLOQUEA la entrega, y se resuelven desde la misma pantalla: lo que se
  /// decide aquí se escribe en la hoja y sale en el siguiente paquete.
  /// (ago-9) EL SEMÁFORO. Seis herramientas revisan cosas distintas y
  /// ninguna respondía la pregunta que de verdad se hace antes de entregar:
  /// "¿ya puedo?". Esto las corre todas y da una sola respuesta, con lo que
  /// bloquea arriba y qué hacer con cada cosa.
  Widget _semaforoEntrega() {
    final estado = '${_listo?['estado'] ?? ''}';
    final bloqueos = (_listo?['bloqueos'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final reservas = (_listo?['reservas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final enOrden = (_listo?['enOrden'] as List? ?? []).cast<dynamic>();

    Color col;
    IconData ico;
    String titulo;
    switch (estado) {
      case 'listo':
        col = const Color(0xFF1E7B34);
        ico = Icons.verified;
        titulo = 'Listo para entregar';
        break;
      case 'con_reservas':
        col = cessumGold;
        ico = Icons.info_outline;
        titulo = 'Se puede entregar, con reservas';
        break;
      case 'no_listo':
        col = cessumRed;
        ico = Icons.report_problem_outlined;
        titulo = 'Todavía no se puede entregar';
        break;
      default:
        col = cessumFaint(context);
        ico = Icons.help_outline;
        titulo = '¿Se puede entregar?';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.withValues(alpha: 0.45), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ico, size: 22, color: col),
              const SizedBox(width: 8),
              Expanded(
                child: Text(titulo,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: col)),
              ),
              if (_cargandoListo)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton(
                  onPressed: _cargarListo,
                  child: Text(_listo == null ? 'Revisar' : 'Volver a revisar',
                      style: const TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
          if (_listo == null)
            Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                  'Corre todas las verificaciones sobre el corte seleccionado '
                  'y te da una sola respuesta.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            )
          else ...[
            const SizedBox(height: 4),
            Text('${_listo!['veredicto'] ?? ''}',
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
            if (_n(_listo!['totalRenglones']) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${_n(_listo!['totalRenglones'])} renglones en total',
                    style: TextStyle(
                        fontSize: 11.5, color: cessumMuted(context))),
              ),
            for (final b in bloqueos) _puntoSemaforo(b, cessumRed, 'BLOQUEA'),
            for (final r in reservas) _puntoSemaforo(r, cessumGold, 'REVISAR'),
            if (enOrden.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final o in enOrden)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check, size: 14,
                          color: Color(0xFF1E7B34)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('$o',
                            style: const TextStyle(
                                fontSize: 11.5, color: Color(0xFF1B5E20))),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8)),
              child: Text('Siguiente paso: ${_listo!['siguientePaso'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 12, height: 1.35, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _puntoSemaforo(Map<String, dynamic> b, Color col, String etiqueta) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: col.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(etiqueta,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: col)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${b['que']}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text('${b['porQue'] ?? ''}',
              style: TextStyle(
                  fontSize: 11.5, height: 1.3, color: cessumMuted(context))),
          const SizedBox(height: 3),
          Text('→ ${b['comoSeArregla'] ?? ''}',
              style: const TextStyle(fontSize: 11.5, height: 1.3)),
        ],
      ),
    );
  }

  Future<void> _cargarListo() async {
    setState(() => _cargandoListo = true);
    try {
      final d = await _get(_qpFiltro('siga_listo'));
      if (mounted && d['ok'] == true) setState(() => _listo = d);
    } catch (_) {
      // el resto de la Cabina sigue sirviendo si esto falla
    }
    if (mounted) setState(() => _cargandoListo = false);
  }

  /// (ago-12) Los dos criterios que definen QUÉ entra al reporte. Van
  /// visibles y no escondidos en el código: cambian por completo el archivo
  /// que se entrega a la autoridad, así que quien lo genera tiene que poder
  /// verlos y desactivarlos.
  Widget _criteriosCorte() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CC.goldBorder),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _porFecha,
            onChanged: (v) => setState(() {
              _porFecha = v;
              _listo = null;
              _faltantes = null;
            }),
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: cessumRed,
            title: const Text('Ubicar por fecha de la materia',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: const Text(
                'Entra todo lo que se cursó en el periodo, sin importar la '
                'generación. Apagado, solo entran las generaciones cuyo '
                'arranque coincide con el ciclo.',
                style: TextStyle(fontSize: 11, height: 1.3)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _soloCursando,
            onChanged: (v) => setState(() {
              _soloCursando = v;
              _listo = null;
              _faltantes = null;
            }),
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: cessumRed,
            title: const Text('Solo alumnos activos calificados',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: const Text(
                'Deja fuera egresados, bajas y a quien no fue calificado en '
                'el periodo. Se aplica a los tres archivos, para que ninguno '
                'referencie a alguien que no está en el padrón declarado. '
                'Úselo solo con el periodo en curso: mide el estado de HOY, y '
                'en un periodo pasado dejaría fuera a quien ya egresó.',
                style: TextStyle(fontSize: 11, height: 1.3)),
          ),
          const Divider(height: 1),
          SwitchListTile(
            value: _inicio,
            onChanged: (v) => setState(() {
              _inicio = v;
              _listo = null;
              _faltantes = null;
            }),
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeThumbColor: cessumRed,
            title: const Text('Inicio de periodo (desde asignaciones)',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: const Text(
                'Para lo que la SEC pide al arrancar: Alumnos y Carga horaria '
                'salen de las materias que empiezan en el periodo y de los '
                'alumnos activos de cada grupo, sin esperar calificaciones.',
                style: TextStyle(fontSize: 11, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Widget _cuadroDecision() {
    final total = _n(_faltantes?['total']);
    final bloquean = _n(_faltantes?['bloquean']);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: bloquean > 0
                ? cessumRed.withValues(alpha: 0.5)
                : cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(bloquean > 0 ? Icons.rule_folder : Icons.rule,
                  size: 19,
                  color: bloquean > 0 ? cessumRed : const Color(0xFF1E7B34)),
              const SizedBox(width: 7),
              const Expanded(
                child: Text('Qué falta y qué hacer con eso',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              if (_cargandoFaltantes)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                TextButton(
                  onPressed: _cargarFaltantes,
                  child: Text(_faltantes == null ? 'Revisar' : 'Actualizar',
                      style: const TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
          if (_faltantes == null)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'Revisa el corte seleccionado y te digo qué impide entregarlo.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            )
          else if (total == 0)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Nada pendiente. El corte está listo para entregar.',
                  style: TextStyle(
                      fontSize: 12.5, color: Color(0xFF1B5E20))),
            )
          else ...[
            const SizedBox(height: 4),
            Text(
                bloquean > 0
                    ? '$bloquean de $total impiden que la autoridad acepte esos renglones.'
                    : '$total detalle(s) por revisar. Ninguno bloquea la entrega.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: bloquean > 0 ? cessumRed : cessumMuted(context))),
            const SizedBox(height: 10),
            // (ago-12) Las dos herramientas que de verdad destraban las
            // materias sin clave. Estaban construidas y solo existían como
            // URL, así que en la práctica no se usaban.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      side: const BorderSide(color: cessumRed),
                      visualDensity: VisualDensity.compact),
                  onPressed: _tarea == 'variantes'
                      ? null
                      : _verVariantes,
                  icon: const Icon(Icons.merge_type, size: 16),
                  label: const Text('Buscar nombres repetidos',
                      style: TextStyle(fontSize: 12)),
                ),
                // (ago-12) Las CURP faltantes son lo ÚNICO que impide
                // entregar, y se resolvían por URL: en la práctica nadie las
                // capturaba.
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFC62828),
                      side: const BorderSide(color: Color(0xFFC62828)),
                      visualDensity: VisualDensity.compact),
                  onPressed:
                      _tarea == 'curps' ? null : _revisarCurps,
                  icon: const Icon(Icons.badge_outlined, size: 16),
                  label: const Text('Revisar CURPs',
                      style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1E7B34),
                      side: const BorderSide(color: Color(0xFF1E7B34)),
                      visualDensity: VisualDensity.compact),
                  onPressed: _tarea == 'claves'
                      ? null
                      : _aplicarClavesExistentes,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: const Text('Aplicar claves que ya existen',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final h in _huecos.take(_verTodos ? 200 : 6)) _fichaHueco(h),
            if (_huecos.length > 6)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _verTodos = !_verTodos),
                  child: Text(
                      _verTodos
                          ? 'Ver menos'
                          : 'Ver los ${_huecos.length} completos',
                      style: const TextStyle(fontSize: 12.5)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _fichaHueco(Map<String, dynamic> h) {
    final bloquea = '${h['gravedad']}' == 'bloquea';
    final col = bloquea ? cessumRed : cessumGold;
    final opciones = (h['opciones'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final ocupado = _resolviendo == '${h['llave']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bloquea ? cessumRed.withValues(alpha: 0.06) : cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(bloquea ? 'BLOQUEA' : 'REVISAR',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: col)),
              ),
              const SizedBox(width: 6),
              if (_n(h['afectados']) > 0)
                Text('${_n(h['afectados'])} ${h['unidad'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${(h['formatos'] as List? ?? []).join(' · ')}',
                  style: TextStyle(
                      fontSize: 10, color: cessumFaint(context))),
            ],
          ),
          const SizedBox(height: 5),
          Text('${h['titulo']}',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if ('${h['contexto'] ?? ''}'.isNotEmpty)
            Text('${h['contexto']}',
                style: TextStyle(
                    fontSize: 11.5, color: cessumMuted(context))),
          const SizedBox(height: 5),
          Text('${h['porQue'] ?? ''}',
              style: TextStyle(
                  fontSize: 11.5, height: 1.35, color: cessumInk(context))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in opciones)
                if ('${o['accion']}' != 'revisar')
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: col,
                        side: BorderSide(color: col.withValues(alpha: 0.5)),
                        visualDensity: VisualDensity.compact),
                    onPressed:
                        ocupado ? null : () => _decidir(h, o),
                    child: Text('${o['etiqueta']}',
                        style: const TextStyle(fontSize: 11.5)),
                  )
                else
                  Text('${o['consecuencia']}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: cessumMuted(context))),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _decidir(
      Map<String, dynamic> h, Map<String, dynamic> opcion) async {
    var valor = '${h['sugerido'] ?? ''}';
    if ('${opcion['accion']}' == 'capturar') {
      final ctrl = TextEditingController(text: valor);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${h['titulo']}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${h['contexto'] ?? ''}',
                    style: TextStyle(
                        fontSize: 12, color: cessumMuted(context))),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: _etiquetaCampo('${h['tipo']}'),
                    helperText: '${opcion['consecuencia'] ?? ''}',
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
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
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      valor = ctrl.text.trim();
      ctrl.dispose();
      if (ok != true || valor.isEmpty) return;
    }

    setState(() => _resolviendo = '${h['llave']}');
    try {
      final qp = {
        'accion': 'siga_decidir',
        'tipo': '${h['tipo']}',
        'llave': '${h['llave']}',
        'decision': '${opcion['accion']}',
        'valor': valor,
        'actor': widget.actor,
      };
      if (_tipoPeriodo.isNotEmpty) qp['tipoPeriodo'] = _tipoPeriodo;
      final d = await _get(qp);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor:
            d['ok'] == true ? const Color(0xFF1E8E3E) : cessumRed,
        content: Text(d['ok'] == true
            ? '${d['aviso'] ?? 'Guardado.'}'
            : '${d['error'] ?? 'No se pudo'}'),
      ));
      if (d['ok'] == true) await _cargarFaltantes();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
    if (mounted) setState(() => _resolviendo = null);
  }

  String _etiquetaCampo(String tipo) {
    if (tipo == 'materia_sin_clave') return 'Clave de la materia en el plan';
    if (tipo == 'sin_equivalencia') return 'Ciclo y carga (ej. 2026-2027|1)';
    if (tipo == 'sin_periodo') return 'Semestre del plan (1, 2, 3…)';
    return 'Valor';
  }

  /// Agrupa las materias que parecen la MISMA escrita distinto —"Conteporáneas"
  /// sin la m— y permite homologarlas de un jalón. Es lo que reduce la lista:
  /// muchas de las 66 no son materias distintas.
  Future<void> _verVariantes() async {
    setState(() => _tarea = 'variantes');
    Map<String, dynamic> d = {};
    try {
      d = await _get({'accion': 'siga_materias_variantes'});
    } catch (e) {
      _avisoSiga('$e');
      if (mounted) setState(() => _tarea = null);
      return;
    }
    if (mounted) setState(() => _tarea = null);
    if (d['ok'] != true) {
      _avisoSiga('${d['error'] ?? 'No se pudo'}');
      return;
    }
    final grupos = (d['detalle'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!mounted) return;
    if (grupos.isEmpty) {
      _avisoSiga('No hay nombres repetidos: las materias sin clave son '
          'distintas entre sí.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombres que parecen la misma materia',
            style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${grupos.length} grupo(s) · '
                    '${_n(d['resolublesYa'])} se pueden resolver ya',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                for (final g in grupos.take(40)) _fichaVariante(g, ctx),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _fichaVariante(Map<String, dynamic> g, BuildContext ctx) {
    final vars = (g['variantes'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final tieneClave = '${g['claveBuena'] ?? ''}'.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cessumMuted(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${g['programa']}',
              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          const SizedBox(height: 4),
          for (final v in vars)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                      v['esLaBuena'] == true
                          ? Icons.star
                          : Icons.subdirectory_arrow_right,
                      size: 14,
                      color: v['esLaBuena'] == true
                          ? cessumGold
                          : cessumFaint(context)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                        '${v['materia']}  ·  ${_n(v['filas'])} fila(s)'
                        '${'${v['clave'] ?? ''}'.isNotEmpty ? ' · ${v['clave']}' : ' · sin clave'}',
                        style: TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            fontWeight: v['esLaBuena'] == true
                                ? FontWeight.w700
                                : FontWeight.w400)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 5),
          Text('${g['veredicto'] ?? ''}',
              style: TextStyle(
                  fontSize: 11, height: 1.3, color: cessumMuted(context))),
          if (tieneClave) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _homologar(g, ctx),
                child: Text(
                    'Unificar en "${g['nombreBueno']}" y copiar clave',
                    style: const TextStyle(fontSize: 11.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _homologar(Map<String, dynamic> g, BuildContext ctx) async {
    final vars = (g['variantes'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    var hechos = 0;
    for (final v in vars) {
      if (v['esLaBuena'] == true) continue;
      try {
        final r = await _get({
          'accion': 'siga_homologar_materia',
          'programa': '${g['programa']}',
          'de': '${v['materia']}',
          'a': '${g['nombreBueno']}',
          'clave': '${g['claveBuena']}',
          'actor': widget.actor,
        });
        if (r['ok'] == true) hechos += _n(r['filasAfectadas']);
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pop(ctx);
    _avisoSiga('Listo: $hechos fila(s) unificadas.');
    await _cargarFaltantes();
  }

  /// Copia, en todas las materias que la tengan capturada en otro grupo, la
  /// clave que ya existe. Es solo escritura de un dato que ya estaba: no
  /// inventa claves.
  Future<void> _aplicarClavesExistentes() async {
    setState(() => _tarea = 'claves');
    try {
      final previa =
          await _get({'accion': 'siga_claves_aplicar', 'prueba': '1'});
      if (mounted) setState(() => _tarea = null);
      if (previa['ok'] != true) {
        _avisoSiga('${previa['error'] ?? 'No se pudo'}');
        return;
      }
      final cuantas = _n(previa['materiasResueltas']);
      final filasTocadas = _n(previa['filasAfectadas']);
      if (!mounted) return;
      if (cuantas == 0) {
        _avisoSiga('Ninguna materia tiene su clave capturada en otro grupo: '
            'hay que tomarlas del plan de estudios.');
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Aplicar claves', style: TextStyle(fontSize: 16)),
          content: Text(
              'Se van a copiar $cuantas clave(s) que ya existen en otros '
              'grupos, sobre $filasTocadas fila(s). '
              'No inventa claves: solo escribe las que ya estaban capturadas.',
              style: const TextStyle(fontSize: 12.5, height: 1.4)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      setState(() => _tarea = 'claves');
      final r = await _get(
          {'accion': 'siga_claves_aplicar', 'actor': widget.actor});
      _avisoSiga(r['ok'] == true
          ? '${r['aviso'] ?? 'Listo.'}'
          : '${r['error'] ?? 'No se pudo'}');
      if (r['ok'] == true) await _cargarFaltantes();
    } catch (e) {
      _avisoSiga('$e');
    }
    if (mounted) setState(() => _tarea = null);
  }

  /// Quién no tiene CURP y quién la tiene mal capturada. Se verifica el
  /// dígito verificador, no solo la forma: una CURP con el dígito mal es un
  /// error de tecleo y la autoridad la rechaza igual que si faltara.
  Future<void> _revisarCurps() async {
    setState(() => _tarea = 'curps');
    Map<String, dynamic> d = {};
    try {
      d = await _get(_qpFiltro('siga_curps_faltantes'));
    } catch (e) {
      _avisoSiga('$e');
      if (mounted) setState(() => _tarea = null);
      return;
    }
    if (mounted) setState(() => _tarea = null);
    if (d['ok'] != true) {
      _avisoSiga('${d['error'] ?? 'No se pudo consultar'}');
      return;
    }
    final faltan = (d['faltantes'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final malas = (d['invalidas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!mounted) return;
    if (faltan.isEmpty && malas.isEmpty) {
      _avisoSiga('Ninguna CURP falta ni está mal formada.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CURPs por resolver',
            style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d['siguiente'] ?? ''}',
                    style: const TextStyle(fontSize: 12, height: 1.35)),
                if (malas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('MAL CAPTURADAS (${malas.length})',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFC62828))),
                  const SizedBox(height: 5),
                  for (final m in malas) _filaCurp(m, true),
                ],
                if (faltan.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('SIN CURP (${faltan.length})',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: cessumGold)),
                  const SizedBox(height: 5),
                  for (final f in faltan) _filaCurp(f, false),
                ],
                const SizedBox(height: 10),
                Text('${d['nota'] ?? ''}',
                    style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        fontStyle: FontStyle.italic,
                        color: cessumMuted(context))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _filaCurp(Map<String, dynamic> x, bool mala) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
          color: mala ? cessumRed.withValues(alpha: 0.06) : cessumGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${x['tipo']}',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      color: cessumFaint(context))),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${x['nombre']}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              if ('${x['clave'] ?? ''}'.isNotEmpty)
                Text('${x['clave']}',
                    style: TextStyle(
                        fontSize: 11, color: cessumFaint(context))),
            ],
          ),
          if (mala) ...[
            const SizedBox(height: 3),
            Text('${x['curp']}',
                style: const TextStyle(
                    fontSize: 11.5, fontFamily: 'monospace')),
            Text('${x['problema']}',
                style: const TextStyle(
                    fontSize: 11, height: 1.3, color: Color(0xFFC62828))),
          ] else if ('${x['comoSeGuarda'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('${x['comoSeGuarda']}',
                style: TextStyle(
                    fontSize: 10.5, height: 1.3, color: cessumMuted(context))),
          ],
        ],
      ),
    );
  }

  void _avisoSiga(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), duration: const Duration(seconds: 5)));
  }

  Future<void> _cargarFaltantes() async {
    setState(() => _cargandoFaltantes = true);
    try {
      final d = await _get(_qpFiltro('siga_faltantes'));
      if (mounted && d['ok'] == true) {
        setState(() {
          _faltantes = d;
          _huecos = (d['huecos'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
      // si falla, la Cabina sigue sirviendo para lo demás
    }
    if (mounted) setState(() => _cargandoFaltantes = false);
  }

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  Widget _selector() {
    // (ago-9) Cada opción es ciclo + carga + TIPO DE PERIODO. La SEC pide
    // reportes separados por tipo, así que "2026-2027 carga 1" no es una sola
    // opción: es la semestral y la trimestral, con contenidos distintos.
    final combos = <String>{
      for (final c in _ciclos)
        '${c['ciclo']}|${c['carga']}|${c['tipoPeriodo'] ?? ''}'
    };
    final valor = '$_ciclo|$_carga|$_tipoPeriodo';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        const Icon(Icons.filter_alt, size: 18, color: Color(0xFF8A5A0F)),
        const SizedBox(width: 8),
        const Text('Ciclo y carga:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: combos.contains(valor) ? valor : null,
            hint: const Text('Sin equivalencias capturadas',
                style: TextStyle(fontSize: 12)),
            items: [
              for (final c in _ciclos)
                DropdownMenuItem(
                  value: '${c['ciclo']}|${c['carga']}|${c['tipoPeriodo'] ?? ''}',
                  // La etiqueta la arma el backend: "2026-2027 · carga 1 ·
                  // enero a julio · Semestral (4 materias)". Antes decía
                  // "carga 1 (12 gen.)", que no le dice a nadie qué va a
                  // exportar ni qué meses cubre.
                  child: Text(
                      '${c['etiqueta'] ?? '${c['ciclo']} · carga ${c['carga']}'}',
                      style: const TextStyle(fontSize: 12.5)),
                ),
              const DropdownMenuItem(
                  value: '||',
                  child: Text('Todos (sin filtro)',
                      style: TextStyle(fontSize: 12.5))),
            ],
            onChanged: (v) {
              if (v == null) return;
              final p = v.split('|');
              setState(() {
                _ciclo = p[0];
                _carga = p.length > 1 ? p[1] : '';
                _tipoPeriodo = p.length > 2 ? p[2] : '';
                // Las materias por periodo vienen con la opción: en semestral
                // son 4, y ese número es el que decide cuántas materias se
                // jalan de cada alumno.
                final sel = _ciclos.firstWhere(
                    (c) =>
                        '${c['ciclo']}' == _ciclo &&
                        '${c['carga']}' == _carga &&
                        '${c['tipoPeriodo'] ?? ''}' == _tipoPeriodo,
                    orElse: () => <String, dynamic>{});
                _ultimas = '${sel['materiasPorPeriodo'] ?? ''}';
              });
            },
          ),
        ),
        // (ago-27) Programa. Vacío = todos, como hasta ahora.
        const SizedBox(width: 12),
        const Text('Programa:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        SizedBox(
          width: 230,
          child: DropdownButton<String>(
            isExpanded: true,
            value: _programa.isEmpty ? null : _programa,
            hint: const Text('Todos los programas',
                style: TextStyle(fontSize: 12)),
            items: const [
              DropdownMenuItem(value: '', child: Text('Todos los programas',
                  style: TextStyle(fontSize: 12.5))),
              DropdownMenuItem(value: 'Maestría en Educación',
                  child: Text('Maestría en Educación',
                      style: TextStyle(fontSize: 12.5))),
              DropdownMenuItem(value: 'Maestría en Psicopedagogía',
                  child: Text('Maestría en Psicopedagogía',
                      style: TextStyle(fontSize: 12.5))),
              DropdownMenuItem(value: 'Maestría en Pedagogía',
                  child: Text('Maestría en Pedagogía',
                      style: TextStyle(fontSize: 12.5))),
              DropdownMenuItem(value: 'Maestría en Educación Inclusiva',
                  child: Text('Maestría en Educación Inclusiva',
                      style: TextStyle(fontSize: 12.5))),
              DropdownMenuItem(value: 'Doctorado en Educación con Énfasis',
                  child: Text('Doctorado en Educación (Investigación)',
                      style: TextStyle(fontSize: 12.5))),
              DropdownMenuItem(value: 'Doctorado en Ciencias de la Educación',
                  child: Text('Doctorado en Ciencias de la Educación',
                      style: TextStyle(fontSize: 12.5))),
              DropdownMenuItem(value: 'Licenciatura en Pedagogía',
                  child: Text('Licenciatura en Pedagogía',
                      style: TextStyle(fontSize: 12.5))),
            ],
            onChanged: (v) => setState(() => _programa = v ?? ''),
          ),
        ),
      ]),
    );
  }

  Widget _botonera() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: cessumRed, foregroundColor: Colors.white),
        onPressed: _trabajando ? null : _auditar,
        icon: const Icon(Icons.troubleshoot, size: 18),
        label: const Text('Auditoría: ¿qué falta?',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E8E3E),
            foregroundColor: Colors.white),
        onPressed: _trabajando ? null : _generarPaquete,
        icon: const Icon(Icons.inventory_2, size: 18),
        label: const Text('Paquete completo (5 Excel)'),
      ),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: cessumGold),
        onPressed: _trabajando ? null : _equivalencias,
        icon: const Icon(Icons.sync_alt, size: 17),
        label: const Text('Equivalencias'),
      ),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
        onPressed: _trabajando ? null : _erroresExcel,
        icon: const Icon(Icons.report_gmailerrorred, size: 17),
        label: const Text('Reporte de errores'),
      ),
      if (_trabajando)
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 8),
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: cessumRed)),
        ),
    ]);
  }

  Widget _tarjetaFormatos() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(children: [
        for (final f in _formatos)
          ListTile(
            dense: true,
            leading: Icon(f[2] as IconData, color: cessumRed, size: 22),
            title: Text(f[0] as String,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: _resultados[f[0]] != null
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        _resultados[f[0]]!['ok'] == true
                            ? '${_resultados[f[0]]!['total']} filas · ${_resultados[f[0]]!['conError']} con error'
                            : '${_resultados[f[0]]!['error']}',
                        style: TextStyle(
                            fontSize: 11,
                            color: _resultados[f[0]]!['ok'] == true &&
                                    (_resultados[f[0]]!['conError'] ?? 0) == 0
                                ? const Color(0xFF1E8E3E)
                                : cessumRed)),
                    // (5-oct-2026) El archivo, a un clic: descargar o abrir.
                    if (_resultados[f[0]]!['ok'] == true) _botonesArchivo(_resultados[f[0]]!),
                  ])
                : null,
            trailing: TextButton.icon(
              onPressed: _trabajando
                  ? null
                  : () => _generar(f[0] as String, f[1] as String),
              icon: const Icon(Icons.table_view, size: 16),
              label:
                  const Text('Excel', style: TextStyle(fontSize: 12)),
            ),
          ),
      ]),
    );
  }

  Widget _tarjetaPaquete() {
    final p = _paquete!;
    if (p['ok'] != true) {
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
        child: Text('${p['error'] ?? 'No se pudo generar el paquete.'}', style: const TextStyle(fontSize: 12.5, height: 1.4)),
      );
    }
    final archivos = ((p['archivos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    // (2-oct-2026) El ciclo/carga del resultado que REALMENTE devolvió el
    // backend (p['ciclo'], p['carga']), no el que esté puesto ahora mismo
    // en el dropdown — si se cambió el selector mientras corría la
    // generación, estos dos ya no coincidirían, y lo que importa aquí es
    // qué se generó de verdad.
    final cicloResultado = '${p['ciclo'] ?? ''}';
    final cargaResultado = '${p['carga'] ?? ''}';
    final etiquetaResultado = cicloResultado.isEmpty || cicloResultado == 'todos'
        ? 'Todos (sin filtro) — histórico completo'
        : '$cicloResultado${cargaResultado.isNotEmpty ? ' · carga $cargaResultado' : ''}';
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E8E3E).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF1E8E3E).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📦 PAQUETE GENERADO',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B5E20))),
          const SizedBox(height: 4),
          // (2-oct-2026) Esto es justo lo que faltaba la vez pasada: el
          // ciclo·carga queda a la vista EN el resultado, no solo en el
          // selector de arriba — si no es el que esperabas, se nota de
          // inmediato en vez de confundirse con "no funcionó".
          Text(etiquetaResultado,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          if ('${p['totalRegistros'] ?? ''}'.isNotEmpty)
            Text('${p['totalRegistros']} registro(s) en total · ${p['totalErrores'] ?? 0} con error',
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          const SizedBox(height: 6),
          for (final a in archivos)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    a['ok'] == true
                        ? '✅ ${a['formato']}: ${a['total']} filas, ${a['conError']} con error'
                        : '⬜ ${a['formato']}: ${a['error']}',
                    style: const TextStyle(fontSize: 11.5, height: 1.35)),
                if (a['ok'] == true) _botonesArchivo(a),
              ]),
            ),
          if ('${p['carpetaUrl'] ?? ''}'.isNotEmpty)
            TextButton.icon(
              onPressed: () =>
                  Helpers.abrirUrlExterna('${p['carpetaUrl']}', context),
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Abrir carpeta en Drive',
                  style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _tarjetaAuditoria() {
    final a = _auditoria!;
    if (a['ok'] != true) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text('Auditoría: ${a['error']}',
            style: const TextStyle(color: cessumRed)),
      );
    }
    final res = Map<String, dynamic>.from(a['resumen'] as Map? ?? {});
    final formatos = ((a['formatos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final sinEq = ((a['generacionesSinEquivalencia'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final sinPer = ((a['materiasSinPeriodo'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final limpio = (res['erroresTotales'] ?? 0) == 0 &&
        sinEq.isEmpty &&
        sinPer.isEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: limpio
                ? const Color(0xFF1E8E3E)
                : cessumRed.withValues(alpha: 0.45),
            width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              limpio
                  ? '🎉 AUDITORÍA LIMPIA — listo para exportar sin errores'
                  : '🔍 AUDITORÍA — esto falta para exportar sin errores',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: limpio ? const Color(0xFF1B5E20) : cessumRed)),
          const SizedBox(height: 8),
          Text(
              'Errores: ${res['erroresTotales'] ?? 0} · Generaciones sin equivalencia: ${res['generacionesSinEquivalencia'] ?? 0} · Materias sin periodo: ${res['materiasSinPeriodo'] ?? 0}',
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700)),
          const Divider(height: 18),
          for (final f in formatos) ...[
            Text(
                f['ok'] == true
                    ? '${f['formato']} — ${f['filas']} filas · ${f['conError']} con error'
                    : '${f['formato']} — ${f['error']}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: f['ok'] == true && (f['conError'] ?? 0) == 0
                        ? const Color(0xFF1E8E3E)
                        : cessumInk(context))),
            if (f['erroresPorTipo'] is List)
              for (final g in (f['erroresPorTipo'] as List))
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text(
                      '· ${g['tipo']} × ${g['casos']} — ej. ${(g['ejemplos'] as List).join(', ')}',
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: Color(0xFFB11D29))),
                ),
            const SizedBox(height: 6),
          ],
          if (sinEq.isNotEmpty) ...[
            const Text('GENERACIONES SIN EQUIVALENCIA (captúralas):',
                style:
                    TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            for (final g in sinEq)
              Text('· ${g['programa']} · Gen ${g['generacion']}',
                  style: const TextStyle(fontSize: 11, height: 1.35)),
            const SizedBox(height: 6),
          ],
          if (sinPer.isNotEmpty) ...[
            const Text('MATERIAS SIN PERIODO (toca para capturar):',
                style:
                    TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            for (final m in sinPer)
              InkWell(
                onTap: () => _capturarPeriodo(m),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                      '· ${m['materia'] ?? m['clave']} (${m['programa'] ?? ''}) ✏️',
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: Color(0xFF8A5A0F),
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
          if ('${a['notaEstructural'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('ℹ️ ${a['notaEstructural']}',
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: cessumMuted(context),
                    fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}

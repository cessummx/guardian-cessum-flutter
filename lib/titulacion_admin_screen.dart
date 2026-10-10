import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'foto_web_picker.dart';
import 'tesis_convenio_screen.dart';
import 'titulacion_examen_screen.dart';
import 'titulacion_motor_screen.dart';
import 'respuesta_guardian.dart';
import 'auth/session_store.dart';

const List<String> kEtapasTitulacion = [
  'Solicitud en validación',
  'Integración de expediente',
  'Expediente en revisión',
  'Expediente aprobado',
  'Sínodos asignados',
  'Examen programado',
  'Ventanilla 1: autenticación',
  'Ventanilla 2: certificación',
  'Titulado',
  'Examen suspendido',
  'Rechazada',
];

/// Panel admin de Titulación: lista de expedientes, revisión documento por
/// documento (aprobar/rechazar con observación), cambio de etapa y notas.
class TitulacionAdminScreen extends StatefulWidget {
  const TitulacionAdminScreen({super.key});

  @override
  State<TitulacionAdminScreen> createState() => _TitulacionAdminScreenState();
}

class _TitulacionAdminScreenState extends State<TitulacionAdminScreen> {
  List<Map<String, dynamic>> _expedientes = [];
  String _busqueda = '';
  String _filtro = 'Pendientes';
  // (30-sep) Pre-cargas sin solicitud: alumnos con documentos adelantados
  // que nunca formalizaron. No viven en _expedientes (esa lista viene de la
  // hoja oficial de Titulación), así que se cargan y filtran aparte.
  List<Map<String, dynamic>> _precargas = [];
  bool _cargandoPrecargas = false;
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=titulacion_admin'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _expedientes = (data['expedientes'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los expedientes.';
      });
    }
  }

  Future<void> _cargarPrecargas() async {
    setState(() => _cargandoPrecargas = true);
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final resp = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'titulacion_precargas_sin_solicitud',
            'actor': correo,
          }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _precargas = ((data['alumnos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoPrecargas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargandoPrecargas = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: cessumRed,
        content: Text('No se pudieron cargar las pre-cargas: $e'),
      ));
    }
  }

  // (30-sep) Vista de pre-cargas sin solicitud — solo lectura: da
  // visibilidad para que Vicerrectoría decida a quién contactar; no dispara
  // ningún correo por sí sola.
  Widget _vistaPrecargas() {
    if (_cargandoPrecargas) {
      return const Center(child: CircularProgressIndicator(color: cessumGold));
    }
    if (_precargas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nadie tiene documentos adelantados sin haber solicitado su titulación.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumMuted(context)),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Estos alumnos ya subieron documentos por adelantado pero nunca '
            'presentaron su solicitud formal. No aparecen en "Motor" ni en '
            'el resto de este panel porque su expediente todavía no existe '
            'como tal.',
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
        for (final a in _precargas) _tarjetaPrecarga(a),
      ],
    );
  }

  Widget _tarjetaPrecarga(Map<String, dynamic> a) {
    final obl = (a['obligatoriosSubidos'] ?? 0) as int;
    final totalObl = (a['totalObligatorios'] ?? 0) as int;
    final completo = totalObl > 0 && obl >= totalObl;
    final color = completo ? const Color(0xFF1E8E3E) : cessumGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${a['nombre']}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(
                  completo
                      ? 'Listo para solicitar'
                      : '$obl de $totalObl obligatorios',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ]),
          Text(
              '${a['matricula']} · ${a['programa']} ${a['generacion']}',
              style: TextStyle(
                  fontSize: 11.5, color: cessumMuted(context))),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.description_outlined,
                size: 14, color: cessumMuted(context)),
            const SizedBox(width: 4),
            Text('${a['documentosSubidos']} documento(s) adelantados',
                style: TextStyle(
                    fontSize: 12, color: cessumMuted(context))),
            const Spacer(),
            if (('${a['actualizado']}').isNotEmpty)
              Text('Últ. actualización: ${a['actualizado']}',
                  style: TextStyle(
                      fontSize: 11, color: cessumMuted(context))),
          ]),
          if (('${a['correo']}').isNotEmpty) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: cessumGold),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${a['correo']}'));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Correo copiado: ${a['correo']}')));
                },
                icon: const Icon(Icons.copy, size: 15),
                label: Text('${a['correo']}',
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<bool> _actualizar(Map<String, dynamic> payload) async {
    setState(() => _guardando = true);
    try {
      payload['accion'] = 'titulacion_actualizar';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 90));
      // (ago-9) Antes esto era `jsonDecode` a secas, y cuando el servidor
      // contestaba una página de error el usuario veía
      // "FormatException: Unexpected token '<'". Ahora el mensaje es humano
      // y, cuando no se puede saber si el cambio se guardó, se lo dice en
      // vez de dar por hecho que falló: repetir la operación a ciegas es
      // peor que revisar.
      final r = leerRespuesta(resp, accion: 'titulacion_actualizar');
      if (!r.ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor:
                r.incierto ? cessumGold : Colors.redAccent,
            duration: Duration(seconds: r.incierto ? 8 : 4),
            content: Text(r.mensaje),
          ));
        }
        return false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content:
              Text('Actualizado. El alumno fue notificado por correo.'),
        ));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo actualizar: $e'),
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  String _normBusq(String t) {
    var s = t.toLowerCase();
    const con = 'áéíóúüñ';
    const sin = 'aeiouun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
  }

  List<Map<String, dynamic>> get _visibles {
    List<Map<String, dynamic>> base;
    if (_filtro == 'Todos') {
      base = _expedientes;
    } else if (_filtro == 'Pendientes') {
      base = _expedientes
          .where((e) =>
              e['etapa'] == 'Solicitud en validación' ||
              e['etapa'] == 'Expediente en revisión')
          .toList();
    } else {
      base = _expedientes.where((e) => e['etapa'] == _filtro).toList();
    }
    if (_busqueda.trim().isEmpty) return base;
    final q = _normBusq(_busqueda.trim());
    return base.where((e) {
      final t = _normBusq(
          '${e['nombre']} ${e['matricula']} ${e['folio']} '
          '${e['programa']} ${e['opcion']} ${e['etapa']}');
      return t.contains(q);
    }).toList();
  }

  /// (22-sep) Lo que le corresponde pagar al alumno (lo calcula el Guardián)
  /// y, si ya reportó un pago, si la cantidad coincide.
  Widget _costoCorresponde(Map<String, dynamic> e) {
    final c = e['costoTitulacion'];
    if (c is! Map) return const SizedBox.shrink();
    final texto = (c['texto'] ?? '').toString();
    if (texto.isEmpty) return const SizedBox.shrink();
    final monto = c['monto'] as num?;
    final repTxt = (e['cantidad'] ?? '').toString();
    final rep = num.tryParse(repTxt.replaceAll(RegExp(r'[^0-9.]'), ''));
    final difiere = monto != null && rep != null && rep.round() != monto.round();
    final opcion = (c['opcionTexto'] ?? '').toString();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'Le corresponde: $texto${opcion.isNotEmpty ? ' · $opcion' : ''}',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, height: 1.45)),
          if (difiere)
            Text(
                'El pago reportado no coincide con lo que le corresponde.',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade800)),
        ]),
      ),
    );
  }

  Color _colorEtapa(String e) {
    if (e == 'Expediente aprobado') return Colors.green.shade700;
    if (e == 'Titulado') return Colors.green.shade700;
    if (e == 'Rechazada') return cessumRed;
    if (e == 'Ventanilla 1: autenticación' ||
        e == 'Ventanilla 2: certificación') return Colors.indigo.shade600;
    return cessumGold;
  }

  Color _colorDoc(String e) {
    switch (e) {
      case 'Aprobado':
        return Colors.green.shade700;
      case 'Rechazado':
        return cessumRed;
      case 'En revisión':
        return cessumGold;
      default:
        return Colors.black38;
    }
  }

  Future<void> _revisarDoc(
      Map<String, dynamic> exp, Map<String, dynamic> d, bool aprobar) async {
    final obsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            '${aprobar ? 'Aprobar' : 'Rechazar'} ${d['etiqueta']}'),
        content: TextField(
          controller: obsCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: aprobar
                ? 'Observación (opcional)'
                : 'Motivo del rechazo (se envía al alumno) *',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: aprobar ? Colors.green : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () {
              if (!aprobar && obsCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hecho = await _actualizar({
      'folio': exp['folio'],
      'docTipo': d['tipo'],
      'docEstatus': aprobar ? 'Aprobado' : 'Rechazado',
      'observacion': obsCtrl.text.trim(),
    });
    if (hecho) _cargar();
  }

  Future<void> _cambiarEtapa(Map<String, dynamic> exp) async {
    String etapa = (exp['etapa'] ?? kEtapasTitulacion.first) as String;
    // (2-sep) Al rechazar hay que decir POR QUÉ: el motivo se guarda en el
    // expediente y viaja en el correo al alumno, junto con el aviso de que
    // puede volver a solicitar. Antes el alumno recibía un correo que solo
    // decía «etapa: Rechazada» y quedaba sin saber qué corregir.
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          final rechaza = etapa.toLowerCase() == 'rechazada';
          return AlertDialog(
            title: Text('Etapa de ${exp['nombre']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: kEtapasTitulacion.contains(etapa) ? etapa : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(), isDense: true),
                  items: kEtapasTitulacion
                      .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setS(() => etapa = v ?? etapa),
                ),
                if (rechaza) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: motivo,
                    maxLines: 4,
                    minLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: 'Motivo del rechazo (obligatorio)',
                      hintText:
                          'Ej.: la opción elegida no corresponde a tu programa. '
                          'Vuelve a solicitar eligiendo Tesis.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Este texto se le envía al alumno y queda en su expediente. '
                    'Al rechazar, el alumno podrá volver a solicitar desde la app.',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2, false),
                  child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white),
                onPressed: (rechaza && motivo.text.trim().length < 5)
                    ? null
                    : () => Navigator.pop(ctx2, true),
                child: const Text('Guardar y notificar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) {
      motivo.dispose();
      return;
    }
    final hecho = await _actualizar({
      'folio': exp['folio'],
      'etapa': etapa,
      if (motivo.text.trim().isNotEmpty) 'motivo': motivo.text.trim(),
    });
    motivo.dispose();
    if (hecho) _cargar();
  }

  /// (24-sep) Revisión del expediente con IA contra los requisitos de la SEC:
  /// nombre del acta vs padrón, CURP, fecha de nacimiento, título y cédula.
  Future<void> _revisarIa(Map<String, dynamic> e) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'expediente_ia_revisar',
            'matricula': '${e['matricula'] ?? ''}',
          }))
          .timeout(const Duration(seconds: 180));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      d = {'ok': false, 'error': 'No se pudo conectar.'};
    }
    if (!mounted) return;
    Navigator.pop(context);
    final hall = ((d['hallazgos'] as List?) ?? []).map((x) => '$x').toList();
    final docs = ((d['documentos'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(d['ok'] != true ? Icons.error_outline : (hall.isEmpty ? Icons.verified : Icons.report_problem_outlined),
              color: d['ok'] != true ? cessumRed : (hall.isEmpty ? const Color(0xFF1E7F52) : cessumGold)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                d['ok'] != true ? 'No se pudo revisar' : (hall.isEmpty ? 'Listo para la SEC' : '${hall.length} punto(s) por revisar'),
                style: const TextStyle(fontSize: 17)),
          ),
        ]),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: d['ok'] != true
                ? Text('${d['error'] ?? ''}')
                : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e['nombre']} · ${e['matricula']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    if ('${d['nombreParaSEC'] ?? ''}'.isNotEmpty) ...[
                      const Text('Nombre para autenticación', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      SelectableText('${d['nombreParaSEC']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      if (d['excepcionAcentos'] == true)
                        const Text('Tiene excepción de acentos registrada.', style: TextStyle(fontSize: 11.5, color: cessumGold)),
                      const SizedBox(height: 8),
                    ],
                    for (final h in hall)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.chevron_right, size: 18, color: cessumRed),
                          Expanded(child: Text(h, style: const TextStyle(fontSize: 13, height: 1.35))),
                        ]),
                      ),
                    const SizedBox(height: 6),
                    const Text('Documentos leídos', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    for (final x in docs)
                      Text(
                        '• ${x['etiqueta']}: ${x['legible'] == true ? '${x['nombre']}${'${x['curp'] ?? ''}'.isNotEmpty ? ' · ${x['curp']}' : ''}' : 'no legible${'${x['nota'] ?? ''}'.isNotEmpty ? ' (${x['nota']})' : ''}'}',
                        style: const TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    const SizedBox(height: 8),
                    Text('${d['aviso'] ?? ''}', style: const TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: Colors.grey)),
                  ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
  }

  Future<void> _editarNotas(Map<String, dynamic> exp) async {
    final ctrl =
        TextEditingController(text: (exp['notas'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota para el alumno'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Visible en el expediente del alumno',
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
    if (ok != true) return;
    final hecho = await _actualizar(
        {'folio': exp['folio'], 'notas': ctrl.text.trim()});
    if (hecho) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final filtros = [
      'Pendientes',
      ...kEtapasTitulacion,
      'Todos',
    ];
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Titulación · Expedientes',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          // (25-sep) Motor de titulación: quién tiene la pelota, acciones en bloque e IA.
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const TitulacionMotorScreen()));
              if (mounted) _cargar();
            },
            icon: const Icon(Icons.bolt),
            label: const Text('Motor'),
          ),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: Column(
        children: [
          // (ago-3) Todas las fases visibles: chips envueltos en varias
          // líneas (el carrusel horizontal escondía la mitad de las etapas).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ...filtros.map((f) {
                  final activo = _filtro == f;
                  return ChoiceChip(
                    label: Text(f),
                    selected: activo,
                    visualDensity: VisualDensity.compact,
                    selectedColor: cessumRed.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      color: activo ? cessumRed : Colors.black87,
                      fontWeight:
                          activo ? FontWeight.w700 : FontWeight.w400,
                    ),
                    onSelected: (_) => setState(() => _filtro = f),
                  );
                }),
                // (30-sep) Alumnos con documentos adelantados que nunca
                // solicitaron formalmente — antes invisibles en este panel
                // y en el Motor, porque ambos solo leen la hoja oficial.
                ChoiceChip(
                  label: Text(_precargas.isNotEmpty || !_cargandoPrecargas
                      ? 'Pre-cargas sin solicitud${_precargas.isNotEmpty ? ' (${_precargas.length})' : ''}'
                      : 'Pre-cargas sin solicitud'),
                  avatar: const Icon(Icons.hourglass_empty, size: 16),
                  selected: _filtro == '_Precargas',
                  visualDensity: VisualDensity.compact,
                  selectedColor: cessumGold.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    color: _filtro == '_Precargas'
                        ? cessumGold
                        : Colors.black87,
                    fontWeight: _filtro == '_Precargas'
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                  onSelected: (_) {
                    setState(() => _filtro = '_Precargas');
                    if (_precargas.isEmpty) _cargarPrecargas();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 19),
                hintText:
                    'Buscar por nombre, matrícula, folio, programa u opción…',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () =>
                            setState(() => _busqueda = ''),
                      ),
              ),
              onChanged: (v) => setState(() => _busqueda = v),
            ),
          ),
          if (_guardando) const LinearProgressIndicator(color: cessumRed),
          Expanded(
            child: _filtro == '_Precargas'
                ? _vistaPrecargas()
                : _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            const SizedBox(height: 8),
                            TextButton(
                                onPressed: _cargar,
                                child: const Text('Reintentar')),
                          ],
                        ),
                      )
                    : _visibles.isEmpty
                        ? Center(
                            child: Text(
                                _busqueda.trim().isEmpty
                                    ? 'Sin expedientes en este filtro.'
                                    : 'Nada coincide con "$_busqueda" en este filtro.',
                                style: const TextStyle(
                                    color: Colors.black54)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _visibles.length,
                            itemBuilder: (ctx, i) =>
                                _tarjetaExpediente(_visibles[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaExpediente(Map<String, dynamic> e) {
    final etapa = (e['etapa'] ?? '') as String;
    final docs = (e['documentos'] as List)
        .map((d) => Map<String, dynamic>.from(d as Map))
        .toList();
    final subidos = docs
        .where((d) => ((d['url'] ?? '') as String).isNotEmpty)
        .length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Text(
          '${e['nombre']} (${e['matricula']})',
          style:
              const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '${e['folio']} · ${e['programa']} · ${e['generacion']}\nOpción: ${e['opcion']} · Docs: $subidos/${docs.length}',
            style: const TextStyle(fontSize: 11.5, height: 1.4),
          ),
        ),
        trailing: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _colorEtapa(etapa).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(etapa,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _colorEtapa(etapa))),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tel: ${e['telefono']} · ${e['correo']}'
              '${((e['cantidad'] ?? '') as String).isNotEmpty ? '\nPago reportado: \$${e['cantidad']} MXN${((e['otros'] ?? '') as String).isNotEmpty ? ' · Otros: ${e['otros']}' : ''}' : ''}',
              style: const TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
          // (22-sep) Cuánto le corresponde pagar según su programa, generación
          // y opción, y si lo que reportó coincide.
          _costoCorresponde(e),
          if (((e['solicitudPdf'] ?? '') as String).isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Helpers.abrirUrlExterna(
                    (e['solicitudPdf'] ?? '') as String, context),
                icon: const Icon(Icons.picture_as_pdf,
                    size: 16, color: cessumGold),
                label: const Text('Solicitud firmable (PDF)',
                    style: TextStyle(color: cessumGold, fontSize: 12)),
              ),
            ),
          const Divider(),
          ...docs.map((d) {
            final url = (d['url'] ?? '') as String;
            final estatus = (d['estatus'] ?? '') as String;
            final obs = (d['observacion'] ?? '') as String;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (d['etiqueta'] ?? '') as String,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600),
                        ),
                        Text(
                          url.isEmpty
                              ? 'Sin subir'
                              : estatus +
                                  (obs.isNotEmpty ? ' · $obs' : ''),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color:
                                  _colorDoc(url.isEmpty ? '' : estatus)),
                        ),
                      ],
                    ),
                  ),
                  if (url.isNotEmpty) ...[
                    IconButton(
                      tooltip: 'Ver documento',
                      icon: const Icon(Icons.visibility,
                          size: 19, color: Colors.black54),
                      onPressed: () =>
                          Helpers.abrirUrlExterna(url, context),
                    ),
                    if (estatus != 'Aprobado')
                      IconButton(
                        tooltip: 'Aprobar',
                        icon: const Icon(Icons.check_circle,
                            size: 20, color: Colors.green),
                        onPressed: _guardando
                            ? null
                            : () => _revisarDoc(e, d, true),
                      ),
                    if (estatus != 'Rechazado')
                      IconButton(
                        tooltip: 'Rechazar',
                        icon: const Icon(Icons.cancel,
                            size: 20, color: cessumRed),
                        onPressed: _guardando
                            ? null
                            : () => _revisarDoc(e, d, false),
                      ),
                  ],
                ],
              ),
            );
          }),
          _fotosRow(e),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _guardando ? null : () => _cambiarEtapa(e),
                  icon: const Icon(Icons.swap_vert,
                      size: 17, color: cessumRed),
                  label: const Text('Cambiar etapa',
                      style:
                          TextStyle(color: cessumRed, fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _guardando ? null : () => _editarNotas(e),
                  icon: const Icon(Icons.edit_note,
                      size: 18, color: cessumGold),
                  label: const Text('Nota al alumno',
                      style:
                          TextStyle(color: cessumGold, fontSize: 12.5)),
                ),
              ),
            ],
          ),
          // (24-sep) Revisión con IA contra los requisitos de la SEC.
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _guardando ? null : () => _revisarIa(e),
              style: OutlinedButton.styleFrom(foregroundColor: cessumGold),
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('Revisar expediente con IA (requisitos SEC)', style: TextStyle(fontSize: 12.5)),
            ),
          ),
          if ((e['opcion'] ?? '').toString().toLowerCase().contains('tesis')) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumGold,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TesisConvenioScreen(
                      matricula: '${e['matricula'] ?? ''}',
                      nombre: '${e['nombre'] ?? ''}',
                      programa: '${e['programa'] ?? ''}',
                      generacion: '${e['generacion'] ?? ''}',
                      correo: '',
                      rol: 'admin',
                    ),
                  ),
                ),
                icon: const Icon(Icons.handshake, size: 18),
                label: const Text('Asesor · convenio · seguimiento (tesis)'),
              ),
            ),
          ],
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _guardando
                  ? null
                  : () async {
                      final ok = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TitulacionExamenScreen(expediente: e),
                        ),
                      );
                      if (ok == true) _cargar();
                    },
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: const Text('Sínodos y examen de grado'),
            ),
          ),
          _entregaSeccion(e),
        ],
      ),
    );
  }

  Widget _fotosRow(Map<String, dynamic> e) {
    final opcion = (e['fotosOpcion'] ?? '') as String;
    final url = (e['fotosUrl'] ?? '') as String;
    // (ago-9) SON DOS ARCHIVOS, NO UNO. Quien elige impresión en CESSUM debe
    // entregar sus fotografías (col 62 → fotosUrl2) Y el comprobante de los
    // $500 (col 56 → fotosUrl). El backend los expone por separado desde
    // siempre, pero esta fila solo mostraba el primero: Control Escolar no
    // podía ver cuál de los dos llegó, ni si el alumno subió las fotos en la
    // ranura del pago por no tener botón para ellas.
    final urlFotos = (e['fotosUrl2'] ?? '') as String;
    final estatus = (e['fotosEstatus'] ?? '') as String;
    final obs = (e['fotosObs'] ?? '') as String;
    final hay = url.isNotEmpty;

    /// (8-sep) LA FILA DECÍA «Sin registrar» SOBRE UN REQUISITO YA APROBADO.
    /// El texto se decidía por `hay`, es decir por la existencia de archivo. En
    /// las entregas en ventanilla no hay archivo por definición: el requisito
    /// se aprueba con «Recibidas en físico» y queda el sello de quién y cuándo
    /// en la observación. Aun así la fila seguía anunciando «Sin registrar»,
    /// y Control Escolar persiguía fotografías que ya estaban entregadas —le
    /// pasó al expediente de Nohemí Barreras, aprobado desde el 3 de
    /// septiembre—. Ahora manda el ESTATUS: si hay dictamen, se muestra; y si
    /// no hay archivo pero sí aprobación, se dice que llegaron en físico.
    final registrado = url.isNotEmpty || urlFotos.isNotEmpty || estatus.isNotEmpty;
    final via = url.isNotEmpty || urlFotos.isNotEmpty
        ? (opcion == 'enviadas'
            ? 'Enviadas (guía adjunta)'
            : 'Impresión en CESSUM (\$500)')
        : 'Recibidas en físico';
    final desc = !registrado
        ? 'Sin registrar'
        : via +
            (estatus.isNotEmpty ? ' · ' + estatus : '') +
            (obs.isNotEmpty ? ' · $obs' : '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Fotografías para el título',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(desc,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _colorDoc(hay ? estatus : ''))),
                // Qué le falta al alumno, dicho en concreto: sin esto hay que
                // deducirlo abriendo los archivos uno por uno.
                if (opcion == 'impresion' &&
                    (urlFotos.isEmpty || url.isEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                        urlFotos.isEmpty && url.isEmpty
                            ? 'Faltan las fotografías y el comprobante'
                            : (urlFotos.isEmpty
                                ? 'Falta el archivo de las fotografías'
                                : 'Falta el comprobante de \$500'),
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFC62828))),
                  ),
              ],
            ),
          ),
          // (ago-17) RECIBIDAS EN FÍSICO. Si el alumno entregó las fotografías
          // en ventanilla, no hay archivo que ver y la fila se quedaba en
          // "Sin registrar" para siempre, sin un solo botón: el expediente no
          // podía cerrarse aunque el trámite estuviera cumplido. Este camino
          // aprueba dejando constancia escrita de quién las recibió y cuándo,
          // que es lo que hace auditable una aprobación sin archivo.
          if (!hay && urlFotos.isEmpty && estatus != 'Aprobado')
            TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1E8E3E),
                  visualDensity: VisualDensity.compact),
              onPressed: _guardando ? null : () => _fotosEnFisico(e),
              icon: const Icon(Icons.inventory_2_outlined, size: 17),
              label: const Text('Recibidas en físico',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          if (hay || urlFotos.isNotEmpty) ...[
            if (urlFotos.isNotEmpty)
              IconButton(
                tooltip: 'Ver las fotografías',
                icon: const Icon(Icons.photo_library_outlined,
                    size: 19, color: cessumGold),
                onPressed: () => Helpers.abrirUrlExterna(urlFotos, context),
              ),
            if (url.isNotEmpty)
              IconButton(
                tooltip: opcion == 'impresion'
                    ? 'Ver el comprobante de \$500'
                    : 'Ver la guía de envío',
                icon: const Icon(Icons.visibility,
                    size: 19, color: Colors.black54),
                onPressed: () => Helpers.abrirUrlExterna(url, context),
              ),
            if (estatus != 'Aprobado')
              IconButton(
                tooltip: 'Aprobar',
                icon: const Icon(Icons.check_circle,
                    size: 20, color: Colors.green),
                onPressed:
                    _guardando ? null : () => _revisarFotos(e, true),
              ),
            if (estatus != 'Rechazado')
              IconButton(
                tooltip: 'Rechazar',
                icon: const Icon(Icons.cancel, size: 20, color: cessumRed),
                onPressed:
                    _guardando ? null : () => _revisarFotos(e, false),
              ),
          ],
        ],
      ),
    );
  }

  /// (ago-17) Aprueba las fotografías cuando llegaron impresas a ventanilla.
  /// Pide quién las recibió: sin eso, meses después nadie puede responder por
  /// qué se aprobó un documento del que no hay archivo.
  Future<void> _fotosEnFisico(Map<String, dynamic> exp) async {
    final quienCtrl = TextEditingController();
    final notaCtrl = TextEditingController();
    bool falta = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Fotografías recibidas en físico',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Usa esto solo si el alumno entregó las fotografías '
                    'impresas en ventanilla. Queda registrado en el expediente '
                    'quién las recibió y en qué fecha.',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quienCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Quién las recibió',
                  hintText: 'Nombre de quien las recibió en ventanilla',
                  border: const OutlineInputBorder(),
                  errorText: falta ? 'Anota quién las recibió.' : null,
                ),
                onChanged: (_) {
                  if (falta) setSt(() => falta = false);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notaCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  hintText: 'Cuántas, tamaño, o cualquier detalle',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Al guardar, al alumno le llega un correo diciéndole que '
                    'sus fotografías quedaron aprobadas.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFB08D57))),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white),
              onPressed: () {
                if (quienCtrl.text.trim().isEmpty) {
                  setSt(() => falta = true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Aprobar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final hoy = DateTime.now();
    final fecha = '${hoy.day.toString().padLeft(2, '0')}/'
        '${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';
    final nota = notaCtrl.text.trim();
    final hecho = await _actualizar({
      'folio': exp['folio'],
      'fotosEstatus': 'Aprobado',
      'fotosObs': 'Recibidas en físico el $fecha · las recibió '
          '${quienCtrl.text.trim()}${nota.isNotEmpty ? ' · $nota' : ''}',
    });
    if (hecho) _cargar();
  }

  Future<void> _revisarFotos(Map<String, dynamic> exp, bool aprobar) async {
    final obsCtrl = TextEditingController();
    // (ago-9) EL BOTÓN SE VEÍA TRABADO. Al rechazar sin escribir motivo, el
    // código hacía `return` y ya: no cerraba, no avisaba, no marcaba el campo.
    // Desde afuera parecía que la app se colgó. El motivo SÍ debe ser
    // obligatorio —ese texto es el que le llega al alumno— pero hay que
    // decirlo, no quedarse callado.
    bool falta = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('${aprobar ? 'Aprobar' : 'Rechazar'} fotografías'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!aprobar)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                      'Explícale al alumno qué debe corregir. Este texto le '
                      'llega por correo, así que sé específico.',
                      style: TextStyle(fontSize: 12, height: 1.35)),
                ),
              TextField(
                controller: obsCtrl,
                maxLines: 3,
                autofocus: !aprobar,
                onChanged: (_) {
                  if (falta) setSt(() => falta = false);
                },
                decoration: InputDecoration(
                  labelText: aprobar
                      ? 'Observación (opcional)'
                      : 'Motivo del rechazo (se envía al alumno) *',
                  errorText:
                      falta ? 'Escribe el motivo: sin él no se puede rechazar.' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: aprobar ? Colors.green : cessumRed,
                  foregroundColor: Colors.white),
              onPressed: () {
                if (!aprobar && obsCtrl.text.trim().isEmpty) {
                  setSt(() => falta = true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final hecho = await _actualizar({
      'folio': exp['folio'],
      'fotosEstatus': aprobar ? 'Aprobado' : 'Rechazado',
      'fotosObs': obsCtrl.text.trim(),
    });
    if (hecho) _cargar();
  }

  // (ago-3) EXPEDIENTE DE PAQUETERÍA: adjuntar la guía (PDF/imagen).
  // (ago-6) Fija el importe real de este envío y avisa al alumno con los
  // datos de pago (1 correo). El comprobante lo sube él desde su pantalla.
  Future<void> _fijarCostoEnvio(Map<String, dynamic> e) async {
    final ctrl = TextEditingController(
        text: (e['envioCosto'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importe del envío',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Importe total en MXN (solo número)',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'Al guardar se le enviará al alumno UN correo con el importe, '
              'los datos bancarios y los pasos para subir su comprobante.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar y avisar')),
        ],
      ),
    );
    if (ok != true) return;
    final monto = ctrl.text.trim();
    if (monto.isEmpty) return;
    setState(() => _guardando = true);
    try {
      final r = await http.post(Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode({
            'accion': 'tit_envio_costo_fijar',
            'folio': '${e['folio']}',
            'monto': monto,
            'actor': 'vicerrectoria',
          })).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(d['ok'] == true
              ? '✅ Importe fijado (\$$monto)${d['avisado'] == true ? ' · alumno avisado por correo' : ''}'
              : 'Error: ${d['error']}')));
      if (d['ok'] == true) _cargar();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $err')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _adjuntarGuia(Map<String, dynamic> e) async {
    final doc = await seleccionarDocumento(tipo: 'ambos');
    if (doc == null || !mounted) return;
    setState(() => _guardando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'tit_envio_guia_adjuntar',
                'folio': e['folio'],
                'base64': base64Encode(doc.bytes),
                'mime': doc.mime,
                'actor': 'vicerrectoria@cessum.mx',
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() => e['envioGuiaArchivoUrl'] = data['url']);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Guía adjuntada al expediente.')));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed,
          content: Text('No se pudo adjuntar: $err')));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // Confirmar que la paquetería ya recolectó el paquete (avisa al alumno).
  Future<void> _confirmarRecoleccion(Map<String, dynamic> e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar recolección'),
        content: Text(
            '¿Confirmas que la paquetería ya recolectó el paquete con el '
            'título de ${e['nombre']}?\n\nSe le avisará por correo que su '
            'título va en camino.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, ya se recolectó')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'tit_envio_recogido',
        'folio': (e['folio'] ?? '').toString(),
        'actor': 'vicerrectoria@cessum.mx',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() => e['envioRecogidoEn'] = 'hoy');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(data['avisadoAlumno'] == true
              ? 'Recolección registrada. El alumno fue avisado por correo.'
              : 'Recolección registrada.')));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed,
          content: Text('No se pudo registrar: $err')));
    }
  }

  Widget _entregaSeccion(Map<String, dynamic> e) {
    final f = (e['entregaFecha'] ?? '') as String;
    final h = (e['entregaHora'] ?? '') as String;
    final l = (e['entregaLugar'] ?? '') as String;
    final hay = f.isNotEmpty || h.isNotEmpty || l.isNotEmpty;
    // (ago-3) Dirección de envío capturada por el alumno al solicitar
    // paquetería — antes solo vivía en el correo y en la hoja.
    final dir = (e['envioDireccion'] ?? '').toString();
    final dirCompleta = dir.isEmpty
        ? ''
        : '$dir\n'
            '${(e['envioCiudad'] ?? '').toString()}'
            '${(e['envioEstado'] ?? '').toString().isNotEmpty ? ', ${e['envioEstado']}' : ''}'
            '${(e['envioCp'] ?? '').toString().isNotEmpty ? ' · C.P. ${e['envioCp']}' : ''}\n'
            'Tel: ${(e['envioTelefono'] ?? '—').toString()}'
            '${(e['envioReferencias'] ?? '').toString().isNotEmpty ? '\nReferencias: ${e['envioReferencias']}' : ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        if (dirCompleta.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: cessumGold.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_shipping,
                        size: 16, color: cessumGold),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('DIRECCIÓN DE ENVÍO (paquetería)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: cessumGold)),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: dirCompleta));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Dirección copiada para la guía.')));
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child:
                            Icon(Icons.copy, size: 16, color: cessumGold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(dirCompleta,
                    style:
                        const TextStyle(fontSize: 12, height: 1.45)),
                const Divider(height: 16),
                // (ago-3) Expediente de paquetería: guía, comprobante, recolección
                Row(children: [
                  Expanded(
                    child: (e['envioGuiaArchivoUrl'] ?? '')
                            .toString()
                            .isNotEmpty
                        ? InkWell(
                            onTap: () => Helpers.abrirUrlExterna(
                                '${e['envioGuiaArchivoUrl']}', context),
                            child: const Text('📎 Ver guía adjunta',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cessumGold,
                                    decoration:
                                        TextDecoration.underline)),
                          )
                        : const Text('Sin guía adjunta',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.black45)),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: cessumGold,
                        visualDensity: VisualDensity.compact),
                    onPressed:
                        _guardando ? null : () => _adjuntarGuia(e),
                    icon: const Icon(Icons.attach_file, size: 15),
                    label: Text(
                        (e['envioGuiaArchivoUrl'] ?? '')
                                .toString()
                                .isNotEmpty
                            ? 'Reemplazar'
                            : 'Adjuntar guía',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ]),
                // (ago-6) Importe manual de ESTE envío: la Vicerrectoría lo
                // fija según destino/peso; al guardarlo se le avisa al
                // alumno (1 correo con datos de pago y pasos).
                Row(children: [
                  const Text('Importe del envío:  ',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(
                      (e['envioCosto'] ?? '').toString().isNotEmpty
                          ? '\$${e['envioCosto']} MXN'
                          : 'sin fijar',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: (e['envioCosto'] ?? '')
                                  .toString()
                                  .isNotEmpty
                              ? const Color(0xFF1E8E3E)
                              : cessumRed)),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: cessumGold,
                        visualDensity: VisualDensity.compact),
                    onPressed:
                        _guardando ? null : () => _fijarCostoEnvio(e),
                    icon: const Icon(Icons.attach_money, size: 15),
                    label: Text(
                        (e['envioCosto'] ?? '').toString().isNotEmpty
                            ? 'Cambiar'
                            : 'Fijar importe',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ]),
                (e['envioPagoUrl'] ?? '').toString().isNotEmpty
                    ? InkWell(
                        onTap: () => Helpers.abrirUrlExterna(
                            '${e['envioPagoUrl']}', context),
                        child: Text(
                            '💳 Comprobante de paquetería del alumno'
                            '${(e['envioPagoFecha'] ?? '').toString().isNotEmpty ? ' (${e['envioPagoFecha']})' : ''} — abrir',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1B5E20),
                                decoration: TextDecoration.underline)),
                      )
                    : const Text(
                        '💳 El alumno aún no sube su comprobante de paquetería.',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.black45)),
                const SizedBox(height: 6),
                (e['envioRecogidoEn'] ?? '').toString().isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: const Color(0xFFEAF5EC),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(
                            '📦 Recolectado por la paquetería el ${e['envioRecogidoEn']}',
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1B5E20))),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E8E3E),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _guardando
                              ? null
                              : () => _confirmarRecoleccion(e),
                          icon: const Icon(Icons.local_shipping,
                              size: 15),
                          label: const Text('Confirmar recolección',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
              ],
            ),
          ),
        if (hay)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF5EC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Entrega oficial → '
              '${f.isNotEmpty ? f : '(sin fecha)'}'
              '${h.isNotEmpty ? ' · $h' : ''}'
              '${l.isNotEmpty ? ' · $l' : ''}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1B5E20)),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _guardando ? null : () => _dialogoEntrega(e),
          icon: const Icon(Icons.event_available,
              size: 18, color: cessumGold),
          label: Text(
              hay
                  ? 'Editar entrega del título'
                  : 'Entrega oficial del título',
              style: const TextStyle(color: cessumGold, fontSize: 12.5)),
        ),
      ],
    );
  }

  Future<void> _dialogoEntrega(Map<String, dynamic> exp) async {
    final fechaCtrl =
        TextEditingController(text: (exp['entregaFecha'] ?? '') as String);
    final horaCtrl =
        TextEditingController(text: (exp['entregaHora'] ?? '') as String);
    final lugarCtrl =
        TextEditingController(text: (exp['entregaLugar'] ?? '') as String);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Entrega oficial · ${exp['nombre']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: fechaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Fecha (ej. 15 de julio de 2026)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: horaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Hora (ej. 12:00 h)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: lugarCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Lugar',
                  border: OutlineInputBorder(),
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
            child: const Text('Guardar y avisar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hecho = await _actualizar({
      'folio': exp['folio'],
      'entregaFecha': fechaCtrl.text.trim(),
      'entregaHora': horaCtrl.text.trim(),
      'entregaLugar': lugarCtrl.text.trim(),
    });
    if (hecho) _cargar();
  }
}

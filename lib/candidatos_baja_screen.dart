import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Vista de administración: CANDIDATOS A BAJA. Reúne automáticamente a los
/// alumnos con alguna materia reprobada (validada, < 7; el 6 es reprobatorio,
/// se aprueba de 7 a 10) o con adeudo del
/// periodo en curso, con toda la información para decidir caso por caso.
/// Permite aplicar la baja (Voluntaria / Automática / Disciplinaria; temporal o
/// definitiva) conforme a los Arts. 36-42 del Reglamento Escolar; al aplicar se
/// genera el acta oficial y se notifica al alumno (Art. 41).
class CandidatosBajaScreen extends StatefulWidget {
  const CandidatosBajaScreen({super.key});

  @override
  State<CandidatosBajaScreen> createState() => _CandidatosBajaScreenState();
}

class _CandidatosBajaScreenState extends State<CandidatosBajaScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  List<Map<String, dynamic>> _items = [];
  bool _cargando = true;
  String? _error;
  String _filtro = 'todos'; // todos | reprobadas | adeudo

  // Bajas temporales reactivables.
  List<Map<String, dynamic>> _temporales = [];
  bool _cargandoTemp = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _cargar();
    _cargarTemporales();
    _cargarRevisados();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _cargarTemporales() async {
    setState(() => _cargandoTemp = true);
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'bajas_temporales'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _temporales = ((data['bajas'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
      // silencioso
    } finally {
      if (mounted) setState(() => _cargandoTemp = false);
    }
  }

  Future<void> _reactivar(Map<String, dynamic> it) async {
    final notaCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivar inscripción',
            style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${it['nombre']} (${it['matricula']})',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${it['programa']} · ${it['generacion']}',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 10),
            const Text(
              'El alumno volverá a estatus Activo, conservando su historial y '
              'su matrícula. Se le notificará por correo.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notaCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E3E),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final quien = await SessionStore.realEmail();
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'baja_reactivar',
              'actor': quien ?? '',
              'matricula': it['matricula'],
              'nota': notaCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Alumno reactivado. Se le notificó.')));
        _cargarTemporales();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo: ${data['error'] ?? 'error'}')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión.')));
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final params = {'accion': 'candidatos_baja'};
      if (_filtro != 'todos') params['criterio'] = _filtro;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() => _error = (data['error'] ?? 'Error').toString());
      } else {
        setState(() {
          _items = ((data['candidatos'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Las causales del reglamento, servidas por el backend.
  /// Viven allá y no aquí a propósito: el reglamento se reforma, y una causal
  /// mal citada en un acta oficial es un problema serio. Así se corrigen sin
  /// volver a compilar.
  Map<String, dynamic> _causales = {};

  // Los revisados y dejados pasar.
  List<Map<String, dynamic>> _revisados = [];
  List<Map<String, dynamic>> _decisiones = [];
  int _vencidos = 0;

  Future<void> _cargarRevisados() async {
    try {
      final r = await http.get(Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'revision_baja_listar'}));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _revisados = ((d['revisados'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _decisiones = ((d['decisiones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _vencidos = (d['vencidos'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {}
  }

  /// Dejar pasar a alguien. Pide DOS cosas: por qué, y hasta cuándo.
  ///
  /// El plazo es lo que evita que esto se vuelva un cajón sin fondo. «Tiene
  /// beca» sigue siendo cierto en marzo; «me dijo que se reincorpora el
  /// próximo ciclo» hay que volver a mirarlo. Al vencer, la persona regresa
  /// sola a la lista de candidatos.
  Future<void> _dejarPasar(Map<String, dynamic> it) async {
    if (_decisiones.isEmpty) await _cargarRevisados();
    String decision = _decisiones.isNotEmpty
        ? '${_decisiones.first['clave']}'
        : 'otro';
    int meses = 3;
    final notaCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Dejar pasar a ${it['nombre']}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      'Sale de la lista de candidatos, pero no se pierde: '
                      'vuelve cuando venza el plazo que elijas.',
                      style: TextStyle(
                          fontSize: 12.5, color: cessumMuted(context))),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: decision,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Por qué se deja pasar',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _decisiones
                      .map((d) => DropdownMenuItem(
                          value: '${d['clave']}',
                          child: Text('${d['etiqueta']}',
                              overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setLocal(() => decision = v ?? 'otro'),
                ),
                // La ayuda de la opción elegida, para no tener que recordar
                // qué significa cada una.
                if (_decisiones.any((d) => d['clave'] == decision))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                          '${_decisiones.firstWhere((d) => d['clave'] == decision)['ayuda']}',
                          style: TextStyle(
                              fontSize: 11.5, color: cessumMuted(context))),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: meses,
                  decoration: const InputDecoration(
                    labelText: 'Volver a revisarlo en',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 mes')),
                    DropdownMenuItem(value: 3, child: Text('3 meses')),
                    DropdownMenuItem(value: 6, child: Text('6 meses')),
                    DropdownMenuItem(value: 12, child: Text('1 año')),
                  ],
                  onChanged: (v) => setLocal(() => meses = v ?? 3),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notaCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Nota para quien lo vea después',
                    helperText: 'Lo que hablaste con esta persona. Sin esto, '
                        'en tres meses alguien le vuelve a llamar preguntando '
                        'lo mismo.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumGold),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Dejar pasar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      final r = await http.get(
        Uri.parse(guardianUrl).replace(queryParameters: {
          'accion': 'revision_baja_guardar',
          'matricula': '${it['matricula']}',
          'decision': decision,
          'meses': '$meses',
          'nota': notaCtrl.text.trim(),
        }),
      );
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: d['ok'] == true ? cessumGold : cessumRed,
        content: Text(d['ok'] == true
            ? 'Listo. Vuelve a la lista el ${d['revisarDeNuevo']}'
            : '${d['error'] ?? 'No se pudo'}'),
      ));
      if (d['ok'] == true) {
        _cargar();
        _cargarRevisados();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
  }

  Future<void> _regresarACandidatos(Map<String, dynamic> r) async {
    try {
      await http.get(Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'revision_baja_quitar',
        'matricula': '${r['matricula']}',
      }));
      if (!mounted) return;
      _cargar();
      _cargarRevisados();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Vuelve a la lista de candidatos')));
    } catch (_) {}
  }

  Widget _vistaRevisados() {
    if (_revisados.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Text(
              'Todavía no has dejado pasar a nadie.\n\n'
              'Cuando revises un candidato y decidas que no procede la baja, '
              'márcalo aquí con el motivo: sale de la lista y vuelve cuando '
              'venza el plazo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5,
                  color: cessumMuted(context))),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_vencidos > 0)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
            ),
            child: Text(
                '$_vencidos venció su plazo y ya volvió a la lista de '
                'candidatos. Conviene revisarlos de nuevo.',
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ),
        ..._revisados.map((r) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: r['vencido'] == true
                      ? BorderSide(color: cessumRed.withValues(alpha: .5))
                      : BorderSide.none),
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('${r['alumno']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                      ),
                      if (r['vencido'] == true)
                        _badge('Por revisar', cessumRed),
                    ]),
                    Text(
                        '${r['matricula']} · ${r['programa']}'
                        '${'${r['grupo']}'.isNotEmpty ? ' · ${r['grupo']}' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: cessumMuted(context))),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: cessumGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${r['decision']}',
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w700)),
                          if ('${r['nota']}'.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('${r['nota']}',
                                style: const TextStyle(
                                    fontSize: 12, height: 1.45)),
                          ],
                          const SizedBox(height: 4),
                          Text(
                              'Revisar de nuevo el ${r['revisarDeNuevo']}'
                              '${'${r['quien']}'.isNotEmpty ? ' · lo marcó ${r['quien']}' : ''}',
                              style: TextStyle(
                                  fontSize: 11, color: cessumMuted(context))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _regresarACandidatos(r),
                          icon: const Icon(Icons.undo, size: 17),
                          label: const Text('Volver a candidatos'),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: cessumGold),
                          onPressed: () => _dejarPasar({
                            'matricula': r['matricula'],
                            'nombre': r['alumno'],
                          }),
                          icon: const Icon(Icons.edit_note, size: 17),
                          label: const Text('Otra nota'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Future<void> _cargarCausales() async {
    if (_causales.isNotEmpty) return;
    try {
      final r = await http.get(Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'causales_baja'}));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && d['causales'] is Map) {
        _causales = Map<String, dynamic>.from(d['causales'] as Map);
      }
    } catch (_) {
      // Si no cargan, el campo sigue siendo de escritura libre: se puede
      // aplicar la baja igual, solo sin los atajos.
    }
  }

  /// Redacta el motivo con los hechos ya detectados y el artículo que
  /// corresponde al tipo de baja.
  ///
  /// POR QUÉ VIENE ESCRITO Y NO EN BLANCO
  /// Un campo vacío que es obligatorio se llena con lo primero que salga —«no
  /// entró»— y eso no funda nada. El acta se le entrega al alumno y puede
  /// terminar ante la autoridad educativa: tiene que citar el precepto y
  /// contar los hechos con sus fechas.
  ///
  /// Es un BORRADOR, no un texto final: se edita antes de aplicar, y ahí es
  /// donde se agrega lo que solo sabe quien revisó el caso.
  String _redactarMotivo(Map<String, dynamic> it, String tipoBaja) {
    final hechos = ((it['porQue'] as List?) ?? [])
        .map((x) => '$x')
        .where((x) => x.trim().isNotEmpty)
        .toList();

    // El artículo que corresponde al tipo elegido.
    final art = tipoBaja == 'Voluntaria'
        ? 'Art. 37'
        : tipoBaja == 'Disciplinaria'
            ? 'Art. 39'
            : 'Art. 38';

    if (tipoBaja == 'Voluntaria') {
      return 'Baja voluntaria solicitada por el estudiante, conforme al '
          '$art del Reglamento Escolar Institucional.';
    }
    if (tipoBaja == 'Disciplinaria') {
      return 'Baja disciplinaria conforme al $art del Reglamento Escolar '
          'Institucional. Hechos que la motivan: ';
    }

    // Automática: se enumeran los hechos detectados, que es lo que de verdad
    // sostiene el acta.
    final buf = StringBuffer(
        'Baja automática conforme al $art del Reglamento Escolar '
        'Institucional, por las siguientes causas registradas en el sistema:');
    if (hechos.isEmpty) {
      buf.write(' inactividad académica prolongada.');
    } else {
      for (final h in hechos) {
        buf.write('\n· $h');
      }
    }
    final rep = (it['numReprobadas'] as num?)?.toInt() ?? 0;
    if (rep > 0) {
      buf.write('\n\nLo anterior en relación con el Art. 48, que establece '
          'la calificación mínima aprobatoria.');
    }
    return buf.toString();
  }

  Future<void> _aplicarBaja(Map<String, dynamic> it) async {
    await _cargarCausales();
    String tipoBaja = 'Voluntaria';
    String temporalidad = 'Temporal';
    // Viene redactado desde el principio, con los hechos de ESTE alumno.
    final motivoCtrl =
        TextEditingController(text: _redactarMotivo(it, tipoBaja));
    // Si la persona lo edita a mano, ya no se le sobrescribe al cambiar el
    // tipo de baja: perder lo que alguien acaba de escribir es imperdonable.
    var motivoTocado = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Aplicar baja', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${it['nombre']} (${it['matricula']})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${it['programa']} · ${it['generacion']}',
                    style:
                        const TextStyle(fontSize: 12.5, color: Colors.black54)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: tipoBaja,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de baja (Art. 37-39)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'Voluntaria',
                        child: Text('Voluntaria (Art. 37)')),
                    DropdownMenuItem(
                        value: 'Automática',
                        child: Text('Automática (Art. 38)')),
                    DropdownMenuItem(
                        value: 'Disciplinaria',
                        child: Text('Disciplinaria (Art. 39)')),
                  ],
                  onChanged: (v) => setLocal(() {
                    tipoBaja = v ?? 'Voluntaria';
                    if (!motivoTocado) {
                      motivoCtrl.text = _redactarMotivo(it, tipoBaja);
                    }
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: temporalidad,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Temporalidad',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'Temporal', child: Text('Temporal')),
                    DropdownMenuItem(
                        value: 'Definitiva', child: Text('Definitiva')),
                  ],
                  onChanged: (v) =>
                      setLocal(() => temporalidad = v ?? 'Temporal'),
                ),
                const SizedBox(height: 10),
                // Las causales del tipo de baja elegido. Cambian al cambiar el
                // tipo: ofrecer una causal disciplinaria en una baja
                // voluntaria invita a fundar mal el acta.
                if ((_causales[tipoBaja] as List?)?.isNotEmpty ?? false) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('FUNDAMENTOS DEL REGLAMENTO · toca uno para usarlo',
                        style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: .8,
                            fontWeight: FontWeight.w800,
                            color: cessumGold)),
                  ),
                  const SizedBox(height: 5),
                  ...((_causales[tipoBaja] as List?) ?? []).map((c) {
                    final m = Map<String, dynamic>.from(c as Map);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: InkWell(
                        onTap: () => setLocal(() {
                          motivoCtrl.text = '${m['texto']}';
                          motivoCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: motivoCtrl.text.length));
                        }),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: cessumGold.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${m['art']}  ',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: cessumGold)),
                                Expanded(
                                    child: Text('${m['texto']}',
                                        style: const TextStyle(
                                            fontSize: 11.5, height: 1.35))),
                              ]),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: motivoCtrl,
                  maxLines: 6,
                  minLines: 4,
                  onChanged: (_) => motivoTocado = true,
                  decoration: const InputDecoration(
                    labelText: 'Motivo / fundamento *',
                    helperText: 'Viene redactado con los hechos detectados. '
                        'Revísalo y complétalo: esto se imprime en el acta y '
                        'lo lee el estudiante.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Al aplicar se genera el acta oficial de baja y se notifica '
                    'al alumno por correo, informándole su derecho a presentar '
                    'alegaciones ante la Vicerrectoría (Art. 41).',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                if (motivoCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('El motivo es obligatorio.')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Aplicar baja'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    final quien = await SessionStore.realEmail();
    try {
      final motivoFull =
          '$temporalidad · ${motivoCtrl.text.trim()}';
      final payload = <String, dynamic>{
        'accion': 'baja_validar',
        'estatus': 'Validada',
        'validadaPor': quien ?? 'Administración',
        'matricula': it['matricula'],
        'nombre': it['nombre'],
        'correo': it['correo'],
        'programa': it['programa'],
        'generacion': it['generacion'],
        'tipoBaja': tipoBaja,
        'motivo': motivoFull,
        'comentarios': _resumenMotivos(it),
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Baja aplicada. Se notificó al alumno.')));
        _cargar();
        _cargarTemporales();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo: ${data['error'] ?? 'error'}')));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error de conexión.')));
    }
  }

  String _resumenMotivos(Map<String, dynamic> it) {
    final partes = <String>[];
    final n = (it['numReprobadas'] ?? 0);
    final a = (it['numAdeudos'] ?? 0);
    if (n is num && n > 0) partes.add('$n materia(s) reprobada(s)');
    if (a is num && a > 0) partes.add('$a adeudo(s)');
    return partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: const Text('Candidatos a baja',
            style: TextStyle(fontSize: 18)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _cargar();
                _cargarTemporales();
                _cargarRevisados();
              }),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 14),
          labelStyle: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w600),
          tabs: [
            const Tab(text: 'Candidatos'),
            // Los ya revisados. El número de VENCIDOS va aparte y en rojo:
            // esos son los que hay que volver a mirar, y si no se ven, el
            // «dejar pasar» se convierte en un cajón donde todo se pierde.
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Revisados (${_revisados.length})'),
                if (_vencidos > 0) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text('$_vencidos',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: cessumRed)),
                  ),
                ],
              ]),
            ),
            Tab(text: 'Temporal (${_temporales.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _vistaCandidatos(),
          _vistaRevisados(),
          _vistaTemporales(),
        ],
      ),
    );
  }

  Widget _vistaCandidatos() {
    return Column(
      children: [
        _filtros(),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!))
                  : _items.isEmpty
                      ? const Center(
                          child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No hay candidatos a baja con el criterio actual.',
                            textAlign: TextAlign.center,
                          ),
                        ))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          itemBuilder: (ctx, i) => _tarjeta(_items[i]),
                        ),
        ),
      ],
    );
  }

  Widget _vistaTemporales() {
    if (_cargandoTemp) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_temporales.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay alumnos en baja temporal por reactivar.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _temporales.length,
      itemBuilder: (ctx, i) {
        final it = _temporales[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${it['nombre']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${it['matricula']} · ${it['programa']} · ${it['generacion']}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Baja ${it['tipoBaja']} · ${it['fecha']}',
                  style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
                ),
                if ((it['motivo'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('${it['motivo']}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8E3E),
                        foregroundColor: Colors.white),
                    onPressed: () => _reactivar(it),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Reactivar inscripción'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filtros() {
    Widget chip(String label, String val) {
      final sel = _filtro == val;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: sel,
          selectedColor: cessumRed.withValues(alpha: 0.15),
          onSelected: (_) {
            setState(() => _filtro = val);
            _cargar();
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          chip('Todos', 'todos'),
          chip('Reprobadas', 'reprobadas'),
          chip('Adeudo', 'adeudo'),
          const Spacer(),
          Text('${_items.length}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: cessumRed)),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> it) {
    final motivos = (it['motivos'] ?? {}) as Map<String, dynamic>;
    final reprob = motivos['reprobadas'] == true;
    final adeudo = motivos['adeudo'] == true;
    // (ago-19) Las dos señales que mejor distinguen a quien SE FUE de quien
    // está batallando. Un alumno con reprobadas sigue ahí y probablemente
    // necesita apoyo; uno que no entra ni tiene calificaciones ya se fue.
    final sinAcceso = motivos['sinAcceso'] == true;
    final sinCalif = motivos['sinCalificaciones'] == true;
    final porQue = (it['porQue'] as List?) ?? [];
    final cuantas = (it['senales'] as num?)?.toInt() ?? 0;
    // Renglones suyos en el reporte a la SEC del corte vigente.
    final enSiga = (it['filasEnSiga'] as num?)?.toInt() ?? 0;
    // Nota para quien revisa. NUNCA entra al motivo del acta ni al correo.
    final avisoInterno = '${it['avisoInterno'] ?? ''}';
    final listaReprob = (it['reprobadas'] as List?) ?? [];
    final listaAdeudo = (it['adeudoPendientes'] as List?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // (ago-19) EN MÓVIL, NOMBRE Y ETIQUETAS NO CABEN EN UNA FILA.
            // El nombre se partía en cuatro renglones de dos letras y las
            // etiquetas lo empujaban fuera. Ahora el nombre ocupa su propio
            // renglón —es lo más importante de la tarjeta: es una persona— y
            // las etiquetas van debajo, en Wrap, acomodándose solas.
            Text('${it['nombre']}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15, height: 1.25)),
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                if (enSiga > 0) _badge('En SIGA', const Color(0xFF1565C0)),
                if (cuantas >= 3) _badge('$cuantas señales', cessumRed),
                if (sinCalif) _badge('Sin calificar', const Color(0xFF7E57C2)),
                if (sinAcceso) _badge('No entra', const Color(0xFF546E7A)),
                if (reprob) _badge('Reprobada', cessumRed),
                if (adeudo) _badge('Adeudo', cessumGold),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${it['matricula']} · ${it['programa']} · ${it['generacion']} · ${it['grupo']}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context)),
            ),
            // El aviso de SIGA va ARRIBA del porqué: es una consecuencia
            // administrativa que hay que conocer antes de decidir, no un
            // detalle más de la ficha.
            if (enSiga > 0) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF1565C0).withValues(alpha: 0.3)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 17, color: Color(0xFF1565C0)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            'Va en el reporte de SIGA con $enSiga renglón(es). '
                            'Si lo das de baja, hay que volver a generar el '
                            'paquete completo antes de entregarlo, o los '
                            'archivos no coincidirán entre sí.',
                            style: const TextStyle(fontSize: 12, height: 1.4)),
                      ),
                    ]),
              ),
            ],
            if (avisoInterno.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 15, color: cessumMuted(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(avisoInterno,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                          color: cessumMuted(context))),
                ),
              ]),
            ],
            // El porqué, en palabras y con fechas. Quien revisa no debería
            // tener que interpretar etiquetas sueltas para decidir sobre la
            // continuidad de una persona.
            if (porQue.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('POR QUÉ APARECE AQUÍ',
                        style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: .9,
                            fontWeight: FontWeight.w800,
                            color: cessumGold)),
                    const SizedBox(height: 4),
                    ...porQue.map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('· ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)),
                                Expanded(
                                    child: Text('$m',
                                        style: const TextStyle(
                                            fontSize: 12.5, height: 1.4))),
                              ]),
                        )),
                    if (cuantas == 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            'Una sola señal casi nunca justifica una baja. '
                            'Puede tener beca, ser materia presencial, o estar '
                            'batallando y necesitar apoyo.',
                            style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: cessumMuted(context))),
                      ),
                  ],
                ),
              ),
            ],
            if (listaReprob.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Materias reprobadas:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cessumRed)),
              ...listaReprob.map((r) {
                final m = Map<String, dynamic>.from(r as Map);
                return Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    '• ${m['materia']}  —  ${m['calificacion']}'
                    '${(m['docente'] ?? '').toString().isNotEmpty ? '  (${m['docente']})' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
            ],
            if (listaAdeudo.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Adeudos del periodo:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cessumGold)),
              ...listaAdeudo.map((r) {
                final m = Map<String, dynamic>.from(r as Map);
                return Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text(
                    '• ${m['concepto']}  —  ${m['monto']}'
                    '${(m['fechaLimite'] ?? '').toString().isNotEmpty ? '  (límite ${m['fechaLimite']})' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
            ],
            const SizedBox(height: 12),
            // (ago-19) EN EL TELÉFONO, CUATRO BOTONES EN FILA NO CABEN.
            // Cada uno quedaba de unos 60 px y el texto se apilaba letra por
            // letra: «A / pli / car / ba / ja». Ilegible, y encima el más
            // peligroso de los cuatro.
            //
            // Se decide por el ancho real. Y no se esconde nada en un menú de
            // tres puntos: quien revisa bajas necesita ver de golpe que existe
            // la alternativa de dejar pasar o avisar, no solo el botón rojo.
            LayoutBuilder(builder: (ctx, cons) {
              final chico = cons.maxWidth < 520;
              final ficha = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cessumMuted(context),
                    side: BorderSide(color: cessumFaint(context)),
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => _verFicha(it),
                icon: const Icon(Icons.person_search, size: 17),
                label: const Text('Ficha',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );
              // Dejar pasar: la salida honesta cuando la baja no procede. Sin
              // ella la única opción sería aplicarla o no hacer nada, y «no
              // hacer nada» significa volver a encontrárselo la semana que
              // viene sin recordar por qué se dejó.
              final pasar = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cessumMuted(context),
                    side: BorderSide(color: cessumFaint(context)),
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => _dejarPasar(it),
                icon: const Icon(Icons.check_circle_outline, size: 17),
                label: const Text('Dejar pasar',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );
              // Avisar sin dar de baja: muchas veces lo que corresponde es
              // preguntar qué pasó, no cerrar la puerta.
              final aviso = OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cessumGold,
                    side: BorderSide(color: cessumGold.withValues(alpha: .5)),
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => _avisarAlumno(it),
                icon: const Icon(Icons.mail_outline, size: 17),
                label: const Text('Aviso previo',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );
              final baja = ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => _aplicarBaja(it),
                icon: const Icon(Icons.person_off, size: 17),
                label: const Text('Aplicar baja',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              );

              if (!chico) {
                return Row(children: [
                  Expanded(child: ficha),
                  const SizedBox(width: 8),
                  Expanded(child: pasar),
                  const SizedBox(width: 8),
                  Expanded(child: aviso),
                  const SizedBox(width: 10),
                  Expanded(child: baja),
                ]);
              }
              // En pantalla chica: dos y dos. «Aplicar baja» comparte renglón
              // con «Aviso previo» a propósito — la acción reversible al lado
              // de la irreversible, para que la suave esté siempre a la vista
              // en el momento de decidir.
              return Column(children: [
                Row(children: [
                  Expanded(child: ficha),
                  const SizedBox(width: 8),
                  Expanded(child: pasar),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: aviso),
                  const SizedBox(width: 8),
                  Expanded(child: baja),
                ]),
              ]);
            }),
          ],
        ),
      ),
    );
  }

  /// Manda el aviso de baja al alumno. SIEMPRE muestra antes lo que se le
  /// va a decir: este correo le comunica a una persona que quedó fuera de la
  /// escuela, y mandarlo sin leerlo es exactamente lo que no debe pasar.
  Future<void> _avisarAlumno(Map<String, dynamic> it) async {
    final porQue = ((it['porQue'] as List?) ?? []).join('. ');
    final motivoCtrl = TextEditingController(
        text: porQue.isNotEmpty ? '$porQue.' : '');

    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Aviso previo a ${it['nombre']}',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Se le enviará a ${it['correo']} un AVISO PREVIO: le '
                    'decimos qué encontramos en su expediente, que su '
                    'inscripción sigue vigente, y le ofrecemos alternativas '
                    'antes de que derive en una baja.',
                    style: TextStyle(
                        fontSize: 12.5, color: cessumMuted(context))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motivoCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Motivo que va a leer *',
                  helperText: 'Esto es lo que la persona va a leer. '
                      'Escríbelo como se lo dirías de frente.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                    'Esto NO da de baja y el correo NO le dice que esté dado '
                    'de baja: su inscripción sigue vigente y así se lo '
                    'decimos. Si además hay que aplicarla, usa «Aplicar '
                    'baja» — ese sí la ejecuta y manda la constancia.',
                    style: TextStyle(fontSize: 11.5, height: 1.4)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumGold),
            onPressed: motivoCtrl.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, true),
            child: const Text('Enviar el aviso'),
          ),
        ],
      ),
    );
    if (enviar != true) return;

    try {
      final r = await http.get(
        Uri.parse(guardianUrl).replace(queryParameters: {
          'accion': 'baja_notificar',
          'matricula': '${it['matricula']}',
          'motivo': motivoCtrl.text.trim(),
        }),
      );
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: d['ok'] == true ? const Color(0xFF1E7B34) : cessumRed,
        content: Text(d['ok'] == true
            ? 'Aviso enviado a ${d['para']}'
            : '${d['error'] ?? 'No se pudo enviar'}'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
  }

  void _verFicha(Map<String, dynamic> it) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${it['nombre']}', style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fichaLinea('Matrícula', '${it['matricula']}'),
              _fichaLinea('Correo', '${it['correo']}'),
              _fichaLinea('Programa', '${it['programa']}'),
              _fichaLinea('Generación', '${it['generacion']}'),
              _fichaLinea('Grupo', '${it['grupo']}'),
              _fichaLinea('Modalidad', '${it['modalidad']}'),
              _fichaLinea('Reprobadas', '${it['numReprobadas']}'),
              _fichaLinea('Adeudos', '${it['numAdeudos']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _fichaLinea(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 13, color: cessumMuted(context)),
          children: [
            TextSpan(
                text: '$k: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: v),
          ],
        ),
      ),
    );
  }

  Widget _badge(String txt, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

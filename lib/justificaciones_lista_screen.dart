import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Lista de justificaciones de faltas.
/// - modoAdmin = true  -> el administrador ve TODAS y puede validar/rechazar.
/// - docenteFiltro != null -> el docente ve solo las de sus materias (lectura).
class JustificacionesListaScreen extends StatefulWidget {
  final bool modoAdmin;
  final String? docenteFiltro;
  const JustificacionesListaScreen({
    super.key,
    this.modoAdmin = false,
    this.docenteFiltro,
  });

  @override
  State<JustificacionesListaScreen> createState() =>
      _JustificacionesListaScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _Justif {
  final int fila;
  final String fecha;
  String estatus;
  final String nombre;
  final String matricula;
  final String correo;
  final String celular;
  final String fechaSesion;
  final String fechasAdicionales;
  final String materia;
  final String docente;
  final String motivo;
  final String detalles;
  final String evidencia;
  final String programa;
  final String generacion;
  final String validadaPor;
  final String fechaValidacion;
  final String comentario;
  /* (3-sep) Cuántas faltas lleva justificadas este alumno. Sin esto, quien
     dictamina veía la solicitud sola y no podía distinguir la primera del
     semestre de la sexta en la misma materia. */
  final int yaEnMateria;
  final int yaEnTotal;
  final int pendientesTotal;
  final int materiasConFaltas;
  final String alerta;
  final List<Map<String, dynamic>> porMateria;
  final List<Map<String, dynamic>> historial;

  _Justif.fromMap(Map<String, dynamic> m)
      : fila = int.tryParse('${m['fila']}') ?? 0,
        fecha = (m['fecha'] ?? '').toString(),
        estatus = (m['estatus'] ?? '').toString(),
        nombre = (m['nombre'] ?? '').toString(),
        matricula = (m['matricula'] ?? '').toString(),
        correo = (m['correo'] ?? '').toString(),
        celular = (m['celular'] ?? '').toString(),
        fechaSesion = (m['fechaSesion'] ?? '').toString(),
        fechasAdicionales = (m['fechasAdicionales'] ?? '').toString(),
        materia = (m['materia'] ?? '').toString(),
        docente = (m['docente'] ?? '').toString(),
        motivo = (m['motivo'] ?? '').toString(),
        detalles = (m['detalles'] ?? '').toString(),
        evidencia = (m['evidencia'] ?? '').toString(),
        programa = (m['programa'] ?? '').toString(),
        generacion = (m['generacion'] ?? '').toString(),
        validadaPor = (m['validadaPor'] ?? '').toString(),
        fechaValidacion = (m['fechaValidacion'] ?? '').toString(),
        comentario = (m['comentario'] ?? '').toString(),
        yaEnMateria =
            int.tryParse('${(m['yaJustificadas'] ?? const {})['enEstaMateria']}') ?? 0,
        yaEnTotal =
            int.tryParse('${(m['yaJustificadas'] ?? const {})['enTotal']}') ?? 0,
        pendientesTotal = int.tryParse(
                '${(m['yaJustificadas'] ?? const {})['pendientesEnTotal']}') ??
            0,
        materiasConFaltas = int.tryParse(
                '${(m['yaJustificadas'] ?? const {})['materiasConFaltas']}') ??
            0,
        alerta = (m['alerta'] ?? '').toString(),
        porMateria = ((m['porMateria'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        historial = ((m['historial'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
}

class _JustificacionesListaScreenState
    extends State<JustificacionesListaScreen> {
  bool _cargando = true;
  String? _error;
  List<_Justif> _items = [];

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
      final params = <String, String>{'accion': 'justificaciones_listar'};
      if (widget.docenteFiltro != null &&
          widget.docenteFiltro!.trim().isNotEmpty) {
        // (10-sep) SE FILTRA POR CORREO, NO POR NOMBRE.
        // El campo «docente» de la justificación lo escribe el alumno, y en la
        // base viene con títulos, faltas de ortografía o el nombre de otro
        // profesor. Comparar contra eso hacía que al docente no le apareciera
        // nada: le pasó a Fernando Isaac con tres justificaciones validadas
        // de su curso. Con el correo, el backend resuelve SUS asignaciones.
        final correo = await SessionStore.validEmail() ?? '';
        if (correo.isNotEmpty) {
          params['correoDocente'] = correo;
        } else {
          params['docente'] = widget.docenteFiltro!.trim();
        }
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final lista = (data['justificaciones'] as List<dynamic>? ?? [])
          .map((e) => _Justif.fromMap(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _items = lista;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error =
              'No se pudo cargar. Revisa tu conexión e intenta de nuevo.';
        });
      }
    }
  }

  /// (24-sep) Sugerencia con IA según los criterios de Vicerrectoría. Solo
  /// propone: la decisión y el texto final son de quien dictamina.
  Future<void> _sugerirIa(_Justif j) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'justificacion_ia_sugerir',
            'fila': '${j.fila}',
            'matricula': j.matricula,
          }))
          .timeout(const Duration(seconds: 120));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (e) {
      d = {'ok': false, 'error': 'No se pudo conectar.'};
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (d['ok'] != true) {
      _aviso('${d['error'] ?? 'No se pudo generar la sugerencia.'}');
      return;
    }
    final sug = '${d['sugerencia'] ?? ''}';
    final Color c = sug == 'Validar' ? _verdeOk : (sug == 'Rechazar' ? cessumRed : cessumGold);
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: cessumGold),
          const SizedBox(width: 8),
          Expanded(child: Text('Sugerencia: $sug', style: TextStyle(fontSize: 17, color: c, fontWeight: FontWeight.w800))),
        ]),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${j.nombre} · ${j.materia} · ${j.fechaSesion}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text('Por qué', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text('${d['razon'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              const Text('Evidencia', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text('${d['evidencia'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              const Text('Dictamen para el alumno', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              Text('${d['dictamen'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 10),
              Text('${d['aviso'] ?? ''}', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, 'Rechazada'),
            child: const Text('Rechazar con este texto'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _verdeOk, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, 'Validada'),
            child: const Text('Validar con este texto'),
          ),
        ],
      ),
    );
    if (accion != null && mounted) await _validar(j, accion, comentarioInicial: '${d['dictamen'] ?? ''}');
  }

  Future<void> _validar(_Justif j, String estatus, {String comentarioInicial = ''}) async {
    final esRechazo = estatus != 'Validada';
    final comentarioCtrl = TextEditingController(text: comentarioInicial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esRechazo ? 'Rechazar' : 'Validar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿${esRechazo ? 'Rechazar' : 'Validar'} la '
              'justificación de ${j.nombre}?\n\n${j.materia} · ${j.fechaSesion}',
              style: TextStyle(height: 1.4),
            ),
            SizedBox(height: 14),
            TextField(
              controller: comentarioCtrl,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                labelText: esRechazo
                    ? 'Motivo del rechazo (se envía al alumno)'
                    : 'Comentario (opcional, se envía al alumno)',
                hintText: esRechazo
                    ? 'Explica por qué se rechaza…'
                    : 'Observaciones para el alumno…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: esRechazo ? cessumRed : _verdeOk,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(esRechazo ? 'Rechazar' : 'Validar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _cargando = true);
    try {
      final correo = await SessionStore.validEmail();
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'justificacion_validar',
              'fila': j.fila,
              'matricula': j.matricula,
              'estatus': estatus,
              'validadaPor': correo ?? 'Administración',
              'comentario': comentarioCtrl.text.trim(),
            }),
          )
          .timeout(Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || data.containsKey('guardadas')) {
        throw Exception(data['error'] ?? 'No se pudo actualizar.');
      }
      _aviso(estatus == 'Validada'
          ? 'Justificación validada.'
          : 'Justificación rechazada.');
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
      _aviso('No se pudo guardar: $e');
    }
  }

  Future<void> _abrirEvidencia(String url) async {
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir la evidencia.');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text(widget.modoAdmin
            ? 'Justificaciones (admin)'
            : 'Justificaciones de mis materias'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _items.isEmpty
                  ? _vistaVacia()
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: EdgeInsets.all(16),
                        children: _items.map(_tarjeta).toList(),
                      ),
                    ),
    );
  }

  Widget _tarjeta(_Justif j) {
    final pendiente = j.estatus == 'Pendiente';
    final validada = j.estatus == 'Validada';
    final Color cEstatus =
        pendiente ? cessumGold : (validada ? _verdeOk : cessumRed);

    return Container(
      margin: EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: cEstatus.withValues(alpha: 0.10),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                  pendiente
                      ? Icons.hourglass_top
                      : (validada ? Icons.verified : Icons.cancel),
                  size: 16,
                  color: cEstatus,
                ),
                SizedBox(width: 6),
                Text(
                  j.estatus.isEmpty ? 'Pendiente' : j.estatus,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: cEstatus, fontSize: 13),
                ),
                Spacer(),
                Text(j.fecha,
                    style: TextStyle(fontSize: 11, color: cessumFaint(context))),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(j.nombre,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context))),
                Text('Matrícula: ${j.matricula}',
                    style:
                        TextStyle(fontSize: 12, color: cessumMuted(context))),
                SizedBox(height: 8),
                // (3-sep) El conteo va ARRIBA de los datos de la solicitud:
                // es lo primero que hay que saber para decidir, no un detalle
                // al final que nadie baja a leer.
                _contador(j),
                SizedBox(height: 10),
                _linea('Materia', j.materia),
                _linea('Docente', j.docente),
                _linea('Sesión', j.fechaSesion),
                if (j.fechasAdicionales.isNotEmpty)
                  _linea('Otras fechas', j.fechasAdicionales),
                _linea('Motivo', j.motivo),
                _linea('Detalles', j.detalles),
                if (j.celular.isNotEmpty) _linea('Celular', j.celular),
                if (j.correo.isNotEmpty) _linea('Correo', j.correo),
                if (!pendiente && j.validadaPor.isNotEmpty)
                  _linea('Resuelta por', '${j.validadaPor} · ${j.fechaValidacion}'),
                if (j.comentario.isNotEmpty)
                  _linea('Comentario', j.comentario),
                if (j.evidencia.isNotEmpty &&
                    j.evidencia.startsWith('http')) ...[
                  SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _abrirEvidencia(j.evidencia),
                    icon: Icon(Icons.image, size: 16, color: cessumRed),
                    label: Text('Ver evidencia',
                        style: TextStyle(color: cessumRed, fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: cessumRed),
                      minimumSize: Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
                if (widget.modoAdmin && pendiente) ...[
                  Divider(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // (24-sep) Sugerencia con IA según los criterios de Vicerrectoría.
                      TextButton.icon(
                        onPressed: () => _sugerirIa(j),
                        style: TextButton.styleFrom(foregroundColor: cessumGold),
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('Sugerencia con IA'),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () => _validar(j, 'Rechazada'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: cessumRed),
                          foregroundColor: cessumRed,
                        ),
                        child: Text('Rechazar'),
                      ),
                      SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => _validar(j, 'Validada'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _verdeOk,
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(Icons.check, size: 18),
                        label: Text('Validar'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Cuántas faltas lleva justificadas el alumno: en esta materia y en total.
  /// Con historial desplegable para poder valorar antes de dictaminar.
  Widget _contador(_Justif j) {
    final mucho = j.yaEnMateria >= 3 || j.yaEnTotal >= 5;
    final Color base = mucho ? cessumRed : cessumGold;
    return Container(
      padding: EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(mucho ? Icons.warning_amber_rounded : Icons.history,
              size: 17, color: base),
          SizedBox(width: 7),
          Expanded(
            child: Text(
              'Ya justificadas: ${j.yaEnMateria} en esta materia · ${j.yaEnTotal} en total',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cessumInk(context)),
            ),
          ),
        ]),
        if (j.pendientesTotal > 1)
          Padding(
            padding: EdgeInsets.only(top: 3, left: 24),
            child: Text(
                'Tiene ${j.pendientesTotal} sesión(es) más esperando dictamen.',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ),
        if (j.alerta.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 5, left: 24),
            child: Text(j.alerta,
                style: TextStyle(
                    fontSize: 12, color: cessumRed, fontWeight: FontWeight.w600)),
          ),
        if (j.historial.isNotEmpty) ...[
          SizedBox(height: 6),
          InkWell(
            onTap: () => _verHistorial(j),
            child: Padding(
              padding: EdgeInsets.only(left: 24, top: 2),
              child: Text('Ver el histórico (${j.historial.length}) →',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: cessumRed,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }

  /// El histórico completo del alumno, para valorar antes de dictaminar.
  void _verHistorial(_Justif j) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(children: [
            Container(
              padding: EdgeInsets.fromLTRB(18, 15, 8, 15),
              decoration: BoxDecoration(
                color: cessumRed,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Histórico de justificaciones',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                        Text(j.nombre,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12)),
                      ]),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            // Resumen por materia: dónde se concentran las faltas.
            if (j.porMateria.isNotEmpty)
              Container(
                width: double.infinity,
                color: cessumGold.withValues(alpha: 0.10),
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: j.porMateria.map((m) {
                      final v = int.tryParse('${m['validadas']}') ?? 0;
                      final p = int.tryParse('${m['pendientes']}') ?? 0;
                      final r = int.tryParse('${m['rechazadas']}') ?? 0;
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Expanded(
                              child: Text('${m['materia']}',
                                  style: TextStyle(fontSize: 12.5))),
                          Text(
                              '$v validada(s)'
                              '${p > 0 ? ' · $p pend.' : ''}'
                              '${r > 0 ? ' · $r rech.' : ''}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: v >= 3 ? cessumRed : cessumInk(context))),
                        ]),
                      );
                    }).toList()),
              ),
            Expanded(
              child: ListView.separated(
                controller: sc,
                padding: EdgeInsets.all(14),
                itemCount: j.historial.length,
                separatorBuilder: (_, __) => SizedBox(height: 9),
                itemBuilder: (_, i) {
                  final h = j.historial[i];
                  final est = '${h['estatus']}';
                  final col = est == 'Validada'
                      ? _verdeOk
                      : (est == 'Rechazada' ? cessumRed : cessumGold);
                  return Container(
                    padding: EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: col.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: col.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Text(est,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: col,
                                      fontWeight: FontWeight.w700)),
                            ),
                            SizedBox(width: 8),
                            Text('${h['fechaSesion']}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            if ((int.tryParse('${h['sesiones']}') ?? 1) > 1)
                              Text('  (${h['sesiones']} sesiones)',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: cessumMuted(context))),
                          ]),
                          SizedBox(height: 5),
                          Text('${h['materia']}',
                              style: TextStyle(fontSize: 12.5)),
                          Text('Motivo: ${h['motivo']}',
                              style: TextStyle(
                                  fontSize: 12, color: cessumMuted(context))),
                          if ('${h['detalles']}'.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 3),
                              child: Text('${h['detalles']}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: cessumMuted(context))),
                            ),
                          Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                                'Evidencia: ${h['evidencia']}'
                                '${'${h['validadaPor']}'.isNotEmpty ? ' · resuelta por ${h['validadaPor']} el ${h['fechaValidacion']}' : ''}',
                                style: TextStyle(
                                    fontSize: 11, color: cessumMuted(context))),
                          ),
                          if ('${h['comentario']}'.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text('«${h['comentario']}»',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontStyle: FontStyle.italic,
                                      color: cessumInk(context))),
                            ),
                        ]),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _linea(String etq, String valor) {
    if (valor.isEmpty) return SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text('$etq:',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          ),
          Expanded(
            child: Text(valor,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cessumInk(context))),
          ),
        ],
      ),
    );
  }

  Widget _vistaVacia() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, color: cessumFaint(context), size: 52),
            SizedBox(height: 12),
            Text(
              'No hay justificaciones por ahora.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context), height: 1.4)),
            SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargar,
              icon: Icon(Icons.refresh),
              label: Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

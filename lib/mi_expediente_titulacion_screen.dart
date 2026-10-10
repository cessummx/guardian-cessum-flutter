import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'foto_web_picker.dart';
import 'helpers.dart';
import 'student_profile.dart';
import 'auth/session_store.dart'; // (24-sep) la de lib\\auth (expira también la llave del servidor)

// =====================================================================
// PANTALLA: "Mi expediente de titulacion" (lado del ALUMNO)
// ---------------------------------------------------------------------
// Permite al alumno SUBIR POR ADELANTADO los documentos que pide
// titulacion, para que cuando solicite su titulacion ya esten listos y
// solo se validen (no se vuelven a pedir).
//
// CONTRATO CON EL GUARDIAN (Code.gs):
//   expediente_titulacion (GET, matricula)
//     -> { ok, enTitulacion, etapa, documentos:[{tipo,etiqueta,
//          obligatorio,url,estatus,observacion}] }
//   expediente_titulacion_doc (POST: accion, matricula, tipo, base64,
//          mime, nombreArchivo) -> { ok, documento }
// =====================================================================


class MiExpedienteTitulacionScreen extends StatefulWidget {
  final StudentProfile perfil;
  const MiExpedienteTitulacionScreen({super.key, required this.perfil});

  @override
  State<MiExpedienteTitulacionScreen> createState() =>
      _MiExpedienteTitulacionScreenState();
}

class _MiExpedienteTitulacionScreenState
    extends State<MiExpedienteTitulacionScreen> {
  bool _cargando = true;
  String? _error;
  bool _enTitulacion = false;
  String _etapa = '';
  List<Map<String, dynamic>> _docs = [];
  /// Documentos que el alumno ya entregó AL INSCRIBIRSE, traídos de la hoja
  /// de respuestas del formulario de inscripción. Van aparte de _docs porque
  /// NO están validados por control escolar: son material que ya está en la
  /// institución y que el alumno puede reutilizar, no documentos aceptados.
  List<Map<String, dynamic>> _inscripcion = [];
  /// Fotografías para el título. Van aparte de _docs porque su ciclo es
  /// distinto: el alumno elige opción de impresión y control escolar las
  /// dictamina. Hasta hoy el admin las veía y el alumno no.
  Map<String, dynamic>? _fotos;
  String _inscCoincidioPor = '';
  String? _subiendoTipo;
  double? _progresoSubida;
  // (29-sep) Promedio de licenciatura (o nivel anterior): lo pide SIGA.
  final _cPromedio = TextEditingController();
  bool _promedioRequerido = false;
  bool _guardandoPromedio = false;
  // (2-oct) Lo que el servidor tiene guardado y si es solo un valor provisional.
  String _promedioGuardado = '';
  bool _promedioProvisional = false;

  /// ¿Hay un número escrito que todavía NO se guardó? Es la causa más común de
  /// «ya lo capturé y no se refleja»: escribirlo y salir sin pulsar Guardar.
  bool get _hayPromedioSinGuardar {
    final t = _cPromedio.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return false;
    final v = double.tryParse(t);
    final g = double.tryParse(_promedioGuardado);
    if (v == null || g == null) return true;
    return (v - g).abs() > 0.0001;
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cPromedio.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // (ago-29) Se manda el correo de la sesión. El expediente de titulación
      // trae CURP, documentos personales y fotografías: la ruta no puede
      // seguir entregándolo a quien pase una matrícula ajena.
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'expediente_titulacion',
        'matricula': widget.perfil.matricula,
        'correo': await SessionStore.validEmail() ?? '',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _enTitulacion = data['enTitulacion'] == true;
        _etapa = (data['etapa'] ?? '').toString();
        _docs = ((data['documentos'] as List?) ?? [])
            .map((d) => Map<String, dynamic>.from(d as Map))
            .toList();
        _inscripcion = ((data['inscripcion'] as List?) ?? [])
            .map((d) => Map<String, dynamic>.from(d as Map))
            .toList();
        _inscCoincidioPor = (data['inscripcionCoincidioPor'] ?? '').toString();
        _fotos = data['fotos'] == null
            ? null
            : Map<String, dynamic>.from(data['fotos'] as Map);
        final promStr = (data['promedioIngreso'] ?? '').toString();
        _cPromedio.text = promStr.isEmpty ? '' : promStr;
        _promedioRequerido = data['promedioIngresoRequerido'] == true;
        _promedioGuardado = promStr;
        _promedioProvisional = data['promedioIngresoProvisional'] == true;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu expediente. Revisa tu conexion.';
      });
    }
  }

  /// Lo que ya entregaste al inscribirte. Solo aparece si el Guardián pudo
  /// emparejar tu registro por matrícula, CURP o correo — nunca por nombre.
  /// Ficha de las fotografías, con el mismo lenguaje visual que un documento
  /// pero mostrando el motivo cuando se las rechazan — que es justo lo que el
  /// alumno necesita saber para volver a entregarlas.
  Widget _fichaFotos() {
    final f = _fotos;
    if (f == null) return const SizedBox.shrink();
    final estatus = (f['estatus'] ?? 'Pendiente').toString();
    final obs = (f['observacion'] ?? '').toString();
    final url = (f['url'] ?? '').toString();
    final opcion = (f['opcion'] ?? '').toString();
    final rechazado = estatus.toLowerCase().contains('rechaz');
    final aprobado = estatus.toLowerCase().contains('aprob');
    final color = rechazado
        ? const Color(0xFFC62828)
        : (aprobado ? const Color(0xFF1E8E3E) : cessumGold);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: rechazado ? 0.55 : 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_camera_outlined, size: 18, color: color),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Fotografías para el título',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(estatus,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ],
          ),
          if (opcion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(opcion,
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ],
          if (obs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: rechazado
                      ? cessumRed.withValues(alpha: 0.12)
                      : cessumMuted(context).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  rechazado ? 'Debes corregir: $obs' : obs,
                  style: const TextStyle(fontSize: 12, height: 1.35)),
            ),
          ],
          if (url.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () => Helpers.abrirUrlExterna(url, context),
                icon: const Icon(Icons.open_in_new, size: 15),
                label: const Text('Ver lo que entregaste',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
          if (rechazado) ...[
            const SizedBox(height: 4),
            const Text(
                'Vuelve a registrarlas desde Mi titulación.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFFC62828))),
          ],
        ],
      ),
    );
  }

  Widget _seccionInscripcion() {
    if (_inscripcion.isEmpty) return const SizedBox.shrink();
    // Se marcan los que corresponden a un documento que aún no has subido:
    // son los que de verdad te ahorran un trámite.
    final yaSubidos = <String>{};
    for (final d in _docs) {
      if ((d['url'] ?? '').toString().isNotEmpty) {
        yaSubidos.add((d['tipo'] ?? '').toString());
      }
    }
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_shared_outlined,
                  color: cessumGold, size: 20),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('YA LOS ENTREGASTE AL INSCRIBIRTE',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: cessumGold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
              'Encontramos ${_inscripcion.length} documento(s) de tu '
              'inscripción. Ábrelos para revisarlos: si siguen vigentes y '
              'legibles, puedes descargarlos y volver a subirlos aquí sin '
              'buscar los originales.',
              style: const TextStyle(fontSize: 12, height: 1.4)),
          const SizedBox(height: 10),
          ..._inscripcion.map((d) {
            final tipo = (d['tipo'] ?? '').toString();
            final falta = !yaSubidos.contains(tipo);
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: falta
                        ? cessumGold.withValues(alpha: 0.5)
                        : cessumMuted(context).withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(falta ? Icons.download_outlined : Icons.check_circle,
                      size: 18,
                      color: falta ? cessumGold : const Color(0xFF1E8E3E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((d['etiqueta'] ?? 'Documento').toString(),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(
                            falta
                                ? 'Aún no lo has subido a tu expediente'
                                : 'Ya lo tienes en tu expediente',
                            style: TextStyle(
                                fontSize: 11, color: cessumMuted(context))),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () =>
                        Helpers.abrirUrlExterna('${d['url']}', context),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Abrir',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            );
          }),
          if (_inscCoincidioPor.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Tu registro de inscripción se identificó por $_inscCoincidioPor.',
                  style: TextStyle(fontSize: 10.5, color: cessumFaint(context))),
            ),
        ],
      ),
    );
  }

  // (30-sep, Fase 2) Vista previa antes de confirmar: el alumno veía solo
  // el selector de archivo del sistema operativo y, si se equivocaba de
  // foto, se enteraba hasta que Control Escolar la rechazaba días después.
  Future<bool> _confirmarVistaPrevia(
      Uint8List bytes, String mime, String nombre, String etiqueta) async {
    final esImagen = mime.startsWith('image');
    final esPdf = mime.contains('pdf');
    final kb = (bytes.length / 1024).round();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Subir esto como "$etiqueta"?',
            style: const TextStyle(fontSize: 15.5)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (esImagen)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(bytes,
                      height: 220, fit: BoxFit.contain),
                )
              else
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: cessumBg(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                            esPdf
                                ? Icons.picture_as_pdf
                                : Icons.description,
                            size: 44,
                            color: esPdf ? cessumRed : cessumGold),
                        const SizedBox(height: 6),
                        Text(esPdf ? 'Documento PDF' : 'Documento',
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text('$kb KB',
                  style: TextStyle(
                      fontSize: 11, color: cessumMuted(context))),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Elegir otro archivo')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, subir'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _subir(String tipo, String etiqueta) async {
    try {
      final doc = await seleccionarDocumento();
      if (doc == null) return;
      final confirma =
          await _confirmarVistaPrevia(
              Uint8List.fromList(doc.bytes), doc.mime, doc.nombre, etiqueta);
      if (!confirma) return;
      if (!mounted) return;
      setState(() {
        _subiendoTipo = tipo;
        _progresoSubida = 0;
      });
      final payload = {
        'accion': 'expediente_titulacion_doc',
        'matricula': widget.perfil.matricula,
        'correo': await SessionStore.validEmail() ?? '',
        'tipo': tipo,
        'base64': base64Encode(doc.bytes),
        'mime': doc.mime,
        'nombreArchivo': doc.nombre,
      };
      // (30-sep, Fase 2) Progreso REAL de envío, no un spinner indefinido:
      // se manda el cuerpo en trozos y se actualiza la barra conforme se
      // van escribiendo — a diferencia de http.post, un StreamedRequest sí
      // permite saber cuánto se ha enviado.
      final bodyBytes = utf8.encode(jsonEncode(payload));
      final total = bodyBytes.length;
      final request = http.StreamedRequest('POST', Uri.parse(guardianUrl));
      request.headers['Content-Type'] = 'text/plain;charset=utf-8';
      final futureResp = request.send();
      const chunk = 65536;
      var enviado = 0;
      while (enviado < total) {
        final fin = (enviado + chunk < total) ? enviado + chunk : total;
        request.sink.add(bodyBytes.sublist(enviado, fin));
        enviado = fin;
        if (mounted) setState(() => _progresoSubida = enviado / total);
        await Future.delayed(Duration.zero);
      }
      await request.sink.close();
      final streamed = await futureResp.timeout(const Duration(seconds: 180));
      final resp = await http.Response.fromStream(streamed);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _subiendoTipo = null;
        _progresoSubida = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('$etiqueta subido. Quedo listo en tu expediente.'),
      ));
      _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subiendoTipo = null;
        _progresoSubida = null;
      });
      _aviso('No se pudo subir: $e');
    }
  }

  Future<void> _guardarPromedio() async {
    final txt = _cPromedio.text.trim().replaceAll(',', '.');
    final v = double.tryParse(txt);
    if (v == null || v <= 0 || v > 100) {
      _aviso('Escribe un promedio válido, de 0 a 10 (o de 0 a 100).');
      return;
    }
    setState(() => _guardandoPromedio = true);
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'promedio_ingreso_guardar',
        'matricula': widget.perfil.matricula,
        'actor': correo,
        'promedio': txt,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      // El servidor confirma el valor que quedó guardado (por ejemplo 94 → 9.4).
      final guardado = (data['promedio'] as num?)?.toString() ?? txt;
      setState(() {
        _guardandoPromedio = false;
        _promedioRequerido = false;
        _promedioProvisional = false;
        _promedioGuardado = guardado;
        _cPromedio.text = guardado;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('Promedio guardado: $guardado. Gracias por completarlo.'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardandoPromedio = false);
      _aviso('No se pudo guardar: $e');
    }
  }

  Widget _tarjetaPromedio() {
    final tieneValor = _cPromedio.text.trim().isNotEmpty;
    final destacar = _promedioRequerido && !tieneValor;
    final color = destacar ? cessumRed : cessumGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: destacar
            ? cessumRed.withValues(alpha: 0.08)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grade_outlined, size: 18, color: color),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Promedio de licenciatura (o nivel anterior)',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              destacar
                  ? (_promedioProvisional
                      ? 'Tenemos un valor provisional mientras recibimos el '
                          'tuyo. Anota tu promedio tal como aparece en tu '
                          'certificado o kardex de estudios y pulsa «Guardar promedio».'
                      : 'Nos falta este dato para tu expediente ante la '
                          'autoridad educativa. Anótalo tal como aparece en tu '
                          'certificado o kardex de estudios y pulsa «Guardar promedio».')
                  : 'Puedes actualizarlo si lo capturamos mal.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _cPromedio,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  // (2-oct) El visto bueno del teclado también guarda.
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _guardarPromedio(),
                  decoration: const InputDecoration(
                    hintText: 'Ej. 8.7',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              _guardandoPromedio
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cessumRed))
                  : Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _guardarPromedio,
                        icon: const Icon(Icons.save_outlined, size: 17),
                        label: const Text('Guardar promedio',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 8),
          if (_hayPromedioSinGuardar)
            Text('Aún no lo has guardado: pulsa «Guardar promedio».',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange.shade800))
          else if (_promedioGuardado.isNotEmpty)
            Text('Guardado: $_promedioGuardado',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E7D32))),
        ],
      ),
    );
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Color _colorDoc(String e) {
    if (e == 'Validado' || e == 'Aprobado') return Colors.green.shade700;
    if (e == 'Rechazado') return cessumRed;
    if (e.isEmpty) return cessumFaint(context);
    return Colors.orange.shade800; // Pre-cargado / En revision
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // (2-oct) Si hay un promedio escrito y sin guardar, se avisa antes de salir.
      canPop: !_hayPromedioSinGuardar,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final salir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Promedio sin guardar'),
            content: const Text(
                'Escribiste tu promedio pero todavía no lo has guardado. '
                'Si sales ahora, no se registrará.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Volver y guardar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salir sin guardar'),
              ),
            ],
          ),
        );
        if (salir == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Mi expediente de titulacion'),
        ),
        body: _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: cessumRed),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargar,
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                child: const Text('Reintentar',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final obligatorios = _docs.where((d) => d['obligatorio'] == true).toList();
    final completados = obligatorios.where((d) {
      final u = (d['url'] ?? '') as String;
      final st = (d['estatus'] ?? '') as String;
      return u.isNotEmpty && st != 'Rechazado';
    }).length;
    final totalObl = obligatorios.length;
    final avance = totalObl > 0 ? completados / totalObl : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _intro(),
        if (_enTitulacion) _bannerTitulacion(),
        const SizedBox(height: 12),
        _tarjetaAvance(completados, totalObl, avance),
        _tarjetaPromedio(),
        _queSigue(),
        const SizedBox(height: 6),
        ..._docs.map(_fichaDoc),
        _fichaFotos(),
        _seccionInscripcion(),
        const SizedBox(height: 8),
        Text(
          'Formatos aceptados: imagen, PDF o Word (.doc/.docx) (max. 8 MB). Los documentos '
          'con * son obligatorios. Subirlos por adelantado agiliza tu '
          'titulacion: cuando la solicites, ya estaran listos para validacion.',
          style: TextStyle(
              fontSize: 11.5, color: cessumMuted(context), height: 1.45),
        ),
      ],
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_shared, color: cessumGold, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Adelanta tus documentos de titulacion. Asi, cuando inicies tu '
              'proceso, ${widget.perfil.nombreCompleto.split(' ').first}, ya '
              'estaran cargados y solo faltara validarlos.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.4, color: cessumInk(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerTitulacion() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
        ),
        child: Text(
          'Tu expediente ya forma parte de tu proceso de titulación'
          '${_etapa.isNotEmpty ? ' (etapa: $_etapa)' : ''}. '
          'Puedes seguir subiendo y corrigiendo tus documentos aquí mismo.',
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
      ),
    );
  }

  Widget _tarjetaAvance(int completados, int totalObl, double avance) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Avance de tu expediente',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: cessumRed)),
              Text('${(avance * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: cessumGold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: avance,
              minHeight: 10,
              backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(cessumGold),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$completados de $totalObl documentos obligatorios listos'
            '${avance >= 1.0 ? ' · ¡Expediente completo!' : ''}',
            style: TextStyle(fontSize: 12, color: cessumMuted(context)),
          ),
        ],
      ),
    );
  }

  /// (ago-9) QUÉ LE TOCA HACER, DICHO EN UNA FRASE.
  /// Antes esta pantalla mostraba una lista de estatus y el alumno tenía que
  /// deducir su siguiente paso: cuáles faltan, cuáles le rechazaron y por
  /// qué. Un trámite de titulación se abandona por esa fricción, no por
  /// falta de ganas. Aquí se le dice en concreto, priorizando lo que lo
  /// tiene detenido: primero lo rechazado (que ya trae instrucciones del
  /// revisor), luego lo que falta por subir.
  Widget _queSigue() {
    final rechazados = <String>[];
    final rechazadosConObs = <Map<String, String>>[];
    final faltantes = <String>[];
    for (final d in _docs) {
      if (d['obligatorio'] != true) continue;
      final st = (d['estatus'] ?? '').toString();
      final url = (d['url'] ?? '').toString();
      final etq = (d['etiqueta'] ?? 'Documento').toString();
      if (st == 'Rechazado') {
        rechazados.add(etq);
        rechazadosConObs.add(
            {'etiqueta': etq, 'observacion': (d['observacion'] ?? '').toString()});
      } else if (url.isEmpty) {
        faltantes.add(etq);
      }
    }
    // Las fotografías cuentan igual: son parte del expediente aunque vayan
    // por otra vía.
    final fo = _fotos;
    if (fo != null) {
      final fe = (fo['estatus'] ?? '').toString().toLowerCase();
      if (fe.contains('rechaz')) {
        rechazados.add('Fotografías para el título');
        rechazadosConObs.add({
          'etiqueta': 'Fotografías para el título',
          'observacion': (fo['observacion'] ?? '').toString(),
        });
      }
    }

    final enRevision = _docs.where((d) =>
        (d['estatus'] ?? '') == 'En revisión' &&
        (d['url'] ?? '').toString().isNotEmpty).length;

    // Todo entregado y nada rechazado: se le dice, en vez de dejarlo con la
    // duda de si falta algo.
    if (rechazados.isEmpty && faltantes.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E8E3E).withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFA8CDA8)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified, color: Color(0xFF1E7B34), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ya entregaste todo lo obligatorio',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B5E20))),
                  const SizedBox(height: 3),
                  Text(
                      enRevision > 0
                          ? 'Control Escolar está revisando tu expediente. '
                              'Te avisamos por correo en cuanto haya novedad; '
                              'no necesitas hacer nada más por ahora.'
                          : 'Tu expediente está completo. Cualquier cambio te '
                              'llegará por correo.',
                      style: const TextStyle(fontSize: 12.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final urge = rechazados.isNotEmpty;
    final color = urge ? const Color(0xFFC62828) : cessumGold;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: urge ? cessumRed.withValues(alpha: 0.12) : cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(urge ? Icons.priority_high : Icons.checklist_rtl,
                  color: color, size: 20),
              const SizedBox(width: 6),
              Text('QUÉ TE FALTA',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: color)),
            ],
          ),
          const SizedBox(height: 8),
          if (rechazados.isNotEmpty) ...[
            // (30-sep, Fase 2) Antes solo se nombraba QUÉ se rechazó — había
            // que bajar hasta la tarjeta de ese documento para saber POR QUÉ.
            // Ahora el motivo va aquí mismo, arriba de todo.
            for (final r in rechazadosConObs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${r['etiqueta']}: ',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    TextSpan(
                        text: (r['observacion'] ?? '').isNotEmpty
                            ? r['observacion']
                            : 'te lo devolvieron; vuelve a subirlo.',
                        style: const TextStyle(fontSize: 13, height: 1.4)),
                  ]),
                ),
              ),
            if (faltantes.isNotEmpty) const SizedBox(height: 4),
          ],
          if (faltantes.isNotEmpty)
            Text(
                faltantes.length == 1
                    ? 'Te falta subir: ${faltantes.first}.'
                    : 'Te faltan ${faltantes.length} documentos: '
                        '${faltantes.join(', ')}.',
                style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 8),
          Text(
              'Súbelos aquí mismo, en las tarjetas de abajo. En cuanto '
              'completes lo obligatorio, tu expediente pasa solo a revisión '
              'de la Dirección.',
              style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: Colors.black.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  Widget _fichaDoc(Map<String, dynamic> d) {
    final estatus = (d['estatus'] ?? '') as String;
    final url = (d['url'] ?? '') as String;
    final obs = (d['observacion'] ?? '') as String;
    final tipo = (d['tipo'] ?? '') as String;
    final etiqueta = (d['etiqueta'] ?? '') as String;
    final oblig = d['obligatorio'] == true;
    final subiendo = _subiendoTipo == tipo;
    // (7-sep) SE PUEDE REEMPLAZAR MIENTRAS NO ESTÉ ACEPTADO.
    // Antes el botón solo aparecía si no había nada subido o si el documento
    // estaba formalmente «Rechazado». Eso dejaba atorada a quien subía el
    // archivo equivocado, o a quien —como en «Fotografías para el título»,
    // que en realidad son dos piezas— completaba solo una parte: el sistema
    // le decía «Incompleto, falta la fotografía» y al mismo tiempo le quitaba
    // la forma de subirla.
    // Un documento en revisión todavía es del alumno: puede corregirlo. Solo
    // deja de poder cuando Vicerrectoría lo acepta.
    final estN = estatus.toLowerCase();
    final yaAceptado = estN.contains('acept') ||
        estN.contains('valid') ||
        estN.contains('aprob');
    // (30-sep, Fase 1) YA NO SE DESACTIVA al tener solicitud formal. Ese
    // candado (8-sep) existía porque lo subido aquí se perdía una vez
    // presentada la solicitud — eso se corrigió en el backend ese mismo día
    // (expedienteTitulacionSubir ya escribe también en la hoja de Titulación
    // cuando existe, y desde hoy corre la misma revisión con IA que el otro
    // camino). Mantener el candado aquí ya solo fragmentaba la experiencia:
    // mandaba al alumno a otra pantalla sin necesidad real.
    final puedeEste = url.isEmpty || !yaAceptado;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etiqueta + (oblig ? ' *' : ' (opcional)'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    url.isEmpty
                        ? 'Sin subir'
                        : estatus + (obs.isNotEmpty ? ' · $obs' : ''),
                    style: TextStyle(
                        fontSize: 11.5,
                        color: _colorDoc(url.isEmpty ? '' : estatus),
                        fontWeight: FontWeight.w600,
                        height: 1.35),
                  ),
                  if (url.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 28)),
                        onPressed: () =>
                            Helpers.abrirUrlExterna(url, context),
                        icon: const Icon(Icons.visibility,
                            size: 15, color: cessumGold),
                        label: const Text('Ver documento',
                            style:
                                TextStyle(color: cessumGold, fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
            if (subiendo)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cessumRed,
                        // (30-sep, Fase 2) value real en vez de spinner
                        // indefinido — null solo mientras arranca el envío.
                        value: (_progresoSubida != null && _progresoSubida! > 0)
                            ? _progresoSubida
                            : null,
                      ),
                    ),
                    if (_progresoSubida != null && _progresoSubida! > 0) ...[
                      const SizedBox(width: 6),
                      Text('${(_progresoSubida! * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 11, color: cessumRed)),
                    ],
                  ],
                ),
              )
            else if (puedeEste)
              TextButton.icon(
                onPressed: () => _subir(tipo, etiqueta),
                icon: const Icon(Icons.upload_file, size: 17, color: cessumRed),
                label: Text(
                    url.isEmpty
                        ? 'Subir'
                        : (estatus == 'Rechazado' ? 'Re-subir' : 'Reemplazar'),
                    style: const TextStyle(color: cessumRed, fontSize: 12.5)),
              )
            else
              const Icon(Icons.check_circle, color: Colors.green, size: 22),
          ],
        ),
      ),
    );
  }
}

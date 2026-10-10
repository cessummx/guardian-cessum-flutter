// ============================================================
//  REINGRESO · pantalla del alumno dado de baja  ·  (ago-27)
//  ------------------------------------------------------------
//  QUIÉN LA VE
//  Solo quien está dado de baja. A todos los demás no les aparece nunca: una
//  opción de «reintegrarse» en el menú de alguien inscrito confunde y asusta.
//
//  POR QUÉ ESTÁ ESCRITA ASÍ
//  Quien vuelve después de una baja suele llegar apenado y con la sensación
//  de que va a tener que dar explicaciones. La pantalla evita eso: no pregunta
//  por qué se fue, no juzga, y dice desde la primera línea que reintegrarse es
//  un derecho con un procedimiento, no un favor que se pide.
//
//  Los tres documentos se piden de uno en uno, no todos de golpe. Una lista de
//  tres requisitos al inicio hace que la gente cierre la pantalla; un solo
//  paso a la vez, con el siguiente ya visible, se completa.
// ============================================================

import 'dart:convert';
import 'dart:html' as html;   // la app es Flutter web; así sube el resto

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';        // cessumRed, cessumGold
import 'cessum_ui.dart';        // cessumBg, cessumMuted
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'convenios_alumno_screen.dart';

class ReingresoAlumnoScreen extends StatefulWidget {
  final String matricula;
  const ReingresoAlumnoScreen({super.key, required this.matricula});

  @override
  State<ReingresoAlumnoScreen> createState() => _ReingresoAlumnoScreenState();
}

/* (21-sep) DATOS DE PAGO DEL KÁRDEX.
   El kárdex se cobra también en el reingreso —es regla institucional—, pero
   esta pantalla decía «tiene un costo de $100» y nada más: ni banco, ni
   cuenta, ni dónde mandar el comprobante. Una alumna terminó preguntando por
   WhatsApp a dónde pagar, con toda razón. Son los mismos datos que usa el
   resto del sistema para cobros. */
const _pagoBanco = 'BBVA';
const _pagoBeneficiario = 'Centro de Estudios Superiores del Mayo';
const _pagoCuenta = '0120887013';
const _pagoClabe = '012777001208870132';

class _ReingresoAlumnoScreenState extends State<ReingresoAlumnoScreen> {
  bool _cargando = true;
  bool _enviando = false;

  // Comprobante del pago del kárdex. El trámite ya aceptaba el comprobante
  // adjunto; lo que faltaba era ofrecer dónde subirlo.
  String? _compB64;
  String? _compMime;
  String? _compNombre;
  String _error = '';
  Map<String, dynamic> _d = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'reingreso_elegible',
        'matricula': widget.matricula,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
        if (d['ok'] != true) _error = '${d['error'] ?? 'No se pudo consultar.'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo consultar tu situación. Intenta de nuevo.';
      });
    }
  }

  /// (8-sep) PEDIR EL DOCUMENTO SIN SALIR DE AQUÍ.
  ///
  /// El paso 1 decía «solicítalo en el menú, en Trámites y documentos». Pero
  /// quien está dado de baja NO TIENE MENÚ: al entrar, menu_screen lo
  /// reemplaza por CuentaBajaScreen, que solo ofrece escribir a Vicerrectoría
  /// o salir. La instrucción lo mandaba a un lugar al que no puede llegar, y
  /// el trámite se atoraba en su primer paso para exactamente el público al
  /// que va dirigido. Dos alumnas escribieron por WhatsApp diciendo que «la
  /// plataforma no me permite solicitarlo»; tenían razón.
  ///
  /// Se usa la MISMA acción `tramite_enviar` y las mismas etiquetas exactas
  /// del catálogo de trámites, porque de esas etiquetas depende que el
  /// backend reconozca el tipo y aplique su tarifa.
  bool _tieneCosto(String tipo) => tipo.contains(r'$') && !tipo.contains(r'$0');

  /// El comprobante del pago. Mismo mecanismo que el resto de las subidas
  /// de esta pantalla (dart:html), para no agregar dependencias.
  Future<void> _elegirComprobante() async {
    final input = html.FileUploadInputElement()
      ..accept = 'application/pdf,image/*';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;
    final file = input.files!.first;
    if (file.size > 8 * 1024 * 1024) {
      _aviso('El comprobante pesa más de 8 MB. Mándalo más ligero.', false);
      return;
    }
    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first;
    final dataUrl = reader.result as String;
    final coma = dataUrl.indexOf(',');
    if (coma < 0) return;
    if (!mounted) return;
    setState(() {
      _compB64 = dataUrl.substring(coma + 1);
      _compMime = file.type.isNotEmpty ? file.type : 'image/jpeg';
      _compNombre = file.name;
    });
  }

  Future<void> _pedirDocumento(String tipoTramite, String comoSeLlama) async {
    /* Sin comprobante no se manda: evita justo la vuelta de pedírselo
       después por WhatsApp. */
    if (_tieneCosto(tipoTramite) && _compB64 == null) {
      _aviso('Primero adjunta el comprobante de tu pago de \$100.', false);
      return;
    }
    setState(() => _enviando = true);
    try {
      final payload = <String, dynamic>{
        'accion': 'tramite_enviar',
        'nombre': '${_d['nombre'] ?? ''}',
        'matricula': widget.matricula,
        'correo': '${_d['correo'] ?? ''}',
        'programa': '${_d['programa'] ?? ''}',
        'generacion': '${_d['generacion'] ?? ''}',
        'tipoTramite': tipoTramite,
        'observaciones': 'SOLICITUD DE TRAMITE ESCOLAR. Tipo: $tipoTramite. '
            'Solicitado desde el trámite de reingreso'
            '${_d['folio'] != null ? ' (folio ${_d['folio']})' : ''}. '
            'El alumno está dado de baja y no tiene acceso al menú de trámites.'
            // Los datos de pago viajan también aquí, para que la tarjeta
            // que ve Vicerrectoría diga lo mismo que vio el alumno.
            '${_tieneCosto(tipoTramite) ? ' PAGO: $_pagoBanco, cuenta $_pagoCuenta, CLABE $_pagoClabe, concepto "Kárdex ${widget.matricula}". ${_compB64 != null ? "Comprobante adjunto." : "SIN comprobante adjunto."}' : ''}',
        if (_compB64 != null && _tieneCosto(tipoTramite)) ...{
          'comprobantePagoBase64': _compB64,
          'comprobantePagoMime': _compMime ?? 'image/jpeg',
        },
      };
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _enviando = false);
      // Un alumno de baja bien puede traer adeudo, y ese candado lo dejaría
      // atorado igual que antes. Se le dice qué hacer, no solo que no se pudo.
      if (d['bloqueoNoAdeudo'] == true) {
        _aviso(
            'Tu solicitud no pudo entrar porque hay un adeudo registrado. '
            'Escríbele a Vicerrectoría para revisarlo: es justo lo que el '
            'informe financiero sirve para aclarar.',
            false);
        return;
      }
      _aviso(
          d['ok'] == true
              ? 'Listo. Pedimos tu $comoSeLlama; te llega por correo y luego '
                  'lo subes aquí.'
              : '${d['error'] ?? 'No se pudo enviar la solicitud.'}',
          d['ok'] == true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No se pudo enviar la solicitud. Intenta de nuevo.', false);
    }
  }

  Future<void> _iniciar() async {
    setState(() => _enviando = true);
    try {
      final r = await http.post(
        Uri.parse(guardianUrl).replace(
            queryParameters: {'accion': 'reingreso_iniciar'}),
        body: jsonEncode({
          'accion': 'reingreso_iniciar',
          'matricula': widget.matricula,
        }),
      ).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso(d['nota'] ?? d['error'] ?? 'Sin respuesta.', d['ok'] == true);
      if (d['ok'] == true) _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No se pudo iniciar la solicitud. Intenta de nuevo.', false);
    }
  }

  /// Sube uno de los tres documentos. Se hace de uno en uno a propósito:
  /// pedir los tres juntos hace que se posponga el trámite entero.
  Future<void> _subir(String tipo, String folio) async {
    // Se usa dart:html como el resto de las pantallas que suben archivos:
    // file_picker no está en el proyecto y agregarlo rompería el build.
    final input = html.FileUploadInputElement()
      ..accept = 'application/pdf,image/*,.doc,.docx';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;
    final file = input.files!.first;

    if (file.size > 8 * 1024 * 1024) {
      _aviso('El archivo pesa más de 8 MB. Mándalo más ligero.', false);
      return;
    }

    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first;
    final dataUrl = reader.result as String;   // data:tipo;base64,XXXX
    final coma = dataUrl.indexOf(',');
    if (coma < 0) return;
    final b64 = dataUrl.substring(coma + 1);
    final mime = file.type.isNotEmpty ? file.type : 'application/pdf';

    if (!mounted) return;
    setState(() => _enviando = true);
    try {
      final r = await http.post(
        Uri.parse(guardianUrl).replace(
            queryParameters: {'accion': 'reingreso_documento'}),
        body: jsonEncode({
          'accion': 'reingreso_documento',
          'folio': folio,
          'tipo': tipo,
          'archivoBase64': b64,
          'mime': mime,
        }),
      ).timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso(d['nota'] ?? d['error'] ?? 'Sin respuesta.', d['ok'] == true);
      if (d['ok'] == true) _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No se pudo subir el archivo. Intenta de nuevo.', false);
    }
  }

  void _aviso(String t, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: ok ? Colors.green.shade700 : cessumRed,
      duration: const Duration(seconds: 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Volver a estudiar',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? _mensajeError()
              : (_d['elegible'] != true ? _noAplica() : _contenido()),
    );
  }

  Widget _mensajeError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      );

  Widget _noAplica() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '${_d['motivo'] ?? 'Esta pantalla es para alumnos dados de baja.'}',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumMuted(context)),
          ),
        ),
      );

  Widget _contenido() {
    final enCurso = _d['enCurso'] as Map<String, dynamic>?;
    final pasos = ((_d['pasos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final aviso = '${_d['aviso'] ?? ''}';

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // El encabezado no pregunta por qué se fue. Dice que puede volver.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border(
                  left: BorderSide(color: cessumRed, width: 4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Puedes volver a estudiar',
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: cessumRed)),
                const SizedBox(height: 6),
                const Text(
                  'Tu lugar en el CESSUM no se cerró. Reintegrarte es un '
                  'trámite con pasos claros, no un favor que tengas que pedir: '
                  'aquí te decimos exactamente qué sigue y qué va a costar, '
                  'sin sorpresas.',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_d['nombre'] ?? ''} · ${_d['programa'] ?? ''}'
                  '${_d['generacion'] != null ? ' · ${_d['generacion']}' : ''}',
                  style: TextStyle(
                      fontSize: 12.5, color: cessumMuted(context)),
                ),
              ],
            ),
          ),

          if (aviso.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border(
                    left: BorderSide(color: Colors.amber.shade800, width: 3)),
              ),
              child: Text(aviso,
                  style: const TextStyle(fontSize: 13.5, height: 1.45)),
            ),
          ],

          const SizedBox(height: 22),

          if (enCurso == null) ...[
            const Text(
              'Qué va a pasar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // (ago-29) Lo primero, antes de los cinco pasos.
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.groups_outlined,
                      size: 19, color: Color(0xFFB07D12)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Vicerrectoría define a qué grupo regresas',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              height: 1.35),
                        ),
                        SizedBox(height: 4),
                        // (4-oct-2026) Antes decía siempre «con un grupo distinto al tuyo». Si tu grupo sigue en curso, regresas a él.
                        Text(
                          'Si tu grupo sigue en curso, te reincorporas a él; si ya '
                          'avanzó demasiado, te integras a uno que esté en curso y '
                          'llevas su calendario. Tu convenio lo dirá con claridad '
                          'antes de que lo firmes.',
                          style: TextStyle(
                              fontSize: 12.5, height: 1.5, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _explicacion(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enviando ? null : _iniciar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_enviando ? 'Iniciando…' : 'Quiero reintegrarme',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Iniciar la solicitud no te compromete a nada. Puedes ver los '
              'costos antes de decidir.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
            ),
          ] else ...[
            Row(children: [
              Text('Tu solicitud',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: cessumRed)),
              const Spacer(),
              Text('${enCurso['folio'] ?? ''}',
                  style: TextStyle(
                      fontSize: 12.5, color: cessumMuted(context))),
            ]),
            const SizedBox(height: 4),
            Text('Estado: ${enCurso['estado'] ?? ''}',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            _lineaDeTiempo(enCurso),
            const SizedBox(height: 16),
            if (enCurso['convenioFirmado'] != true) ...pasos.map((p) => _paso(p, enCurso)),
            if ('${enCurso['convenio'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 18),
              _convenio('${enCurso['convenio']}'),
              const SizedBox(height: 12),
              _firmaOSiguiente(enCurso),
            ],
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _explicacion() {
    /* (ago-29) LA CONDICIÓN DE LA GENERACIÓN, DICHA AL PRINCIPIO.
     *
     * El convenio incluye una cláusula donde el alumno acepta que NO vuelve
     * a su generación: se integra a una que ya va en curso y lleva sus
     * fechas. Es la condición que más cambia su vida —no vuelve con sus
     * compañeros— y estaba solo en la letra del convenio, al final.
     *
     * Esta pantalla promete "sin sorpresas". Guardarse eso para la firma la
     * convertía en una promesa falsa. Va arriba, antes de los pasos, y se
     * repite en el paso donde ocurre.
     */
    const pasos = [
      ['1', 'Solicitas tu kárdex',
        'Es el documento con las materias que ya acreditaste. Sin él no se '
            'puede saber qué te falta.'],
      ['2', 'Solicitas tu informe financiero',
        'Para revisar juntos si quedó algún adeudo. Es mejor saberlo ahora '
            'que cuando vayas a titularte.'],
      ['3', 'Firmas tu solicitud',
        'La escribes, la firmas y la subes aquí en foto o PDF. Abajo te '
            'decimos qué debe decir.'],
      ['4', 'Vicerrectoría resuelve',
        'Con tus calificaciones a la vista. Ahí se define a qué grupo te '
            'integras, y te avisamos por correo.'],
      ['5', 'Firmas el convenio',
        'Ahí quedan por escrito las materias que debes recursar, su costo, '
            'tu plan de pagos y el grupo al que entras.'],
    ];
    return Column(
      children: pasos.map((p) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                  color: cessumRed, borderRadius: BorderRadius.circular(13)),
              alignment: Alignment.center,
              child: Text(p[0],
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p[1],
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w600)),
                  Text(p[2],
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: cessumMuted(context))),
                ],
              ),
            ),
          ]),
        );
      }).toList(),
    );
  }

  Widget _paso(Map<String, dynamic> p, Map<String, dynamic> enCurso) {
    final hecho = p['hecho'] == true;
    final n = p['n'] as int;
    final folio = '${enCurso['folio'] ?? ''}';

    // Solo el paso pendiente muestra su botón. Enseñar los tres a la vez hace
    // que se pospongan los tres.
    final esElSiguiente = !hecho &&
        (n == 1 ||
            (n == 2 && enCurso['kardex'] == true) ||
            (n == 3 && enCurso['informe'] == true));

    String? tipo;
    String? etiqueta;
    if (n == 1) {
      tipo = 'kardex';
      etiqueta = 'Subir mi kárdex';
    } else if (n == 2) {
      tipo = 'financiero';
      etiqueta = 'Subir mi informe financiero';
    } else if (n == 3) {
      tipo = 'solicitud';
      etiqueta = 'Subir mi solicitud firmada';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hecho
            ? Colors.green.withValues(alpha: 0.06)
            : (esElSiguiente ? Colors.white : Colors.grey.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: hecho
              ? Colors.green.withValues(alpha: 0.35)
              : (esElSiguiente
                  ? cessumRed.withValues(alpha: 0.35)
                  : Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              hecho ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 19,
              color: hecho
                  ? Colors.green.shade600
                  : (esElSiguiente ? cessumRed : Colors.grey),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${p['paso'] ?? ''}',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: esElSiguiente || hecho
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: hecho || esElSiguiente
                        ? null
                        : cessumMuted(context),
                  )),
            ),
          ]),
          if (esElSiguiente && tipo != null) ...[
            const SizedBox(height: 6),
            // (ago-29) Cada paso dice DONDE se consigue el documento. El
            // paso 2 no tenía ninguna indicación: el alumno llegaba, veía
            // "Subir mi informe financiero" y no sabía de dónde sacarlo.
            if (n == 1)
              Padding(
                padding: const EdgeInsets.only(left: 27, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tiene un costo de \$100. Primero haz el pago, adjunta '
                      'tu comprobante y luego solicítalo. Te llega por correo '
                      'y después lo subes en este mismo paso.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cessumMuted(context),
                          height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    _datosDePago(),
                    const SizedBox(height: 10),
                    // Paso: adjuntar comprobante
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _compB64 != null
                              ? const Color(0xFF1E7F52)
                              : cessumRed,
                          side: BorderSide(
                              color: _compB64 != null
                                  ? const Color(0xFF1E7F52)
                                  : cessumRed)),
                      onPressed: _enviando ? null : _elegirComprobante,
                      icon: Icon(
                          _compB64 != null
                              ? Icons.check_circle
                              : Icons.upload_file,
                          size: 17),
                      label: Text(
                          _compB64 != null
                              ? 'Comprobante: ${_compNombre ?? "listo"}'
                              : 'Adjuntar mi comprobante de pago',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5)),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: cessumRed),
                      onPressed: (_enviando || _compB64 == null)
                          ? null
                          : () => _pedirDocumento(
                              'Kardex digital o físico (\$100.00 MXN)',
                              'kárdex'),
                      icon: const Icon(Icons.mail_outline, size: 17),
                      label: const Text('Solicitar mi kárdex',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            if (n == 2)
              Padding(
                padding: const EdgeInsets.only(left: 27, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Es el estado de cuenta con tus pagos registrados. '
                      'Pídelo desde aquí; no tiene costo. Te llega por correo '
                      'y luego lo subes en este paso.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cessumMuted(context),
                          height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed)),
                      onPressed: _enviando
                          ? null
                          : () => _pedirDocumento(
                              'Informe financiero (gratuita)',
                              'informe financiero'),
                      icon: const Icon(Icons.mail_outline, size: 17),
                      label: const Text('Solicitar mi informe financiero',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            if (n == 3)
              Padding(
                padding: const EdgeInsets.only(left: 27, bottom: 8),
                child: Text(
                  'No hay formato que descargar: la escribes tú, a mano o en '
                  'computadora, y la firmas. Debe decir tu nombre completo, '
                  'tu matrícula, tu programa, que solicitas reintegrarte y el '
                  'motivo por el que interrumpiste. Súbela en foto o PDF, '
                  'legible y completa.',
                  style: TextStyle(
                      fontSize: 12.5, color: cessumMuted(context), height: 1.4),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 27),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      _enviando ? null : () => _subir(tipo!, folio),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(_enviando ? 'Subiendo…' : etiqueta!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: BorderSide(color: cessumRed.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /* ── (4-oct-2026) LÍNEA DE TIEMPO DEL REINGRESO ──────────────────────────────────────────────────────────────────────────
     El alumno veía los pasos de los documentos y, si había convenio, el texto; nada le decía qué faltaba después. Ahora ve los seis
     momentos del trámite y en cuál va, incluido el convenio de pago, que es lo que le permite regularizar el adeudo. */
  Widget _lineaDeTiempo(Map<String, dynamic> e) {
    final est = '${e['estado'] ?? ''}';
    final docs = e['kardex'] == true && e['informe'] == true && e['solicitud'] == true;
    final autorizada = est == 'Autorizada';
    final firmado = e['convenioFirmado'] == true;
    final cp = e['convenioPago'] is Map ? Map<String, dynamic>.from(e['convenioPago'] as Map) : null;
    final cpEst = '${cp?['estado'] ?? ''}'.toLowerCase();
    final cpVigente = cp != null && (cpEst.contains('acept') || cpEst.contains('aprob') || cpEst.contains('vigente') || cpEst.contains('firm'));
    final grupo = '${e['grupoDestino'] ?? ''}';
    final genD = '${e['generacionDestino'] ?? ''}';
    final pasos = <List<dynamic>>[
      ['Solicitud iniciada', true, 'Folio ${e['folio'] ?? ''}'],
      ['Documentos completos', docs, 'Kárdex, informe financiero y solicitud firmada'],
      ['Dictamen de Vicerrectoría', autorizada, autorizada ? (grupo.isNotEmpty ? 'Regresas al grupo $grupo${genD.isNotEmpty ? ' · $genD' : ''}' : 'Autorizada') : (est.isEmpty ? 'En revisión' : est)],
      ['Firma del convenio y reactivación', firmado, firmado ? 'Firmado el ${e['firmadoEn'] ?? ''}' : 'Lo firmas aquí mismo cuando esté autorizado'],
      ['Convenio de pago', cpVigente, cp == null ? 'Lo solicitas en «Convenios» después de firmar' : 'Solicitud: ${cp['estado']}'],
      ['Al corriente', false, 'Con tu convenio de pago al día se habilitan las materias pendientes'],
    ];
    int actual = pasos.indexWhere((p) => p[1] != true);
    if (actual < 0) actual = pasos.length - 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tu avance', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        for (var i = 0; i < pasos.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(pasos[i][1] == true ? Icons.check_circle : (i == actual ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  size: 19, color: pasos[i][1] == true ? Colors.green.shade700 : (i == actual ? cessumRed : Colors.black26)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${pasos[i][0]}', style: TextStyle(fontSize: 13.5, fontWeight: i == actual ? FontWeight.w800 : FontWeight.w600,
                    color: pasos[i][1] == true || i == actual ? Colors.black87 : Colors.black45)),
                Text('${pasos[i][2]}', style: TextStyle(fontSize: 12, height: 1.35, color: cessumMuted(context))),
              ])),
            ]),
          ),
      ]),
    );
  }

  /// Debajo del convenio: si ya está autorizado y no se ha firmado, la aceptación expresa y el botón de firmar (antes no había ninguna
  /// forma de firmarlo desde la app, y sin firma no hay reactivación). Si ya se firmó, el siguiente paso: el convenio de pago.
  bool _aceptoConvenio = false;
  Widget _firmaOSiguiente(Map<String, dynamic> e) {
    final firmado = e['convenioFirmado'] == true;
    if (!firmado && '${e['estado'] ?? ''}' != 'Autorizada') {
      return Text('Este es el convenio propuesto. Podrás firmarlo cuando Vicerrectoría autorice tu reingreso.',
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context)));
    }
    if (!firmado) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _aceptoConvenio,
          activeColor: cessumRed,
          onChanged: _enviando ? null : (v) => setState(() => _aceptoConvenio = v == true),
          title: const Text('Leí el convenio completo y acepto sus cláusulas.', style: TextStyle(fontSize: 13.5)),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (!_aceptoConvenio || _enviando) ? null : () => _firmar('${e['folio'] ?? ''}'),
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            icon: const Icon(Icons.draw_outlined),
            label: Text(_enviando ? 'Firmando…' : 'Firmar mi convenio de reincorporación', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 6),
        Text('Al firmar, tu inscripción se reactiva y queda guardado el texto exacto que aceptaste.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ]);
    }
    final cp = e['convenioPago'] is Map ? Map<String, dynamic>.from(e['convenioPago'] as Map) : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: Colors.green.shade700, width: 3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Convenio firmado${'${e['firmadoEn'] ?? ''}'.isNotEmpty ? ' el ${e['firmadoEn']}' : ''}. Tu inscripción quedó reactivada.',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(cp == null
                ? 'Siguiente paso: solicita tu convenio de pago para acordar cómo cubrirás el adeudo anterior a tu baja.'
                : 'Tu solicitud de convenio de pago está en estado: ${cp['estado']}.',
            style: const TextStyle(fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => _irAConvenioPago(e),
          style: ElevatedButton.styleFrom(backgroundColor: cessumGold, foregroundColor: Colors.white),
          icon: const Icon(Icons.handshake_outlined, size: 18),
          label: Text(cp == null ? 'Solicitar convenio de pago' : 'Ver mi convenio de pago'),
        ),
      ]),
    );
  }

  Future<void> _firmar(String folio) async {
    if (folio.isEmpty) return;
    setState(() => _enviando = true);
    try {
      final r = await http.post(
        Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'reingreso_convenio_firmar'}),
        body: jsonEncode({'accion': 'reingreso_convenio_firmar', 'folio': folio, 'acepto': '1', 'matricula': widget.matricula}),
      ).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('${d['nota'] ?? d['error'] ?? 'Sin respuesta.'}', d['ok'] == true);
      if (d['ok'] == true) await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No se pudo registrar la firma. Intenta de nuevo.', false);
    }
  }

  void _irAConvenioPago(Map<String, dynamic> e) {
    final cp = e['convenioPago'];
    Navigator.push(context, MaterialPageRoute(builder: (_) => ConveniosAlumnoScreen(
      matricula: widget.matricula,
      abrirSolicitud: cp == null,
      mensajeInicial: 'Me reincorporo con el folio de reingreso ${e['folio'] ?? ''} y solicito un convenio para cubrir el adeudo anterior a mi baja.',
    ))).then((_) => _cargar());
  }

  Widget _convenio(String texto) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(11),
        border: Border(
            left: BorderSide(color: cessumGold, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tu convenio de reincorporación',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: cessumGold)),
          const SizedBox(height: 8),
          SelectableText(texto,
              style: const TextStyle(fontSize: 12.5, height: 1.5)),
        ],
      ),
    );
  }

  /// Los datos para el pago, con botón de copiar en lo que se teclea: una
  /// CLABE de 18 dígitos copiada a mano es la forma más segura de que el
  /// pago se pierda.
  Widget _datosDePago() {
    Widget fila(String etiqueta, String valor, {bool copiable = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(
              width: 92,
              child: Text(etiqueta,
                  style: TextStyle(
                      fontSize: 12, color: cessumMuted(context))),
            ),
            Expanded(
              child: SelectableText(valor,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            if (copiable)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: valor));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('$etiqueta copiada'),
                      duration: const Duration(seconds: 2)));
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.copy, size: 15, color: cessumRed),
                ),
              ),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Datos para tu pago · \$100',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          fila('Banco', _pagoBanco),
          fila('Beneficiario', _pagoBeneficiario),
          fila('Cuenta', _pagoCuenta, copiable: true),
          fila('CLABE', _pagoClabe, copiable: true),
          fila('Concepto', 'Kárdex ${widget.matricula}', copiable: true),
          const SizedBox(height: 4),
          Text(
              'Pon tu matrícula en el concepto: así tu pago se identifica '
              'sin que tengas que avisar.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: cessumMuted(context))),
        ],
      ),
    );
  }

}

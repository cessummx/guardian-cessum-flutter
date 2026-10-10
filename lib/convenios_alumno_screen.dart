// ALUMNO: Convenios (ago-2026). Convenios institucionales dirigidos al
// alumno: los lee completos y los firma estampando su firma digital
// registrada, con constancia por correo. Si no tiene firma registrada,
// se le lleva a registrarla (FirmaAlumnoScreen).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'firma_alumno_screen.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class ConveniosAlumnoScreen extends StatefulWidget {
  final String matricula;
  /// (4-oct-2026) Desde el reingreso: abre de una vez el diálogo «Solicitar convenio de pago» con el mensaje ya contado.
  final bool abrirSolicitud;
  final String mensajeInicial;
  const ConveniosAlumnoScreen({super.key, required this.matricula, this.abrirSolicitud = false, this.mensajeInicial = '', this.embebido = false});
  /// (4-oct-2026) Dentro de «Pagos» (pestañas) va sin barra propia: la pone el contenedor.
  final bool embebido;


  @override
  State<ConveniosAlumnoScreen> createState() => _ConveniosAlumnoScreenState();
}

class _ConveniosAlumnoScreenState extends State<ConveniosAlumnoScreen> {
  bool _cargando = true;
  String _error = '';
  bool _tieneFirma = false;
  List<Map<String, dynamic>> _convenios = [];
  // (2-oct-2026) Solicitud propia de convenio de pago — el alumno propone
  // montos/plazos concretos, y ve aquí si Vicerrectoría ya respondió o le
  // propuso otros términos.
  Map<String, dynamic>? _miSolicitud;

  @override
  void initState() {
    super.initState();
    _cargar().then((_) {
      // Solo si no tiene ya una solicitud viva: no se duplica.
      if (!mounted || !widget.abrirSolicitud) return;
      final est = '${_miSolicitud?['estado'] ?? ''}'.toLowerCase();
      if (_miSolicitud == null || est.contains('rechaz')) _solicitarConvenio();
    });
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'convenios_alumno',
        'matricula': widget.matricula,
      });
      final r = await http.get(u).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _tieneFirma = d['tieneFirmaRegistrada'] == true;
        _convenios = ((d['convenios'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
    // (2-oct-2026) Por separado: si esta consulta falla, no debe tumbar la
    // lista de convenios ya cargada arriba.
    try {
      final u2 = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'convenio_solicitud_mia',
        'matricula': widget.matricula,
      });
      final r2 = await http.get(u2).timeout(const Duration(seconds: 25));
      final d2 = jsonDecode(r2.body) as Map<String, dynamic>;
      if (mounted && d2['ok'] == true) {
        setState(() => _miSolicitud = d2['solicitud'] as Map<String, dynamic>?);
      }
    } catch (_) {}
  }

  // (2-oct-2026) SOLICITUD DE CONVENIO DE PAGO — el alumno propone montos
  // y plazos concretos; Vicerrectoría acepta, contrapropone o rechaza desde
  // su panel. Este widget cubre los 4 estados posibles: sin solicitud (solo
  // el botón), Pendiente/Rechazada (estado informativo), Contrapropuesta
  // admin (botones Aceptar / Proponer otra cosa), y Acordado (a la espera
  // de que Vicerrectoría formalice el convenio).
  Widget _seccionMiSolicitud() {
    final sol = _miSolicitud;
    if (sol == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
          onPressed: _solicitarConvenio,
          icon: const Icon(Icons.request_quote_outlined, size: 18),
          label: const Text('Solicitar convenio de pago'),
        ),
      );
    }
    final estado = '${sol['estado'] ?? ''}';
    if (estado == 'Rechazada') {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tu solicitud de convenio no procedió', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if ((sol['motivo'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${sol['motivo']}', style: const TextStyle(fontSize: 12.5)),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
            onPressed: _solicitarConvenio,
            icon: const Icon(Icons.replay, size: 16),
            label: const Text('Volver a solicitar'),
          ),
        ]),
      );
    }
    if (estado == 'Acordado') {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFF1E7B34).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: const Row(children: [
          Icon(Icons.check_circle_outline, color: Color(0xFF1E7B34), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('Ya acordaron los términos. Vicerrectoría está formalizando tu convenio — en cuanto esté listo, lo verás aquí para firmarlo.',
                style: TextStyle(fontSize: 12.5)),
          ),
        ]),
      );
    }
    // Pendiente (esperando respuesta de Vicerrectoría) o Contrapropuesta admin.
    final prop = Map<String, dynamic>.from(sol['propuestaActual'] as Map? ?? {});
    final esContrapropuesta = estado == 'Contrapropuesta admin';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (esContrapropuesta ? const Color(0xFF1565C0) : cessumGold).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (esContrapropuesta ? const Color(0xFF1565C0) : cessumGold).withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            esContrapropuesta ? 'Vicerrectoría te propone otros términos' : 'Tu solicitud está en revisión',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        if ((prop['montoPorPago'] ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '${prop['numeroPagos']} pago(s) de \$${(prop['montoPorPago'] as num).toStringAsFixed(2)}'
                ' (total \$${(prop['montoTotal'] as num? ?? 0).toStringAsFixed(2)})'
                '${(prop['fechaInicio'] ?? '').toString().isNotEmpty ? ', desde ${prop['fechaInicio']}' : ''}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        if (esContrapropuesta && (prop['comentario'] ?? '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${prop['comentario']}', style: const TextStyle(fontSize: 12.5)),
          ),
        if (esContrapropuesta) ...[
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _responderPropuesta(sol, aceptar: false),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Proponer otra cosa'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E7B34)),
              onPressed: () => _responderPropuesta(sol, aceptar: true),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Aceptar'),
            ),
          ]),
        ],
      ]),
    );
  }

  Future<void> _solicitarConvenio() async {
    final montoCtrl = TextEditingController();
    final pagosCtrl = TextEditingController(text: '3');
    final fechaCtrl = TextEditingController();
    final mensajeCtrl = TextEditingController(text: widget.mensajeInicial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Solicitar convenio de pago', style: TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cuéntanos tu situación y lo que propones:', style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 10),
              TextField(
                controller: mensajeCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Tu situación', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto que puedes pagar por parcialidad', prefixText: '\$ ', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pagosCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'En cuántos pagos', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fechaCtrl,
                decoration: const InputDecoration(labelText: 'Desde cuándo (opcional)', hintText: 'Ej. 15 de octubre', isDense: true, border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () {
              if (mensajeCtrl.text.trim().isEmpty) return;
              final m = double.tryParse(montoCtrl.text.trim()) ?? 0;
              if (m <= 0) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final u = Uri.parse(guardianUrl);
      final r = await http
          .post(u, headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode({
            'accion': 'convenio_solicitud_crear',
            'matricula': widget.matricula,
            'mensaje': mensajeCtrl.text.trim(),
            'montoPorPago': montoCtrl.text.trim(),
            'numeroPagos': pagosCtrl.text.trim(),
            'fechaInicioDeseada': fechaCtrl.text.trim(),
          }))
          .timeout(const Duration(seconds: 25));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) {
        _mensajeSnack('${d['error'] ?? 'No se pudo enviar la solicitud.'}', error: true);
        return;
      }
      _mensajeSnack('Solicitud enviada. Te avisaremos en cuanto la revisen.');
      _cargar();
    } catch (_) {
      if (mounted) _mensajeSnack('No se pudo enviar. Intenta de nuevo.', error: true);
    }
  }

  Future<void> _responderPropuesta(Map<String, dynamic> sol, {required bool aceptar}) async {
    final payload = <String, dynamic>{
      'accion': 'convenio_solicitud_responder',
      'id': sol['id'],
      'matricula': widget.matricula,
      'respuesta': aceptar ? 'aceptar' : 'proponer',
    };
    if (!aceptar) {
      final montoCtrl = TextEditingController();
      final pagosCtrl = TextEditingController(text: '3');
      final fechaCtrl = TextEditingController();
      final comentarioCtrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Proponer otros términos', style: TextStyle(fontSize: 15)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Monto por pago', prefixText: '\$ ', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pagosCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Número de pagos', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: fechaCtrl,
                  decoration: const InputDecoration(labelText: 'Desde cuándo (opcional)', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: comentarioCtrl,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Comentario (opcional)', isDense: true, border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                final m = double.tryParse(montoCtrl.text.trim()) ?? 0;
                if (m <= 0) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Enviar propuesta'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      payload['montoPorPago'] = montoCtrl.text.trim();
      payload['numeroPagos'] = pagosCtrl.text.trim();
      payload['fechaInicio'] = fechaCtrl.text.trim();
      payload['comentario'] = comentarioCtrl.text.trim();
    }
    try {
      final r = await http
          .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 25));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) {
        _mensajeSnack('${d['error'] ?? 'No se pudo enviar.'}', error: true);
        return;
      }
      _mensajeSnack(aceptar ? 'Aceptaste los términos. Vicerrectoría formalizará tu convenio.' : 'Tu nueva propuesta fue enviada.');
      _cargar();
    } catch (_) {
      if (mounted) _mensajeSnack('No se pudo enviar. Intenta de nuevo.', error: true);
    }
  }

  void _mensajeSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : null,
    ));
  }

  Future<void> _irARegistrarFirma() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => FirmaAlumnoScreen(matricula: widget.matricula)),
    );
    _cargar();
  }

  Future<void> _abrirConvenio(Map<String, dynamic> c) async {
    var acepto = false;
    final firmado = c['firmado'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text('${c['titulo']}',
              style:
                  const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 520,
            height: 430,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    firmado
                        ? 'Firmado el ${c['firmadoEn']}.'
                        : 'Publicado el ${c['fecha']}. Léelo completo antes de firmar.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: firmado
                            ? const Color(0xFF1E8E3E)
                            : Colors.black54)),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cessumBg(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                  foregroundColor: cessumGold,
                                  visualDensity: VisualDensity.compact),
                              onPressed: () => _verDocumento(c),
                              icon: const Icon(Icons.description,
                                  size: 16),
                              label: const Text('Ver como documento',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          Text('${c['terminos']}',
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.55)),
                          _acuerdosSeccion('${c['id']}'),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!firmado) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                        '¿Algo que ajustar? Antes de firmar puedes hacer '
                        'observaciones (botón Observaciones): la institución '
                        'las responde y, si procede, actualiza el convenio.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.black54)),
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: cessumRed,
                    value: acepto,
                    onChanged: (v) => setLocal(() => acepto = v ?? false),
                    title: const Text(
                        'He leído y ACEPTO los términos de este convenio. '
                        'Autorizo estampar mi firma digital registrada.',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cessumGold),
                onPressed: () {
                  Navigator.pop(ctx, false);
                  _abrirObservaciones(c);
                },
                icon: const Icon(Icons.forum, size: 17),
                label: const Text('Observaciones')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(firmado ? 'Cerrar' : 'Cancelar')),
            if (!firmado)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8E3E),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400),
                onPressed: acepto ? () => Navigator.pop(ctx, true) : null,
                icon: const Icon(Icons.draw, size: 18),
                label: const Text('Firmar convenio'),
              ),
          ],
        );
      }),
    );
    if (ok != true) return;
    await _firmar(c);
  }

  Future<void> _firmar(Map<String, dynamic> c) async {
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'convenio_firmar',
                'convenioId': (c['id'] ?? '').toString(),
                'matricula': widget.matricula,
                'acepto': 'SI',
              }))
          .timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Color(0xFF1E8E3E),
            content: Text('¡Convenio firmado! Te enviamos tu constancia '
                'por correo.')));
        _cargar();
      } else if ('${d['error']}' == 'SIN_FIRMA') {
        final ir = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Falta tu firma digital'),
            content: const Text(
                'Para firmar convenios necesitas registrar primero tu firma '
                'digital (una sola vez). ¿Quieres registrarla ahora?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Después')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Registrar mi firma')),
            ],
          ),
        );
        if (ir == true) _irARegistrarFirma();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('${d['error']}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('Error: $e')));
      }
    }
  }

  Future<void> _abrirObservaciones(Map<String, dynamic> c) async {
    await showDialog(
      context: context,
      builder: (ctx) => _ChatObservaciones(
        convenioId: (c['id'] ?? '').toString(),
        titulo: (c['titulo'] ?? '').toString(),
        matricula: widget.matricula,
        esInstitucion: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendientes =
        _convenios.where((c) => c['firmado'] != true).toList();
    final firmados = _convenios.where((c) => c['firmado'] == true).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: widget.embebido ? null : AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Convenios',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No se pudo cargar: $_error'),
                ))
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _seccionMiSolicitud(),
                      if (!_tieneFirma)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: cessumGold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                  'Aún no tienes firma digital registrada. '
                                  'La necesitas para firmar convenios (se '
                                  'registra una sola vez).',
                                  style: TextStyle(fontSize: 12)),
                              const SizedBox(height: 6),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: cessumRed,
                                    side: const BorderSide(
                                        color: cessumRed)),
                                onPressed: _irARegistrarFirma,
                                icon: const Icon(Icons.draw, size: 17),
                                label: const Text('Registrar mi firma'),
                              ),
                            ],
                          ),
                        ),
                      if (_convenios.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                              'No tienes convenios dirigidos a ti por ahora.',
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.black54)),
                        ),
                      if (pendientes.isNotEmpty) ...[
                        const Text('POR FIRMAR',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: cessumGold)),
                        for (final c in pendientes) _tarjeta(c, false),
                        const SizedBox(height: 14),
                      ],
                      if (firmados.isNotEmpty) ...[
                        const Text('FIRMADOS',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1E8E3E))),
                        for (final c in firmados) _tarjeta(c, true),
                      ],
                    ],
                  ),
                ),
    );
  }

  // (ago-3) Acuerdos del convenio visibles para el alumno: qué se
  // comprometió cada parte, para cuándo y en qué estado va.
  Future<List<Map<String, dynamic>>> _cargarAcuerdos(String id) async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'convenio_acuerdos',
            'id': id,
          }))
          .timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      return ((d['acuerdos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // (ago-3) El alumno puede leer el convenio como DOCUMENTO formal
  // (pergamino con membrete), no solo como texto corrido en la tarjeta.
  void _verDocumento(Map<String, dynamic> c) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                color: cessumRed,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: Image.asset('assets/images/logo.png',
                      height: 26,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.school,
                          color: cessumRed,
                          size: 26)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${c['titulo']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
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
              child: Container(
                width: double.infinity,
                color: const Color(0xFFFAF8F5),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Text('${c['terminos']}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.6,
                          fontFamily: 'serif')),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              child: const Text(
                  'Las firmas se estampan en el documento conforme cada '
                  'parte va firmando.',
                  style: TextStyle(fontSize: 11, color: Colors.black45)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _acuerdosSeccion(String convenioId) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _cargarAcuerdos(convenioId),
      builder: (ctx, snap) {
        final acs = snap.data ?? [];
        if (acs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 14),
            const Divider(),
            const Text('ACUERDOS Y COMPROMISOS',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: cessumGold)),
            const SizedBox(height: 6),
            for (final a in acs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        (a['estado'] ?? '') == 'Cumplido'
                            ? '✅'
                            : (a['semaforo'] ?? '') == 'rojo'
                                ? '🔴'
                                : (a['semaforo'] ?? '') == 'ambar'
                                    ? '🟡'
                                    : '⏳',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${a['acuerdo']}',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35)),
                          Text(
                              '${a['responsable'] == 'alumno' ? 'Te corresponde a ti' : 'Corresponde a la institución'} · ${a['fecha']}'
                              '${(a['estado'] ?? '') == 'Cumplido' ? ' · cumplido ✓' : ''}',
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Colors.black54)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _tarjeta(Map<String, dynamic> c, bool firmado) {
    final color = firmado ? const Color(0xFF1E8E3E) : cessumGold;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _abrirConvenio(c),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(firmado ? Icons.verified : Icons.history_edu,
                    color: color, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c['titulo']}',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      Text(
                        firmado
                            ? 'Firmado el ${c['firmadoEn']} · toca para releerlo'
                            : 'Publicado el ${c['fecha']} · toca para leer y firmar',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: firmado ? color : Colors.black54),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hilo de observaciones del convenio, tipo chat: el alumno propone,
/// la institución responde; la versión final se firma con acuerdo.
class _ChatObservaciones extends StatefulWidget {
  final String convenioId;
  final String titulo;
  final String matricula;
  final bool esInstitucion;
  const _ChatObservaciones(
      {required this.convenioId,
      required this.titulo,
      required this.matricula,
      required this.esInstitucion});

  @override
  State<_ChatObservaciones> createState() => _ChatObservacionesState();
}

class _ChatObservacionesState extends State<_ChatObservaciones> {
  bool _cargando = true;
  bool _enviando = false;
  List<Map<String, dynamic>> _msgs = [];
  final _txt = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _txt.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'convenio_observaciones',
            'id': widget.convenioId,
            'matricula': widget.matricula,
          }))
          .timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _msgs = ((d['observaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _enviar() async {
    final m = _txt.text.trim();
    if (m.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'convenio_observacion',
                'convenioId': widget.convenioId,
                'matricula': widget.matricula,
                'autor': widget.esInstitucion ? 'institucion' : 'alumno',
                'nombre': widget.esInstitucion ? 'Vicerrectoría Académica' : '',
                'mensaje': m,
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        _txt.clear();
        await _cargar();
      }
    } catch (_) {}
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          children: [
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
                const Icon(Icons.forum, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Observaciones · ${widget.titulo}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 20)),
              ]),
            ),
            Expanded(
              child: _cargando
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: cessumRed))
                  : _msgs.isEmpty
                      ? const Center(
                          child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'Sin observaciones todavía.\nEscribe la primera: '
                              'qué ajustarías o qué duda tienes sobre los términos.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ))
                      : ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (final m in _msgs) _burbuja(m),
                          ],
                        ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border:
                    Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _txt,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: widget.esInstitucion
                          ? 'Responder a la observación…'
                          : 'Escribe tu observación al convenio…',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: cessumRed,
                  child: _enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : IconButton(
                          onPressed: _enviar,
                          icon: const Icon(Icons.send,
                              color: Colors.white, size: 18)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _burbuja(Map<String, dynamic> m) {
    final esInst = (m['autor'] ?? '') == 'institucion';
    final mio = widget.esInstitucion ? esInst : !esInst;
    final color = esInst ? cessumRed : cessumGold;
    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              esInst
                  ? '🏛 ${(m['nombre'] ?? '').toString().isEmpty ? 'Institución' : m['nombre']}'
                  : '🎓 ${(m['nombre'] ?? '').toString().isEmpty ? 'Alumno(a)' : m['nombre']} · ${m['matricula']}',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: color),
            ),
            Text('${m['mensaje']}',
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
            Text('${m['fecha']}',
                style: const TextStyle(
                    fontSize: 9.5, color: Colors.black38)),
          ],
        ),
      ),
    );
  }
}

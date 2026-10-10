// Pantalla del ALUMNO: solicitar recibir el título POR ENVÍO.
// Captura dirección completa + teléfono, y el consentimiento (casilla +
// deslinde + firma por nombre tecleado). Envía a titulacion_envio_solicitar.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'firma_alumno_screen.dart';

class EnvioTituloScreen extends StatefulWidget {
  final String folio;
  final String matricula;
  final String nombreAlumno;
  const EnvioTituloScreen({
    super.key,
    required this.folio,
    required this.matricula,
    required this.nombreAlumno,
  });

  @override
  State<EnvioTituloScreen> createState() => _EnvioTituloScreenState();
}

class _EnvioTituloScreenState extends State<EnvioTituloScreen> {
  final _calle = TextEditingController();
  final _numero = TextEditingController();
  final _colonia = TextEditingController();
  final _cp = TextEditingController();
  final _ciudad = TextEditingController();
  final _estado = TextEditingController();
  final _referencias = TextEditingController();
  final _telefono = TextEditingController();

  bool _acepta = false;
  bool _enviando = false;

  // Firma digital ya registrada del alumno.
  bool _cargandoFirma = true;
  bool _tieneFirma = false;
  String _firmaUrl = '';

  @override
  void initState() {
    super.initState();
    _verificarFirma();
  }

  Future<void> _verificarFirma() async {
    setState(() => _cargandoFirma = true);
    try {
      final uri = Uri.parse('$guardianUrl?accion=firma_alumno_estado'
          '&matricula=${Uri.encodeComponent(widget.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _tieneFirma = data['tiene'] == true;
        _firmaUrl = (data['url'] ?? '').toString();
        _cargandoFirma = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoFirma = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _calle, _numero, _colonia, _cp, _ciudad,
      _estado, _referencias, _telefono
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _formularioListo =>
      _calle.text.trim().isNotEmpty &&
      _numero.text.trim().isNotEmpty &&
      _colonia.text.trim().isNotEmpty &&
      _cp.text.trim().isNotEmpty &&
      _ciudad.text.trim().isNotEmpty &&
      _estado.text.trim().isNotEmpty &&
      _telefono.text.trim().isNotEmpty &&
      _acepta &&
      _tieneFirma;

  Future<void> _solicitar() async {
    if (!_formularioListo) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.orange,
        content: Text(_tieneFirma
            ? 'Completa la dirección, el teléfono y acepta el consentimiento.'
            : 'Necesitas registrar tu firma digital antes de solicitar el envío.'),
      ));
      return;
    }
    setState(() => _enviando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'titulacion_envio_solicitar',
                'folio': widget.folio,
                'matricula': widget.matricula,
                'calle': _calle.text.trim(),
                'numero': _numero.text.trim(),
                'colonia': _colonia.text.trim(),
                'cp': _cp.text.trim(),
                'ciudad': _ciudad.text.trim(),
                'estado': _estado.text.trim(),
                'referencias': _referencias.text.trim(),
                'telefono': _telefono.text.trim(),
                'acepta': '1',
                'firmaUrl': _firmaUrl,
                'nombre': widget.nombreAlumno,
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.local_shipping, color: cessumRed, size: 40),
            title: const Text('Solicitud registrada'),
            content: const Text(
              'Registramos tu solicitud de envío. Prepararemos tu título y te '
              'avisaremos por correo con el número de guía para que lo rastrees. '
              'Cuando lo recibas, podrás confirmar la recepción desde la app.',
              style: TextStyle(fontSize: 13.5, height: 1.4),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, true);
                },
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(data['error']?.toString() ?? 'No se pudo registrar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error de conexión: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Recibir mi título por envío'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumRed.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: cessumRed, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Indica la dirección donde quieres recibir tu título. '
                    'Enviaremos por paquetería y te daremos el número de guía.',
                    style: TextStyle(
                        fontSize: 12.5, color: cessumMuted(context), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _seccion('Dirección de envío'),
          _campo(_calle, 'Calle', Icons.signpost),
          Row(
            children: [
              Expanded(child: _campo(_numero, 'Número', Icons.tag)),
              const SizedBox(width: 10),
              Expanded(child: _campo(_cp, 'C.P.', Icons.markunread_mailbox,
                  teclado: TextInputType.number)),
            ],
          ),
          _campo(_colonia, 'Colonia', Icons.location_city),
          Row(
            children: [
              Expanded(child: _campo(_ciudad, 'Ciudad / Municipio', Icons.apartment)),
              const SizedBox(width: 10),
              Expanded(child: _campo(_estado, 'Estado', Icons.map)),
            ],
          ),
          _campo(_referencias, 'Referencias (entre calles, color de casa…)',
              Icons.place, opcional: true, lineas: 2),
          _campo(_telefono, 'Teléfono de contacto', Icons.phone,
              teclado: TextInputType.phone),
          const SizedBox(height: 20),
          _seccion('Consentimiento'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
            ),
            child: Text(
              'Bajo protesta de decir verdad, manifiesto que la dirección '
              'proporcionada es correcta y solicito el envío de mi título '
              'profesional a la misma. Reconozco que CESSUM entrega el documento '
              'a la empresa de paquetería en buen estado, y que a partir de ese '
              'momento el traslado queda a cargo de dicha empresa; en '
              'consecuencia, deslindo a CESSUM de extravíos, daños o retrasos '
              'imputables al servicio de mensajería. Me comprometo a confirmar '
              'la recepción del título una vez recibido.',
              style: TextStyle(
                  fontSize: 12, height: 1.5, color: cessumMuted(context)),
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _acepta,
            onChanged: (v) => setState(() => _acepta = v ?? false),
            activeColor: cessumRed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Acepto el consentimiento y el deslinde anteriores.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          _seccion('Tu firma'),
          _bloqueFirma(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _formularioListo ? cessumRed : Colors.grey,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: (_enviando || !_formularioListo) ? null : _solicitar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.local_shipping),
              label: Text(_enviando ? 'Enviando…' : 'Solicitar envío de mi título'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _bloqueFirma() {
    if (_cargandoFirma) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cessumRed))),
      );
    }
    if (_tieneFirma) {
      // Muestra la firma registrada del alumno.
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E8E3E).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified,
                    color: Color(0xFF1E8E3E), size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Firmarás con tu firma digital registrada.',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FirmaAlumnoScreen(matricula: widget.matricula),
                      ),
                    );
                    _verificarFirma();
                  },
                  child: const Text('Cambiar',
                      style: TextStyle(fontSize: 12, color: cessumRed)),
                ),
              ],
            ),
            if (_firmaUrl.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                height: 90,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Image.network(_firmaUrl, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                          child: Text('Firma registrada',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cessumMuted(context))))),
                ),
              ),
          ],
        ),
      );
    }
    // No tiene firma: mandar a registrarla.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aún no tienes una firma digital registrada. La necesitas para '
            'firmar el consentimiento del envío.',
            style: TextStyle(
                fontSize: 12.5, color: cessumMuted(context), height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        FirmaAlumnoScreen(matricula: widget.matricula),
                  ),
                );
                _verificarFirma();
              },
              icon: const Icon(Icons.draw, size: 18),
              label: const Text('Registrar mi firma digital'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccion(String t) => Padding(        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
      );

  Widget _campo(TextEditingController c, String label, IconData icono,
      {TextInputType? teclado,
      bool opcional = false,
      int lineas = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: teclado,
        maxLines: lineas,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: opcional ? '$label (opcional)' : label,
          prefixIcon: Icon(icono, size: 20, color: cessumRed),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: cessumRed, width: 1.5),
          ),
        ),
      ),
    );
  }
}

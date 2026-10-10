import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'foto_web_picker.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Solicitud de factura DESDE la app (reemplaza el correo a administración).
/// Prellena los datos del alumno, pide concepto, monto y fecha del pago, y
/// la constancia de situación fiscal. Llega al panel de Trámites del admin
/// como "Solicitud de factura".
class SolicitudFacturaScreen extends StatefulWidget {
  const SolicitudFacturaScreen({super.key});

  @override
  State<SolicitudFacturaScreen> createState() =>
      _SolicitudFacturaScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

const List<String> _programas = [
  'Maestría en Psicopedagogía',
  'Maestría en Pedagogía',
  'Maestría en Educación',
  'Maestría en Educación Inclusiva',
  'Doctorado en Ciencias de la Educación',
  'Doctorado en Educación con énfasis en Investigación',
];

const List<String> _modalidades = ['Mixta', 'No Escolarizada'];

const List<String> _conceptos = [
  'Mensualidad',
  'Materia',
  'Reinscripción',
  'Inscripción',
  'Trámite escolar',
  'Otro',
];

class _SolicitudFacturaScreenState extends State<SolicitudFacturaScreen> {
  bool _esPrueba = false;
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _generacion = TextEditingController();
  final _monto = TextEditingController();
  final _fechaPago = TextEditingController();
  final _comentarios = TextEditingController();

  String _matricula = '';
  String? _programa;
  String? _modalidad;
  String? _concepto;

  DocElegido? _constancia;
  DocElegido? _comprobantePago;
  bool _enviando = false;
  bool _enviado = false;

  @override
  void initState() {
    super.initState();
    _prellenar();
  }

  Future<void> _prellenar() async {
    final perfil = await StudentProfile.load();
    _esPrueba = perfil?.esVistaAdmin == true;
    final correo = await SessionStore.validEmail();
    if (!mounted) return;
    setState(() {
      if (perfil != null) {
        _nombre.text = perfil.nombreCompleto;
        _matricula = perfil.matricula;
        _generacion.text = perfil.generacion;
        if (_programas.contains(perfil.programa)) _programa = perfil.programa;
        final m = perfil.modalidad.toLowerCase();
        if (m.contains('mixt')) {
          _modalidad = 'Mixta';
        } else if (m.contains('escolariz') ||
            m.contains('línea') ||
            m.contains('linea') ||
            m.contains('virtual')) {
          _modalidad = 'No Escolarizada';
        }
      }
      if (correo != null && correo.isNotEmpty) _correo.text = correo;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _nombre,
      _correo,
      _generacion,
      _monto,
      _fechaPago,
      _comentarios
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final f = await showDatePicker(
      context: context,
      initialDate: hoy,
      firstDate: DateTime(hoy.year - 1),
      lastDate: hoy,
      helpText: 'Fecha del pago',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: cessumRed),
        ),
        child: child!,
      ),
    );
    if (f != null && mounted) {
      setState(() {
        _fechaPago.text =
            '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
      });
    }
  }

  Future<void> _elegirConstancia() async {
    try {
      final f = await seleccionarDocumento(tipo: 'pdf');
      if (f == null) return;
      final esPdf = f.mime.toLowerCase().contains('pdf') ||
          f.nombre.toLowerCase().endsWith('.pdf');
      if (!esPdf) {
        _aviso('La constancia debe ser un PDF. El régimen fiscal aparece en '
            'la 2ª página del PDF, por eso no se acepta foto.');
        return;
      }
      if (mounted) setState(() => _constancia = f);
    } catch (e) {
      _aviso('No se pudo adjuntar el PDF: $e');
    }
  }

  String? _falta() {
    if (_nombre.text.trim().isEmpty) return 'Escribe tu nombre completo.';
    if (_correo.text.trim().isEmpty) return 'Escribe tu correo.';
    if (_matricula.trim().isEmpty) return 'Falta tu matrícula.';
    if (_programa == null) return 'Selecciona tu programa.';
    if (_modalidad == null) return 'Selecciona tu modalidad.';
    if (_generacion.text.trim().isEmpty) return 'Escribe tu generación.';
    if (_concepto == null) return 'Selecciona el concepto del pago.';
    if (_monto.text.trim().isEmpty) return 'Escribe el monto del pago.';
    if (_fechaPago.text.trim().isEmpty) return 'Indica la fecha del pago.';
    if (_comprobantePago == null) {
      return 'Adjunta tu comprobante de pago.';
    }
    if (_constancia == null) {
      return 'Adjunta tu constancia de situación fiscal.';
    }
    return null;
  }

  Future<void> _enviar() async {
    final falta = _falta();
    if (falta != null) {
      _aviso(falta);
      return;
    }
    setState(() => _enviando = true);
    try {
      final obs = StringBuffer()
        ..write(_esPrueba ? '[MODO PRUEBA - NO PROCESAR] ' : '')
        ..write('SOLICITUD DE FACTURA. ')
        ..write('Concepto del pago: ${_concepto ?? ''}. ')
        ..write('Monto: \$${_monto.text.trim()}. ')
        ..write('Fecha del pago: ${_fechaPago.text.trim()}.');
      if (_comentarios.text.trim().isNotEmpty) {
        obs.write(' Comentarios: ${_comentarios.text.trim()}.');
      }
      obs.write(' Adjunta constancia de situación fiscal.');

      final payload = <String, dynamic>{
        'accion': 'tramite_enviar',
        'modoPrueba': _esPrueba,
        'nombre': _nombre.text.trim(),
        'matricula': _matricula,
        'correo': _correo.text.trim(),
        'programa': _programa,
        'modalidad': _modalidad,
        'generacion': _generacion.text.trim(),
        'tipoTramite': 'Solicitud de factura',
        'observaciones': obs.toString(),
        'comprobanteBase64': base64Encode(_constancia!.bytes),
        'comprobanteMime': _constancia!.mime,
        'comprobantePagoBase64': base64Encode(_comprobantePago!.bytes),
        'comprobantePagoMime': _comprobantePago!.mime,
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || data.containsKey('guardadas')) {
        throw Exception(data['error'] ?? 'No se pudo enviar la solicitud.');
      }
      if (mounted) {
        setState(() {
          _enviando = false;
          _enviado = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _enviando = false);
      _aviso('No se pudo enviar: $e');
    }
  }

  Future<void> _abrirWhatsapp() async {
    final uri = Uri.parse(
        'https://wa.me/5216421376117?text=${Uri.encodeComponent('Hola, tengo una duda sobre mi solicitud de factura. Mi matrícula es $_matricula.')}');
    try {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir WhatsApp.');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Solicitud de factura'),
      ),
      body: _enviando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _enviado
              ? _vistaEnviado()
              : _formulario(),
    );
  }

  Widget _vistaEnviado() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: _verdeOk, size: 64),
            const SizedBox(height: 16),
            Text('Tu solicitud de factura se envió.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textoFuerte)),
            const SizedBox(height: 8),
            Text(
              'Administración emitirá tu factura con los datos de tu '
              'constancia de situación fiscal y te la enviará a tu correo. '
              'El plazo es de hasta 72 horas naturales.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textoSuave, height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }

  // Colores que responden al tema (claro/oscuro), sin alterar el modo claro.
  Color get _fillCampo =>
      cessumIsDark(context) ? const Color(0xFF26241F) : Colors.white;
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : cessumInk(context);
  Color get _textoSuave => cessumMuted(context);

  Widget _formulario() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
          ),
          child: Text(
            'Solicita aquí la factura de un pago realizado. Es indispensable '
            'adjuntar tu constancia de situación fiscal vigente en PDF '
            '(el régimen fiscal aparece en la 2ª página del PDF). La factura '
            'llega a tu correo en un plazo de hasta 72 horas naturales.',
            style: TextStyle(fontSize: 12, color: _textoFuerte, height: 1.45),
          ),
        ),
        _campo(_nombre, 'Nombre completo *'),
        _campo(_correo, 'Correo electrónico *'),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Matrícula',
              filled: true,
              fillColor: cessumIsDark(context)
                  ? const Color(0xFF201E1B)
                  : cessumMuted(context).withValues(alpha: 0.10),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(_matricula.isEmpty ? '—' : _matricula),
          ),
        ),
        _dropdown('Programa académico *', _programas, _programa,
            (v) => setState(() => _programa = v)),
        _dropdown('Modalidad *', _modalidades, _modalidad,
            (v) => setState(() => _modalidad = v)),
        _campo(_generacion, 'Generación *'),
        _dropdown('Concepto del pago *', _conceptos, _concepto,
            (v) => setState(() => _concepto = v)),
        _campo(_monto, 'Monto del pago (MXN) *',
            tipo: const TextInputType.numberWithOptions(decimal: true)),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _fechaPago,
            readOnly: true,
            onTap: _elegirFecha,
            decoration: InputDecoration(
              labelText: 'Fecha del pago *',
              hintText: 'Toca para elegir la fecha',
              suffixIcon: const Icon(Icons.calendar_today, size: 18),
              filled: true,
              fillColor: _fillCampo,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        _campo(_comentarios, 'Comentarios (opcional)', lineas: 3),
        const SizedBox(height: 4),
        _constanciaWidget(),
        const SizedBox(height: 12),
        _comprobantePagoWidget(),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _enviar,
            icon: const Icon(Icons.send),
            label: const Text('Enviar solicitud de factura'),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: _abrirWhatsapp,
            icon: const Icon(Icons.chat, color: _verdeOk, size: 18),
            label: const Text('¿Dudas? Escríbenos al 642 137 6117',
                style: TextStyle(color: _verdeOk)),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _campo(TextEditingController c, String etq,
      {int lineas = 1, TextInputType? tipo}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lineas,
        keyboardType: tipo,
        decoration: InputDecoration(
          labelText: etq,
          filled: true,
          fillColor: _fillCampo,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dropdown(String etq, List<String> ops, String? val,
      ValueChanged<String?> onCh) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: val,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: etq,
          filled: true,
          fillColor: _fillCampo,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: ops
            .map((m) => DropdownMenuItem(
                value: m,
                child: Text(m, style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: onCh,
      ),
    );
  }

  Future<void> _elegirComprobantePago() async {
    try {
      final f = await seleccionarDocumento(tipo: 'cualquiera');
      if (f == null) return;
      if (mounted) setState(() => _comprobantePago = f);
    } catch (e) {
      _aviso('No se pudo adjuntar el comprobante de pago.');
    }
  }

  Widget _comprobantePagoWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: cessumIsDark(context)
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Icon(
              _comprobantePago != null ? Icons.receipt_long : Icons.payments,
              color: _comprobantePago != null
                  ? cessumRed
                  : (cessumIsDark(context) ? Colors.white38 : cessumFaint(context)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Comprobante de pago *',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: _textoFuerte)),
                Text(
                  _comprobantePago != null
                      ? 'Adjuntado: ${_comprobantePago!.nombre}'
                      : 'Adjunta tu comprobante de la transferencia (PDF o imagen)',
                  style: TextStyle(fontSize: 12, color: _textoSuave),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _elegirComprobantePago,
            child: Text(_comprobantePago != null ? 'Cambiar' : 'Adjuntar',
                style: const TextStyle(color: cessumRed)),
          ),
        ],
      ),
    );
  }

  Widget _constanciaWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: cessumIsDark(context)
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Icon(
              _constancia != null
                  ? Icons.picture_as_pdf
                  : Icons.description,
              color: _constancia != null
                  ? cessumRed
                  : (cessumIsDark(context) ? Colors.white38 : cessumFaint(context)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Constancia de situación fiscal *',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: _textoFuerte)),
                Text(
                  _constancia != null
                      ? 'PDF adjuntado: ${_constancia!.nombre}'
                      : 'Adjunta el PDF (el régimen va en la 2ª página)',
                  style: TextStyle(fontSize: 12, color: _textoSuave),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _elegirConstancia,
            child: Text(_constancia != null ? 'Cambiar' : 'Adjuntar',
                style: const TextStyle(color: cessumRed)),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'mis_tramites_screen.dart';
import 'student_profile.dart';
import 'foto_web_picker.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Tramites escolares DESDE la app (reemplaza el correo a administración).
/// Prellena los datos del alumno, pide concepto, monto y fecha del pago, y
/// la comprobante de depósito. Llega al panel de Trámites del admin
/// como "Tramites escolares".
String _genLegible(String g) {
  final s = g.trim();
  if (s.isEmpty) return s;
  const meses = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
  };
  final mTxt = RegExp(r'\b([A-Za-z]{3})\s+(\d{1,2})\s+\d{4}').firstMatch(s);
  if (mTxt != null) {
    final mes = meses[mTxt.group(1)!.toLowerCase()];
    final dia = int.tryParse(mTxt.group(2)!);
    if (mes != null && dia != null) return '$dia-$mes';
  }
  return s;
}

class SolicitudTramitesScreen extends StatefulWidget {
  const SolicitudTramitesScreen({super.key});

  @override
  State<SolicitudTramitesScreen> createState() =>
      _SolicitudTramitesScreenState();
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

const List<String> _tiposTramite = [
  'Constancia de inscripción (\$50.00 MXN)',
  'Constancia de estudios digital o físico (\$80.00 MXN)',
  'Constancia de estudios oficial (periodo, fechas y promedios) (\$80.00 MXN)',
  'Boleta física (\$100.00 MXN)',
  'Boleta Digital (gratuita)',
  'Kardex digital o físico (\$100.00 MXN)',
  'Informe financiero (gratuita)',
  'Constancia de no adeudo (gratuita)',
  'Constancia de terminación de estudios (\$80.00 MXN)',
  // (14-sep) FICHA DE PLAN Y PROGRAMA DE ESTUDIO. Becas y empleadores piden
  // «constancia o plan de estudios que especifique el número de periodos y
  // materias del nivel que cursa». No es la constancia de estudios oficial
  // —esa trae periodo, fechas y promedio— y por eso la primera vez se
  // rechazó un trámite que sí tenía sustento. Ahora tiene su propio tipo,
  // con el RVOE, la publicación en el Boletín y el mapa curricular.
  'Ficha de plan y programa de estudio con RVOE (\$50.00 MXN)',
  // (5-oct-2026) Para becas y crédito educativo (IBCEES y financieras): lo que solo CESSUM puede emitir.
  'Carta de costos del programa (\$80.00 MXN)',
  'Constancia de beca institucional (gratuita)',
  'Factura (gratuita)',
  'Otro (\$50.00 MXN)',
];

class _SolicitudTramitesScreenState extends State<SolicitudTramitesScreen> {
  bool _esPrueba = false;

  // (ago-22) La etiqueta del selector ahora trae el importe, así que ya no se
  // puede comparar contra el literal 'Otro'. El valor que se GUARDA sigue
  // siendo 'Otro: <lo que escribió el alumno>', sin el paréntesis del precio:
  // de eso depende que tarifaDeTramite_ lo reconozca y le cobre los $50.
  bool get _esOtro => (_tipoSel ?? '').startsWith('Otro');
  bool get _esFicha => (_tipoSel ?? '').startsWith('Ficha de plan');
  bool get _esFactura => (_tipoSel ?? '').startsWith('Factura');

  // (1-oct-2026) La factura solo se puede pedir del MES EN CURSO — así lo
  // marca el aviso del comprobante de pago ("solicítala antes del cierre
  // del mes"). El selector ni siquiera ofrece meses anteriores: no hay
  // nada que el alumno pueda elegir mal.
  static const List<String> _mesesNombre = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  String get _mesActualEtiqueta {
    final hoy = DateTime.now();
    return '${_mesesNombre[hoy.month - 1]} ${hoy.year}';
  }

  String get _mesActualValor {
    final hoy = DateTime.now();
    return '${hoy.year.toString().padLeft(4, '0')}-${hoy.month.toString().padLeft(2, '0')}';
  }

  String get _tipo => _esOtro
      ? 'Otro: ${_otroTramite.text.trim()}'
      : (_tipoSel ?? '');

  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _generacion = TextEditingController();
  final _comentarios = TextEditingController();

  String _matricula = '';
  String? _programa;
  String? _modalidad;
  String? _tipoSel;
  final _otroTramite = TextEditingController();

  FotoElegida? _constancia;
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
        _generacion.text = _genLegible(perfil.generacion);
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
      _comentarios,
      _otroTramite
    ]) {
      c.dispose();
    }
    super.dispose();
  }


  Future<void> _elegirConstancia() async {
    try {
      final f = await seleccionarFoto();
      if (f != null && mounted) setState(() => _constancia = f);
    } catch (_) {
      _aviso('No se pudo abrir el selector de archivos.');
    }
  }

  String? _falta() {
    if (_nombre.text.trim().isEmpty) return 'Escribe tu nombre completo.';
    if (_correo.text.trim().isEmpty) return 'Escribe tu correo.';
    if (_matricula.trim().isEmpty) return 'Falta tu matrícula.';
    if (_programa == null) return 'Selecciona tu programa.';
    if (_modalidad == null) return 'Selecciona tu modalidad.';
    if (_generacion.text.trim().isEmpty) return 'Escribe tu generación.';
    if (_tipoSel == null) return 'Selecciona el tipo de tramite.';
    if (_esOtro && _otroTramite.text.trim().isEmpty) {
      return 'Describe el tramite en "Otros".';
    }
    // (ago-22) «Otro» tiene cuota de $50, así que se pide el comprobante en la
    // solicitud y no después: sin él, el trámite entraba a la cola sin pago y
    // alguien tenía que perseguir al alumno para cobrarle.
    if (_esOtro && _constancia == null) {
      return 'Los trámites de "Otros" tienen un costo de \$50.00 MXN: '
          'adjunta tu comprobante de pago.';
    }
    // (14-sep) La ficha de plan de estudio cuesta $50 igual que «Otro»:
    // el comprobante se pide aquí, no después.
    if (_esFicha && _constancia == null) {
      return 'La ficha de plan y programa de estudio tiene un costo de '
          '\$50.00 MXN: adjunta tu comprobante de pago.';
    }
    // (1-oct) El comprobante del pago a facturar es obligatorio: sin él,
    // el sistema no puede verificar automáticamente que sea del mes en
    // curso, que es justo la regla que protege.
    if (_esFactura && _constancia == null) {
      return 'Adjunta el comprobante del pago que quieres facturar.';
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
        ..write('SOLICITUD DE TRAMITE ESCOLAR. ')
        ..write('Tipo: $_tipo.');
      if (_esFactura) {
        obs.write(' Mes a facturar: $_mesActualEtiqueta.');
      }
      if (_comentarios.text.trim().isNotEmpty) {
        obs.write(' Observaciones: ${_comentarios.text.trim()}.');
      }
      if (_constancia != null) {
        obs.write(' Adjunta comprobante de deposito.');
      }

      final payload = <String, dynamic>{
        'accion': 'tramite_enviar',
        'modoPrueba': _esPrueba,
        'nombre': _nombre.text.trim(),
        'matricula': _matricula,
        'correo': _correo.text.trim(),
        'programa': _programa,
        'modalidad': _modalidad,
        'generacion': _generacion.text.trim(),
        'tipoTramite': _tipo,
        'observaciones': obs.toString(),
        if (_esFactura) 'mesFactura': _mesActualValor,
      };
      if (_constancia != null) {
        payload['comprobanteBase64'] = base64Encode(_constancia!.bytes);
        payload['comprobanteMime'] = _constancia!.mime;
      }
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['bloqueoNoAdeudo'] == true) {
        if (mounted) setState(() => _enviando = false);
        await _dialogoNoAdeudo((data['error'] ?? '').toString());
        return;
      }
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
        'https://wa.me/5216421376117?text=${Uri.encodeComponent('Hola, tengo una duda sobre mi trámite escolar. Mi matrícula es $_matricula.')}');
    try {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir WhatsApp.');
    }
  }

  // Aviso cuando se intenta No Adeudo antes del final del posgrado: explica y
  // ofrece cambiar al Informe financiero (lo adecuado durante los estudios).
  Future<void> _dialogoNoAdeudo(String mensaje) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Adeudo: solo al concluir'),
        content: Text(
          mensaje.isNotEmpty
              ? mensaje
              : 'La Constancia de No Adeudo se solicita al concluir el posgrado. '
                  'Durante tus estudios, lo adecuado es el Informe financiero.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB11D29)),
            onPressed: () {
              Navigator.pop(ctx);
              if (mounted) {
                setState(() => _tipoSel = 'Informe financiero (gratuita)');
              }
            },
            child: const Text('Usar Informe financiero'),
          ),
        ],
      ),
    );
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
        title: const Text('Trámites escolares'),
        actions: [
          IconButton(
            tooltip: 'Mis trámites',
            icon: const Icon(Icons.history),
            onPressed: () {
              if (_matricula.isEmpty) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MisTramitesScreen(matricula: _matricula),
                ),
              );
            },
          ),
        ],
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
            Text('Tu solicitud se envió correctamente.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cessumInk(context))),
            const SizedBox(height: 8),
            Text(
              'Administración revisará tu solicitud y tu comprobante de '
              'depósito, y recibirás tu documento o respuesta en tu correo. '
              'El plazo es de hasta 72 horas naturales.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context),
              child: const Text('Listo'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumGold,
                side: const BorderSide(color: cessumGold),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MisTramitesScreen(matricula: _matricula),
                ),
              ),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('Ver el estado de mis trámites'),
            ),
          ],
        ),
      ),
    );
  }

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
            'Para emitir constancias y documentos de acreditación se revisa el adeudo escolar; el Informe financiero puede solicitarse aun cuando existan pagos pendientes. '
            'Consultas: WhatsApp 642 137 6117. El documento se '
            'entrega en un plazo maximo de 72 horas naturales.\n\n'
            'Datos para tu deposito:\n'
            '\u2022 A nombre de: CESSUM\n'
            '\u2022 Concepto: [tipo de tramite] + tu nombre\n'
            '\u2022 Cuenta BBVA: 0120887013\n'
            '\u2022 CLABE: 012777001208870132',
            style:
                TextStyle(fontSize: 12, color: cessumInk(context), height: 1.45),
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
              fillColor: cessumMuted(context).withValues(alpha: 0.10),
              border: OutlineInputBorder(),
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
        _dropdown('Tipo de tramite *', _tiposTramite, _tipoSel,
            (v) => setState(() => _tipoSel = v)),
        if (_esOtro) _campo(_otroTramite, 'Otros: describe el tramite *'),
        if (_esFactura)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: cessumGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta factura será por tu pago de $_mesActualEtiqueta. '
                      'Las facturas SOLO se pueden solicitar dentro del mismo mes del pago. '
                      'El comprobante que adjuntes se revisa automáticamente: si es de otro mes, '
                      'la solicitud se rechaza de inmediato. Para un mes ya cerrado, contacta '
                      'directamente a Administración.',
                      style: TextStyle(fontSize: 12.5, color: cessumInk(context), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        _campo(_comentarios,
            'Observaciones (particularidades del documento, opcional)',
            lineas: 3),
        const SizedBox(height: 4),
        _constanciaWidget(),
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
            label: const Text('Enviar solicitud'),
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
          fillColor: Theme.of(context).cardColor,
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
          fillColor: Theme.of(context).cardColor,
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

  Widget _constanciaWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: _constancia != null
                ? Image.memory(Uint8List.fromList(_constancia!.bytes),
                    fit: BoxFit.cover)
                : Icon(Icons.description, color: cessumFaint(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    (_esOtro || _esFicha)
                        ? 'Comprobante de pago (obligatorio)'
                        : _esFactura
                            ? 'Comprobante del pago a facturar (obligatorio)'
                            : 'Comprobante de pago (opcional)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: cessumInk(context))),
                Text(
                  (_esOtro || _esFicha)
                      ? (_constancia != null
                          ? 'Archivo adjuntado'
                          : (_esFicha
                              ? 'La ficha de plan de estudio cuesta \$50.00 MXN: '
                                  'adjunta tu comprobante para poder enviar.'
                              : 'Los trámites de "Otros" cuestan \$50.00 MXN: '
                                  'adjunta tu comprobante para poder enviar.'))
                      : _esFactura
                          ? (_constancia != null
                              ? 'Archivo adjuntado — se verifica automáticamente que sea del mes en curso.'
                              : 'Adjunta el comprobante del pago que quieres facturar; se '
                                  'verifica automáticamente que sea de este mes.')
                          : (_tipoSel ?? '').toLowerCase().contains('gratu')
                              ? 'Este trámite es gratuito: no requiere comprobante.'
                              : _constancia != null
                                  ? 'Archivo adjuntado'
                                  : 'Si tu trámite tiene costo, puedes adjuntarlo aquí.',
                  style: TextStyle(
                      fontSize: 12,
                      color: ((_esOtro || _esFicha || _esFactura) && _constancia == null)
                          ? cessumRed
                          : cessumMuted(context)),
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

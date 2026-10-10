import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: genera RECONOCIMIENTOS o CONSTANCIAS desde una plantilla, con QR de
/// verificación. Una sola pantalla con selector de tipo. Pega nombre, apellido
/// y correo (el correo se detecta solo); opcionalmente envía a cada quien su PDF.
class DocumentosPlantillaScreen extends StatefulWidget {
  const DocumentosPlantillaScreen({super.key});

  @override
  State<DocumentosPlantillaScreen> createState() =>
      _DocumentosPlantillaScreenState();
}

class _Persona {
  final String nombres;
  final String apellidos;
  final String correo;
  _Persona(this.nombres, this.apellidos, this.correo);
  String get full =>
      '$nombres $apellidos'.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _DocumentosPlantillaScreenState extends State<DocumentosPlantillaScreen> {
  // 'reconocimiento' | 'constancia'
  String _tipo = 'reconocimiento';

  final _motivo = TextEditingController();
  final _fecha = TextEditingController();
  final _taller = TextEditingController();
  final _horas = TextEditingController();
  final _fechaEvento = TextEditingController();
  final _lista = TextEditingController();
  final _tipoEventoOtro = TextEditingController();
  final _tipoPartOtro = TextEditingController();

  static const _tiposEvento = [
    'Taller', 'Curso', 'Conferencia', 'Diplomado', 'Seminario',
    'Webinar', 'Congreso', 'Jornada', 'Simposio', 'Otro'
  ];
  static const _tiposParticipacion = [
    'Participante', 'Asistente', 'Ponente', 'Tallerista', 'Conferencista',
    'Expositor', 'Moderador', 'Organizador', 'Otro'
  ];
  String _tipoEvento = 'Taller';
  String _tipoParticipacion = 'Participante';

  List<Map<String, String>> _recVariantes = [];
  List<Map<String, String>> _consPlantillas = [];
  String? _recVariante;
  String? _consPlantilla;

  // Por defecto ENCENDIDO: al generar, se envía a cada quien su PDF por correo
  // (solo a quienes tengan correo). Karina puede apagarlo si solo quiere PDFs.
  bool _enviarCorreo = true;
  bool _cargando = true;
  bool _generando = false;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _motivo.dispose();
    _fecha.dispose();
    _taller.dispose();
    _horas.dispose();
    _fechaEvento.dispose();
    _lista.dispose();
    _tipoEventoOtro.dispose();
    _tipoPartOtro.dispose();
    super.dispose();
  }

  Future<List<Map<String, String>>> _cargarLista(
      String accion, String campo) async {
    try {
      final uri =
          Uri.parse(guardianUrl).replace(queryParameters: {'accion': accion});
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        return ((data[campo] as List<dynamic>? ?? [])).map((e) {
          final m = e as Map<String, dynamic>;
          return {
            'key': (m['key'] ?? '').toString(),
            'label': (m['label'] ?? '').toString(),
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _cargarTodo() async {
    final rec = await _cargarLista('reconocimiento_variantes', 'variantes');
    final cons = await _cargarLista('constancia_plantillas', 'plantillas');
    if (!mounted) return;
    setState(() {
      _recVariantes = rec;
      _consPlantillas = cons;
      _recVariante = rec.isNotEmpty ? rec.first['key'] : null;
      _consPlantilla = cons.isNotEmpty ? cons.first['key'] : null;
      _cargando = false;
    });
  }

  // Cada línea -> {nombres, apellidos, correo}. Acepta pegado desde la hoja
  // (fecha, nombres, apellidos, correo) o "Nombre Apellido, correo".
  List<_Persona> _parsear() {
    final out = <_Persona>[];
    for (final raw in _lista.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      String correo = '';
      final _m = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}')
          .firstMatch(line);
      if (_m != null) correo = _m.group(0)!.trim();
      var resto = line;
      if (correo.isNotEmpty) resto = resto.replaceFirst(correo, ' ');
      final antes = resto
          .split(RegExp(r'[\s,;\t]+'))
          .map((s) => s.trim())
          .where((s) =>
              s.isNotEmpty && RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(s))
          .toList();
      String nombres = '';
      String apellidos = '';
      if (antes.length >= 4) {
        apellidos = antes.sublist(antes.length - 2).join(' ');
        nombres = antes.sublist(0, antes.length - 2).join(' ');
      } else if (antes.length == 3) {
        nombres = antes[0];
        apellidos = antes.sublist(1).join(' ');
      } else if (antes.length == 2) {
        nombres = antes[0];
        apellidos = antes[1];
      } else if (antes.length == 1) {
        nombres = antes[0];
      }
      if ('$nombres$apellidos'.trim().isNotEmpty) {
        out.add(_Persona(nombres, apellidos, correo));
      }
    }
    return out;
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cessumRed : null,
    ));
  }

  bool get _esRec => _tipo == 'reconocimiento';
  String? get _variante => _esRec ? _recVariante : _consPlantilla;
  String get _noun => _esRec ? 'reconocimientos' : 'constancias';

  Future<void> _generar({bool prueba = false}) async {
    final personas = _parsear();
    if (_variante == null) {
      _aviso('Elige una plantilla.', error: true);
      return;
    }
    if (_esRec && _motivo.text.trim().isEmpty) {
      _aviso('Escribe el motivo del reconocimiento.', error: true);
      return;
    }
    if (personas.isEmpty) {
      _aviso('Agrega al menos una persona.', error: true);
      return;
    }
    final tope = _esRec ? 60 : 40;
    if (!prueba && personas.length > tope) {
      _aviso('Máximo $tope por lote.', error: true);
      return;
    }
    final conCorreo = personas.where((p) => p.correo.isNotEmpty).length;
    if (!prueba && _enviarCorreo && conCorreo == 0) {
      _aviso('Activaste el envío pero ninguna persona tiene correo.',
          error: true);
      return;
    }
    // (24-sep) ANTES de enviar correos, decir a quién le llegan, cuántos son y
    // qué reciben, y pedir confirmación. El envío venía encendido de entrada y
    // salía al pulsar Generar, sin aviso.
    if (!prueba && _enviarCorreo && conCorreo > 0) {
      final destinatarios = personas.where((p) => p.correo.isNotEmpty).toList();
      final sinCorreo = personas.length - destinatarios.length;
      final tipo = _esRec ? 'reconocimiento' : 'constancia';
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Enviar ${destinatarios.length} correo(s)', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    'A cada persona le llegará UN correo con su $tipo en PDF, a su nombre.'
                    '${sinCorreo > 0 ? ' $sinCorreo sin correo: su PDF se genera pero no se envía.' : ''}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final p in destinatarios.take(40))
                  Text('• ${p.full} · ${p.correo}', style: const TextStyle(fontSize: 12.5)),
                if (destinatarios.length > 40)
                  Text('… y ${destinatarios.length - 40} más.', style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                const Text('Si prefiere revisar primero, cancele y use la vista previa.',
                    style: TextStyle(fontSize: 12)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Generar y enviar ${destinatarios.length}'),
            ),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }

    setState(() => _generando = true);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final Map<String, dynamic> payload = {
        'actor': actor,
        'variante': _variante,
        'motivo': _motivo.text.trim(),
        'fecha': _fecha.text.trim(),
        'enviarCorreo': prueba ? false : _enviarCorreo,
      };
      if (_esRec) {
        payload['accion'] = 'reconocimiento_lote';
        payload['personas'] = personas
            .map((p) => {'nombre': p.full, 'correo': p.correo})
            .toList();
      } else {
        payload['accion'] = 'constancia_plantilla_lote';
        payload['taller'] = _taller.text.trim();
        payload['horas'] = _horas.text.trim();
        payload['fechaEvento'] = _fechaEvento.text.trim();
        payload['tipoEvento'] = _tipoEvento == 'Otro'
            ? _tipoEventoOtro.text.trim()
            : _tipoEvento;
        payload['tipoParticipacion'] = _tipoParticipacion == 'Otro'
            ? _tipoPartOtro.text.trim()
            : _tipoParticipacion;
        payload['prueba'] = prueba;
        payload['personas'] = personas
            .map((p) => {
                  'nombres': p.nombres,
                  'apellidos': p.apellidos,
                  'correo': p.correo,
                })
            .toList();
      }

      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 300));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() => _generando = false);

      final docs = (data['docs'] as List<dynamic>? ?? []);
      var primerPdf =
          docs.isNotEmpty ? (docs.first['pdf'] ?? '').toString() : '';
      if (primerPdf.isEmpty) {
        primerPdf =
            (data['pdf'] ?? data['previewUrl'] ?? data['url'] ?? '').toString();
      }

      if (prueba) {
        _dialogo(
          titulo: 'Vista previa',
          mensaje:
              'Generé una constancia de muestra (no se envió ni se registró). '
              'Ábrela para revisar nombre, QR y diseño antes de generar el lote.',
          pdf: primerPdf,
          pdfLabel: 'Abrir la muestra',
        );
        return;
      }

      final enviados = data['enviados'] ?? 0;
      final sinCorreo = data['sinCorreo'] ?? 0;
      final fallos = (data['fallos'] as List<dynamic>? ?? []);
      final total = data['total'] ?? data['generadas'] ?? docs.length;

      final buffer = StringBuffer()
        ..write('Se generaron $total $_noun con QR');
      if (_enviarCorreo) {
        buffer.write(' y se enviaron $enviados por correo.');
        if (sinCorreo is int && sinCorreo > 0) {
          buffer.write('\n\n$sinCorreo persona(s) no tenían correo, así que '
              'solo se les generó el PDF.');
        }
        if (fallos.isNotEmpty) {
          final primero = fallos.first as Map<String, dynamic>;
          buffer.write('\n\n⚠️ ${fallos.length} envío(s) fallaron. '
              'Motivo: ${primero['motivo'] ?? 'desconocido'}');
        }
      } else {
        buffer.write('.');
      }
      buffer.write('\n\nQuedaron registrados con folio para su verificación.');

      _dialogo(
        titulo: _esRec ? 'Reconocimientos generados' : 'Constancias generadas',
        mensaje: buffer.toString(),
        pdf: primerPdf,
        pdfLabel: 'Abrir el primero',
      );
    } catch (e) {
      if (mounted) setState(() => _generando = false);
      _aviso('No se pudo generar: $e'.replaceAll('Exception: ', ''),
          error: true);
    }
  }

  void _dialogo(
      {required String titulo,
      required String mensaje,
      String pdf = '',
      String pdfLabel = 'Abrir'}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.verified, color: cessumRed),
          const SizedBox(width: 8),
          Expanded(
              child: Text(titulo,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        content: Text(mensaje),
        actions: [
          if (pdf.isNotEmpty)
            TextButton(
              onPressed: () => Helpers.abrirUrlExterna(pdf, context),
              child: Text(pdfLabel),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  // ---------- UI ----------

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: cessumRed, width: 1.6)),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6)),
          ],
        ),
        child: child,
      );

  Widget _label(IconData ic, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(ic, size: 18, color: cessumRed),
          const SizedBox(width: 7),
          Text(t,
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: cessumRed)),
        ]),
      );

  Widget _segBtn(String label, String value, IconData ic) {
    final sel = _tipo == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tipo = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? cessumRed : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: sel
                ? [
                    BoxShadow(
                        color: cessumRed.withValues(alpha: 0.30),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(ic, size: 18, color: sel ? Colors.white : Colors.black54),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: sel ? Colors.white : Colors.black54)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final personas = _parsear();
    final conCorreo = personas.where((p) => p.correo.isNotEmpty).length;
    final lista = _esRec ? _recVariantes : _consPlantillas;
    final selKey = _esRec ? _recVariante : _consPlantilla;

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Documentos por plantilla'),
      ),
      body: _generando
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: cessumRed),
              SizedBox(height: 12),
              Text('Generando con QR… puede tardar si son varios.'),
            ]))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Hero header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [cessumRed, Color(0xFF7E1420)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: cessumRed.withValues(alpha: 0.28),
                          blurRadius: 20,
                          offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.workspace_premium,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Documentos por plantilla',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text(
                                'Reconocimientos y constancias con QR de '
                                'verificación',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12.5)),
                          ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),

                // Selector de tipo (segmentado)
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Row(children: [
                    _segBtn('Reconocimiento', 'reconocimiento',
                        Icons.emoji_events_outlined),
                    const SizedBox(width: 5),
                    _segBtn('Constancia', 'constancia',
                        Icons.verified_outlined),
                  ]),
                ),
                const SizedBox(height: 14),

                // Plantilla / diseño
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(Icons.style_outlined,
                          _esRec ? 'Diseño del reconocimiento' : 'Plantilla'),
                      _cargando
                          ? const LinearProgressIndicator(color: cessumRed)
                          : DropdownButtonFormField<String>(
                              initialValue: selKey,
                              isExpanded: true,
                              decoration: _dec('Selecciona'),
                              items: [
                                for (final v in lista)
                                  DropdownMenuItem(
                                      value: v['key'],
                                      child: Text(v['label'] ?? '')),
                              ],
                              onChanged: (v) => setState(() {
                                if (_esRec) {
                                  _recVariante = v;
                                } else {
                                  _consPlantilla = v;
                                }
                              }),
                            ),
                    ],
                  ),
                ),

                // Datos del evento / motivo
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(Icons.event_note_outlined,
                          _esRec ? 'Motivo' : 'Datos del evento'),
                      if (_esRec) ...[
                        TextField(
                          controller: _motivo,
                          maxLines: 2,
                          decoration: _dec('Motivo del reconocimiento',
                              hint:
                                  'Ej. su destacada participación en el Congreso…'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _fecha,
                          decoration: _dec('Lugar y fecha (opcional)',
                              hint: 'Navojoa, Sonora, a … (si se omite, hoy)'),
                        ),
                      ] else ...[
                        DropdownButtonFormField<String>(
                          initialValue: _tipoEvento,
                          isExpanded: true,
                          decoration: _dec('Tipo de evento'),
                          items: [
                            for (final t in _tiposEvento)
                              DropdownMenuItem(value: t, child: Text(t)),
                          ],
                          onChanged: (v) =>
                              setState(() => _tipoEvento = v ?? 'Taller'),
                        ),
                        if (_tipoEvento == 'Otro') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _tipoEventoOtro,
                            decoration: _dec('Especifica el tipo de evento',
                                hint: 'Ej. Curso-taller, Coloquio…'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: _taller,
                          decoration: _dec('Nombre / título del evento',
                              hint: 'Ej. Adicciones: Prevención y Apoyo…'),
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: TextField(
                              controller: _horas,
                              keyboardType: TextInputType.number,
                              decoration: _dec('Horas', hint: 'Ej. 2'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _fechaEvento,
                              decoration: _dec('Fecha del evento',
                                  hint: 'Ej. 4 de diciembre de 2025'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: _tipoParticipacion,
                          isExpanded: true,
                          decoration: _dec('Tipo de participación'),
                          items: [
                            for (final t in _tiposParticipacion)
                              DropdownMenuItem(value: t, child: Text(t)),
                          ],
                          onChanged: (v) => setState(
                              () => _tipoParticipacion = v ?? 'Participante'),
                        ),
                        if (_tipoParticipacion == 'Otro') ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: _tipoPartOtro,
                            decoration: _dec('Especifica la participación',
                                hint: 'Ej. Ponente magistral, Jurado…'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: _fecha,
                          decoration: _dec('Fecha de expedición (opcional)',
                              hint: 'Si tu plantilla usa {{fecha}}'),
                        ),
                      ],
                    ],
                  ),
                ),

                // Personas
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label(Icons.groups_outlined, 'Personas'),
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: cessumGold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Una persona por línea. Pon una COMA entre el nombre '
                          'completo y el correo:  "Nombre Apellidos, '
                          'correo@ejemplo.com".  También puedes pegar directo '
                          'desde tu hoja; el correo se detecta solo.',
                          style:
                              TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ),
                      TextField(
                        controller: _lista,
                        maxLines: 9,
                        onChanged: (_) => setState(() {}),
                        decoration: _dec('Lista',
                            hint:
                                'Ángel Ramiro Buitimea Valenzuela, correo@mail.com\n'
                                'Adriana Montes Alvarado, cecilia@hotmail.com'),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: cessumRed.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${personas.length} persona(s) · $conCorreo con correo',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: cessumRed,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: cessumRed,
                        title: const Text('Enviar a cada quien su PDF por correo'),
                        subtitle: const Text(
                            'Con el mensaje institucional. Solo a quienes tengan '
                            'correo.'),
                        value: _enviarCorreo,
                        onChanged: (v) => setState(() => _enviarCorreo = v),
                      ),
                    ],
                  ),
                ),

                // Acciones
                if (!_esRec) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      side: const BorderSide(color: cessumRed),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _generar(prueba: true),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Vista previa (1 de muestra)'),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _generar(),
                    icon: const Icon(Icons.verified),
                    label: Text(_esRec
                        ? 'Generar reconocimientos con QR'
                        : 'Generar constancias con QR'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

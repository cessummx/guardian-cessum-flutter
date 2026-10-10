import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: genera CONSTANCIAS desde las plantillas de Google Slides (CONEPSIA,
/// Doctorado…), con QR de verificación. Pega nombre, apellido y correo;
/// opcionalmente envía a cada quien su PDF.
class ConstanciasPlantillaScreen extends StatefulWidget {
  const ConstanciasPlantillaScreen({super.key});

  @override
  State<ConstanciasPlantillaScreen> createState() =>
      _ConstanciasPlantillaScreenState();
}

class _Persona {
  final String nombres;
  final String apellidos;
  final String correo;
  _Persona(this.nombres, this.apellidos, this.correo);
  String get full => '$nombres $apellidos'.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _ConstanciasPlantillaScreenState
    extends State<ConstanciasPlantillaScreen> {
  final _motivo = TextEditingController();
  final _fecha = TextEditingController();
  final _taller = TextEditingController();
  final _horas = TextEditingController();
  final _fechaEvento = TextEditingController();
  final _lista = TextEditingController();

  List<Map<String, String>> _plantillas = [];
  String? _plantilla;
  bool _enviarCorreo = false;
  bool _cargando = true;
  bool _generando = false;

  @override
  void initState() {
    super.initState();
    _cargarPlantillas();
  }

  @override
  void dispose() {
    _motivo.dispose();
    _fecha.dispose();
    _taller.dispose();
    _horas.dispose();
    _fechaEvento.dispose();
    _lista.dispose();
    super.dispose();
  }

  Future<void> _cargarPlantillas() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'constancia_plantillas'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _plantillas = ((data['plantillas'] as List<dynamic>? ?? [])).map((e) {
          final m = e as Map<String, dynamic>;
          return {
            'key': (m['key'] ?? '').toString(),
            'label': (m['label'] ?? '').toString(),
          };
        }).toList();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _plantilla = _plantillas.isNotEmpty ? _plantillas.first['key'] : null;
        _cargando = false;
      });
    }
  }

  // Cada línea -> {nombres, apellidos, correo}. Acepta pegado desde la hoja
  // (fecha, nombres, apellidos, correo) o "Nombre Apellido, correo".
  List<_Persona> _parsear() {
    final out = <_Persona>[];
    for (final raw in _lista.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final partes = line.contains('\t')
          ? line.split('\t')
          : line.split(RegExp(r'[,;]'));
      int idxMail = -1;
      for (var i = 0; i < partes.length; i++) {
        if (partes[i].contains('@')) {
          idxMail = i;
          break;
        }
      }
      String correo = '';
      List<String> antes;
      if (idxMail >= 0) {
        correo = partes[idxMail].trim();
        antes = partes.sublist(0, idxMail);
      } else {
        antes = List<String>.from(partes);
      }
      // Quita marcas de tiempo / fechas / teléfonos del inicio.
      antes = antes
          .map((s) => s.trim())
          .where((s) =>
              s.isNotEmpty && RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(s))
          .toList();
      String nombres = '';
      String apellidos = '';
      if (antes.length >= 2) {
        // Columnas separadas (nombres | apellidos).
        nombres = antes[antes.length - 2];
        apellidos = antes[antes.length - 1];
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

  Future<void> _generar({bool prueba = false}) async {
    final personas = _parsear();
    if (_plantilla == null) {
      _aviso('Elige una plantilla.', error: true);
      return;
    }
    if (personas.isEmpty) {
      _aviso('Agrega al menos una persona.', error: true);
      return;
    }
    if (!prueba && personas.length > 40) {
      _aviso('Máximo 40 por lote.', error: true);
      return;
    }
    final conCorreo = personas.where((p) => p.correo.isNotEmpty).length;
    if (!prueba && _enviarCorreo && conCorreo == 0) {
      _aviso('Activaste el envío pero ninguna persona tiene correo.',
          error: true);
      return;
    }

    setState(() => _generando = true);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'constancia_plantilla_lote',
                'actor': actor,
                'variante': _plantilla,
                'motivo': _motivo.text.trim(),
                'fecha': _fecha.text.trim(),
                'taller': _taller.text.trim(),
                'horas': _horas.text.trim(),
                'fechaEvento': _fechaEvento.text.trim(),
                'enviarCorreo': prueba ? false : _enviarCorreo,
                'prueba': prueba,
                'personas': personas
                    .map((p) => {
                          'nombres': p.nombres,
                          'apellidos': p.apellidos,
                          'correo': p.correo,
                        })
                    .toList(),
              }))
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
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Vista previa'),
            content: const Text(
                'Generé una constancia de muestra (no se envió ni se '
                'registró). Ábrela para revisar nombre, QR y diseño antes '
                'de generar el lote.'),
            actions: [
              if (primerPdf.isNotEmpty)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white),
                  onPressed: () {
                    Helpers.abrirUrlExterna(primerPdf, context);
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir la muestra'),
                ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar')),
            ],
          ),
        );
        return;
      }

      final enviados = data['enviados'] ?? 0;
      final total = data['total'] ?? data['generadas'] ?? docs.length;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Constancias generadas'),
          content: Text(
            'Se generaron $total constancias con QR'
            '${_enviarCorreo ? ' y se enviaron $enviados por correo.' : '.'}\n\n'
            'Quedaron registradas con folio para su verificación.',
          ),
          actions: [
            if (primerPdf.isNotEmpty)
              TextButton(
                onPressed: () {
                  Helpers.abrirUrlExterna(primerPdf, context);
                },
                child: const Text('Abrir la primera'),
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
    } catch (e) {
      if (mounted) setState(() => _generando = false);
      _aviso('No se pudo generar: $e'.replaceAll('Exception: ', ''),
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final personas = _parsear();
    final conCorreo = personas.where((p) => p.correo.isNotEmpty).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Constancias por plantilla · b2'),
      ),
      body: _generando
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: cessumRed),
              SizedBox(height: 12),
              Text('Generando con QR… puede tardar si son varias.'),
            ]))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _seccion('Plantilla'),
                _cargando
                    ? const LinearProgressIndicator(color: cessumRed)
                    : DropdownButtonFormField<String>(
                        initialValue: _plantilla,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Plantilla',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final v in _plantillas)
                            DropdownMenuItem(
                                value: v['key'], child: Text(v['label'] ?? '')),
                        ],
                        onChanged: (v) => setState(() => _plantilla = v),
                      ),
                _seccion('Datos del evento'),
                TextField(
                  controller: _taller,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del taller / curso / conferencia',
                    hintText: 'Ej. Adicciones en Hijos: Prevención y Apoyo…',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _horas,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Horas',
                          hintText: 'Ej. 2',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _fechaEvento,
                        decoration: const InputDecoration(
                          labelText: 'Fecha del evento',
                          hintText: 'Ej. 4 de diciembre de 2025',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _fecha,
                  decoration: const InputDecoration(
                    labelText: 'Fecha de expedición (opcional)',
                    hintText: 'Si tu plantilla usa {{fecha}}',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                _seccion('Personas'),
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Una persona por línea. Puedes pegar directo desde tu hoja '
                    '(nombre, apellido y correo) o escribir "Nombre Apellido, '
                    'correo". El correo se detecta solo.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                TextField(
                  controller: _lista,
                  maxLines: 10,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText:
                        'Ángel Ramiro\tBuitimea Valenzuela\tam452323@gmail.com\n'
                        'Adriana Cecilia, Montes Alvarado, ceciliamontes424@hotmail.com',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${personas.length} persona(s) · $conCorreo con correo',
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: cessumRed,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: cessumRed,
                  title: const Text('Enviar a cada quien su PDF por correo'),
                  subtitle: const Text(
                      'Con el mensaje de felicitación. Solo a quienes tengan '
                      'correo.'),
                  value: _enviarCorreo,
                  onChanged: (v) => setState(() => _enviarCorreo = v),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed: () => _generar(prueba: true),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Vista previa (1 de muestra)'),
                ),
                const SizedBox(height: 10),
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
                    onPressed: () => _generar(),
                    icon: const Icon(Icons.verified),
                    label: const Text('Generar constancias con QR'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed)),
      );
}

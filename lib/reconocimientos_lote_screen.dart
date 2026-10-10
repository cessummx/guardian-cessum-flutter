import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: genera RECONOCIMIENTOS en lote eligiendo una plantilla (variante),
/// pegando los nombres (y opcionalmente correos). Puede enviar a cada quien
/// su PDF por correo.
class ReconocimientosLoteScreen extends StatefulWidget {
  const ReconocimientosLoteScreen({super.key});

  @override
  State<ReconocimientosLoteScreen> createState() =>
      _ReconocimientosLoteScreenState();
}

class _Persona {
  final String nombre;
  final String correo;
  _Persona(this.nombre, this.correo);
}

class _ReconocimientosLoteScreenState extends State<ReconocimientosLoteScreen> {
  final _motivo = TextEditingController();
  final _fecha = TextEditingController();
  final _lista = TextEditingController();

  List<Map<String, String>> _variantes = [];
  String? _variante;
  bool _enviarCorreo = false;
  bool _cargandoVar = true;
  bool _generando = false;

  @override
  void initState() {
    super.initState();
    _cargarVariantes();
  }

  @override
  void dispose() {
    _motivo.dispose();
    _fecha.dispose();
    _lista.dispose();
    super.dispose();
  }

  Future<void> _cargarVariantes() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'reconocimiento_variantes'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _variantes = ((data['variantes'] as List<dynamic>? ?? [])).map((e) {
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
        _variante = _variantes.isNotEmpty ? _variantes.first['key'] : null;
        _cargandoVar = false;
      });
    }
  }

  // Convierte el texto pegado en personas {nombre, correo}.
  // Acepta: solo nombre · "Nombre, correo" · líneas pegadas de una hoja
  // (toma el campo con @ como correo y lo de antes como nombre).
  List<_Persona> _parsear() {
    final out = <_Persona>[];
    for (var raw in _lista.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final partes =
          line.contains('\t') ? line.split('\t') : line.split(RegExp(r'[,;]'));
      int idxMail = -1;
      for (var i = 0; i < partes.length; i++) {
        if (partes[i].contains('@')) {
          idxMail = i;
          break;
        }
      }
      String correo = '';
      List<String> nombrePartes;
      if (idxMail >= 0) {
        correo = partes[idxMail].trim();
        nombrePartes = partes.sublist(0, idxMail);
      } else {
        nombrePartes = [partes.first];
      }
      // Quita marcas de tiempo o fechas del inicio.
      nombrePartes = nombrePartes
          .map((s) => s.trim())
          .where((s) =>
              s.isNotEmpty &&
              !RegExp(r'^\d{1,4}[/:\-]').hasMatch(s) &&
              RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]').hasMatch(s))
          .toList();
      final nombre = nombrePartes.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (nombre.isNotEmpty) out.add(_Persona(nombre, correo));
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

  Future<void> _generar() async {
    final personas = _parsear();
    if (_variante == null) {
      _aviso('Elige una plantilla.', error: true);
      return;
    }
    if (_motivo.text.trim().isEmpty) {
      _aviso('Escribe el motivo del reconocimiento.', error: true);
      return;
    }
    if (personas.isEmpty) {
      _aviso('Agrega al menos una persona.', error: true);
      return;
    }
    if (personas.length > 60) {
      _aviso('Máximo 60 por lote.', error: true);
      return;
    }
    final conCorreo = personas.where((p) => p.correo.isNotEmpty).length;
    if (_enviarCorreo && conCorreo == 0) {
      _aviso('Activaste el envío por correo pero ninguna persona tiene correo.',
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
                'accion': 'reconocimiento_lote',
                'actor': actor,
                'variante': _variante,
                'motivo': _motivo.text.trim(),
                'fecha': _fecha.text.trim(),
                'enviarCorreo': _enviarCorreo,
                'personas': personas
                    .map((p) => {'nombre': p.nombre, 'correo': p.correo})
                    .toList(),
              }))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() => _generando = false);
      final pdf = (data['pdf'] ?? '').toString();
      final enviados = data['enviados'] ?? 0;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reconocimientos generados'),
          content: Text(
            'Se generaron ${data['total']} reconocimientos'
            '${_enviarCorreo ? ' y se enviaron $enviados por correo.' : '.'}',
          ),
          actions: [
            if (pdf.isNotEmpty)
              TextButton(
                onPressed: () {
                  Helpers.abrirUrlExterna(pdf, context);
                },
                child: const Text('Abrir PDF'),
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
        title: const Text('Reconocimientos en lote'),
      ),
      body: _generando
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: cessumRed),
              SizedBox(height: 12),
              Text('Generando… puede tardar si son muchos.'),
            ]))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _seccion('Plantilla'),
                _cargandoVar
                    ? const LinearProgressIndicator(color: cessumRed)
                    : DropdownButtonFormField<String>(
                        initialValue: _variante,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Variante',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final v in _variantes)
                            DropdownMenuItem(
                                value: v['key'], child: Text(v['label'] ?? '')),
                        ],
                        onChanged: (v) => setState(() => _variante = v),
                      ),
                _seccion('Motivo'),
                TextField(
                  controller: _motivo,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText:
                        'Ej. Por su participación en el Congreso CONEDU 2026…',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _fecha,
                  decoration: const InputDecoration(
                    labelText: 'Fecha (opcional)',
                    hintText: 'Si lo dejas vacío, pone la fecha de hoy',
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
                  child: Text(
                    'Una persona por línea. Puede ser solo el nombre, o '
                    '"Nombre, correo". También puedes pegar directo desde tu '
                    'hoja (detecta el correo automáticamente).',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                  ),
                ),
                TextField(
                  controller: _lista,
                  maxLines: 10,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText:
                        'Ángel Ramiro Leonardo Buitimea Valenzuela, am452323@gmail.com\n'
                        'Adriana Cecilia Montes Alvarado, ceciliamontes424@hotmail.com',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${personas.length} persona(s) detectada(s) · '
                  '$conCorreo con correo',
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
                      'Solo a quienes tengan correo. Si lo dejas apagado, '
                      'solo se genera el PDF para descargar.'),
                  value: _enviarCorreo,
                  onChanged: (v) => setState(() => _enviarCorreo = v),
                ),
                const SizedBox(height: 14),
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
                    onPressed: _generar,
                    icon: const Icon(Icons.workspace_premium),
                    label: const Text('Generar reconocimientos'),
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

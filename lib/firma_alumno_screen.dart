// firma_alumno_screen.dart
// Pantalla para que el ESTUDIANTE registre/actualice su firma digital.
// El backend (Guardián) ya tiene los endpoints:
//   POST firma_alumno_guardar  { matricula, imagenBase64 }   (PNG SIN fondo)
//   GET  firma_alumno_estado   ?matricula=...   -> { ok, tiene, url }
//   GET  firma_alumno_imagen   ?matricula=...   -> { ok, b64 }
//
// Uso (agregar un botón en el menú o en la pantalla de tesis):
//   import 'firma_alumno_screen.dart';
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => FirmaAlumnoScreen(matricula: miMatricula)));
//
// Es autónoma: solo usa material, http y dart:html (Flutter web).

import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class FirmaAlumnoScreen extends StatefulWidget {
  final String matricula;
  const FirmaAlumnoScreen({super.key, required this.matricula});

  @override
  State<FirmaAlumnoScreen> createState() => _FirmaAlumnoScreenState();
}

class _FirmaAlumnoScreenState extends State<FirmaAlumnoScreen> {
  static const String _guardianUrl = 'https://app.cessum.mx/guardian.php';
  static const Color _rojo = Color(0xFFB11D29);
  static const Color _dorado = Color(0xFFA56B16);

  bool _cargando = true;
  bool _subiendo = false;
  bool _tiene = false;
  String? _previewB64; // base64 PNG de la firma actual
  String _msg = '';
  bool _msgError = false;

  @override
  void initState() {
    super.initState();
    _cargarEstado();
  }

  Future<void> _cargarEstado() async {
    setState(() {
      _cargando = true;
      _msg = '';
    });
    try {
      final mat = Uri.encodeComponent(widget.matricula);
      final est = await http.get(Uri.parse(
          '$_guardianUrl?accion=firma_alumno_estado&matricula=$mat'));
      final je = jsonDecode(est.body) as Map<String, dynamic>;
      final tiene = je['tiene'] == true;
      String? b64;
      if (tiene) {
        final img = await http.get(Uri.parse(
            '$_guardianUrl?accion=firma_alumno_imagen&matricula=$mat'));
        final ji = jsonDecode(img.body) as Map<String, dynamic>;
        if (ji['ok'] == true && ji['b64'] != null) {
          b64 = ji['b64'] as String;
        }
      }
      if (!mounted) return;
      setState(() {
        _tiene = tiene;
        _previewB64 = b64;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _msg = 'No se pudo cargar el estado de tu firma. Revisa tu conexión.';
        _msgError = true;
      });
    }
  }

  Future<void> _elegirYSubir() async {
    final input = html.FileUploadInputElement()..accept = 'image/png';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;
    final file = input.files!.first;

    if (!file.name.toLowerCase().endsWith('.png')) {
      setState(() {
        _msg = 'El archivo debe ser PNG con fondo transparente (sin fondo).';
        _msgError = true;
      });
      return;
    }

    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first;
    final dataUrl = reader.result as String; // data:image/png;base64,XXXX

    await _subir(dataUrl);
  }

  Future<void> _subir(String dataUrl) async {
    setState(() {
      _subiendo = true;
      _msg = '';
    });
    try {
      final resp = await http.post(
        Uri.parse(_guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'accion': 'firma_alumno_guardar',
          'matricula': widget.matricula,
          'imagenBase64': dataUrl,
        }),
      );
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (j['ok'] == true) {
        setState(() {
          _subiendo = false;
          _msg = '¡Listo! Tu firma quedó registrada. Ya puedes firmar tu convenio.';
          _msgError = false;
        });
        await _cargarEstado();
      } else {
        setState(() {
          _subiendo = false;
          _msg = (j['error'] ?? 'No se pudo guardar la firma.').toString();
          _msgError = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subiendo = false;
        _msg = 'Error al subir la firma. Inténtalo de nuevo.';
        _msgError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _rojo,
        foregroundColor: Colors.white,
        title: const Text('Mi firma digital'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _rojo))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tarjetaInfo(),
                  const SizedBox(height: 16),
                  _tarjetaFirma(),
                  if (_msg.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _aviso(),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _subiendo ? null : _elegirYSubir,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _rojo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _subiendo
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.upload_file),
                    label: Text(_subiendo
                        ? 'Subiendo...'
                        : (_tiene
                            ? 'Reemplazar mi firma (PNG sin fondo)'
                            : 'Subir mi firma (PNG sin fondo)')),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tarjetaInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E2D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.draw, color: _dorado),
              SizedBox(width: 8),
              Expanded(
                child: Text('Registra tu firma para poder firmar tu convenio',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Sube una imagen PNG de tu firma CON FONDO TRANSPARENTE (sin fondo '
            'blanco). Una vez registrada, el botón "Firmar como estudiante" '
            'funcionará en tu convenio de tesis.',
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaFirma() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7E2D6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(_tiene ? Icons.check_circle : Icons.info_outline,
                  color: _tiene ? Colors.green : Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                _tiene ? 'Firma registrada' : 'Aún no tienes firma registrada',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _tiene ? Colors.green.shade800 : Colors.orange.shade800),
              ),
            ],
          ),
          if (_tiene && _previewB64 != null) ...[
            const SizedBox(height: 14),
            Container(
              height: 120,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFD9C189)),
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFFFFFDF8),
              ),
              child: Image.memory(base64Decode(_previewB64!),
                  fit: BoxFit.contain),
            ),
          ],
        ],
      ),
    );
  }

  Widget _aviso() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _msgError ? const Color(0xFFFDECEC) : const Color(0xFFEAF6EC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: _msgError ? const Color(0xFFE3A0A0) : const Color(0xFFA9D5B3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_msgError ? Icons.error_outline : Icons.check_circle_outline,
              color: _msgError ? _rojo : Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_msg,
                style: TextStyle(
                    fontSize: 13,
                    color: _msgError ? const Color(0xFF8B1A1A) : const Color(0xFF1B6B2E))),
          ),
        ],
      ),
    );
  }
}

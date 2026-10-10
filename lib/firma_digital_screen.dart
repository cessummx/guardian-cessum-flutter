import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

/// Pantalla del portal docente: subir / actualizar la firma digital.
/// La firma se guarda en el servidor y el Guardián la coloca automáticamente
/// dentro del acta de calificaciones de ese docente.
///
/// Recomendación al docente: subir un PNG con fondo transparente (sin fondo).
/// Si la sube con fondo blanco, marca la casilla y el sistema la encuadra en
/// un recuadro de dimensión fija para que el bloque blanco se vea ordenado.
class FirmaDigitalScreen extends StatefulWidget {
  const FirmaDigitalScreen({super.key});

  @override
  State<FirmaDigitalScreen> createState() => _FirmaDigitalScreenState();
}

class _FirmaDigitalScreenState extends State<FirmaDigitalScreen> {
  String _correo = '';
  bool _cargando = true;
  bool _guardando = false;
  bool _conFondo = false;
  bool _quitarFondo = true; // por defecto: dejar la firma sin fondo
  String? _dataUrlOriginal; // imagen tal cual la subió (para reprocesar)

  String? _firmaActualUrl; // firma ya guardada (si existe)
  Uint8List? _bytesActual; // bytes de la firma guardada (para previsualizar)
  Uint8List? _bytesNueva; // imagen recién seleccionada (para previsualizar)
  String? _dataUrlNueva; // base64 (data URL) para enviar al Guardián

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _correo = await SessionStore.validEmail() ?? '';
    await _cargarEstado();
  }

  Future<void> _cargarEstado() async {
    setState(() => _cargando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'firma_docente_estado',
        'correo': _correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['tiene'] == true) {
        _firmaActualUrl = (data['url'] ?? '').toString();
        _conFondo = data['conFondo'] == true;
        await _cargarImagenFirma();
      } else {
        _firmaActualUrl = null;
        _bytesActual = null;
      }
    } catch (_) {
      // si falla, simplemente no mostramos firma previa
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarImagenFirma() async {
    try {
      final solicitante = await SessionStore.realEmail() ?? _correo;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'firma_docente_imagen',
        'correo': _correo,
        'solicitante': solicitante,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && (data['b64'] ?? '').toString().isNotEmpty) {
        _bytesActual = base64Decode(data['b64'].toString());
      } else {
        _bytesActual = null;
      }
    } catch (_) {
      _bytesActual = null;
    }
  }

  void _seleccionar() {
    final input = html.FileUploadInputElement()
      ..accept = 'image/png,image/jpeg';
    input.click();
    input.onChange.listen((_) {
      final files = input.files;
      if (files == null || files.isEmpty) return;
      final reader = html.FileReader();
      reader.readAsDataUrl(files.first);
      reader.onLoadEnd.listen((_) {
        _dataUrlOriginal = reader.result as String;
        _reprocesarFirma();
      });
    });
  }

  // Reprocesa la imagen seleccionada según la opción "quitar fondo".
  Future<void> _reprocesarFirma() async {
    final orig = _dataUrlOriginal;
    if (orig == null) return;
    final procesado = await _procesarFirma(orig, _quitarFondo);
    if (!mounted) return;
    if (procesado == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No pudimos leer la imagen. Sube una foto o un PNG de tu firma.'),
        backgroundColor: cessumRed,
      ));
      setState(() {
        _bytesNueva = null;
        _dataUrlNueva = null;
      });
      return;
    }
    final b64 = procesado.substring(procesado.indexOf(',') + 1);
    setState(() {
      _dataUrlNueva = procesado;
      _bytesNueva = base64Decode(b64);
      _conFondo = !_quitarFondo;
    });
  }

  // Dibuja la imagen en un canvas y, si se pide, vuelve transparente el fondo
  // blanco (píxeles casi blancos -> alfa 0). Devuelve un data URL PNG, o null
  // si no se pudo leer la imagen. Acepta PNG y JPG (fotos de la firma).
  Future<String?> _procesarFirma(String dataUrl, bool quitarFondo) async {
    final completer = Completer<String?>();
    final img = html.ImageElement();
    img.onError.listen((_) {
      if (!completer.isCompleted) completer.complete(null);
    });
    img.onLoad.listen((_) {
      try {
        final w = img.width ?? 0;
        final h = img.height ?? 0;
        if (w == 0 || h == 0) {
          if (!completer.isCompleted) completer.complete(null);
          return;
        }
        final canvas = html.CanvasElement(width: w, height: h);
        final ctx = canvas.context2D;
        ctx.drawImage(img, 0, 0);
        if (quitarFondo) {
          final imageData = ctx.getImageData(0, 0, w, h);
          final d = imageData.data;
          for (var i = 0; i < d.length; i += 4) {
            if (d[i] > 238 && d[i + 1] > 238 && d[i + 2] > 238) {
              d[i + 3] = 0; // píxel casi blanco -> transparente
            }
          }
          ctx.putImageData(imageData, 0, 0);
        }
        if (!completer.isCompleted) {
          completer.complete(canvas.toDataUrl('image/png'));
        }
      } catch (_) {
        if (!completer.isCompleted) completer.complete(null);
      }
    });
    img.src = dataUrl;
    return completer.future;
  }

  // '' = PNG con transparencia (válido); si no, el motivo del rechazo.
  String _motivoPngInvalido(Uint8List b) {
    if (b.length < 33) return 'archivo_invalido';
    const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < 8; i++) {
      if (b[i] != sig[i]) return 'no_png';
    }
    final ct = b[25];
    if (ct == 6 || ct == 4) return '';
    if (ct == 3) {
      for (var j = 8; j < b.length - 4; j++) {
        if (b[j] == 0x74 && b[j + 1] == 0x52 && b[j + 2] == 0x4E &&
            b[j + 3] == 0x53) {
          return '';
        }
      }
      return 'sin_transparencia';
    }
    return 'sin_transparencia';
  }

  String _msgFirmaInvalida(String motivo) {
    switch (motivo) {
      case 'no_png':
        return 'La firma debe ser un archivo PNG con fondo transparente (sin fondo).';
      case 'sin_transparencia':
        return 'La firma debe ser un PNG SIN fondo (transparente). Tu archivo tiene fondo; quítaselo y vuelve a subirla.';
      default:
        return 'No pudimos leer la imagen. Sube un PNG con fondo transparente.';
    }
  }

  Future<void> _guardar() async {
    if (_dataUrlNueva == null || _correo.isEmpty) return;
    setState(() => _guardando = true);
    try {
      final solicitante = await SessionStore.realEmail() ?? _correo;
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'firma_docente_guardar',
              'correo': _correo,
              'solicitante': solicitante,
              'imagenBase64': _dataUrlNueva,
              'conFondo': _conFondo,
            }),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Firma guardada. Se colocará automáticamente en tus actas.'),
          backgroundColor: Color(0xFF1E8E3E),
        ));
        setState(() {
          _bytesNueva = null;
          _dataUrlNueva = null;
        });
        await _cargarEstado();
      } else {
        throw Exception(data['error'] ?? 'No se pudo guardar');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al guardar la firma: $e'),
          backgroundColor: cessumRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Subir firma digital'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _tarjetaRecomendaciones(),
                const SizedBox(height: 16),
                if (_firmaActualUrl != null && _firmaActualUrl!.isNotEmpty) ...[
                  _tarjetaFirmaActual(),
                  const SizedBox(height: 16),
                ],
                _tarjetaNueva(),
              ],
            ),
    );
  }

  Widget _tarjetaRecomendaciones() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, color: cessumGold, size: 20),
              SizedBox(width: 8),
              Text('Recomendaciones',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: cessumGold)),
            ],
          ),
          SizedBox(height: 10),
          Text(
            '• Puedes subir tu firma como PNG o como foto (JPG). El sistema le '
            'quita el fondo blanco automáticamente y la deja transparente.\n'
            '• Usa una imagen horizontal de tu firma, nítida y oscura sobre '
            'fondo claro.\n'
            '• Si prefieres conservar el fondo, desactiva la casilla "Quitar '
            'el fondo blanco" antes de guardar.',
            style: TextStyle(fontSize: 13, height: 1.5, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaFirmaActual() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Firma registrada actualmente',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 240,
              height: 95,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(6),
              ),
              child: _bytesActual != null
                  ? Image.memory(_bytesActual!, fit: BoxFit.contain)
                  : Image.network(
                      _firmaActualUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text(
                          'No se pudo cargar',
                          style:
                              TextStyle(color: Colors.black45, fontSize: 12)),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _conFondo
                  ? 'Guardada con fondo blanco (encuadrada).'
                  : 'Guardada con fondo transparente.',
              style: const TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text('Puedes reemplazarla subiendo una nueva abajo.',
                style: TextStyle(fontSize: 11.5, color: Colors.black45)),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaNueva() {
    final hayNueva = _bytesNueva != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _firmaActualUrl != null ? 'Reemplazar firma' : 'Subir mi firma',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed, width: 1.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _guardando ? null : _seleccionar,
              icon: const Icon(Icons.upload_file),
              label: Text(hayNueva ? 'Elegir otra imagen' : 'Seleccionar imagen'),
            ),
          ),
          if (hayNueva) ...[
            const SizedBox(height: 16),
            const Text('Vista previa:',
                style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 240,
                height: 95,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _conFondo ? Colors.white : const Color(0xFFF0F0F0),
                  border: Border.all(
                    color: _conFondo ? Colors.black45 : Colors.black12,
                    width: _conFondo ? 1.4 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Image.memory(_bytesNueva!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                _conFondo
                    ? 'Se guardará encuadrada (recuadro de dimensión fija).'
                    : 'Fondo gris claro solo para previsualizar; no se guarda.',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _quitarFondo,
              onChanged: (v) {
                setState(() => _quitarFondo = v ?? true);
                _reprocesarFirma();
              },
              activeColor: cessumRed,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Quitar el fondo blanco (recomendado)',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: const Text(
                  'Deja tu firma sin fondo para que se vea limpia sobre el '
                  'acta. Desactívalo si prefieres conservar el fondo.',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'Guardando...' : 'Guardar firma'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

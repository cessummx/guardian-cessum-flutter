import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'foto_web_picker.dart';
import 'student_profile.dart';

/// "Mi expediente" — el alumno carga por adelantado los documentos que NO
/// cambian (acta de nacimiento, CURP, título y cédula del grado previo).
/// Cuando solicite su titulación, estos documentos se jalan solos a su
/// expediente (el Guardián los migra). El kárdex, la constancia de no adeudo
/// y el comprobante de pago NO se suben aquí: se generan o se solicitan al
/// momento del trámite.
///
/// Backend:
///   GET  expediente_titulacion?matricula=...  -> {ok, enTitulacion, documentos}
///   POST expediente_titulacion_doc            -> sube un documento
class MiExpedienteScreen extends StatefulWidget {
  const MiExpedienteScreen({super.key});

  @override
  State<MiExpedienteScreen> createState() => _MiExpedienteScreenState();
}

class _MiExpedienteScreenState extends State<MiExpedienteScreen> {
  // Documentos que el alumno SÍ sube por adelantado.
  static const List<List<String>> _subibles = [
    ['actaNacimiento', 'Acta de nacimiento'],
    ['curp', 'CURP'],
    ['titulo', 'Título del grado previo'],
    ['cedula', 'Cédula del grado previo'],
  ];

  // Documentos que se generan o se solicitan al tramitar (no se suben aquí).
  static const List<List<String>> _despues = [
    ['Kárdex', 'Lo genera la institución cuando tramitas.'],
    ['Constancia de no adeudo', 'Se solicita al iniciar el trámite.'],
    ['Comprobante de pago de titulación', 'Se sube cuando realizas el pago.'],
  ];

  StudentProfile? _perfil;
  bool _cargando = true;
  String? _error;
  bool _enTitulacion = false;
  String? _subiendo;
  final Map<String, Map<String, dynamic>> _docs = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      _perfil ??= await StudentProfile.load();
      final mat = _perfil?.matricula ?? '';
      if (mat.isEmpty) throw Exception('Sin matrícula');
      final uri = Uri.parse(
          '$guardianUrl?accion=expediente_titulacion&matricula=${Uri.encodeComponent(mat)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _docs.clear();
      for (final d in (data['documentos'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(d as Map);
        _docs['${m['tipo']}'] = m;
      }
      if (!mounted) return;
      setState(() {
        _enTitulacion = data['enTitulacion'] == true;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu expediente.';
      });
    }
  }

  Future<void> _subir(String tipo) async {
    try {
      final doc = await seleccionarDocumento();
      if (doc == null) return;
      setState(() => _subiendo = tipo);
      final mat = _perfil?.matricula ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'expediente_titulacion_doc',
                'matricula': mat,
                'tipo': tipo,
                'base64': base64Encode(doc.bytes),
                'mime': doc.mime,
                'nombreArchivo': doc.nombre,
              }))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _msg('Documento subido correctamente.');
      await _cargar();
    } catch (e) {
      _msg('No se pudo subir. Intenta de nuevo.', error: true);
    } finally {
      if (mounted) setState(() => _subiendo = null);
    }
  }

  Future<void> _ver(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      _msg('No se pudo abrir el documento.', error: true);
    }
  }

  void _msg(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi expediente'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _contenido(),
    );
  }

  Widget _contenido() {
    final fuerte = cessumIsDark(context) ? Colors.white : cessumInk(context);
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Adelanta tu expediente. Sube aquí los documentos que no cambian; '
              'cuando tramites tu titulación se agregarán automáticamente a tu '
              'solicitud y avanzarás más rápido.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.4, color: cessumMuted(context)),
            ),
          ),
          if (_enTitulacion) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_outlined,
                      color: cessumRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ya iniciaste tu titulación: lo que subas aquí se refleja '
                      'directo en tu expediente de titulación.',
                      style:
                          TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text('Documentos a cargar',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 8),
          ..._subibles.map((d) => _tarjetaDoc(d[0], d[1])),
          const SizedBox(height: 18),
          Text('No necesitas subir estos',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: fuerte)),
          const SizedBox(height: 8),
          ..._despues.map(_tarjetaDespues),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _tarjetaDoc(String tipo, String etiqueta) {
    final d = _docs[tipo] ?? const {};
    final url = '${d['url'] ?? ''}';
    final estatus = '${d['estatus'] ?? ''}';
    final obs = '${d['observacion'] ?? ''}';
    final tiene = url.isNotEmpty;
    final st = estatus.toLowerCase();

    Color cEst;
    String txtEst;
    if (st.contains('valid')) {
      cEst = const Color(0xFF1E8E3E);
      txtEst = 'Validado';
    } else if (st.contains('rechaz')) {
      cEst = cessumRed;
      txtEst = 'Rechazado';
    } else if (tiene) {
      cEst = cessumGold;
      txtEst = estatus.isEmpty ? 'Subido' : estatus;
    } else {
      cEst = Colors.grey;
      txtEst = 'Falta subir';
    }

    final subiendo = _subiendo == tipo;
    final fuerte = cessumIsDark(context) ? Colors.white : cessumInk(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(etiqueta,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fuerte)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: cEst.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(txtEst,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cEst)),
              ),
            ],
          ),
          if (st.contains('rechaz') && obs.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Motivo: $obs',
                style: TextStyle(fontSize: 12, color: cessumRed)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (tiene)
                OutlinedButton.icon(
                  onPressed: () => _ver(url),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumGold,
                    side: const BorderSide(color: cessumGold),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                  ),
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Ver'),
                ),
              if (tiene) const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: subiendo ? null : () => _subir(tipo),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                ),
                icon: subiendo
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Icon(tiene ? Icons.refresh : Icons.upload_file, size: 16),
                label: Text(subiendo
                    ? 'Subiendo…'
                    : (tiene ? 'Cambiar' : 'Subir')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tarjetaDespues(List<String> d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: cessumFaint(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d[0],
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cessumMuted(context))),
                Text(d[1],
                    style:
                        TextStyle(fontSize: 11.5, color: cessumFaint(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

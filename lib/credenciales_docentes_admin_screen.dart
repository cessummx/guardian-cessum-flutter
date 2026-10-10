import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';

// =====================================================================
// PANEL ADMIN: credenciales de DOCENTES (aprobar / rechazar)
//   GET  credenciales_docentes_listar ?actor
//   POST credencial_docente_aprobar  { actor, id }
//   POST credencial_docente_rechazar { actor, id, observaciones }
// =====================================================================

class CredencialesDocentesAdminScreen extends StatefulWidget {
  const CredencialesDocentesAdminScreen({super.key});

  @override
  State<CredencialesDocentesAdminScreen> createState() =>
      _CredencialesDocentesAdminScreenState();
}

class _CredencialesDocentesAdminScreenState
    extends State<CredencialesDocentesAdminScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _cargando = true;
  String _actor = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    final actor = (await SessionStore.realEmail()) ?? '';
    _actor = actor;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'credenciales_docentes_listar',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No autorizado');
      }
      final lista = (data['credenciales'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar (¿tienes permisos de administrador?).';
      });
    }
  }

  Future<void> _resolver(String correo, String accion,
      {String obs = ''}) async {
    try {
      final payload = <String, dynamic>{
        'accion': accion,
        'actor': _actor,
        'id': correo,
      };
      if (obs.isNotEmpty) payload['observaciones'] = obs;
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _snack('Actualizado.');
        _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo actualizar.'}', esError: true);
      }
    } catch (_) {
      _snack('Error de conexión.', esError: true);
    }
  }

  Future<void> _verPdf(String correo) async {
    _snack('Generando PDF…');
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'credencial_docente_pdf',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final url = (data['url'] ?? '').toString();
      if (data['ok'] == true && url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _snack('${data['error'] ?? 'No se pudo generar el PDF.'}', esError: true);
      }
    } catch (_) {
      _snack('Error al generar el PDF.', esError: true);
    }
  }

  void _snack(String t, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: esError ? cessumRed : CC.goldDark,
    ));
  }

  Future<void> _rechazarConObs(String correo) async {
    final ctrl = TextEditingController();
    final obs = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Motivo del rechazo'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Ej. La foto no es clara / fondo no blanco…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (obs != null) {
      _resolver(correo, 'credencial_docente_rechazar', obs: obs);
    }
  }

  Color _colorEstado(String e) {
    switch (e.toLowerCase()) {
      case 'aprobada':
        return const Color(0xFF1E8E3E);
      case 'rechazada':
        return cessumRed;
      case 'observaciones':
        return CC.goldDark;
      default:
        return CC.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Credenciales docentes'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : RefreshIndicator(
              color: cessumRed,
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error,
                          style: const TextStyle(color: cessumRed)),
                    ),
                  if (_items.isEmpty && _error.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                          child: Text('No hay solicitudes de credencial.',
                              style: TextStyle(color: CC.muted))),
                    ),
                  ..._seccionesAgrupadas(),
                ],
              ),
            ),
    );
  }

  // Convierte 'dd/MM/yyyy HH:mm' a un valor comparable para ordenar por fecha
  // de solicitud (marca), más reciente primero.
  int _marcaOrden(Map<String, dynamic> c) {
    final s = (c['marca'] ?? '').toString().trim();
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})(?:\s+(\d{2}):(\d{2}))?')
        .firstMatch(s);
    if (m == null) return 0;
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    final h = int.parse(m.group(4) ?? '0');
    final mi = int.parse(m.group(5) ?? '0');
    return ((((y * 12 + mo) * 31 + d) * 24 + h) * 60 + mi);
  }

  List<Map<String, dynamic>> _delEstado(List<String> estados) {
    final out = _items.where((c) {
      final e = (c['estado'] ?? '').toString().toLowerCase();
      return estados.contains(e);
    }).toList();
    out.sort((a, b) => _marcaOrden(b).compareTo(_marcaOrden(a))); // reciente primero
    return out;
  }

  Widget _encabezado(String titulo, int n, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Container(width: 4, height: 18,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(titulo,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Text('$n',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }

  List<Widget> _seccionesAgrupadas() {
    final pendientes = _delEstado(['pendiente', '']);
    final aprobadas = _delEstado(['aprobada', 'aprobado']);
    final rechazadas = _delEstado(['rechazada', 'rechazado', 'observada']);
    final w = <Widget>[];
    if (pendientes.isNotEmpty) {
      w.add(_encabezado('Pendientes', pendientes.length, cessumGold));
      w.addAll(pendientes.map(_tarjeta));
    }
    if (aprobadas.isNotEmpty) {
      w.add(_encabezado('Aprobadas', aprobadas.length, const Color(0xFF1E8E3E)));
      w.addAll(aprobadas.map(_tarjeta));
    }
    if (rechazadas.isNotEmpty) {
      w.add(_encabezado('Rechazadas', rechazadas.length, cessumRed));
      w.addAll(rechazadas.map(_tarjeta));
    }
    return w;
  }

  Widget _tarjeta(Map<String, dynamic> c) {
    final correo = (c['correo'] ?? '').toString();
    final estado = (c['estado'] ?? '').toString();
    final obs = (c['observaciones'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CC.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FotoDoc(correo: correo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(c['titulo'] ?? '').toString()} ${(c['nombre'] ?? '').toString()}'
                          .trim(),
                      style: const TextStyle(
                          color: CC.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(correo,
                        style:
                            const TextStyle(color: CC.muted, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text('Folio: ${(c['folio'] ?? '—').toString()}',
                        style:
                            const TextStyle(color: CC.muted, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _colorEstado(estado).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(estado,
                    style: TextStyle(
                        color: _colorEstado(estado),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (obs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Obs.: $obs',
                style: const TextStyle(color: CC.ink, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          if (estado.toLowerCase() == 'aprobada') ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: CC.goldDark,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Ver PDF imprimible'),
                onPressed: () => _verPdf(correo),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed)),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Revocar aprobación'),
                onPressed: () => _rechazarConObs(correo),
              ),
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed,
                        side: const BorderSide(color: cessumRed)),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Rechazar'),
                    onPressed: () => _rechazarConObs(correo),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8E3E),
                        foregroundColor: Colors.white),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Aprobar'),
                    onPressed: () =>
                        _resolver(correo, 'credencial_docente_aprobar'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// Miniatura de foto del docente (carga perezosa desde el Guardián).
class _FotoDoc extends StatefulWidget {
  final String correo;
  const _FotoDoc({required this.correo});
  @override
  State<_FotoDoc> createState() => _FotoDocState();
}

class _FotoDocState extends State<_FotoDoc> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'credencial_docente_foto',
        'correo': widget.correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final b64 = (data['b64'] ?? '').toString();
      if (data['ok'] == true && b64.isNotEmpty && mounted) {
        setState(() => _bytes = base64Decode(b64));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 52,
        height: 64,
        color: CC.hueso,
        alignment: Alignment.center,
        child: _bytes != null
            ? Image.memory(_bytes!, width: 52, height: 64, fit: BoxFit.cover)
            : const Icon(Icons.person, color: CC.muted, size: 26),
      ),
    );
  }
}

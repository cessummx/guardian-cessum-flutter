import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: código institucional **USICAMM26**.
/// Condiciones fijas: inscripción de $100 + beca del 20% en TODO el posgrado.
/// Registra la redención del código aunque el aspirante aún no tenga matrícula;
/// cuando ya tiene matrícula, se vincula y la beca del 20% se empuja a la hoja
/// 'Becas' (de ahí sale el convenio con folio/QR).
class UsicammAdminScreen extends StatefulWidget {
  const UsicammAdminScreen({super.key});

  @override
  State<UsicammAdminScreen> createState() => _UsicammAdminScreenState();
}

class _UsicammAdminScreenState extends State<UsicammAdminScreen> {
  static const String _codigo = 'USICAMM26';

  final _aspirante = TextEditingController();
  final _correo = TextEditingController();
  final _programa = TextEditingController();
  final _generacion = TextEditingController();
  final _matricula = TextEditingController();

  bool _cargando = true;
  bool _registrando = false;
  String? _vinculandoId;
  int _pendientes = 0;
  int _vinculadas = 0;
  List<Map<String, dynamic>> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _aspirante.dispose();
    _correo.dispose();
    _programa.dispose();
    _generacion.dispose();
    _matricula.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : null));
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'usicamm_listar',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _lista = ((data['redenciones'] as List<dynamic>? ?? []))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _pendientes = (data['pendientes'] as num?)?.toInt() ?? 0;
        _vinculadas = (data['vinculadas'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _registrar() async {
    if (_aspirante.text.trim().isEmpty && _correo.text.trim().isEmpty) {
      _aviso('Escribe al menos el nombre o el correo del aspirante.',
          error: true);
      return;
    }
    setState(() => _registrando = true);
    try {
      final actor = await _actor();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'usicamm_registrar',
                'actor': actor,
                'codigo': _codigo,
                'aspirante': _aspirante.text.trim(),
                'correo': _correo.text.trim(),
                'programa': _programa.text.trim(),
                'generacion': _generacion.text.trim(),
                'matricula': _matricula.text.trim(),
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      _aviso(data['yaExistia'] == true
          ? 'Ya estaba registrado (${data['estatus']}).'
          : 'Registrado. Inscripción \$${data['inscripcion']} + beca '
              '${data['becaPorc']}%.');
      _aspirante.clear();
      _correo.clear();
      _programa.clear();
      _generacion.clear();
      _matricula.clear();
      await _cargar();
    } catch (e) {
      _aviso('No se pudo: $e'.replaceAll('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  Future<void> _vincular(Map<String, dynamic> r) async {
    final id = (r['id'] ?? '').toString();
    final ctrl =
        TextEditingController(text: (r['matricula'] ?? '').toString());
    final mat = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vincular matrícula'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r['aspirante'] ?? r['correo'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
                'Al vincular, la beca del 20% se registra en la hoja Becas '
                'y queda lista para el convenio.',
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Matrícula',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
    if (mat == null || mat.isEmpty) return;
    setState(() => _vinculandoId = id);
    try {
      final actor = await _actor();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'usicamm_vincular',
                'actor': actor,
                'id': id,
                'matricula': mat,
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _aviso('Vinculada a $mat. Beca ${data['becaPorc']}% aplicada en Becas.');
        await _cargar();
      } else {
        _aviso('${data['error'] ?? 'No se pudo vincular.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    } finally {
      if (mounted) setState(() => _vinculandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _lista
        .where((r) => '${r['estatus']}'.toLowerCase() == 'pendiente')
        .toList();
    final vinculadas = _lista
        .where((r) => '${r['estatus']}'.toLowerCase() != 'pendiente')
        .toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Código USICAMM26'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner de condiciones
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium, color: cessumGold),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                          fontSize: 13, color: cessumInk(context), height: 1.35),
                      children: [
                        TextSpan(
                            text: 'USICAMM26: ',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(
                            text:
                                'inscripción \$100 + beca del 20% en todo el '
                                'posgrado.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Formulario de registro
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Registrar aspirante con USICAMM26',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: cessumRed)),
                const SizedBox(height: 4),
                Text(
                    'Captura al aspirante aunque todavía no tenga matrícula. '
                    'Cuando ya tenga, vincúlala desde la lista para aplicar la '
                    'beca.',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                const SizedBox(height: 10),
                TextField(
                  controller: _aspirante,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del aspirante',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _correo,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo del aspirante',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _programa,
                  decoration: const InputDecoration(
                    labelText: 'Programa (opcional)',
                    hintText: 'Ej. Maestría en Educación Inclusiva',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _generacion,
                        decoration: const InputDecoration(
                          labelText: 'Generación (opcional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _matricula,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Matrícula (si ya tiene)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white),
                    onPressed: _registrando ? null : _registrar,
                    icon: _registrando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.discount),
                    label: const Text('Registrar redención'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Text('Pendientes de matrícula (${pendientes.length})',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 8),
          if (_cargando)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: cessumRed),
            ))
          else if (pendientes.isEmpty)
            Text('Sin pendientes.',
                style: TextStyle(color: cessumMuted(context)))
          else
            ...pendientes.map((r) => _item(r, true)),

          const SizedBox(height: 18),
          Text('Vinculadas (${vinculadas.length})',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E8E3E))),
          const SizedBox(height: 8),
          if (vinculadas.isEmpty)
            const Text('Aún ninguna.', style: TextStyle(color: Colors.black54))
          else
            ...vinculadas.map((r) => _item(r, false)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _item(Map<String, dynamic> r, bool pendiente) {
    final id = (r['id'] ?? '').toString();
    final correo = (r['correo'] ?? '').toString();
    final programa = (r['programa'] ?? '').toString();
    final matricula = (r['matricula'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              (r['aspirante'] ?? '').toString().isNotEmpty
                  ? (r['aspirante']).toString()
                  : (correo.isNotEmpty ? correo : '(sin nombre)'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (correo.isNotEmpty && (r['aspirante'] ?? '').toString().isNotEmpty)
            Text(correo,
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          if (programa.isNotEmpty)
            Text(programa,
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
          Text(
              'Inscripción \$${r['inscripcion']} · Beca ${r['becaPorc']}% · '
              '${r['fecha']}',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (matricula.isNotEmpty)
            Text('Matrícula: $matricula',
                style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (pendiente) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _vinculandoId == id
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumRed)))
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E8E3E),
                          foregroundColor: Colors.white),
                      onPressed: () => _vincular(r),
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Vincular matrícula'),
                    ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.verified,
                      size: 16, color: Color(0xFF1E8E3E)),
                  const SizedBox(width: 4),
                  Text('Beca 20% aplicada en Becas',
                      style: const TextStyle(
                          color: Color(0xFF1E8E3E),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

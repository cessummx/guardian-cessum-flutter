import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: programa "Recomienda". Registra un aspirante con el código del
/// alumno y, al verificar su inscripción, aprueba manualmente la bonificación
/// del alumno ($250 para su próxima colegiatura).
class RecomiendaAdminScreen extends StatefulWidget {
  const RecomiendaAdminScreen({super.key});

  @override
  State<RecomiendaAdminScreen> createState() => _RecomiendaAdminScreenState();
}

class _RecomiendaAdminScreenState extends State<RecomiendaAdminScreen> {
  final _codigo = TextEditingController();
  final _aspirante = TextEditingController();
  final _contacto = TextEditingController();

  bool _cargando = true;
  bool _registrando = false;
  String? _aprobandoId;
  List<Map<String, dynamic>> _lista = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _codigo.dispose();
    _aspirante.dispose();
    _contacto.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'recomienda_admin_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _lista = ((data['referidos'] as List<dynamic>? ?? []))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : null));
  }

  Future<void> _registrar() async {
    if (_codigo.text.trim().isEmpty || _aspirante.text.trim().isEmpty) {
      _aviso('Escribe el código y el nombre del aspirante.', error: true);
      return;
    }
    setState(() => _registrando = true);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'recomienda_registrar',
                'actor': actor,
                'codigo': _codigo.text.trim(),
                'aspirante': _aspirante.text.trim(),
                'contacto': _contacto.text.trim(),
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      _aviso('Registrado. Recomendó: ${data['referente']}');
      _codigo.clear();
      _aspirante.clear();
      _contacto.clear();
      await _cargar();
    } catch (e) {
      _aviso('No se pudo: $e'.replaceAll('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  Future<void> _aprobar(Map<String, dynamic> r) async {
    final id = (r['id'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Habilitar bonificación'),
        content: Text(
            'Confirma que ${r['aspirante']} ya se inscribió.\n\n'
            'Se habilitará la bonificación para ${r['nombreReferente']} '
            '(\$${r['bono'] == 0 ? 250 : r['bono']} para su próxima '
            'colegiatura).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Habilitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _aprobandoId = id);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'recomienda_aprobar',
                'actor': actor,
                'id': id,
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _aviso('Bonificación habilitada (\$${data['bono']}).');
        await _cargar();
      } else {
        _aviso('${data['error'] ?? 'No se pudo aprobar.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    } finally {
      if (mounted) setState(() => _aprobandoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes =
        _lista.where((r) => '${r['estatus']}'.toLowerCase() != 'aprobado').toList();
    final aprobados =
        _lista.where((r) => '${r['estatus']}'.toLowerCase() == 'aprobado').toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Recomendaciones'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                const Text('Registrar aspirante',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: cessumRed)),
                const SizedBox(height: 4),
                Text(
                    'Cuando un aspirante se inscriba con un código, regístralo '
                    'aquí. Luego confírmalo para habilitar la bonificación.',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                const SizedBox(height: 10),
                TextField(
                  controller: _codigo,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código de recomendación *',
                    hintText: 'Ej. CES1A2B3C',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _aspirante,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del aspirante *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _contacto,
                  decoration: const InputDecoration(
                    labelText: 'Contacto (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
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
                        : const Icon(Icons.person_add),
                    label: const Text('Registrar'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('Pendientes de habilitar (${pendientes.length})',
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
          Text('Aprobadas (${aprobados.length})',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E8E3E))),
          const SizedBox(height: 8),
          if (aprobados.isEmpty)
            const Text('Aún ninguna.', style: TextStyle(color: Colors.black54))
          else
            ...aprobados.map((r) => _item(r, false)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _item(Map<String, dynamic> r, bool pendiente) {
    final id = (r['id'] ?? '').toString();
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
          Text((r['aspirante'] ?? '').toString(),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
              'Recomendó: ${r['nombreReferente']} · ${r['matriculaReferente']}',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
          Text('Código: ${r['codigo']} · ${r['fecha']}',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if ((r['contacto'] ?? '').toString().isNotEmpty)
            Text('Contacto: ${r['contacto']}',
                style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (pendiente) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _aprobandoId == id
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
                      onPressed: () => _aprobar(r),
                      icon: const Icon(Icons.verified, size: 18),
                      label: const Text('Verificar y habilitar'),
                    ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Bonificación habilitada: \$${r['bono']}',
                  style: const TextStyle(
                      color: Color(0xFF1E8E3E),
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

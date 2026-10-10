import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

/// Panel de administrador: estado de respaldos y respaldo manual.
class RespaldosScreen extends StatefulWidget {
  const RespaldosScreen({super.key});

  @override
  State<RespaldosScreen> createState() => _RespaldosScreenState();
}

class _RespaldosScreenState extends State<RespaldosScreen> {
  bool _cargando = true;
  bool _respaldando = false;
  String? _error;
  List<Map<String, dynamic>> _respaldos = [];
  int _conserva = 0;

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
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'respaldos_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _respaldos = ((data['respaldos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _conserva = (data['conserva'] ?? 0) is int
            ? data['conserva'] as int
            : int.tryParse('${data['conserva']}') ?? 0;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar ($e)';
      });
    }
  }

  Future<void> _respaldarAhora() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Respaldar ahora'),
        content: const Text(
          'Se generará una copia de todas las bases en este momento. '
          'Puede tardar un poco. ¿Continuar?',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Respaldar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _respaldando = true);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'respaldo_ahora', 'actor': actor}))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Respaldo creado: ${data['copiados']}/${data['total']} bases.'),
          backgroundColor: const Color(0xFF1E8E3E),
        ));
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'No autorizado');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: cessumRed));
    } finally {
      if (mounted) setState(() => _respaldando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ultimo = _respaldos.isNotEmpty ? _respaldos.first : null;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Respaldos'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                  ultimo != null
                                      ? Icons.cloud_done
                                      : Icons.cloud_off,
                                  color: ultimo != null
                                      ? const Color(0xFF1E8E3E)
                                      : cessumRed),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  ultimo != null
                                      ? 'Último respaldo: ${ultimo['fecha']}'
                                      : 'Aún no hay respaldos.',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          if (_conserva > 0) ...[
                            const SizedBox(height: 6),
                            Text('Se conservan los últimos $_conserva días.',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cessumRed,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: _respaldando ? null : _respaldarAhora,
                              icon: _respaldando
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.backup),
                              label: Text(_respaldando
                                  ? 'Respaldando...'
                                  : 'Respaldar ahora'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 6),
                      child: Text('Historial de respaldos',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    if (_respaldos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Sin respaldos registrados.',
                            style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ..._respaldos.map(_fila),
                  ],
                ),
    );
  }

  Widget _fila(Map<String, dynamic> r) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: const Icon(Icons.folder_zip, color: cessumGold),
        title: Text((r['fecha'] ?? '').toString(),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: Text('${r['archivos'] ?? 0} archivo(s)',
            style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

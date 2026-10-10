import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Resumen de captura a docentes: muestra a todos los docentes con su número
/// de grupos, capturas completas y pendientes, y permite enviarles su resumen.
class ResumenDocentesScreen extends StatefulWidget {
  const ResumenDocentesScreen({super.key});

  @override
  State<ResumenDocentesScreen> createState() => _ResumenDocentesScreenState();
}

class _ResumenDocentesScreenState extends State<ResumenDocentesScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  bool _enviando = false;
  List<Map<String, dynamic>> _docentes = [];
  DateTime? _ultimaCarga;

  @override
  void initState() {
    super.initState();
    _cargarPreview();
  }

  Future<void> _cargarPreview() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=resumen_docentes_preview'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _docentes = ((data['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
        _ultimaCarga = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la vista previa.';
      });
    }
  }

  Future<void> _enviar() async {
    final n = _docentes.length;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enviar resumen', style: TextStyle(fontSize: 16)),
        content: Text(
          'Se enviará su resumen de captura a $n docente(s). Los correos se '
          'envían de inmediato. ¿Continuar?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _enviando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=resumen_docentes_enviar'))
          .timeout(const Duration(seconds: 300));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _enviando = false);
      if (data['ok'] == true) {
        final env = (data['enviados'] ?? 0).toString();
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resúmenes enviados: $env')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo enviar: ${data['error'] ?? 'error'}')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo conectar con el sistema.')));
    }
  }

  void _copiarExcel() {
    final b = StringBuffer();
    b.writeln('Nombre\tCorreo\tGrupos\tCompletas\tPendientes');
    for (final d in _docentes) {
      b.writeln('${d['nombre'] ?? ''}\t${d['correo'] ?? ''}\t'
          '${d['grupos'] ?? 0}\t${d['completas'] ?? 0}\t'
          '${d['pendientes'] ?? 0}');
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Resumen docentes (${_docentes.length})');
  }

  @override
  Widget build(BuildContext context) {
    final conPend =
        _docentes.where((d) => ((d['pendientes'] ?? 0) as int) > 0).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Resumen a docentes',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: (_cargando || _docentes.isEmpty)
                  ? null
                  : _copiarExcel,
              tooltip: 'Copiar para Excel',
              icon: const Icon(Icons.table_view)),
          IconButton(
              onPressed: (_cargando || _enviando) ? null : _cargarPreview,
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
                          onPressed: _cargarPreview,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _docentes.isEmpty
                            ? 'No hay docentes con asignaciones.'
                            : '${_docentes.length} docente(s) recibirán su resumen. '
                                '$conPend con captura pendiente, '
                                '${_docentes.length - conPend} al día.',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cessumRed),
                      ),
                    ),
                    if (_ultimaCarga != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(Helpers.haceTexto(_ultimaCarga),
                              style: TextStyle(
                                  fontSize: 11.5, color: cessumFaint(context))),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _docentes.length,
                        itemBuilder: (ctx, i) {
                          final d = _docentes[i];
                          final pend = (d['pendientes'] ?? 0) as int;
                          final alDia = pend == 0;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: Icon(
                                  alDia ? Icons.check_circle : Icons.mail_outline,
                                  color: alDia ? _verde : cessumRed),
                              title: Text((d['nombre'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${d['correo'] ?? ''}'
                                '\nGrupos: ${d['grupos'] ?? 0} · Completas: ${d['completas'] ?? 0} · Pendientes: $pend',
                                style: const TextStyle(fontSize: 11),
                              ),
                              isThreeLine: true,
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: (alDia ? _verde : cessumRed)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(alDia ? 'Al día' : '$pend pend.',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: alDia ? _verde : cessumRed)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: (_docentes.isEmpty || _cargando || _error != null)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _enviando ? null : _enviar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    label: Text(
                        _enviando
                            ? 'Enviando...'
                            : 'Enviar resumen (${_docentes.length})',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
    );
  }
}

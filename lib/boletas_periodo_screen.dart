import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Boletas por periodo: muestra los alumnos con su periodo completo (todas
/// las materias validadas) listos para recibir boleta, y permite enviarlas.
class BoletasPeriodoScreen extends StatefulWidget {
  const BoletasPeriodoScreen({super.key});

  @override
  State<BoletasPeriodoScreen> createState() => _BoletasPeriodoScreenState();
}

class _BoletasPeriodoScreenState extends State<BoletasPeriodoScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  bool _enviando = false;
  // (2-oct) Envío por tandas: progreso visible y bloqueo temporal tras un corte de conexión.
  String _progreso = '';
  DateTime? _bloqueadoHasta;
  List<Map<String, dynamic>> _boletas = [];

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
          .get(Uri.parse('$guardianUrl?accion=boletas_periodo_preview'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _boletas = ((data['boletas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
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
    // (2-oct) Tras un corte de conexión, el envío anterior puede seguir en el
    // servidor: reintentar enseguida lo duplicaría. Se espera antes de volver a enviar.
    final bloqueo = _bloqueadoHasta;
    if (bloqueo != null && DateTime.now().isBefore(bloqueo)) {
      final min = bloqueo.difference(DateTime.now()).inMinutes + 1;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Hubo un corte hace poco y el envío anterior puede seguir '
            'en el servidor. Espera unos $min min y actualiza la lista antes '
            'de volver a enviar.'),
      ));
      return;
    }
    final n = _boletas.length;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enviar boletas', style: TextStyle(fontSize: 16)),
        content: Text(
          'Se enviará la boleta del periodo a $n alumno(s) con todas sus '
          'materias validadas. No se reenvía a quienes ya la recibieron.\n\n'
          'El envío se hace por tandas y puede tardar unos minutos: no cierres '
          'esta pantalla hasta que termine. ¿Continuar?',
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
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _enviando = true;
      _progreso = 'Preparando…';
    });
    var enviados = 0;
    var quedan = n;
    var vacias = 0;
    String? fallo;
    try {
      // Cada llamada manda hasta 10 boletas y termina antes del corte de 120 s
      // del servidor intermedio; se repite hasta que no quede ninguna.
      for (var vuelta = 0; vuelta < 80; vuelta++) {
        final resp = await http
            .get(Uri.parse(
                '$guardianUrl?accion=boletas_periodo_enviar&confirmar=ENVIAR&max=10'))
            .timeout(const Duration(seconds: 110));
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] != true) {
          final msg = (data['error'] ?? 'error').toString();
          fallo = msg;
          final txt = msg.toLowerCase();
          if (data['enCurso'] == true ||
              txt.contains('timed out') ||
              txt.contains('proxy')) {
            _bloqueadoHasta = DateTime.now().add(const Duration(minutes: 3));
          }
          break;
        }
        final env = (data['enviadas'] as num?)?.toInt() ?? 0;
        enviados += env;
        quedan = (data['quedan'] as num?)?.toInt() ?? 0;
        if (mounted) {
          setState(() => _progreso = 'Enviadas $enviados · quedan $quedan');
        }
        if (data['parcial'] != true || quedan <= 0) break;
        vacias = env == 0 ? vacias + 1 : 0;
        if (vacias >= 2) {
          fallo = 'Quedan $quedan boleta(s) que no se pudieron enviar en este '
              'momento. Vuelve a intentarlo en unos minutos.';
          break;
        }
      }
    } catch (e) {
      // Corte de conexión o tiempo de espera: NO se reintenta solo.
      _bloqueadoHasta = DateTime.now().add(const Duration(minutes: 3));
      fallo = 'Se cortó la conexión. El envío puede seguir en el servidor: '
          'espera unos 3 min y actualiza la lista antes de volver a enviar.';
    }
    if (mounted) {
      setState(() {
        _enviando = false;
        _progreso = '';
      });
    }
    messenger.showSnackBar(SnackBar(
      content: Text(fallo == null
          ? 'Boletas enviadas: $enviados'
          : '${enviados > 0 ? 'Enviadas: $enviados. ' : ''}No se pudo terminar: $fallo'),
      duration: const Duration(seconds: 8),
    ));
    if (mounted) _cargarPreview();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // (2-oct) No se puede salir de la pantalla mientras se envía.
      canPop: !_enviando,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Espera a que termine el envío de boletas.')));
        }
      },
      child: Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Boletas por periodo',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
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
                        color: (_boletas.isEmpty ? _verde : cessumRed)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _boletas.isEmpty
                            ? 'No hay periodos completos pendientes de boleta.'
                            : '${_boletas.length} alumno(s) con su periodo completo, '
                                'listos para recibir boleta. Revise y, si está de acuerdo, envíe.',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _boletas.isEmpty ? _verde : cessumRed),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        itemCount: _boletas.length,
                        itemBuilder: (ctx, i) {
                          final b = _boletas[i];
                          final mats = (b['materias'] ?? 0).toString();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: const Icon(Icons.description,
                                  color: cessumRed),
                              title: Text((b['nombre'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                '${b['matricula'] ?? ''} · ${b['periodo'] ?? ''}'
                                '\n${b['correo'] ?? ''}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              isThreeLine: true,
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: cessumGold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text('$mats mat.',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: cessumGold)),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: (_boletas.isEmpty || _cargando || _error != null)
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
                            ? 'Enviando… $_progreso'
                            : 'Enviar boletas (${_boletas.length})',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

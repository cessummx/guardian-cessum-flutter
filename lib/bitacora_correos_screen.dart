import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Bitácora de correos: monitoreo del sistema de notificaciones. Muestra la
/// cuota disponible, conteos por estado y tipo, y los envíos recientes.
class BitacoraCorreosScreen extends StatefulWidget {
  const BitacoraCorreosScreen({super.key});

  @override
  State<BitacoraCorreosScreen> createState() => _BitacoraCorreosScreenState();
}

class _BitacoraCorreosScreenState extends State<BitacoraCorreosScreen> {
  static const Color _verde = Color(0xFF1E8E3E);
  static const Color _naranja = Color(0xFFE08A00);

  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _data = {};
  DateTime? _ultimaCarga;

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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=bitacora_correos'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
        _ultimaCarga = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la bitácora.';
      });
    }
  }

  Color _colorEstado(String e) {
    if (e == 'enviado') return _verde;
    if (e == 'error') return cessumRed;
    return cessumGold;
  }

  void _copiarExcel() {
    final recientes = (_data['recientes'] as List?) ?? [];
    final b = StringBuffer();
    b.writeln('Fecha\tTipo\tAsunto\tDestinatario\tEstado\tDetalle');
    for (final e in recientes) {
      final m = Map<String, dynamic>.from(e as Map);
      final det = (m['detalle'] ?? '').toString().replaceAll('\n', ' ');
      b.writeln('${m['fecha'] ?? ''}\t${m['tipo'] ?? ''}\t'
          '${m['asunto'] ?? ''}\t${m['destinatario'] ?? ''}\t'
          '${m['estatus'] ?? m['estado'] ?? ''}\t$det');
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Bitácora de correos (${recientes.length})');
  }

  @override
  Widget build(BuildContext context) {
    final cuota = _data['cuotaRestante'];
    final tipos = (_data['porTipo'] as List?) ?? [];
    final recientes = (_data['recientes'] as List?) ?? [];
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Bitácora de correos',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _copiarExcel,
              tooltip: 'Copiar para Excel',
              icon: const Icon(Icons.table_view)),
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
                    if (_ultimaCarga != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, left: 2),
                        child: Text(Helpers.haceTexto(_ultimaCarga),
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.black45)),
                      ),
                    Row(
                      children: [
                        _kpi('Cuota restante hoy',
                            cuota == null || cuota == -1 ? '—' : '$cuota',
                            Icons.battery_charging_full,
                            (cuota is int && cuota >= 0 && cuota < 20)
                                ? cessumRed
                                : _verde),
                        const SizedBox(width: 10),
                        _kpi('Enviados hoy', '${_data['enviadosHoy'] ?? 0}',
                            Icons.mark_email_read, cessumRed),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _kpi('Enviados (total)', '${_data['enviados'] ?? 0}',
                            Icons.check_circle, _verde),
                        const SizedBox(width: 10),
                        _kpi('Errores', '${_data['errores'] ?? 0}',
                            Icons.error_outline,
                            ((_data['errores'] ?? 0) as int) > 0
                                ? cessumRed
                                : _verde),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _kpi('En cola', '${_data['enCola'] ?? 0}',
                            Icons.schedule_send,
                            ((_data['enCola'] ?? 0) as int) > 0
                                ? _naranja
                                : _verde),
                        const SizedBox(width: 10),
                        _kpi('Omitidos', '${_data['omitidos'] ?? 0}',
                            Icons.do_not_disturb_on, cessumGold),
                      ],
                    ),
                    if (tipos.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _titulo('Por tipo de correo'),
                      ...tipos.map((t) {
                        final m = t as Map;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            dense: true,
                            title: Text((m['tipo'] ?? '').toString(),
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            trailing: Text(
                              '${m['enviados'] ?? 0} enviados'
                              '${((m['errores'] ?? 0) as int) > 0 ? ' · ${m['errores']} err' : ''}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: ((m['errores'] ?? 0) as int) > 0
                                      ? cessumRed
                                      : Colors.black54),
                            ),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 20),
                    _titulo('Envíos recientes'),
                    if (recientes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Aún no hay correos registrados.',
                            style: TextStyle(color: Colors.black54)),
                      )
                    else
                      ...recientes.map((r) {
                        final m = r as Map;
                        final estado = (m['estado'] ?? '').toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.circle,
                                size: 12, color: _colorEstado(estado)),
                            title: Text((m['asunto'] ?? '').toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${m['destinatario'] ?? ''} · ${m['fecha'] ?? ''}'
                              '${(m['detalle'] ?? '').toString().isNotEmpty ? '\n${m['detalle']}' : ''}',
                              style: const TextStyle(fontSize: 10.5),
                            ),
                            isThreeLine:
                                (m['detalle'] ?? '').toString().isNotEmpty,
                            trailing: Text(estado,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _colorEstado(estado))),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }

  Widget _titulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: cessumRed)),
    );
  }

  Widget _kpi(String etiqueta, String valor, IconData icono, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color, size: 22),
            const SizedBox(height: 8),
            Text(valor,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(etiqueta,
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';

/// Vista de VICERRECTORÍA: avisos de inasistencia que envían los docentes
/// desde "Justificar mi inasistencia". Aquí se autorizan (Justificada) o se
/// rechazan (No justificada). Al autorizar, el backend avisa a
/// contacto@cessum.mx para que el cambio entre en el aviso diario al grupo.
class InasistenciasDocentesScreen extends StatefulWidget {
  const InasistenciasDocentesScreen({super.key});

  @override
  State<InasistenciasDocentesScreen> createState() =>
      _InasistenciasDocentesScreenState();
}

class _InasistenciasDocentesScreenState
    extends State<InasistenciasDocentesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _cargando = true;
  String? _error;
  bool _soloPendientes = true;

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
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'inasistencias_docentes_listar',
        if (_soloPendientes) 'pendientes': 'true',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() => _error = (data['error'] ?? 'Error').toString());
      } else {
        setState(() {
          _items = ((data['inasistencias'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _resolver(Map<String, dynamic> it, String estatus) async {
    final notaCtrl = TextEditingController();
    final justifica = estatus == 'Justificada';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(justifica ? 'Autorizar inasistencia' : 'No justificar',
            style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${it['docente']} · ${it['materia']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Sesión del ${it['fechaSesion']} · ${it['motivo']}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              const SizedBox(height: 12),
              if (justifica)
                const Text(
                  'Al autorizar se avisa a contacto@cessum.mx con la sesión '
                  'perdida y su reposición, para que entre en el aviso diario '
                  'al grupo.',
                  style: TextStyle(fontSize: 11.5, height: 1.35),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: notaCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota para el docente (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    justifica ? const Color(0xFF1E8E3E) : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(justifica ? 'Autorizar' : 'No justificar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    final quien = await SessionStore.realEmail();
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'inasistencia_docente_resolver',
        'fila': (it['fila'] ?? '').toString(),
        'estatus': estatus,
        'actor': quien ?? '',
        'nota': notaCtrl.text.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(justifica
              ? 'Autorizada. Se avisó al docente y a contacto@cessum.mx.'
              : 'Marcada como no justificada. Se avisó al docente.'),
        ));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo: ${data['error'] ?? 'error'}')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error de conexión. Intenta de nuevo.')),
      );
    }
  }

  Color _color(String e) {
    if (e == 'Justificada') return const Color(0xFF1E8E3E);
    if (e == 'No justificada') return cessumRed;
    return cessumGold;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Inasistencias de docentes'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            dense: true,
            value: _soloPendientes,
            activeColor: cessumGold,
            title: const Text('Solo pendientes de autorizar',
                style: TextStyle(fontSize: 13)),
            onChanged: _cargando
                ? null
                : (v) {
                    setState(() => _soloPendientes = v);
                    _cargar();
                  },
          ),
          const Divider(height: 1),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : _items.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No hay avisos de inasistencia.',
                                  textAlign: TextAlign.center),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length,
                            itemBuilder: (_, i) => _tarjeta(_items[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> it) {
    final est = (it['estatus'] ?? '').toString();
    final col = _color(est);
    final comp = (it['comprobante'] ?? '').toString();
    final repone = (it['repondra'] ?? '').toString() == 'SI';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((it['docente'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(est,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: col)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text((it['materia'] ?? '').toString(),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            Text(
              '${it['programa']} · ${it['generacion']} · Grupo ${it['grupo']}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
            ),
            const SizedBox(height: 8),
            _linea(Icons.event_busy, 'Sesión no impartida',
                '${it['fechaSesion']}${(it['hora'] ?? '').toString().isNotEmpty ? ' · ${it['hora']}' : ''}'),
            _linea(Icons.help_outline, 'Motivo', (it['motivo'] ?? '').toString()),
            if ((it['descripcion'] ?? '').toString().isNotEmpty)
              _linea(Icons.notes, 'Descripción',
                  (it['descripcion'] ?? '').toString()),
            _linea(
                repone ? Icons.event_repeat : Icons.event_busy,
                'Reposición',
                repone
                    ? 'Repone el ${it['fechaReposicion']}'
                    : 'NO propone reposición'),
            if ((it['resolucion'] ?? '').toString().isNotEmpty)
              _linea(Icons.gavel, 'Resolución',
                  (it['resolucion'] ?? '').toString()),
            if (comp.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Helpers.abrirUrlExterna(comp, context),
                  icon:
                      const Icon(Icons.attach_file, size: 16, color: cessumRed),
                  label: const Text('Ver comprobante',
                      style: TextStyle(color: cessumRed, fontSize: 12)),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Sin comprobante adjunto.',
                    style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
              ),
            if (est == 'Pendiente') ...[
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _resolver(it, 'No justificada'),
                    child: const Text('No justificar',
                        style: TextStyle(color: cessumRed)),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8E3E),
                        foregroundColor: Colors.white),
                    onPressed: () => _resolver(it, 'Justificada'),
                    icon: const Icon(Icons.check, size: 17),
                    label: const Text('Autorizar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linea(IconData ic, String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ic, size: 15, color: cessumFaint(context)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                    fontSize: 12, color: cessumInk(context), height: 1.35),
                children: [
                  TextSpan(
                      text: '$etiqueta: ',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: valor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

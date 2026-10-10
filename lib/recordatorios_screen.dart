import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

/// Herramienta para estudiantes: recordatorios de entregas, clases y pagos.
/// Persisten en el Guardián por matrícula.
class RecordatoriosScreen extends StatefulWidget {
  final String matricula;
  const RecordatoriosScreen({super.key, this.matricula = ''});

  @override
  State<RecordatoriosScreen> createState() => _RecordatoriosScreenState();
}

class _RecordatoriosScreenState extends State<RecordatoriosScreen> {
  static const Map<String, IconData> _tiposIcono = {
    'entrega': Icons.assignment_turned_in,
    'clase': Icons.cast_for_education,
    'pago': Icons.payments,
    'otro': Icons.push_pin,
  };
  static const List<String> _tipos = ['entrega', 'clase', 'pago', 'otro'];

  String _matricula = '';
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _matricula = widget.matricula.trim();
    _init();
  }

  Future<void> _init() async {
    if (_matricula.isEmpty) {
      final p = await StudentProfile.load();
      _matricula = p?.matricula ?? '';
    }
    await _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> p) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: p);
    final r = await http.get(uri).timeout(const Duration(seconds: 45));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 45));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      if (_matricula.isEmpty) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo identificar tu matrícula.';
        });
        return;
      }
      final data =
          await _get({'accion': 'recordatorios_listar', 'matricula': _matricula});
      if (!mounted) return;
      setState(() {
        _items = ((data['recordatorios'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus recordatorios.';
      });
    }
  }

  String _dosDig(int n) => n < 10 ? '0$n' : '$n';

  Future<void> _editar([Map<String, dynamic>? item]) async {
    final tituloCtrl = TextEditingController(text: '${item?['titulo'] ?? ''}');
    final notaCtrl = TextEditingController(text: '${item?['nota'] ?? ''}');
    String tipo = '${item?['tipo'] ?? 'entrega'}';
    if (!_tipos.contains(tipo)) tipo = 'otro';
    String fecha = '${item?['fecha'] ?? ''}';
    String hora = '${item?['hora'] ?? ''}';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(item == null ? 'Nuevo recordatorio' : 'Editar recordatorio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Título', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Tipo', border: OutlineInputBorder()),
                  items: _tipos
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Row(children: [
                            Icon(_tiposIcono[t], size: 18, color: cessumRed),
                            const SizedBox(width: 8),
                            Text(t[0].toUpperCase() + t.substring(1)),
                          ])))
                      .toList(),
                  onChanged: (v) => setS(() => tipo = v ?? tipo),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(fecha.isEmpty ? 'Fecha' : fecha),
                      onPressed: () async {
                        final hoy = DateTime.now();
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: hoy,
                          firstDate: DateTime(hoy.year - 1),
                          lastDate: DateTime(hoy.year + 3),
                        );
                        if (d != null) {
                          setS(() => fecha =
                              '${_dosDig(d.day)}/${_dosDig(d.month)}/${d.year}');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(hora.isEmpty ? 'Hora' : hora),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: TimeOfDay.now());
                        if (t != null) {
                          setS(() =>
                              hora = '${_dosDig(t.hour)}:${_dosDig(t.minute)}');
                        }
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: notaCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            if (item != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cerrar'),
              ),
            if (item == null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                if (tituloCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      final payload = <String, dynamic>{
        'accion': item == null ? 'recordatorio_crear' : 'recordatorio_actualizar',
        'matricula': _matricula,
        'titulo': tituloCtrl.text.trim(),
        'tipo': tipo,
        'fecha': fecha,
        'hora': hora,
        'nota': notaCtrl.text.trim(),
      };
      if (item != null) payload['id'] = item['id'];
      final data = await _post(payload);
      if (data['ok'] == true) {
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo guardar.'}');
      }
    } catch (e) {
      _snack('Error de conexión.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    setState(() => item['hecho'] = !(item['hecho'] == true));
    try {
      await _post({
        'accion': 'recordatorio_actualizar',
        'id': item['id'],
        'hecho': item['hecho'] == true,
      });
    } catch (_) {}
  }

  Future<void> _eliminar(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar recordatorio'),
        content: Text('¿Eliminar "${item['titulo']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _post({'accion': 'recordatorio_eliminar', 'id': item['id']});
      await _cargar();
    } catch (_) {
      _snack('No se pudo eliminar.');
    }
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t), backgroundColor: cessumRed));
  }

  bool _vencido(Map<String, dynamic> item) {
    if (item['hecho'] == true) return false;
    final m = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch('${item['fecha']}');
    if (m == null) return false;
    final f = DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!),
        int.parse(m.group(1)!));
    final hoy = DateTime.now();
    return f.isBefore(DateTime(hoy.year, hoy.month, hoy.day));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis recordatorios'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _guardando ? null : () => _editar(),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 10),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: cessumRed),
                          onPressed: _cargar,
                          child: const Text('Reintentar',
                              style: TextStyle(color: Colors.white))),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aún no tienes recordatorios.\nToca "Nuevo" para agregar una entrega, clase o pago.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cessumMuted(context)),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _tile(_items[i]),
                      ),
                    ),
    );
  }

  Widget _tile(Map<String, dynamic> item) {
    final hecho = item['hecho'] == true;
    final venc = _vencido(item);
    final tipo = '${item['tipo'] ?? 'otro'}';
    final fechaHora = [
      '${item['fecha'] ?? ''}',
      '${item['hora'] ?? ''}'
    ].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      color: Theme.of(context).cardColor,
      child: ListTile(
        leading: Icon(_tiposIcono[tipo] ?? Icons.push_pin,
            color: venc ? Colors.redAccent : cessumGold),
        title: Text(
          '${item['titulo']}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: hecho ? TextDecoration.lineThrough : null,
            color: hecho ? Colors.grey : cessumInk(context),
          ),
        ),
        subtitle: Text([
          if (fechaHora.isNotEmpty) fechaHora,
          if (venc) '¡Vencido!',
          if ('${item['nota'] ?? ''}'.isNotEmpty) '${item['nota']}',
        ].join('  ·  '),
            style: TextStyle(
                color: venc ? Colors.redAccent : cessumMuted(context),
                fontSize: 12.5)),
        onTap: () => _editar(item),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: Icon(
                hecho ? Icons.check_circle : Icons.radio_button_unchecked,
                color: hecho ? Colors.green : Colors.grey),
            onPressed: () => _toggle(item),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _eliminar(item),
          ),
        ]),
      ),
    );
  }
}

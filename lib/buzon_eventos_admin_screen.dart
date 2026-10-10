import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Panel admin de buzón anónimo y eventos con confirmación de asistencia.
class BuzonEventosAdminScreen extends StatelessWidget {
  const BuzonEventosAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Buzón y eventos',
              style: TextStyle(fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            tabs: [
              Tab(icon: Icon(Icons.inbox, size: 20), text: 'Buzón'),
              Tab(icon: Icon(Icons.event, size: 20), text: 'Eventos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _BuzonAdminTab(),
            _EventosAdminTab(),
          ],
        ),
      ),
    );
  }
}

/* ---------------- Pestaña 1: Buzón ---------------- */
class _BuzonAdminTab extends StatefulWidget {
  const _BuzonAdminTab();
  @override
  State<_BuzonAdminTab> createState() => _BuzonAdminTabState();
}

class _BuzonAdminTabState extends State<_BuzonAdminTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _lista = [];
  String _filtro = 'Todos';
  bool _cargando = true;
  bool _procesando = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

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
      final uri = Uri.parse('$guardianUrl?accion=buzon_listar'
          '${_filtro != 'Todos' ? '&estatus=${Uri.encodeComponent(_filtro)}' : ''}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _lista = ((data['mensajes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar.';
      });
    }
  }

  Color _color(String est) {
    switch (est) {
      case 'Nuevo':
        return cessumRed;
      case 'Atendido':
        return const Color(0xFF1E8E3E);
      default:
        return cessumGold;
    }
  }

  Future<void> _resolver(Map<String, dynamic> m) async {
    String estatus = (m['estatus'] ?? 'Nuevo').toString();
    if (!['Nuevo', 'Leído', 'Atendido'].contains(estatus)) estatus = 'Nuevo';
    final notas = TextEditingController(text: (m['notas'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => AlertDialog(
          title: Text('${m['categoria']} · ${m['folio']}',
              style: const TextStyle(fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${m['mensaje']}',
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: estatus,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Estatus',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Nuevo', child: Text('Nuevo')),
                    DropdownMenuItem(value: 'Leído', child: Text('Leído')),
                    DropdownMenuItem(
                        value: 'Atendido', child: Text('Atendido')),
                  ],
                  onChanged: (v) => setS(() => estatus = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notas,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notas internas',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'buzon_resolver',
                'fila': m['fila'],
                'estatus': estatus,
                'notas': notas.text.trim(),
              }))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtros = ['Todos', 'Nuevo', 'Leído', 'Atendido'];
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (_procesando) const LinearProgressIndicator(color: cessumRed),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: filtros.map((f) {
              final activo = _filtro == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f, style: const TextStyle(fontSize: 12)),
                  selected: activo,
                  selectedColor: cessumRed.withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    color: activo ? cessumRed : Colors.black87,
                    fontWeight: activo ? FontWeight.w700 : FontWeight.w400,
                  ),
                  onSelected: (_) {
                    setState(() => _filtro = f);
                    _cargar();
                  },
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: _lista.isEmpty
              ? const Center(
                  child: Text('Sin mensajes en este filtro.',
                      style: TextStyle(color: Colors.black54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _lista.length,
                  itemBuilder: (ctx, i) {
                    final m = _lista[i];
                    final est = (m['estatus'] ?? 'Nuevo').toString();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _color(est).withValues(alpha: 0.15),
                          child: Icon(Icons.feedback, color: _color(est)),
                        ),
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cessumGold.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${m['categoria']}',
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF8A6118))),
                            ),
                            const Spacer(),
                            Text(est,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: _color(est))),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${m['mensaje']}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5, height: 1.35, color: Colors.black87),
                          ),
                        ),
                        onTap: _procesando ? null : () => _resolver(m),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/* ---------------- Pestaña 2: Eventos ---------------- */
class _EventosAdminTab extends StatefulWidget {
  const _EventosAdminTab();
  @override
  State<_EventosAdminTab> createState() => _EventosAdminTabState();
}

class _EventosAdminTabState extends State<_EventosAdminTab>
    with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _eventos = [];
  List<Map<String, dynamic>> _generaciones = [];
  bool _cargando = true;
  bool _procesando = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

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
      final ev = await http
          .get(Uri.parse('$guardianUrl?accion=eventos_listar'))
          .timeout(const Duration(seconds: 60));
      final evd = jsonDecode(ev.body) as Map<String, dynamic>;
      final g = await http
          .get(Uri.parse('$guardianUrl?accion=circular_generaciones'))
          .timeout(const Duration(seconds: 60));
      final gd = jsonDecode(g.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _eventos = ((evd['eventos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _generaciones = ((gd['generaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar.';
      });
    }
  }

  List<String> get _programas {
    final set = <String>{};
    for (final g in _generaciones) {
      set.add((g['programa'] ?? '').toString());
    }
    final l = set.toList()..sort();
    return l;
  }

  Future<void> _crearEvento() async {
    final titulo = TextEditingController();
    final desc = TextEditingController();
    final fecha = TextEditingController();
    final lugar = TextEditingController();
    String? programa;
    String? generacion;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          final gensDe = programa == null
              ? <String>[]
              : (_generaciones
                  .where((g) => (g['programa'] ?? '') == programa)
                  .map((g) => (g['generacion'] ?? '').toString())
                  .toList()
                ..sort((a, b) => b.compareTo(a)));
          return AlertDialog(
            title: const Text('Nuevo evento', style: TextStyle(fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titulo,
                    decoration: const InputDecoration(
                      labelText: 'Título *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: desc,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fecha,
                    decoration: const InputDecoration(
                      labelText: 'Fecha del evento',
                      hintText: 'Ej. 15 de julio, 10:00 h',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: lugar,
                    decoration: const InputDecoration(
                      labelText: 'Lugar',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: programa,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Dirigido a',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Todos')),
                      ..._programas.map((p) => DropdownMenuItem<String?>(
                          value: p, child: Text(p))),
                    ],
                    onChanged: (v) => setS(() {
                      programa = v;
                      generacion = null;
                    }),
                  ),
                  if (programa != null) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      value: generacion,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Generación',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Todas')),
                        ...gensDe.map((g) => DropdownMenuItem<String?>(
                            value: g, child: Text(g))),
                      ],
                      onChanged: (v) => setS(() => generacion = v),
                    ),
                  ],
                  const SizedBox(height: 6),
                  const Text(
                    'Se enviará una invitación por correo a los destinatarios.',
                    style: TextStyle(fontSize: 11.5, color: Colors.black54),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2, false),
                  child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () {
                  if (titulo.text.trim().isEmpty) return;
                  Navigator.pop(ctx2, true);
                },
                child: const Text('Crear y enviar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'evento_crear',
                'titulo': titulo.text.trim(),
                'descripcion': desc.text.trim(),
                'fechaEvento': fecha.text.trim(),
                'lugar': lugar.text.trim(),
                'dirigidoPrograma': programa ?? '',
                'dirigidoGeneracion': generacion ?? '',
              }))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('Evento creado · ${data['invitados']} invitación(es) enviada(s).'),
        ));
      }
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _borrarEvento(Map<String, dynamic> ev) async {
    final id = (ev['id'] ?? '').toString();
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar evento'),
        content: Text(
            '¿Seguro que quieres borrar "${ev['titulo']}"? Se eliminará junto '
            'con sus confirmaciones. Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(
                {'accion': 'evento_eliminar', 'id': id, 'actor': actor}),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Evento borrado.'),
            backgroundColor: Color(0xFF1E8E3E)));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['error']?.toString() ?? 'No se pudo borrar.'),
            backgroundColor: cessumRed));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error de conexión: $e'), backgroundColor: cessumRed));
      }
    }
  }

  Future<void> _verConfirmaciones(Map<String, dynamic> ev) async {    showDialog(
      context: context,
      builder: (ctx) => _DialogoConfirmaciones(eventoId: ev['id'].toString(), titulo: ev['titulo'].toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Column(
          children: [
            if (_procesando) const LinearProgressIndicator(color: cessumRed),
            Expanded(
              child: _eventos.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Aún no has creado eventos. Usa el botón + para crear el primero.',
                          style: TextStyle(color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                      itemCount: _eventos.length,
                      itemBuilder: (ctx, i) {
                        final ev = _eventos[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${ev['titulo']}',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumRed)),
                                const SizedBox(height: 4),
                                Text(
                                  '${ev['dirigido']}'
                                  '${(ev['fechaEvento'] ?? '').toString().isNotEmpty ? ' · ${ev['fechaEvento']}' : ''}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                                const Divider(height: 18),
                                Row(
                                  children: [
                                    _chip(Icons.check_circle,
                                        '${ev['asistire']} asistirán',
                                        const Color(0xFF1E8E3E)),
                                    const SizedBox(width: 8),
                                    _chip(Icons.cancel,
                                        '${ev['noAsistire']} no',
                                        Colors.grey),
                                    const Spacer(),
                                    IconButton(
                                      onPressed: () => _borrarEvento(ev),
                                      icon: const Icon(Icons.delete_outline,
                                          size: 20, color: cessumRed),
                                      tooltip: 'Borrar evento',
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    TextButton(
                                      onPressed: () => _verConfirmaciones(ev),
                                      child: const Text('Ver lista',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            backgroundColor: cessumRed,
            foregroundColor: Colors.white,
            onPressed: _procesando ? null : _crearEvento,
            icon: const Icon(Icons.add),
            label: const Text('Nuevo evento'),
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icono, String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 4),
          Text(texto,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/* ---------------- Diálogo: lista de confirmaciones ---------------- */
class _DialogoConfirmaciones extends StatefulWidget {
  final String eventoId;
  final String titulo;
  const _DialogoConfirmaciones({required this.eventoId, required this.titulo});

  @override
  State<_DialogoConfirmaciones> createState() => _DialogoConfirmacionesState();
}

class _DialogoConfirmacionesState extends State<_DialogoConfirmaciones> {
  List<Map<String, dynamic>> _asistiran = [];
  List<Map<String, dynamic>> _noAsistiran = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resp = await http
          .get(Uri.parse(
              '$guardianUrl?accion=evento_detalle&id=${Uri.encodeComponent(widget.eventoId)}'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _asistiran = ((data['asistiran'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _noAsistiran = ((data['noAsistiran'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo, style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        child: _cargando
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(color: cessumRed)),
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Asistirán (${_asistiran.length})',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E8E3E))),
                    const SizedBox(height: 4),
                    if (_asistiran.isEmpty)
                      const Text('Nadie ha confirmado aún.',
                          style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ..._asistiran.map((a) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${a['nombre']} (${a['matricula']})',
                              style: const TextStyle(fontSize: 12.5)),
                        )),
                    const Divider(height: 20),
                    Text('No asistirán (${_noAsistiran.length})',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, color: Colors.grey)),
                    const SizedBox(height: 4),
                    ..._noAsistiran.map((a) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${a['nombre']} (${a['matricula']})',
                              style: const TextStyle(fontSize: 12.5)),
                        )),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

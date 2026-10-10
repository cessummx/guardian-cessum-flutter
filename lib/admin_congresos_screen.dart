import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Vista admin: Congresos/Eventos académicos (COINEDU) + Revista CESSUMEX.
/// Lee los formularios reales por el Guardián y permite capturar el
/// seguimiento (etapa, dictamen, revisores) sin tocar los formularios.
class AdminCongresosScreen extends StatelessWidget {
  const AdminCongresosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: Text('Congresos y Revista'),
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.groups), text: 'Congresos'),
              Tab(icon: Icon(Icons.menu_book), text: 'Revista'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_CongresosTab(), _RevistaTab()],
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>> _get(Map<String, String> params) async {
  final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
  final resp = await http.get(uri).timeout(Duration(seconds: 90));
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
  final resp = await http
      .post(Uri.parse(guardianUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload))
      .timeout(Duration(seconds: 90));
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

// ============================================================
//  PESTAÑA 1 — CONGRESOS
// ============================================================
class _CongresosTab extends StatefulWidget {
  const _CongresosTab();
  @override
  State<_CongresosTab> createState() => _CongresosTabState();
}

class _CongresosTabState extends State<_CongresosTab>
    with AutomaticKeepAliveClientMixin {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _eventos = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await _get({'accion': 'congresos_listar'});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      if (mounted) setState(() {
        _eventos = (r['eventos'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorVista(mensaje: _error!, onReintentar: _cargar);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: EdgeInsets.all(12),
        children: _eventos.map(_tarjetaEvento).toList(),
      ),
    );
  }

  Widget _tarjetaEvento(Map<String, dynamic> ev) {
    final etapas = (ev['etapas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Card(
      margin: EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _CongresoDetalle(
              clave: ev['clave'].toString(),
              nombre: ev['nombre'].toString(),
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(ev['nombre'].toString(),
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text('${ev['registros']} registros',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: cessumRed,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: etapas.map((et) {
                  return Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: Color(0xFFF0F0F0),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('${et['etapa']}: ${et['total']}',
                        style: TextStyle(fontSize: 11)),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CongresoDetalle extends StatefulWidget {
  final String clave;
  final String nombre;
  const _CongresoDetalle({required this.clave, required this.nombre});
  @override
  State<_CongresoDetalle> createState() => _CongresoDetalleState();
}

class _CongresoDetalleState extends State<_CongresoDetalle> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _parts = [];
  List<String> _etapasDef = [];
  List<String> _dictamenes = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r =
          await _get({'accion': 'congreso_detalle', 'clave': widget.clave});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      if (mounted) setState(() {
        _parts = (r['participantes'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _etapasDef =
            (r['etapasDef'] as List? ?? []).map((e) => e.toString()).toList();
        _dictamenes =
            (r['dictamenes'] as List? ?? []).map((e) => e.toString()).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _capturar(Map<String, dynamic> p) async {
    String etapa = p['etapaManual']?.toString() ?? '';
    String dictamen = p['dictamen']?.toString() ?? 'Pendiente';
    final notas = TextEditingController(text: p['notas']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: Text(p['titulo'].toString(),
              style: TextStyle(fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _etapasDef.contains(etapa) ? etapa : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: 'Etapa actual', border: OutlineInputBorder()),
                  items: _etapasDef
                      .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setSt(() => etapa = v ?? etapa),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _dictamenes.contains(dictamen) ? dictamen : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: 'Dictamen', border: OutlineInputBorder()),
                  items: _dictamenes
                      .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setSt(() => dictamen = v ?? dictamen),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: notas,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: 'Notas',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancelar')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Guardar',
                    style: TextStyle(color: Colors.white))),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      final r = await _post({
        'accion': 'congreso_estado',
        'evento': widget.clave,
        'titulo': p['titulo'],
        'autor': p['autor'],
        'etapa': etapa,
        'dictamen': dictamen,
        'notas': notas.text.trim(),
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _cargar();
    } catch (e) {
      _snack('No se pudo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text(widget.nombre, style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _cargando ? null : _cargar),
        ],
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorVista(mensaje: _error!, onReintentar: _cargar)
              : _parts.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Aún no hay registros en este evento.\nAparecerán conforme lleguen las inscripciones.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cessumMuted(context))),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.all(12),
                      children: _parts.map(_tarjetaParticipante).toList(),
                    ),
    );
  }

  Widget _tarjetaParticipante(Map<String, dynamic> p) {
    final alcanzadas = (p['etapasAlcanzadas'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    final dictamen = p['dictamen']?.toString() ?? 'Pendiente';
    Color cd = Colors.grey;
    if (dictamen == 'Aprobado') cd = const Color(0xFF1E8E3E);
    if (dictamen == 'Aprobado con cambios') cd = cessumGold;
    if (dictamen == 'Rechazado') cd = const Color(0xFFC62828);
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => _capturar(p),
        title: Text(p['titulo'].toString(),
            style:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((p['autor'] ?? '').toString().isNotEmpty)
              Text(p['autor'].toString(),
                  style: TextStyle(fontSize: 11.5)),
            SizedBox(height: 4),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                ..._etapasDef.map((et) {
                  final hecha = alcanzadas.contains(et);
                  return Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                        color: hecha
                            ? Color(0xFF1E8E3E).withValues(alpha: 0.13)
                            : Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(et,
                        style: TextStyle(
                            fontSize: 9.5,
                            color: hecha
                                ? Color(0xFF1E8E3E)
                                : cessumFaint(context),
                            fontWeight: hecha
                                ? FontWeight.w700
                                : FontWeight.w400)),
                  );
                }),
              ],
            ),
          ],
        ),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: cd.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20)),
          child: Text(dictamen,
              style: TextStyle(
                  fontSize: 9.5, color: cd, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ============================================================
//  PESTAÑA 2 — REVISTA CESSUMEX
// ============================================================
class _RevistaTab extends StatefulWidget {
  const _RevistaTab();
  @override
  State<_RevistaTab> createState() => _RevistaTabState();
}

class _RevistaTabState extends State<_RevistaTab>
    with AutomaticKeepAliveClientMixin {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _arts = [];
  List<String> _estados = [];
  String _filtro = 'Todos';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await _get({'accion': 'revista_listar'});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      if (mounted) setState(() {
        _arts = (r['articulos'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _estados =
            (r['estados'] as List? ?? []).map((e) => e.toString()).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Color _colorEstado(String e) {
    switch (e) {
      case 'En revisión':
        return Color(0xFF1565C0);
      case 'Cambios solicitados':
        return cessumGold;
      case 'Aceptado':
        return Color(0xFF1E8E3E);
      case 'Rechazado':
        return Color(0xFFC62828);
      case 'Publicado':
        return Color(0xFF6A1B9A);
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> _capturar(Map<String, dynamic> a) async {
    String estado = a['estado']?.toString() ?? 'Recibido';
    final rev1 = TextEditingController(text: a['revisor1']?.toString() ?? '');
    final rev2 = TextEditingController(text: a['revisor2']?.toString() ?? '');
    final dictamen =
        TextEditingController(text: a['dictamen']?.toString() ?? '');
    final notas = TextEditingController(text: a['notas']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: Text(a['titulo'].toString(),
              style: TextStyle(fontSize: 14)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: _estados.contains(estado) ? estado : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: 'Estado', border: OutlineInputBorder()),
                  items: _estados
                      .map((e) =>
                          DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => setSt(() => estado = v ?? estado),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: rev1,
                  decoration: InputDecoration(
                      labelText: 'Revisor 1',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: rev2,
                  decoration: InputDecoration(
                      labelText: 'Revisor 2',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: dictamen,
                  decoration: InputDecoration(
                      labelText: 'Dictamen (resumen)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: notas,
                  maxLines: 2,
                  decoration: InputDecoration(
                      labelText: 'Notas',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancelar')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Guardar',
                    style: TextStyle(color: Colors.white))),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      final r = await _post({
        'accion': 'revista_estado',
        'titulo': a['titulo'],
        'autor': a['autor'],
        'tipo': a['tipo'],
        'estado': estado,
        'revisor1': rev1.text.trim(),
        'revisor2': rev2.text.trim(),
        'dictamen': dictamen.text.trim(),
        'notas': notas.text.trim(),
      });
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      _cargar();
    } catch (e) {
      _snack('No se pudo: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorVista(mensaje: _error!, onReintentar: _cargar);
    }
    final filtros = ['Todos', ..._estados];
    final lista = _filtro == 'Todos'
        ? _arts
        : _arts.where((a) => a['estado'] == _filtro).toList();
    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: filtros.map((f) {
              final sel = f == _filtro;
              return Padding(
                padding: EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(f, style: TextStyle(fontSize: 11.5)),
                  selected: sel,
                  selectedColor: cessumRed.withValues(alpha: 0.15),
                  onSelected: (_) => setState(() => _filtro = f),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _cargar,
            child: lista.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                            child: Text('Sin artículos en este filtro.',
                                style: TextStyle(color: cessumMuted(context)))),
                      ),
                    ],
                  )
                : ListView(
                    padding: EdgeInsets.all(12),
                    children: lista.map(_tarjetaArticulo).toList(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _tarjetaArticulo(Map<String, dynamic> a) {
    final estado = a['estado']?.toString() ?? 'Recibido';
    final c = _colorEstado(estado);
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => _capturar(a),
        title: Text(a['titulo'].toString(),
            style:
                TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 2),
            Text(
                '${a['autor']}  ·  ${a['tipo']}'
                '${(a['fecha'] ?? '').toString().isNotEmpty ? '  ·  ${a['fecha']}' : ''}',
                style: TextStyle(fontSize: 11)),
            if ((a['linea'] ?? '').toString().isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(a['linea'].toString(),
                    style: TextStyle(
                        fontSize: 10.5, color: cessumMuted(context))),
              ),
            if ((a['revisor1'] ?? '').toString().isNotEmpty ||
                (a['revisor2'] ?? '').toString().isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Text(
                    'Revisores: ${[a['revisor1'], a['revisor2']].where((x) => (x ?? '').toString().isNotEmpty).join(', ')}',
                    style: TextStyle(
                        fontSize: 10.5, color: cessumMuted(context))),
              ),
          ],
        ),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(20)),
          child: Text(estado,
              style: TextStyle(
                  fontSize: 9.5, color: c, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

// ============================================================
class _ErrorVista extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;
  const _ErrorVista({required this.mensaje, required this.onReintentar});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center),
            SizedBox(height: 16),
            ElevatedButton(
                onPressed: onReintentar, child: Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';

/// Tablero de calendarización (pantalla nativa). Por cada grupo del padrón
/// muestra las sesiones agendadas (materia · día · hora · docente · estado),
/// las materias por agendar del plan y los contadores. Consume
/// guardian.php?accion=tablero_calendarizacion (JSON de la V354).
class TableroCalendarizacionScreen extends StatefulWidget {
  const TableroCalendarizacionScreen({super.key});

  @override
  State<TableroCalendarizacionScreen> createState() =>
      _TableroCalendarizacionScreenState();
}

class _TableroCalendarizacionScreenState
    extends State<TableroCalendarizacionScreen> {
  static const String _guardianUrl = 'https://app.cessum.mx/guardian.php';
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  String _actualizado = '';
  List<Map<String, dynamic>> _grupos = [];
  final TextEditingController _busqueda = TextEditingController();
  String _progFiltro = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$_guardianUrl?accion=tablero_calendarizacion'))
          .timeout(const Duration(seconds: 120));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) {
        throw Exception(j['error']?.toString() ?? 'Respuesta inválida');
      }
      final grupos = (j['grupos'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _grupos = grupos;
        _actualizado = (j['actualizado'] ?? '').toString();
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  List<String> get _programas {
    final s = <String>{};
    for (final g in _grupos) {
      final p = (g['programa'] ?? '').toString();
      if (p.isNotEmpty) s.add(p);
    }
    final l = s.toList()..sort();
    return l;
  }

  List<Map<String, dynamic>> get _filtrados {
    final q = _busqueda.text.trim().toLowerCase();
    return _grupos.where((g) {
      if (_progFiltro.isNotEmpty && (g['programa'] ?? '') != _progFiltro) {
        return false;
      }
      if (q.isEmpty) return true;
      final ses = (g['sesiones'] as List? ?? [])
          .map((s) => '${s['materia'] ?? ''} ${s['docente'] ?? ''}')
          .join(' ');
      final pa = (g['porAgendar'] as List? ?? []).join(' ');
      final txt = [g['programa'], g['generacion'], g['grupo'], ses, pa]
          .map((e) => (e ?? '').toString().toLowerCase())
          .join(' ');
      return txt.contains(q);
    }).toList();
  }

  int get _totSinMaestro {
    var n = 0;
    for (final g in _grupos) {
      for (final s in (g['sesiones'] as List? ?? [])) {
        if (s['sinMaestro'] == true) n++;
      }
    }
    return n;
  }

  int get _totPorAgendar {
    var n = 0;
    for (final g in _grupos) {
      n += (g['porAgendar'] as List? ?? []).length;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tablero de calendarización'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _vistaError() : _vistaTablero()),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44, color: Colors.black38),
            const SizedBox(height: 12),
            Text('No se pudo cargar el tablero.\n${_error ?? ''}',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _cargar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaTablero() {
    final items = _filtrados;
    return Column(
      children: [
        Container(
          color: cessumGold.withValues(alpha: 0.08), // (24-sep) modo oscuro
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_grupos.length} grupo(s) · $_totPorAgendar por agendar · $_totSinMaestro sin maestro'
                '${_actualizado.isNotEmpty ? ' · $_actualizado' : ''}',
                style: TextStyle(fontSize: 12, color: cessumMuted(context)),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _progFiltro,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('Todos los programas')),
                  ..._programas.map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _progFiltro = v ?? ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _busqueda,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  hintText: 'Buscar materia, docente, grupo…',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text('Nada que mostrar con ese filtro.',
                      style: TextStyle(color: cessumFaint(context))))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _tarjeta(items[i]),
                ),
        ),
      ],
    );
  }

  Widget _chip(Color c, String txt) {
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14)),
      child: Text(txt,
          style:
              TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _rotulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 11, color: cessumFaint(context), letterSpacing: 0.5)),
      );

  Widget _tarjeta(Map<String, dynamic> g) {
    final r = Map<String, dynamic>.from(g['resumen'] as Map? ?? {});
    final sesiones = (g['sesiones'] as List? ?? []);
    final porAgendar = (g['porAgendar'] as List? ?? []);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((g['programa'] ?? '').toString(),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cessumRed,
                    fontSize: 15)),
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 8),
              child: Text(
                'Gen. ${g['generacion']} · Grupo ${g['grupo']} · ${g['nAlum'] ?? 0} alumno(s)',
                style: TextStyle(fontSize: 13, color: cessumInk(context)),
              ),
            ),
            Wrap(children: [
              _chip(_verde, 'Cursadas ${r['cursadas'] ?? 0}'),
              _chip(cessumGold, 'En curso ${r['enCurso'] ?? 0}'),
              _chip(cessumRed, 'Por agendar ${r['pendientes'] ?? 0}'),
            ]),
            const SizedBox(height: 4),
            _rotulo('Agendadas'),
            if (sesiones.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('Sin sesiones agendadas',
                    style: TextStyle(color: cessumRed, fontSize: 13)),
              )
            else
              ...sesiones.map(
                  (s) => _sesion(Map<String, dynamic>.from(s as Map))),
            const SizedBox(height: 8),
            _rotulo('Por agendar del plan'),
            if (porAgendar.isEmpty)
              const Text('✔ Nada pendiente por agendar',
                  style: TextStyle(color: _verde, fontSize: 12))
            else
              Wrap(
                children: porAgendar
                    .map((m) => Container(
                          margin: const EdgeInsets.only(right: 6, top: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: cessumGold.withValues(alpha: 0.08), // (24-sep) modo oscuro
                            border: Border.all(color: cessumGold),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(m.toString(),
                              style: TextStyle(
                                  fontSize: 12, color: cessumGold)),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sesion(Map<String, dynamic> e) {
    final sinMaestro = e['sinMaestro'] == true;
    final estado = (e['estado'] ?? '').toString();
    final estColor =
        (estado == 'Aceptada' || estado == 'SI') ? _verde : cessumGold;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((e['materia'] ?? '').toString(),
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('${e['dia'] ?? '—'} · ${e['hora'] ?? '—'}   ',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.black54)),
              if (sinMaestro)
                Text('SIN MAESTRO',
                    style: TextStyle(
                        fontSize: 12,
                        color: cessumRed,
                        fontWeight: FontWeight.w600))
              else ...[
                Text((e['docente'] ?? '').toString(),
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black87)),
                const SizedBox(width: 6),
                Text(estado,
                    style: TextStyle(
                        fontSize: 11,
                        color: estColor,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

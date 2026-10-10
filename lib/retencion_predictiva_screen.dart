// retencion_predictiva_screen.dart · CESSUM · (24-sep-2026)
//
// RETENCIÓN PREDICTIVA · fase 4 de los centros inteligentes.
// Va más allá de la alerta: combina el riesgo que ya calcula el Guardián
// con el adeudo y con las intervenciones registradas, ordena por
// probabilidad de abandono y muestra a quién NO se ha atendido todavía.
// Abajo, la efectividad de cada tipo de intervención (cuántos intervenidos
// siguen activos), para que la institución aprenda qué sí retiene.
// Base: GET retencion_predictiva (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';
import 'expediente_360_screen.dart';

class RetencionPredictivaScreen extends StatefulWidget {
  const RetencionPredictivaScreen({super.key});

  @override
  State<RetencionPredictivaScreen> createState() => _RetencionPredictivaScreenState();
}

class _RetencionPredictivaScreenState extends State<RetencionPredictivaScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  Map<String, dynamic>? _d;
  String _filtro = 'sinAtender'; // sinAtender | altos | todos
  final _busca = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await http.get(Uri.parse('$guardianUrl?accion=retencion_predictiva')).timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo calcular la retención.');
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = (m.contains('TimeoutException') || m.contains('ClientException') || m.contains('SocketException'))
            ? 'No se pudo cargar. Revise su conexión e intente de nuevo.'
            : m;
      });
    }
  }

  List<Map<String, dynamic>> get _alumnos => ((_d?['alumnos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  List<Map<String, dynamic>> get _visibles {
    final q = _busca.text.trim().toLowerCase();
    return _alumnos.where((a) {
      final prob = (a['probabilidad'] as num? ?? 0).toInt();
      final activo = '${a['estado']}' == 'activo';
      if (_filtro == 'sinAtender' && !(activo && prob >= 60 && (a['intervenciones'] as num? ?? 0) == 0)) return false;
      if (_filtro == 'altos' && !(activo && prob >= 60)) return false;
      if (q.isNotEmpty && !'${a['nombre']} ${a['matricula']} ${a['programa']}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  Color _colorProb(int p) => p >= 75 ? cessumRed : (p >= 60 ? cessumGold : (p >= 40 ? const Color(0xFF1F5B9C) : _verde));

  @override
  Widget build(BuildContext context) {
    final vis = _visibles;
    final efect = Map<String, dynamic>.from((_d?['efectividad'] as Map?) ?? {});
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Retención predictiva', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.groups_outlined, size: 44, color: cessumFaint(context)),
                      const SizedBox(height: 10),
                      Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cessumInk(context))),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _encabezado(),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'sinAtender', label: Text('Sin atender (${_d?['sinAtender'] ?? 0})')),
                          ButtonSegment(value: 'altos', label: Text('Alto riesgo (${_d?['altos'] ?? 0})')),
                          ButtonSegment(value: 'todos', label: Text('Todos (${_d?['total'] ?? 0})')),
                        ],
                        selected: {_filtro},
                        onSelectionChanged: (s) => setState(() => _filtro = s.first),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _busca,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre, matrícula o programa…',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (vis.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text(_filtro == 'sinAtender' ? 'Todos los alumnos de alto riesgo tienen al menos una intervención.' : 'Nada coincide.', style: TextStyle(color: cessumMuted(context)))),
                        ),
                      for (final a in vis) _fila(a),
                      if (efect.isNotEmpty) ...[const SizedBox(height: 16), _efectividad(efect)],
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(onPressed: () => abrirPantallaCentro(context, 'riesgoAlerta'), icon: const Icon(Icons.warning_amber_rounded, size: 18), label: const Text('Alerta temprana')),
                        OutlinedButton.icon(onPressed: () => abrirPantallaCentro(context, 'retencion'), icon: const Icon(Icons.favorite_border, size: 18), label: const Text('Registrar intervención')),
                      ]),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _encabezado() {
    final sin = (_d?['sinAtender'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sin == 0 ? 'Todos los de alto riesgo ya tienen intervención' : (sin == 1 ? '1 alumno de alto riesgo sin atender' : '$sin alumnos de alto riesgo sin atender'),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${_d?['altos'] ?? 0} en alto riesgo de ${_d?['total'] ?? 0} con seguimiento · ${_d?['generado'] ?? ''}. La probabilidad combina riesgo, adeudo y si ya se intervino.',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
      ]),
    );
  }

  Widget _fila(Map<String, dynamic> a) {
    final p = (a['probabilidad'] as num? ?? 0).toInt();
    final c = _colorProb(p);
    final inter = (a['intervenciones'] as num? ?? 0).toInt();
    final factores = ((a['factores'] as List?) ?? []).map((e) => '$e').where((s) => s.isNotEmpty).take(3).join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.withValues(alpha: 0.45))),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Expediente360Screen(matricula: '${a['matricula']}'))),
        leading: SizedBox(
          width: 46,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$p%', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
            Text('abandono', style: TextStyle(fontSize: 8.5, color: cessumMuted(context))),
          ]),
        ),
        title: Text('${a['nombre'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context))),
        subtitle: Text(
          [
            '${a['matricula']}',
            if ('${a['programa'] ?? ''}'.isNotEmpty) '${a['programa']}',
            if ('${a['nivel'] ?? ''}'.isNotEmpty) 'Riesgo ${a['nivel']}',
            if (a['adeudo'] == true) 'con adeudo${(a['cortesVencidos'] as num? ?? 0) > 0 ? ' (${a['cortesVencidos']} corte(s) vencido(s))' : ''}',
            if (factores.isNotEmpty) factores,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: (inter > 0 ? _verde : cessumRed).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(inter > 0 ? '$inter intervención(es)' : 'sin atender', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: inter > 0 ? _verde : cessumRed)),
          ),
          if ('${a['estado']}' == 'baja')
            Padding(padding: const EdgeInsets.only(top: 3), child: Text('BAJA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cessumFaint(context)))),
        ]),
      ),
    );
  }

  Widget _efectividad(Map<String, dynamic> e) {
    final entradas = e.entries.toList()..sort((x, y) => ((y.value['intervenidos'] as num?) ?? 0).compareTo((x.value['intervenidos'] as num?) ?? 0));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).dividerColor)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('QUÉ SÍ RETIENE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
        const SizedBox(height: 4),
        Text('De los alumnos intervenidos con cada tipo, cuántos siguen activos.', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 8),
        for (final en in entradas)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(child: Text(en.key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cessumInk(context)))),
              Text('${en.value['retenidos']} de ${en.value['intervenidos']} activos', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ((en.value['retenidos'] as num? ?? 0) >= ((en.value['intervenidos'] as num? ?? 0) * 0.7)) ? _verde : cessumGold)),
            ]),
          ),
      ]),
    );
  }
}

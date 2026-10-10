// DOCENTE: Revisiones pendientes (ago-2026). Control de calidad: cada
// entrega de alumno abre una cuenta regresiva de 24 h para revisarla.
// El reloj corre en vivo; las vencidas se marcan en rojo. Fuente:
// ?accion=entregas_revision_docente (hoja EntregasRevision).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'entrega_visor_screen.dart';
import 'revision_tarea_screen.dart';   // (5-oct-2026) revisar por tarea, en lote
import 'cessum_header.dart';

class RevisionesScreen extends StatefulWidget {
  const RevisionesScreen({super.key});

  @override
  State<RevisionesScreen> createState() => _RevisionesScreenState();
}

class _RevisionesScreenState extends State<RevisionesScreen> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _entregas = [];
  int _desfaseMs = 0; // reloj del servidor vs local
  // (5-oct-2026) El plazo de revisión del Guardián y el factor «Revisión de entregas» del escalafón.
  int _plazoHoras = 72;
  Map<String, dynamic>? _esc;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _cargar();
    _tick = Timer.periodic(
        const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);   // (5-oct-2026) cuenta regresiva al segundo
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final correo = await SessionStore.validEmail();
      if (correo == null || correo.isEmpty) {
        throw Exception('Inicia sesión de nuevo.');
      }
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'entregas_revision_docente',
        'correo': correo,
      });
      final r = await http.get(u).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _entregas = ((d['entregas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final ahoraSrv = (d['ahoraMs'] ?? 0) as num;
        _desfaseMs = ahoraSrv > 0
            ? (ahoraSrv.toInt() - DateTime.now().millisecondsSinceEpoch)
            : 0;
        _plazoHoras = int.tryParse('${d['plazoHoras'] ?? 72}') ?? 72;
        _esc = d['escalafon'] is Map ? Map<String, dynamic>.from(d['escalafon'] as Map) : null;
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  int get _ahoraMs => DateTime.now().millisecondsSinceEpoch + _desfaseMs;

  String _restante(num venceMs) {
    final dif = venceMs.toInt() - _ahoraMs;
    if (dif <= 0) return 'VENCIDA';
    final h = dif ~/ 3600000;
    final m = (dif % 3600000) ~/ 60000;
    final s = (dif % 60000) ~/ 1000;
    String d2(int x) => x.toString().padLeft(2, '0');
    return h > 0 ? '$h h ${d2(m)} m ${d2(s)} s' : '${d2(m)} m ${d2(s)} s';
  }

  Color _colorRestante(num venceMs, String estado) {
    if (estado == 'Vencida') return cessumRed;
    final dif = venceMs.toInt() - _ahoraMs;
    if (dif <= 0) return cessumRed;
    if (dif < 6 * 3600000) return cessumGold;
    return const Color(0xFF1E8E3E);
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _entregas
        .where((e) => e['estado'] == 'Pendiente' || e['estado'] == 'Vencida')
        .toList();
    // (4-oct-2026, estética) Lo más urgente primero: vencidas y luego por tiempo restante.
    pendientes.sort((x, y) => ((x['venceMs'] ?? 0) as num).compareTo((y['venceMs'] ?? 0) as num));
    final revisadas =
        _entregas.where((e) => e['estado'] == 'Revisada').take(15).toList();
    final vencidas = pendientes.where((e) => e['estado'] == 'Vencida' || ((e['venceMs'] ?? 0) as num) <= _ahoraMs).length;
    final porVencer = pendientes.where((e) {
      final dif = ((e['venceMs'] ?? 0) as num).toInt() - _ahoraMs;
      return e['estado'] != 'Vencida' && dif > 0 && dif < 6 * 3600000;
    }).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: CessumAppBar(
        titulo: 'Revisiones pendientes',
        actions: [
          IconButton(
              tooltip: 'Revisar por tarea',
              onPressed: _abrirPorTarea,
              icon: const Icon(Icons.fact_check_outlined)),
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList(count: 4)
          : _error.isNotEmpty
              ? CessumEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'No se pudieron cargar tus revisiones',
                  subtitle: _error.replaceFirst('Exception: ', ''),
                  action: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: cessumRed),
                    onPressed: _cargar,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Intentar de nuevo'),
                  ),
                )
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    children: [
                      _resumen(pendientes.length, vencidas, porVencer),
                      if (_esc != null) ...[const SizedBox(height: 10), _tarjetaEscalafon()],
                      const SizedBox(height: 10),
                      // (5-oct-2026) Revisar una tarea completa: pre-llenar con IA, editar todas y enviar de un jalón.
                      Material(
                        color: cessumGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: _abrirPorTarea,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              const Icon(Icons.fact_check_outlined, color: cessumGold, size: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Revisar por tarea', style: CessumType.heading(14.5, color: cessumInk(context), weight: FontWeight.w800)),
                                  Text('Pre-llena con IA todas las retroalimentaciones de una tarea, ajústalas y envíalas de un jalón.',
                                      style: CessumType.body(12, color: cessumMuted(context))),
                                ]),
                              ),
                              const Icon(Icons.chevron_right, color: cessumGold),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (pendientes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: CessumEmptyState(
                            icon: Icons.task_alt_rounded,
                            title: 'Estás al corriente',
                            subtitle: 'No tienes entregas pendientes de revisión.',
                          ),
                        ),
                      for (final e in pendientes) _tarjeta(e),
                      if (revisadas.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text('REVISADAS RECIENTEMENTE',
                            style: CessumType.label(11, color: cessumMuted(context)).copyWith(letterSpacing: 1.6, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14)),
                          child: Column(children: [
                            for (var k = 0; k < revisadas.length; k++) ...[
                              if (k > 0) Divider(height: 1, color: cessumFaint(context).withValues(alpha: 0.15)),
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.check_circle_rounded, color: Color(0xFF1E7B34), size: 20),
                                title: Text('${revisadas[k]['alumno']}', style: CessumType.body(13, color: cessumInk(context), weight: FontWeight.w600)),
                                subtitle: Text('${revisadas[k]['tarea']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: CessumType.body(11.5, color: cessumMuted(context))),
                                trailing: Text('${revisadas[k]['revisadaEn'] ?? ''}', style: CessumType.label(11, color: cessumMuted(context))),
                              ),
                            ],
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Future<void> _abrirPorTarea() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const RevisionPorTareaScreen()));
    if (mounted) _cargar();
  }

  /// Resumen arriba: cuántas hay, cuántas vencieron y cuántas están por vencer; con el compromiso de 24 horas.
  /// (5-oct-2026) El plazo cruzado con el escalafón: % a tiempo, peso del factor y cómo queda si revisa a tiempo o se vencen.
  Widget _tarjetaEscalafon() {
    final e = _esc!;
    final pct = e['pctEnTiempo'];
    final si = e['puntajeSiATiempo'], no = e['puntajeSiSeVencen'];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E8E3E).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.military_tech_outlined, color: Color(0xFF1E8E3E)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Tu escalafón · Revisión de entregas${(e['peso'] ?? 0) != 0 ? ' (pesa ${e['peso']} %)' : ''}',
                style: CessumType.heading(14, color: cessumInk(context), weight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          pct == null
              ? 'Todavía no tienes revisiones cerradas que cuenten. El plazo es de $_plazoHoras h desde que el alumno entrega.'
              : 'Revisas a tiempo el $pct % de tus entregas (puntaje de este factor: ${e['puntaje']}). El plazo es de $_plazoHoras h desde que el alumno entrega.',
          style: CessumType.body(12.5, color: cessumInk(context)),
        ),
        if (si != null && no != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _escenario('Si revisas tus ${e['pendientes']} pendientes a tiempo', '$si', const Color(0xFF1E8E3E))),
            const SizedBox(width: 8),
            Expanded(child: _escenario('Si se te vencen', '$no', cessumRed)),
          ]),
        ],
      ]),
    );
  }

  Widget _escenario(String t, String v, Color c) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: CessumType.heading(22, color: c, weight: FontWeight.w900)),
          Text(t, style: CessumType.label(11, color: cessumMuted(context))),
        ]),
      );

  Widget _resumen(int total, int vencidas, int porVencer) {
    Widget dato(String n, String t, Color c) => Expanded(
          child: Column(children: [
            Text(n, style: CessumType.heading(24, color: c, weight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(t, textAlign: TextAlign.center, style: CessumType.label(11, color: cessumMuted(context))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        Row(children: [
          dato('$total', 'Por revisar', cessumInk(context)),
          Container(width: 1, height: 34, color: cessumFaint(context).withValues(alpha: 0.2)),
          dato('$vencidas', 'Vencidas', vencidas > 0 ? cessumRed : const Color(0xFF1E7B34)),
          Container(width: 1, height: 34, color: cessumFaint(context).withValues(alpha: 0.2)),
          dato('$porVencer', 'Vencen en menos de 6 h', porVencer > 0 ? cessumGold : const Color(0xFF1E7B34)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.schedule_rounded, size: 15, color: cessumGold),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Compromiso de calidad CESSUM: cada entrega se revisa y califica dentro de las 24 horas siguientes.',
                style: CessumType.body(11.5, color: cessumMuted(context))),
          ),
        ]),
      ]),
    );
  }

  /// (8-oct-2026) El diálogo «Borrador con IA» que vivía aquí —copiar la retro y abrir el aula a
  /// mano— se retiró: el botón de IA de cada tarjeta ahora abre la entrega y genera ahí mismo la
  /// calificación sugerida (ver EntregaVisorScreen.autoGenerarBorrador), que se guarda directo con
  /// «Calificar y retroalimentar» en vez de pegarse a mano en Moodle.

  Widget _tarjeta(Map<String, dynamic> e) {
    final venceMs = (e['venceMs'] ?? 0) as num;
    final estado = (e['estado'] ?? '').toString();
    final c = _colorRestante(venceMs, estado);
    final restante = estado == 'Vencida' ? 'VENCIDA' : _restante(venceMs);
    final vencida = restante == 'VENCIDA';
    final alumno = '${e['alumno'] ?? ''}';
    final iniciales = alumno.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).map((x) => x[0].toUpperCase()).join();
    final tieneLlave = (e['llave'] ?? '').toString().isNotEmpty;
    final link = (e['link'] ?? '').toString();
    Future<void> abrir({bool conSugerencia = false}) async {
      final calificada = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EntregaVisorScreen(
            llave: '${e['llave'] ?? ''}',
            alumno: alumno,
            tarea: '${e['tarea'] ?? ''}',
            enlaceAula: link,
            // (8-oct-2026) El botón de IA de esta tarjeta ya no abre el diálogo aparte que copiaba
            // la retro y abría el aula a mano (_borradorIa, ahora retirado): abre esta misma
            // pantalla y genera la sugerencia de una vez, para guardarla directo con «Calificar».
            autoGenerarBorrador: conSugerencia,
          ),
        ),
      );
      if (calificada == true) _cargar();   // (R3) ya revisada: sale de la lista
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: c),   // franja de urgencia
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: CC.goldCard,
                    child: Text(iniciales.isEmpty ? '?' : iniciales, style: CessumType.heading(13, color: CC.goldDark, weight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(alumno, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: CessumType.heading(14.5, color: cessumInk(context), weight: FontWeight.w800)),
                      Text('${e['tarea']}', maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: CessumType.body(12.5, color: cessumInk(context), weight: FontWeight.w600)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(vencida ? Icons.error_rounded : Icons.timer_outlined, size: 14, color: c),
                      const SizedBox(width: 4),
                      Text(vencida ? 'Vencida' : restante, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  '${e['materia'] ?? ''}'.isNotEmpty ? '${e['materia']} · ${e['curso']}' : '${e['curso']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CessumType.body(11.5, color: cessumMuted(context)),
                ),
                Text('Entregada: ${e['entregada']}', style: CessumType.label(11.5, color: cessumMuted(context))),
                // (5-oct-2026) Cuánto del plazo de revisión ya se consumió.
                if (!vencida && estado != 'Revisada') ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (1 - (venceMs.toInt() - _ahoraMs) / (_plazoHoras * 3600000)).clamp(0.0, 1.0),
                      minHeight: 6,
                      color: c,
                      backgroundColor: c.withValues(alpha: 0.14),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('Quedan $restante de $_plazoHoras h para revisarla', style: CessumType.label(11, color: c)),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  if (tieneLlave)
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: cessumRed,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: abrir,
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Ver, leer y calificar', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    )
                  else if (link.isNotEmpty)
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: cessumRed,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => Helpers.abrirUrlExterna(link, context),
                        icon: const Icon(Icons.rate_review_outlined, size: 18),
                        label: const Text('Calificar en el aula'),
                      ),
                    ),
                  if (tieneLlave) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Calificación sugerida con IA',
                      style: IconButton.styleFrom(foregroundColor: cessumGold, side: const BorderSide(color: CC.goldBorder)),
                      onPressed: () => abrir(conSugerencia: true),
                      icon: const Icon(Icons.auto_awesome, size: 19),
                    ),
                  ],
                  if (tieneLlave && link.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    IconButton.outlined(
                      tooltip: 'Abrir en el aula',
                      onPressed: () => Helpers.abrirUrlExterna(link, context),
                      icon: const Icon(Icons.open_in_new_rounded, size: 19),
                    ),
                  ],
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

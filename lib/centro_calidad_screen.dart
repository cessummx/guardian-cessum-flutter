// =====================================================================
//  centro_calidad_screen.dart · CESSUM · Aula CESSUM
//  Centro de calidad institucional: todo lo que los alumnos dicen, en un
//  solo lugar.
//
//  Por qué existe: la información de calidad estaba repartida en pantallas
//  que nadie cruzaba. La opinión sobre la app en un tablero, la de los
//  docentes en el pulso general, el buzón anónimo en otra pantalla y las
//  quejas por escrito en ninguna parte. Cada una por separado no permite
//  decidir: el número de la app no dice si el problema es la app o el
//  proceso, y el buzón no se lee junto a la evaluación que lo explica.
//
//  Qué NO hace: no inventa promedios nuevos. Cada pestaña muestra lo que
//  el Guardián ya calcula, con su tamaño de muestra a la vista, para que
//  nadie tome una decisión sobre tres respuestas creyendo que son cien.
//
//  Backend (Code.gs V933):
//    ?accion=calidad_plataforma&dias=90   → app: grupos, preguntas, muestra
//    ?accion=pulso_resumen                → todas las categorías del pulso
//    ?accion=buzon_listar[&estatus=]      → buzón anónimo
//    ?accion=calidad_detalle&pregunta=ID  → respuesta por respuesta
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'calidad_plataforma_screen.dart';

class CentroCalidadScreen extends StatefulWidget {
  const CentroCalidadScreen({super.key});
  @override
  State<CentroCalidadScreen> createState() => _CentroCalidadScreenState();
}

class _CentroCalidadScreenState extends State<CentroCalidadScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _dias = 90;

  bool _cargando = true;
  String? _error;

  Map<String, dynamic> _plat = {};
  Map<String, dynamic> _pulso = {};
  List<Map<String, dynamic>> _buzon = [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Las tres fuentes se piden en paralelo: son independientes y esperar una
  /// tras otra triplicaba el tiempo de apertura. Si una falla, las demás se
  /// muestran igual; la pestaña que se quedó sin datos lo dice por su cuenta.
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        _get({'accion': 'calidad_plataforma', 'dias': '$_dias'}),
        _get({'accion': 'pulso_resumen'}),
        _get({'accion': 'buzon_listar'}),
      ]);
      if (!mounted) return;
      setState(() {
        _plat = res[0];
        _pulso = res[1];
        _buzon = ((res[2]['mensajes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<Map<String, dynamic>> _get(Map<String, String> q) async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: q);
      final r = await http.get(uri).timeout(const Duration(seconds: 90));
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false};
    }
  }

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  Color _col(int v) => v >= 85
      ? const Color(0xFF1E8E3E)
      : (v >= 70 ? cessumGold : const Color(0xFFC62828));

  // El pulso guarda promedios en la escala original (1-10 casi siempre).
  // Aquí se llevan a 100 para que se lean igual que los de plataforma.
  int _sobre100(dynamic prom) {
    final p = prom is num ? prom.toDouble() : 0.0;
    if (p <= 0) return 0;
    final v = p <= 5 ? p / 5 * 100 : p / 10 * 100;
    return v.round().clamp(0, 100);
  }

  List<Map<String, dynamic>> _preguntasDe(String categoria) {
    final lista = (_pulso['preguntasOrdenadasDePeorAMejor'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => '${e['categoria']}' == categoria)
        .toList();
    return lista;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Centro de calidad'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Periodo',
            icon: const Icon(Icons.date_range),
            onSelected: (v) {
              setState(() => _dias = v);
              _cargar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 30, child: Text('Últimos 30 días')),
              PopupMenuItem(value: 90, child: Text('Últimos 90 días')),
              PopupMenuItem(value: 365, child: Text('Último año')),
            ],
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Panorama'),
            Tab(text: 'Docentes'),
            Tab(text: 'Plataforma'),
            Tab(text: 'Buzón anónimo'),
          ],
        ),
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? _vistaError()
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _tabPanorama(),
                    _tabCategoria('docente', 'Evaluación docente',
                        'Lo que los alumnos dicen de sus profesores. '
                            'Ordenado de peor a mejor.'),
                    _tabPlataforma(),
                    _tabBuzon(),
                  ],
                ),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 46, color: Colors.grey),
              const SizedBox(height: 10),
              const Text(
                  'El sistema tardó más de lo normal en responder. No es tu '
                  'conexión: vuelve a intentarlo.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton(
                  onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  // ================= PANORAMA =================

  Widget _tabPanorama() {
    final gPlat = _plat['general'] is num ? _n(_plat['general']) : null;
    final porCat = (_pulso['porCategoria'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final pend =
        _buzon.where((m) => '${m['estatus']}'.toLowerCase() != 'resuelto').length;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          Text('Cómo nos ven los alumnos',
              style: CessumType.display(20)),
          const SizedBox(height: 3),
          Text('Últimos $_dias días. Toca cualquier tarjeta para el detalle.',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 14),

          // Tarjetas grandes: una por frente de calidad.
          Row(
            children: [
              Expanded(
                child: _tarjetaGrande(
                  titulo: 'Plataforma',
                  valor: gPlat,
                  pie: '${_n(_plat['alumnosQueRespondieron'])} de '
                      '${_n(_plat['alumnosActivos'])} alumnos',
                  onTap: () => _tabs.animateTo(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tarjetaGrande(
                  titulo: 'Docentes',
                  valor: _promCategoria(porCat, 'docente'),
                  pie: '${_preguntasDe('docente').length} preguntas',
                  onTap: () => _tabs.animateTo(1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _tarjetaGrande(
                  titulo: 'Procesos',
                  valor: _promCategoria(porCat, 'procesos'),
                  pie: 'inscripción, pagos, titulación',
                  onTap: () => _tabs.animateTo(0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tarjetaBuzon(pend),
              ),
            ],
          ),

          // Participación: el dato que decide si algo de esto es creíble.
          const SizedBox(height: 16),
          _bloqueParticipacion(),

          // Lo peor de todo el sistema, mezclando categorías: es la lista
          // por la que hay que empezar el lunes.
          const SizedBox(height: 16),
          _titulo('Lo peor evaluado, de todo'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
                'De todas las categorías juntas. Fíjate siempre en cuántas '
                'respuestas tiene cada una antes de actuar.',
                style: TextStyle(fontSize: 11.5, color: Colors.black54)),
          ),
          ..._peoresGlobales().map(_filaPregunta),

          const SizedBox(height: 16),
          _titulo('Últimos mensajes del buzón'),
          if (_buzon.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Sin mensajes en el buzón.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            )
          else
            ..._buzon.take(3).map(_fichaBuzon),
          if (_buzon.length > 3)
            TextButton(
              onPressed: () => _tabs.animateTo(3),
              child: Text('Ver los ${_buzon.length} mensajes'),
            ),
        ],
      ),
    );
  }

  int? _promCategoria(List<Map<String, dynamic>> porCat, String id) {
    for (final c in porCat) {
      if ('${c['categoria'] ?? c['id'] ?? ''}' == id) {
        final v = _sobre100(c['promedio']);
        return v == 0 ? null : v;
      }
    }
    // Si el resumen no trae la categoría, se calcula con sus preguntas.
    final qs = _preguntasDe(id);
    if (qs.isEmpty) return null;
    var s = 0.0;
    for (final q in qs) {
      s += _sobre100(q['promedio']).toDouble();
    }
    return (s / qs.length).round();
  }

  List<Map<String, dynamic>> _peoresGlobales() {
    final todas = (_pulso['preguntasOrdenadasDePeorAMejor'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return todas.take(6).toList();
  }

  Widget _bloqueParticipacion() {
    final resp = _n(_plat['alumnosQueRespondieron']);
    final act = _n(_plat['alumnosActivos']);
    final pct = _plat['participacionPct'];
    final p = pct is num ? pct.toInt() : null;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: (p != null && p < 20)
            ? const Color(0xFFFDF3F3)
            : const Color(0xFFF6F8F6),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
            color: (p != null && p < 20)
                ? const Color(0xFFC62828).withValues(alpha: 0.3)
                : const Color(0xFF1E8E3E).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  (p != null && p < 20)
                      ? Icons.warning_amber_rounded
                      : Icons.groups_outlined,
                  size: 18,
                  color: (p != null && p < 20)
                      ? const Color(0xFFC62828)
                      : const Color(0xFF1E8E3E)),
              const SizedBox(width: 7),
              const Text('Participación',
                  style:
                      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 7),
          if (act > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (resp / act).clamp(0.0, 1.0),
                minHeight: 9,
                backgroundColor: const Color(0xFFEEEAE2),
                valueColor: AlwaysStoppedAnimation<Color>(
                    (p != null && p < 20)
                        ? const Color(0xFFC62828)
                        : const Color(0xFF1E8E3E)),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
              act > 0
                  ? '$resp de $act alumnos activos respondieron '
                      '(${p ?? 0} %). ${_n(_plat['totalRespuestas'])} respuestas '
                      'en total.'
                  : '$resp alumnos respondieron · '
                      '${_n(_plat['totalRespuestas'])} respuestas.',
              style: const TextStyle(fontSize: 12, height: 1.35)),
          if ('${_plat['aviso'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${_plat['aviso']}',
                style: const TextStyle(
                    fontSize: 11.5, height: 1.35, color: Color(0xFFC62828))),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaGrande({
    required String titulo,
    required int? valor,
    required String pie,
    VoidCallback? onTap,
  }) {
    final col = valor == null ? Colors.grey : _col(valor);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: col.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(valor == null ? '—' : '$valor',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: col)),
                if (valor != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 5, left: 2),
                    child: Text('/100',
                        style:
                            TextStyle(fontSize: 11, color: Colors.black38)),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(pie,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaBuzon(int pendientes) {
    final col = pendientes > 0 ? cessumGold : const Color(0xFF1E8E3E);
    return InkWell(
      onTap: () => _tabs.animateTo(3),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: col.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Buzón anónimo',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('$pendientes',
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, color: col)),
            const SizedBox(height: 3),
            Text(
                pendientes == 0
                    ? 'todo atendido · ${_buzon.length} en total'
                    : 'sin atender · ${_buzon.length} en total',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          ],
        ),
      ),
    );
  }

  // ================= CATEGORÍA (docentes) =================

  Widget _tabCategoria(String cat, String titulo, String bajada) {
    final qs = _preguntasDe(cat);
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          Text(titulo, style: CessumType.display(19)),
          const SizedBox(height: 3),
          Text(bajada,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 14),
          if (qs.isEmpty)
            const CessumEmptyState(
              title: 'Todavía no hay respuestas',
              subtitle:
                  'Cuando los alumnos contesten el pulso sobre sus docentes, '
                  'aquí aparecerá qué funciona y qué no.',
              icon: Icons.school_outlined,
            )
          else ...[
            _avisoMuestra(qs),
            const SizedBox(height: 12),
            ...qs.map(_filaPregunta),
          ],
        ],
      ),
    );
  }

  /// Aviso honesto: si casi todas las preguntas tienen pocas respuestas, se
  /// dice antes de que alguien tome una decisión sobre ellas.
  Widget _avisoMuestra(List<Map<String, dynamic>> qs) {
    var debiles = 0;
    for (final q in qs) {
      if (_n(q['respuestas']) < 10) debiles++;
    }
    if (debiles == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
      ),
      child: Text(
          '$debiles de ${qs.length} preguntas tienen menos de 10 respuestas. '
          'Sirven para detectar señales, no para calificar a nadie.',
          style: const TextStyle(fontSize: 11.5, height: 1.35)),
    );
  }

  Widget _filaPregunta(Map<String, dynamic> q) {
    final v = _sobre100(q['promedio']);
    final col = _col(v);
    final n = _n(q['respuestas']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('${q['texto']}',
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
              const SizedBox(width: 8),
              Text('$v',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: col)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (v / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: const Color(0xFFEEEAE2),
              valueColor: AlwaysStoppedAnimation<Color>(col),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text('${q['id']} · $n respuesta(s)',
                    style: const TextStyle(
                        fontSize: 10.5, color: Colors.black45)),
              ),
              _sello(n),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sello(int n) {
    final firme = n >= 10;
    final media = n >= 4;
    final col = firme
        ? const Color(0xFF1E8E3E)
        : (media ? cessumGold : const Color(0xFF8A8A8A));
    final txt = firme
        ? 'muestra firme'
        : (media ? 'solo indicativa' : 'anecdótica');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: col.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(txt,
          style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700, color: col)),
    );
  }

  // ================= PLATAFORMA =================

  Widget _tabPlataforma() {
    final qs = (_plat['preguntas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final grupos = (_plat['porGrupo'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          Text('La app, por área', style: CessumType.display(19)),
          const SizedBox(height: 10),
          for (final g in grupos)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    child: Text('${_n(g['promedio'])}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _col(_n(g['promedio'])))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${g['grupo']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (_n(g['promedio']) / 100).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: const Color(0xFFEEEAE2),
                            valueColor: AlwaysStoppedAnimation<Color>(
                                _col(_n(g['promedio']))),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('${_n(g['preguntas'])} pregunta(s) · '
                            '${_n(g['respuestas'])} respuesta(s)',
                            style: const TextStyle(
                                fontSize: 10.5, color: Colors.black45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Abrir el detalle completo de la app'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CalidadPlataformaScreen()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'Ahí está pregunta por pregunta, el reparto de respuestas y '
              'quién contestó qué, una por una.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54)),
          const SizedBox(height: 16),
          _titulo('Lo que hay que arreglar primero'),
          ...qs.take(5).map((q) => _filaPregunta({
                'texto': q['texto'],
                'promedio': (_n(q['promedio']) / 10),
                'respuestas': q['respuestas'],
                'id': q['id'],
              })),
        ],
      ),
    );
  }

  // ================= BUZÓN =================

  Widget _tabBuzon() {
    final pend = _buzon
        .where((m) => '${m['estatus']}'.toLowerCase() != 'resuelto')
        .toList();
    final resueltos = _buzon
        .where((m) => '${m['estatus']}'.toLowerCase() == 'resuelto')
        .toList();
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          Text('Buzón anónimo', style: CessumType.display(19)),
          const SizedBox(height: 3),
          const Text(
              'Lo que los alumnos escriben sin dar su nombre. Es la única vía '
              'donde dicen lo que no se atreven a firmar: léelo aunque no '
              'traiga número.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 14),
          if (_buzon.isEmpty)
            const CessumEmptyState(
              title: 'Sin mensajes',
              subtitle:
                  'Nadie ha escrito al buzón anónimo. Si lleva mucho vacío, '
                  'quizá los alumnos no saben que existe.',
              icon: Icons.markunread_mailbox_outlined,
            )
          else ...[
            if (pend.isNotEmpty) ...[
              _titulo('Sin atender · ${pend.length}'),
              ...pend.map(_fichaBuzon),
              const SizedBox(height: 14),
            ],
            if (resueltos.isNotEmpty) ...[
              _titulo('Atendidos · ${resueltos.length}'),
              ...resueltos.map(_fichaBuzon),
            ],
          ],
        ],
      ),
    );
  }

  Widget _fichaBuzon(Map<String, dynamic> m) {
    final resuelto = '${m['estatus']}'.toLowerCase() == 'resuelto';
    final col = resuelto ? const Color(0xFF1E8E3E) : cessumGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${m['categoria']}',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: col)),
              ),
              const Spacer(),
              Text('${m['fecha']}',
                  style: const TextStyle(
                      fontSize: 10.5, color: Colors.black45)),
            ],
          ),
          const SizedBox(height: 7),
          Text('${m['mensaje']}',
              style: const TextStyle(fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 6),
          Text([
            '${m['folio']}',
            if ('${m['programa'] ?? ''}'.isNotEmpty) '${m['programa']}',
            '${m['estatus']}',
          ].where((e) => e.isNotEmpty).join(' · '),
              style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          if ('${m['notas'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFFF7F5F0),
                  borderRadius: BorderRadius.circular(7)),
              child: Text('Atendido: ${m['notas']}',
                  style: const TextStyle(fontSize: 11.5, height: 1.35)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: cessumRed)),
      );
}

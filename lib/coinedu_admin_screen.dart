// =====================================================================
//  coinedu_admin_screen.dart · CESSUM
//  COINEDU 2026 — II Congreso Internacional de Educación.
//  Tablero de dictaminación y seguimiento de contribuciones.
//
//  Las ponencias y los carteles llegan por dos formularios de Google. Esta
//  pantalla los lee, los deja dictaminar y lleva el seguimiento posterior
//  (pago, extenso, semblanza) SIN tocar las hojas de respuestas: el
//  dictamen vive en una hoja aparte, ligada por folio.
//
//  Backend (Code.gs V531):
//    GET  coinedu_resumen · coinedu_listar · coinedu_marcar · coinedu_anios
//    POST coinedu_dictaminar   (el correo al autor solo sale con avisar=1)
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

const List<String> _kDictamenes = [
  'Pendiente',
  'En dictamen',
  'Aceptado',
  'Aceptado con cambios',
  'Rechazado',
];

Color _colorEstado(String e) {
  switch (e) {
    case 'Aceptado':
      return const Color(0xFF1E8E3E);
    case 'Aceptado con cambios':
      return const Color(0xFF6A4FB0);
    case 'Rechazado':
      return const Color(0xFFC62828);
    case 'En dictamen':
      return cessumGold;
  }
  return const Color(0xFF8A8A8A);
}

class CoineduAdminScreen extends StatefulWidget {
  const CoineduAdminScreen({super.key});
  @override
  State<CoineduAdminScreen> createState() => _CoineduAdminScreenState();
}

class _CoineduAdminScreenState extends State<CoineduAdminScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _lista = [];
  String _correo = '';

  final _busca = TextEditingController();
  String _filtroTipo = '';
  String _filtroEstado = '';
  String? _trabajando;

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

  Future<Map<String, dynamic>> _get(Map<String, String> p) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: p);
    final r = await http.get(uri).timeout(const Duration(seconds: 90));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      _correo = (await SessionStore.realEmail()) ?? '';
      final res = await _get({'accion': 'coinedu_resumen'});
      if (res['ok'] != true) throw Exception(res['error'] ?? 'Error');
      final lis = await _get({'accion': 'coinedu_listar'});
      if (!mounted) return;
      setState(() {
        _resumen = res;
        _lista = (lis['contribuciones'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _norm(String s) {
    s = s.toLowerCase();
    const a = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const b = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _norm(_busca.text);
    return _lista.where((c) {
      if (_filtroTipo.isNotEmpty && '${c['tipo']}' != _filtroTipo) return false;
      if (_filtroEstado.isNotEmpty && '${c['estado']}' != _filtroEstado) {
        return false;
      }
      if (q.isEmpty) return true;
      return _norm([
        c['titulo'],
        c['autores'],
        c['correo'],
        c['institucion'],
        c['linea'],
        c['folio'],
        c['claveComite'],
      ].join(' ')).contains(q);
    }).toList();
  }

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  @override
  Widget build(BuildContext context) {
    final vis = _cargando ? <Map<String, dynamic>>[] : _visibles;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('COINEDU 2026'),
        actions: [
          IconButton(
            tooltip: 'Más acciones',
            icon: const Icon(Icons.more_vert),
            onPressed: _cargando ? null : _menuAcciones,
          ),
          IconButton(
            tooltip: 'Calendario del congreso',
            icon: const Icon(Icons.calendar_month),
            onPressed: _cargando ? null : _verCalendario,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? _vistaError()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                    children: [
                      _cabecera(),
                      const SizedBox(height: 12),
                      _etapaActual(),
                      const SizedBox(height: 12),
                      _porLinea(),
                      const SizedBox(height: 14),
                      _filtros(),
                      const SizedBox(height: 10),
                      if (_lista.isEmpty)
                        const CessumEmptyState(
                          title: 'Todavía no hay contribuciones',
                          subtitle:
                              'Cuando alguien envíe una ponencia o un cartel '
                              'desde coinedu.cessum.mx, aparecerá aquí para '
                              'dictaminar.',
                          icon: Icons.inbox_outlined,
                        )
                      else if (vis.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                              child: Text('Ninguna coincide con el filtro.',
                                  style: TextStyle(color: Colors.black54))),
                        )
                      else
                        ...vis.map(_tarjeta),
                    ],
                  ),
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
              Text(_error ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton(
                  onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _cabecera() {
    final tipos = Map<String, dynamic>.from(_resumen['porTipo'] ?? {});
    final pend = _n(_resumen['pendientesDictamen']);
    final dias = _n(_resumen['diasMasViejo']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB11D29), Color(0xFF8E1720)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_n(_resumen['total'])}',
              style: CessumType.display(38, color: Colors.white)),
          const Text('contribuciones recibidas',
              style: TextStyle(fontSize: 12.5, color: Colors.white70)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _pastilla('${_n(tipos['ponencia'])} ponencias'),
              _pastilla('${_n(tipos['cartel'])} carteles'),
              _pastilla('${_n(_resumen['instituciones'])} instituciones'),
              if (pend > 0)
                _pastilla(
                    '$pend por dictaminar'
                    '${dias > 0 ? ' · $dias días' : ''}',
                    alerta: true),
              if (_n(_resumen['dictaminadosSinNotificar']) > 0)
                _pastilla(
                    '${_n(_resumen['dictaminadosSinNotificar'])} sin notificar',
                    alerta: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pastilla(String t, {bool alerta = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: alerta ? 0.30 : 0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
      );

  Widget _etapaActual() {
    final cal = Map<String, dynamic>.from(_resumen['calendario'] ?? {});
    final act = cal['actual'] == null
        ? null
        : Map<String, dynamic>.from(cal['actual'] as Map);
    final prox = cal['proxima'] == null
        ? null
        : Map<String, dynamic>.from(cal['proxima'] as Map);
    if (act == null && prox == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF6EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CC.goldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (act != null) ...[
            Row(
              children: [
                const Icon(Icons.play_circle_outline,
                    size: 18, color: cessumGold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Ahora: ${act['etapa']}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
                Text('${_n(act['diasRestantes'])} días',
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: cessumGold)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text('Cierra el ${act['fin']}',
                  style: const TextStyle(
                      fontSize: 11.5, color: Colors.black54)),
            ),
          ],
          if (prox != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule, size: 16, color: Colors.black45),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Sigue: ${prox['etapa']} · en ${_n(prox['enDias'])} días',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _porLinea() {
    final lin = Map<String, dynamic>.from(_resumen['porLinea'] ?? {});
    if (lin.isEmpty) return const SizedBox.shrink();
    final entradas = lin.entries.toList()
      ..sort((a, b) => _n(b.value).compareTo(_n(a.value)));
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.donut_small, color: cessumRed, size: 20),
        title: Text('Por línea temática (${entradas.length})',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        children: [
          for (final e in entradas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(e.key,
                        style: const TextStyle(fontSize: 12, height: 1.3)),
                  ),
                  const SizedBox(width: 8),
                  Text('${_n(e.value)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: cessumRed)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Column(
      children: [
        TextField(
          controller: _busca,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Buscar por título, autor, institución o folio…',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: const OutlineInputBorder(),
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _busca.clear()),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip('Todas', _filtroEstado.isEmpty && _filtroTipo.isEmpty, () {
                setState(() {
                  _filtroEstado = '';
                  _filtroTipo = '';
                });
              }),
              const SizedBox(width: 6),
              _chip('Ponencias', _filtroTipo == 'ponencia',
                  () => setState(() => _filtroTipo =
                      _filtroTipo == 'ponencia' ? '' : 'ponencia')),
              const SizedBox(width: 6),
              _chip('Carteles', _filtroTipo == 'cartel',
                  () => setState(() => _filtroTipo =
                      _filtroTipo == 'cartel' ? '' : 'cartel')),
              const SizedBox(width: 12),
              for (final e in _kDictamenes) ...[
                _chip(e, _filtroEstado == e,
                    () => setState(
                        () => _filtroEstado = _filtroEstado == e ? '' : e),
                    color: _colorEstado(e)),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String t, bool sel, VoidCallback onTap, {Color? color}) {
    final c = color ?? cessumRed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? c.withValues(alpha: 0.14) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: sel ? c : Colors.black12, width: sel ? 1.4 : 1),
        ),
        child: Text(t,
            style: TextStyle(
                fontSize: 12,
                fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                color: sel ? c : Colors.black87)),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> c) {
    final estado = '${c['estado']}';
    final col = _colorEstado(estado);
    final dias = _n(c['diasEsperando']);
    final coautores = (c['coautores'] as List? ?? []).cast<dynamic>();
    final archivo = '${c['archivo'] ?? ''}';
    final ocupado = _trabajando == '${c['folio']}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: col.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(estado,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: col)),
                ),
                const SizedBox(width: 6),
                Text('${c['tipo']}'.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.black45)),
                const Spacer(),
                Text('${c['folio']}',
                    style: const TextStyle(
                        fontSize: 10.5, color: Colors.black38)),
              ],
            ),
            const SizedBox(height: 6),
            Text('${c['titulo']}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, height: 1.3)),
            const SizedBox(height: 4),
            Text('${c['autores']}'
                '${coautores.isNotEmpty ? ' · +${coautores.length} coautor(es)' : ''}',
                style: const TextStyle(fontSize: 12.5)),
            Text('${c['institucion']}',
                style:
                    const TextStyle(fontSize: 11.5, color: Colors.black54)),
            const SizedBox(height: 4),
            Text('${c['linea']}',
                style: const TextStyle(
                    fontSize: 11.5,
                    color: cessumGold,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
                'Recibida el ${c['fecha']}'
                '${estado == 'Pendiente' && dias > 0 ? ' · lleva $dias días esperando dictamen' : ''}',
                style: TextStyle(
                    fontSize: 11,
                    color: dias >= 15 && estado == 'Pendiente'
                        ? const Color(0xFFC62828)
                        : Colors.black45,
                    fontWeight: dias >= 15 && estado == 'Pendiente'
                        ? FontWeight.w700
                        : FontWeight.w400)),
            if ('${c['comentarios'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: const Color(0xFFF7F5F0),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Dictamen: ${c['comentarios']}',
                    style: const TextStyle(fontSize: 11.5, height: 1.35)),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (archivo.startsWith('http'))
                  _mini('Ver archivo', Icons.attach_file,
                      () => Helpers.abrirUrlExterna(archivo, context)),
                _mini('Ficha completa', Icons.info_outline,
                    () => _verFicha(c)),
                if (estado != 'Pendiente')
                  _mini(
                      '${c['notificado'] ?? ''}'.isNotEmpty
                          ? 'Notificado'
                          : 'Sin notificar',
                      '${c['notificado'] ?? ''}'.isNotEmpty
                          ? Icons.mark_email_read_outlined
                          : Icons.mail_outline,
                      () => _dictaminar(c),
                      color: '${c['notificado'] ?? ''}'.isNotEmpty
                          ? const Color(0xFF1E8E3E)
                          : cessumGold),
                if (estado == 'Pendiente' || estado == 'En dictamen')
                  _mini(
                      '${c['par1'] ?? ''}'.isEmpty
                          ? 'Enviar a dictaminar'
                          : 'Reenviar a pares',
                      Icons.send_outlined,
                      () => _enviarPares(c),
                      color: const Color(0xFF6A4FB0)),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact),
                  onPressed: ocupado ? null : () => _dictaminar(c),
                  icon: ocupado
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.gavel, size: 16),
                  label: Text(estado == 'Pendiente' ? 'Dictaminar' : 'Cambiar',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            if ('${c['par1'] ?? ''}'.isNotEmpty ||
                '${c['par2'] ?? ''}'.isNotEmpty) ...[
              const Divider(height: 18),
              _bloquePares(c),
            ],
            if (estado == 'Aceptado' || estado == 'Aceptado con cambios') ...[
              const Divider(height: 18),
              const Text('SEGUIMIENTO',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.black45)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _marca(c, 'pago', 'Pago', c['pagoVerificado']),
                  _marca(c, 'extenso', 'Extenso', c['extensoRecibido']),
                  _marca(c, 'semblanza', 'Semblanza', c['semblanzaRecibida']),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Estado del dictamen por pares: a quién se le mandó, desde cuándo, y qué
  /// devolvió cada uno. Los doce días son los que dura la etapa oficial de
  /// dictaminación (12 al 23 de octubre); pasados, se marca en rojo.
  Widget _bloquePares(Map<String, dynamic> c) {
    final p1 = '${c['par1'] ?? ''}';
    final p2 = '${c['par2'] ?? ''}';
    final dias = _n(c['diasConPares']);
    final tarde = dias > 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.groups_outlined, size: 15, color: Color(0xFF6A4FB0)),
            const SizedBox(width: 5),
            const Text('DICTAMEN POR PARES',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: Color(0xFF6A4FB0))),
            const Spacer(),
            if (dias > 0)
              Text('$dias día${dias == 1 ? '' : 's'} con los pares',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: tarde ? FontWeight.w800 : FontWeight.w500,
                      color: tarde
                          ? const Color(0xFFC62828)
                          : Colors.black45)),
          ],
        ),
        const SizedBox(height: 6),
        if (p1.isNotEmpty) _filaPar(c, '1', p1, c['dictamenPar1']),
        if (p2.isNotEmpty) _filaPar(c, '2', p2, c['dictamenPar2']),
      ],
    );
  }

  // (ago-9) La contribución se pasa por parámetro. La primera versión la
  // buscaba con firstWhere sobre la lista, y eso REVIENTA si no la encuentra
  // —por ejemplo con un filtro activo—: un fallo en tiempo de ejecución por
  // no pasar un dato que ya se tenía a la mano.
  Widget _filaPar(Map<String, dynamic> c, String par, String correo,
      dynamic dictamen) {
    final etiqueta = 'Par $par';
    final t = '${dictamen ?? ''}'.trim();
    final tiene = t.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(tiene ? Icons.check_circle : Icons.hourglass_empty,
                  size: 14,
                  color: tiene ? const Color(0xFF1E8E3E) : cessumGold),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$etiqueta · $correo',
                    style: const TextStyle(fontSize: 11.5)),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => _capturarDictamenPar(c, par, t),
                child: Text(tiene ? 'Editar' : 'Capturar',
                    style: const TextStyle(fontSize: 11.5)),
              ),
            ],
          ),
          if (tiene)
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(t,
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.35, color: Colors.black54)),
            ),
        ],
      ),
    );
  }

  /// Envía la contribución a uno o dos dictaminadores. El correo va CIEGO:
  /// sin nombre, correo ni institución del autor, como exigen las bases.
  Future<void> _enviarPares(Map<String, dynamic> c) async {
    final p1 = TextEditingController(text: '${c['par1'] ?? ''}');
    final p2 = TextEditingController(text: '${c['par2'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar a dictaminar', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['titulo']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                Text('${c['folio']} · ${c['linea']}',
                    style: const TextStyle(
                        fontSize: 11.5, color: Colors.black54)),
                const SizedBox(height: 12),
                TextField(
                  controller: p1,
                  decoration: const InputDecoration(
                      labelText: 'Correo del dictaminador 1 *',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: p2,
                  decoration: const InputDecoration(
                      labelText: 'Correo del dictaminador 2 (opcional)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFDE7E7),
                      border: Border.all(color: const Color(0xFFE0A6A6)),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                      '⚠ Se le enviará un correo a cada dictaminador con el '
                      'enlace al trabajo.\n\n'
                      'El correo va CIEGO: no lleva el nombre, el correo ni la '
                      'institución del autor, porque las bases establecen '
                      'dictamen por pares ciegos. La contribución quedará '
                      '"En dictamen".',
                      style: TextStyle(fontSize: 11.5, height: 1.4)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A4FB0),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    final c1 = p1.text.trim();
    final c2 = p2.text.trim();
    p1.dispose();
    p2.dispose();
    if (ok != true) return;
    if (!c1.contains('@')) {
      _aviso('Escribe al menos un correo válido.');
      return;
    }
    setState(() => _trabajando = '${c['folio']}');
    try {
      final d = await _get({
        'accion': 'coinedu_enviar_pares',
        'folio': '${c['folio']}',
        'pares': c2.contains('@') ? '$c1,$c2' : c1,
        'actor': _correo,
      });
      _aviso(d['ok'] == true
          ? '${d['aviso'] ?? 'Enviado.'}'
          : '${d['error'] ?? 'No se pudo enviar'}');
      if (d['ok'] == true) await _cargar();
    } catch (e) {
      _aviso('$e');
    }
    if (mounted) setState(() => _trabajando = null);
  }

  /// Captura lo que devolvió un par. No resuelve el dictamen final: eso lo
  /// decide el comité viendo ambos.
  Future<void> _capturarDictamenPar(
      Map<String, dynamic> c, String par, String actual) async {
    final txt = TextEditingController(text: actual);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dictamen del par $par',
            style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: txt,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Lo que devolvió el dictaminador',
              helperText:
                  'Se guarda para el expediente. El resultado final lo decides '
                  'tú al dictaminar, viendo los dos.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final t = txt.text.trim();
    txt.dispose();
    if (ok != true || t.isEmpty) return;
    try {
      final d = await _get({
        'accion': 'coinedu_dictamen_par',
        'folio': '${c['folio']}',
        'par': par,
        'texto': t,
        'actor': _correo,
      });
      if (d['ok'] != true) {
        _aviso('${d['error'] ?? 'No se pudo guardar'}');
        return;
      }
      await _cargar();
    } catch (e) {
      _aviso('$e');
    }
  }

  Widget _mini(String t, IconData i, VoidCallback onTap, {Color? color}) {
    final c = color ?? cessumRed;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c.withValues(alpha: 0.5)),
          visualDensity: VisualDensity.compact),
      onPressed: onTap,
      icon: Icon(i, size: 15),
      label: Text(t, style: const TextStyle(fontSize: 11.5)),
    );
  }

  /// Palomea pago, extenso o semblanza. Un toque alterna: es seguimiento
  /// interno, no un dictamen, así que no necesita confirmación ni avisa a nadie.
  Widget _marca(Map<String, dynamic> c, String campo, String etiqueta,
      dynamic valor) {
    final hecho = '${valor ?? ''}'.toUpperCase() == 'SI';
    return InkWell(
      onTap: () => _marcarSeguimiento(c, campo, !hecho),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: hecho
              ? const Color(0xFF1E8E3E).withValues(alpha: 0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: hecho ? const Color(0xFF1E8E3E) : Colors.black26),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hecho ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: hecho ? const Color(0xFF1E8E3E) : Colors.black38),
            const SizedBox(width: 5),
            Text(etiqueta,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: hecho ? FontWeight.w700 : FontWeight.w500,
                    color: hecho
                        ? const Color(0xFF1B5E20)
                        : Colors.black54)),
          ],
        ),
      ),
    );
  }

  Future<void> _marcarSeguimiento(
      Map<String, dynamic> c, String campo, bool valor) async {
    try {
      final d = await _get({
        'accion': 'coinedu_marcar',
        'folio': '${c['folio']}',
        'campo': campo,
        'valor': valor ? 'SI' : 'NO',
      });
      if (d['ok'] != true) {
        _aviso('${d['error'] ?? 'No se pudo'}');
        return;
      }
      _cargar();
    } catch (e) {
      _aviso('$e');
    }
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _verFicha(Map<String, dynamic> c) async {
    final coautores = (c['coautores'] as List? ?? []).cast<dynamic>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${c['folio']} · ${c['tipo']}',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['titulo']}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.3)),
                const SizedBox(height: 10),
                _dato('Autor principal', c['autores']),
                if (coautores.isNotEmpty)
                  _dato('Coautores', coautores.join(' · ')),
                _dato('Institución', c['institucion']),
                _dato('Correo', c['correo']),
                _dato('Correo alterno', c['correoAlterno']),
                _dato('ORCID', c['orcid']),
                _dato('Línea temática', c['linea']),
                _dato('Clave del comité', c['claveComite']),
                _dato('Recibida', c['fecha']),
                _dato('Originalidad', c['originalidad']),
                _dato('Derechos de autor', c['derechos']),
                const Divider(height: 20),
                _dato('Estado', c['estado']),
                _dato('Dictaminó', c['dictaminador']),
                _dato('Fecha de dictamen', c['fechaDictamen']),
                _dato('Notificado al autor', c['notificado']),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _dato(String k, dynamic v) {
    final t = '${v ?? ''}'.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(k,
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          ),
          Expanded(
            child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.3)),
          ),
        ],
      ),
    );
  }

  Future<void> _dictaminar(Map<String, dynamic> c) async {
    var decision = '${c['estado']}' == 'Pendiente' ? 'Aceptado' : '${c['estado']}';
    final coment =
        TextEditingController(text: '${c['comentarios'] ?? ''}');
    var avisar = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Dictamen', style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c['titulo']}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  Text('${c['autores']} · ${c['folio']}',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: decision,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Resultado del dictamen',
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: _kDictamenes
                        .map((e) => DropdownMenuItem(
                            value: e,
                            child: Text(e,
                                style: const TextStyle(fontSize: 13))))
                        .toList(),
                    onChanged: (v) => setSt(() => decision = v ?? decision),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: coment,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: decision == 'Rechazado' ||
                              decision == 'Aceptado con cambios'
                          ? 'Observaciones del dictamen *'
                          : 'Observaciones (opcional)',
                      helperText:
                          'Este texto es el que recibe el autor. Sé específico.',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: avisar,
                    onChanged: (v) => setSt(() => avisar = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Enviarle el dictamen al autor por correo',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: avisar
                            ? const Color(0xFFFDE7E7)
                            : const Color(0xFFF4F2ED),
                        border: Border.all(
                            color: avisar
                                ? const Color(0xFFE0A6A6)
                                : Colors.black12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        avisar
                            ? '⚠ Se le enviará UN correo a ${c['correo']} con '
                                'el resultado y tus observaciones. Un dictamen '
                                'enviado no se puede deshacer.'
                            : 'El dictamen se guarda sin avisarle a nadie. '
                                'Puedes notificarlo después, cuando el comité '
                                'lo tenga listo.',
                        style: const TextStyle(fontSize: 11.5, height: 1.35)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(avisar ? 'Guardar y notificar' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
    final texto = coment.text.trim();
    coment.dispose();
    if (ok != true) return;

    setState(() => _trabajando = '${c['folio']}');
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'coinedu_dictaminar',
                'folio': c['folio'],
                'decision': decision,
                'comentarios': texto,
                'actor': _correo,
                if (avisar) 'avisar': '1',
              }))
          .timeout(const Duration(seconds: 90));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        _aviso('${d['error'] ?? 'No se pudo guardar'}');
      } else {
        _aviso('${d['aviso'] ?? 'Dictamen guardado.'}');
        await _cargar();
      }
    } catch (e) {
      _aviso('$e');
    }
    if (mounted) setState(() => _trabajando = null);
  }

  /// Acciones que aplican a todo el congreso, no a una contribución: por eso
  /// van en el menú del encabezado y no en las tarjetas.
  Future<void> _menuAcciones() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('ACCIONES DEL CONGRESO',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: cessumRed)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.alarm, color: Color(0xFF6A4FB0)),
              title: const Text('Recordar a los pares pendientes',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Escribe solo a quien lleva días sin devolver su dictamen',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () {
                Navigator.pop(ctx);
                _recordarPares();
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_view, color: Color(0xFF1E7B34)),
              title: const Text('Exportar el listado a Excel',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Para repartir dictámenes o armar el programa fuera de la app',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () {
                Navigator.pop(ctx);
                _exportar();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Manda recordatorio a los pares que no han devuelto. Primero muestra a
  /// quién le llegaría: son correos a personas externas a la institución y
  /// eso no se dispara a ciegas.
  Future<void> _recordarPares() async {
    setState(() => _trabajando = 'recordar');
    Map<String, dynamic> previa = {};
    try {
      previa = await _get({
        'accion': 'coinedu_recordar_pares',
        'prueba': '1',
        'actor': _correo,
      });
    } catch (e) {
      _aviso('$e');
      if (mounted) setState(() => _trabajando = null);
      return;
    }
    if (mounted) setState(() => _trabajando = null);
    if (previa['ok'] != true) {
      _aviso('${previa['error'] ?? 'No se pudo consultar'}');
      return;
    }
    final lista = (previa['lista'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!mounted) return;
    if (lista.isEmpty) {
      _aviso('Ningún par lleva más de 7 días sin devolver su dictamen.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recordar dictamen', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Se le escribirá a ${lista.length} dictaminador(es):',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final x in lista)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                        '· ${x['correo']} — ${x['folio']}, '
                        'lleva ${_n(x['dias'])} días',
                        style: const TextStyle(fontSize: 12, height: 1.3)),
                  ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFDE7E7),
                      border: Border.all(color: const Color(0xFFE0A6A6)),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                      '⚠ Son correos a personas externas a la institución. El '
                      'mensaje sigue siendo ciego: no menciona al autor.',
                      style: TextStyle(fontSize: 11.5, height: 1.35)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A4FB0),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar recordatorios'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _trabajando = 'recordar');
    try {
      final d = await _get({
        'accion': 'coinedu_recordar_pares',
        'actor': _correo,
      });
      _aviso(d['ok'] == true
          ? 'Enviados ${_n(d['enviados'])} recordatorio(s).'
          : '${d['error'] ?? 'No se pudo'}');
    } catch (e) {
      _aviso('$e');
    }
    if (mounted) setState(() => _trabajando = null);
  }

  Future<void> _exportar() async {
    setState(() => _trabajando = 'excel');
    try {
      final d = await _get({'accion': 'coinedu_excel'});
      if (d['ok'] != true) {
        _aviso('${d['error'] ?? 'No se pudo exportar'}');
      } else {
        final url = '${d['xlsxUrl'] ?? ''}';
        if (url.startsWith('http') && mounted) {
          Helpers.abrirUrlExterna(url, context);
        }
        _aviso('Exportadas ${_n(d['total'])} contribuciones.');
      }
    } catch (e) {
      _aviso('$e');
    }
    if (mounted) setState(() => _trabajando = null);
  }

  Future<void> _verCalendario() async {
    final etapas = (_resumen['etapas'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cal = Map<String, dynamic>.from(_resumen['calendario'] ?? {});
    final actual = cal['actual'] == null
        ? ''
        : '${Map<String, dynamic>.from(cal['actual'] as Map)['etapa']}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Calendario COINEDU 2026',
            style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in etapas)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: '${e['etapa']}' == actual
                          ? cessumGold.withValues(alpha: 0.12)
                          : const Color(0xFFF7F5F0),
                      borderRadius: BorderRadius.circular(8),
                      border: '${e['etapa']}' == actual
                          ? Border.all(color: cessumGold)
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e['etapa']}',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: '${e['etapa']}' == actual
                                    ? FontWeight.w800
                                    : FontWeight.w600)),
                        Text(
                            '${e['inicio']}'
                            '${e['fin'] != e['inicio'] ? ' → ${e['fin']}' : ''}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }
}

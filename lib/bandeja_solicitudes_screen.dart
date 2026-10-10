// bandeja_solicitudes_screen.dart · CESSUM · (24-sep-2026)
//
// BANDEJA ÚNICA DE SOLICITUDES (fase 1 de los centros inteligentes).
// Reúne en una sola lista lo que hoy vive en más de doce pantallas:
// justificaciones, correcciones de datos, cambios de horario y de programa,
// bajas, constancias, no adeudo, reingresos, recursamientos, mesa de ayuda,
// titulación, trámites, tesis y becas. Cada solicitud lleva un semáforo de
// tiempo de 72 HORAS HÁBILES (5-oct-2026: el mismo plazo para todos los trámites; antes 3/7 días naturales), se abre en la pantalla que
// ya la atiende, y tiene un borrador de respuesta con IA que el
// administrador revisa antes de enviar.
// Base: GET bandeja_solicitudes y POST bandeja_ia_respuesta (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

class BandejaSolicitudesScreen extends StatefulWidget {
  const BandejaSolicitudesScreen({super.key});

  @override
  State<BandejaSolicitudesScreen> createState() => _BandejaSolicitudesScreenState();
}

class _BandejaSolicitudesScreenState extends State<BandejaSolicitudesScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  String _generado = '';
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _fuentes = [];
  String _tipo = '';
  // (5-oct-2026) 72 h hábiles: resumen, lo que espera al solicitante y lo que no se pudo leer.
  Map<String, dynamic> _res = {};
  bool _verEspera = false;
  List<String> _noLeidas = [];
  Map<String, dynamic> _desconocidos = {};
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
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=bandeja_solicitudes'))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar la bandeja.');
      if (!mounted) return;
      setState(() {
        _items = ((d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _fuentes = ((d['fuentes'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _generado = '${d['generado'] ?? ''}';
        _res = d['resumen'] is Map ? Map<String, dynamic>.from(d['resumen'] as Map) : {};
        _noLeidas = ((d['hojasNoLeidas'] as List?) ?? []).map((e) => '$e').toList();
        _desconocidos = d['estadosNoReconocidos'] is Map ? Map<String, dynamic>.from(d['estadosNoReconocidos'] as Map) : {};
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

  String _norm(String s) {
    s = s.toLowerCase();
    const a = 'áàäâéèëêíìïîóòöôúùüûñ';
    const b = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _norm(_busca.text);
    return _items.where((it) {
      // Lo que espera al solicitante solo se ve con su filtro.
      if ((it['espera'] == true) != _verEspera) return false;
      if (_tipo.isNotEmpty && '${it['tipo']}' != _tipo) return false;
      if (q.isEmpty) return true;
      return _norm('${it['nombre']} ${it['matricula']} ${it['detalle']} ${it['tipoTitulo']}').contains(q);
    }).toList();
  }

  /// (5-oct-2026) Semáforo por el plazo de 72 horas hábiles.
  Color _semaforo(Map<String, dynamic> it) {
    switch ('${it['nivel'] ?? ''}') {
      case 'vencido':
      case 'critico':
        return cessumRed;
      case 'alerta':
        return cessumGold;
      case 'ok':
        return _verde;
      default:
        return cessumMuted(context);
    }
  }

  String _textoPlazo(Map<String, dynamic> it) {
    final nv = '${it['nivel'] ?? ''}';
    if (nv == 'espera') return 'en espera';
    if (nv == 'vencido') {
      final h = (it['horasVencido'] as num?)?.toInt() ?? 0;
      return h > 0 ? 'vencido hace $h h' : 'vencido';
    }
    return 'quedan ${(it['horasRestantes'] as num?)?.toInt() ?? 0} h';
  }

  Future<void> _borrador(Map<String, dynamic> it) async {
    final decision = TextEditingController();
    String? texto;
    var pidiendo = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Respuesta · ${it['tipoTitulo'] ?? ''}', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${it['nombre'] ?? ''}${'${it['matricula'] ?? ''}'.isNotEmpty ? ' · ${it['matricula']}' : ''}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(ctx))),
                if ('${it['detalle'] ?? ''}'.isNotEmpty)
                  Text('${it['detalle']}', style: TextStyle(fontSize: 12.5, color: cessumMuted(ctx))),
                const SizedBox(height: 10),
                TextField(
                  controller: decision,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Decisión o indicación (opcional)',
                    hintText: 'Ej. Aprobada; pasar a Control Escolar por su constancia el lunes.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: pidiendo
                        ? null
                        : () async {
                            setS(() => pidiendo = true);
                            try {
                              final r = await http
                                  .post(Uri.parse(guardianUrl),
                                      headers: {'Content-Type': 'text/plain;charset=utf-8'},
                                      body: jsonEncode({'accion': 'bandeja_ia_respuesta', 'item': it, 'decision': decision.text.trim()}))
                                  .timeout(const Duration(seconds: 90));
                              final d = jsonDecode(r.body) as Map<String, dynamic>;
                              if (d['ok'] == true) {
                                setS(() => texto = '${d['texto'] ?? ''}');
                              } else if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${d['error'] ?? 'No se pudo redactar.'}')));
                              }
                            } catch (_) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('No se pudo conectar para redactar.')));
                              }
                            }
                            setS(() => pidiendo = false);
                          },
                    icon: pidiendo
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: Text(pidiendo ? 'Redactando…' : (texto == null ? 'Redactar con IA' : 'Redactar de nuevo')),
                  ),
                ),
                if (texto != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cessumGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
                    ),
                    child: SelectableText(texto!, style: TextStyle(fontSize: 13, height: 1.45, color: cessumInk(ctx))),
                  ),
                  const SizedBox(height: 6),
                  Text('Revise el texto antes de enviarlo desde la pantalla de la solicitud.',
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
                ],
              ]),
            ),
          ),
          actions: [
            if (texto != null)
              TextButton(
                onPressed: () => Helpers.copiarAlPortapapeles(ctx, texto!, 'Respuesta'),
                child: const Text('Copiar'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                Navigator.pop(ctx);
                abrirPantallaCentro(context, '${it['pantalla'] ?? ''}');
              },
              child: const Text('Abrir la solicitud'),
            ),
          ],
        ),
      ),
    );
    decision.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vis = _visibles;
    final vencidas = (_res['vencidos'] as num?)?.toInt() ?? _items.where((i) => i['nivel'] == 'vencido').length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Bandeja de solicitudes', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.inbox_outlined, size: 44, color: cessumFaint(context)),
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
                      _resumen(vencidas),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _busca,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre, matrícula o detalle…',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          suffixIcon: _busca.text.isEmpty
                              ? null
                              : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _busca.clear())),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _filtros(),
                      const SizedBox(height: 10),
                      if (vis.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text(_items.isEmpty ? 'No hay solicitudes pendientes.' : 'Nada coincide con el filtro.',
                                style: TextStyle(color: cessumMuted(context))),
                          ),
                        ),
                      for (final it in vis) _fila(it),
                      if (_noLeidas.isNotEmpty || _desconocidos.isNotEmpty) _avisoRegistro(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _resumen(int vencidas) {
    final total = _items.length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (vencidas > 0 ? cessumRed : cessumGold).withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Plazo para todos los trámites: 72 horas hábiles (lunes a viernes)',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: cessumMuted(context))),
        const SizedBox(height: 8),
        Wrap(spacing: 18, runSpacing: 10, children: [
          _cifra('${_res['abiertos'] ?? total}', 'pendientes', cessumInk(context)),
          _cifra('$vencidas', 'vencidos', vencidas > 0 ? cessumRed : _verde),
          _cifra('${_res['criticos'] ?? 0}', '12 h o menos', ((_res['criticos'] as num?) ?? 0) > 0 ? cessumRed : _verde),
          _cifra('${_res['enEspera'] ?? 0}', 'en espera del solicitante', cessumMuted(context)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
        const Spacer(),
        Text(_generado.isEmpty ? '' : 'Actualizado\n$_generado',
            textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
        ]),
      ]),
    );
  }

  Widget _cifra(String n, String t, Color c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: c, height: 1)),
        Text(t, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ]);

  Widget _filtros() {
    final tipos = _fuentes.where((f) => (f['pendientes'] as num? ?? 0) > 0).toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        ChoiceChip(
            label: Text('Todas (${_items.where((i) => i['espera'] != true).length})'),
            selected: _tipo.isEmpty && !_verEspera,
            onSelected: (_) => setState(() { _tipo = ''; _verEspera = false; })),
        const SizedBox(width: 6),
        ChoiceChip(
            label: Text('En espera del solicitante (${_res['enEspera'] ?? 0})'),
            selected: _verEspera,
            onSelected: (_) => setState(() { _verEspera = !_verEspera; _tipo = ''; })),
        for (final f in tipos) ...[
          const SizedBox(width: 6),
          ChoiceChip(
            label: Text('${f['titulo']} (${f['pendientes']})'),
            selected: _tipo == '${f['tipo']}',
            onSelected: (_) => setState(() => _tipo = _tipo == '${f['tipo']}' ? '' : '${f['tipo']}'),
          ),
        ],
      ]),
    );
  }

  Widget _fila(Map<String, dynamic> it) {
    final c = _semaforo(it);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.withValues(alpha: 0.4))),
      child: ListTile(
        onTap: () => abrirPantallaCentro(context, '${it['pantalla'] ?? ''}'),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(iconoCentro('${it['pantalla'] ?? it['tipo'] ?? ''}'), color: c, size: 20),
        ),
        title: Text('${it['nombre'] ?? ''}'.isEmpty ? '${it['tipoTitulo']}' : '${it['nombre']}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context))),
        subtitle: Text(
          [
            '${it['tipoTitulo'] ?? ''}',
            if ('${it['matricula'] ?? ''}'.isNotEmpty) '${it['matricula']}',
            if ('${it['detalle'] ?? ''}'.isNotEmpty) '${it['detalle']}',
            if ('${it['limite'] ?? ''}'.isNotEmpty && it['espera'] != true) 'límite ${it['limite']}',
            if ('${it['area'] ?? ''}'.isNotEmpty) '${it['area']}',
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: cessumMuted(context)),
        ),
        trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(_textoPlazo(it), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _borrador(it),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.auto_awesome, size: 18, color: cessumGold),
            ),
          ),
        ]),
      ),
    );
  }

  /// (5-oct-2026) Para que ningún trámite se pierda: hojas que no se pudieron leer y estados que el sistema no reconoce.
  Widget _avisoRegistro() => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Revisión del registro', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          if (_noLeidas.isNotEmpty) Text('No se pudieron leer: ${_noLeidas.join(' · ')}', style: const TextStyle(fontSize: 12, height: 1.4)),
          if (_desconocidos.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Estados que el sistema no reconoce (se muestran como pendientes para que no se pierdan):', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            for (final e in _desconocidos.entries) Text('· ${e.key}: ${e.value}', style: const TextStyle(fontSize: 12)),
          ],
        ]),
      );
}

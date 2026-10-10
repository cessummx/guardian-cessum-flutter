// ADMIN: Oficios foliados — emitir y dar seguimiento.
//
// (ago-24) Hasta ahora todo oficio institucional se redactaba en Word, fuera
// del sistema. Eso significa tres cosas: sin folio, sin verificación y sin
// rastro. Nadie podía decir cuántos oficios salieron este mes, a quién, ni
// quién los firmó — y si alguien preguntaba por uno, había que buscarlo en
// la computadora de quien lo escribió.
//
// Aquí el oficio nace dentro: toma un folio del consecutivo institucional
// (el mismo de constancias y actas, así que su QR verifica igual), se
// registra con destinatario, asunto, firmante y quién lo elaboró, y se
// descarga en Word para terminar de darle forma si hace falta.
//
// El cuerpo lo escribe quien emite. No se genera texto automático: un oficio
// dice lo que la institución decide decir, y adivinarlo sería peor que
// dejarlo en blanco.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class OficiosScreen extends StatefulWidget {
  const OficiosScreen({super.key});

  @override
  State<OficiosScreen> createState() => _OficiosScreenState();
}

class _OficiosScreenState extends State<OficiosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // --- formulario ---
  final _asunto = TextEditingController();
  final _destinatario = TextEditingController();
  final _cargo = TextEditingController();
  final _cuerpo = TextEditingController();
  final _despedida = TextEditingController(
      text: 'Sin otro particular, reciba un cordial saludo.');
  final _ccp = TextEditingController();
  String _firmante = 'rector';
  bool _firmar = true;
  bool _emitiendo = false;

  // --- seguimiento ---
  bool _cargando = false;
  String _error = '';
  List<Map<String, dynamic>> _oficios = [];
  List<Map<String, dynamic>> _porEstado = [];
  final _q = TextEditingController();

  static const _estados = [
    'Emitido',
    'Entregado',
    'Esperando respuesta',
    'Respondido',
    'Cancelado',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _cargarLista();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _asunto,
      _destinatario,
      _cargo,
      _cuerpo,
      _despedida,
      _ccp,
      _q
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 4)));
  }

  Future<void> _cargarLista() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'oficios_listar',
        if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
      });
      final r = await http.get(u).timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _oficios = ((d['oficios'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _porEstado = ((d['porEstado'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  Future<void> _emitir() async {
    if (_asunto.text.trim().isEmpty ||
        _destinatario.text.trim().isEmpty ||
        _cuerpo.text.trim().isEmpty) {
      _aviso('Faltan asunto, destinatario o el sentido del oficio.');
      return;
    }
    // Un folio consumido no se devuelve: se confirma antes de gastarlo.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emitir oficio', style: TextStyle(fontSize: 17)),
        content: Text(
            'Se tomará un folio del consecutivo institucional y quedará '
            'registrado a nombre de ${_destinatario.text.trim()}.\n\n'
            'El folio se consume aunque después no uses el documento, así que '
            'no se emite "de prueba".',
            style: const TextStyle(fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Emitir y foliar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _emitiendo = true);
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'oficio_generar',
                'asunto': _asunto.text.trim(),
                'destinatario': _destinatario.text.trim(),
                'cargo': _cargo.text.trim(),
                'cuerpo': _cuerpo.text.trim(),
                'despedida': _despedida.text.trim(),
                'ccp': _ccp.text.trim(),
                'firmante': _firmante,
                'firmar': _firmar ? '1' : '0',
                'actor': correo ?? 'Administración',
              }))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() => _emitiendo = false);
      if (d['ok'] != true) {
        _aviso(d['error']?.toString() ?? 'No se pudo emitir.');
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Oficio emitido', style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${d['folio']}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${d['asunto']}\nPara: ${d['destinatario']}\n'
                  'Firma: ${d['firmante']}',
                  style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 10),
              const Text(
                  'Quedó registrado y su código QR ya verifica. Está en '
                  'seguimiento con estado «Emitido».',
                  style: TextStyle(fontSize: 12, height: 1.35)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
            OutlinedButton.icon(
              onPressed: () {
                launchUrl(Uri.parse((d['docUrl'] ?? '').toString()),
                    webOnlyWindowName: '_blank');
              },
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Abrir en Drive'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                launchUrl(Uri.parse((d['docxUrl'] ?? '').toString()),
                    webOnlyWindowName: '_blank');
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.download, size: 17),
              label: const Text('Descargar Word'),
            ),
          ],
        ),
      );
      _asunto.clear();
      _destinatario.clear();
      _cargo.clear();
      _cuerpo.clear();
      _ccp.clear();
      await _cargarLista();
      _tabs.animateTo(1);
    } catch (e) {
      setState(() => _emitiendo = false);
      _aviso('Error de conexión: $e');
    }
  }

  Future<void> _cambiarEstado(Map<String, dynamic> o) async {
    var estado = (o['estado'] ?? 'Emitido').toString();
    final notas = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setL) => AlertDialog(
          title: Text('${o['folio']}', style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${o['asunto']}',
                  style: const TextStyle(fontSize: 13, height: 1.35)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _estados.contains(estado) ? estado : 'Emitido',
                decoration: const InputDecoration(
                    labelText: 'Estado', border: OutlineInputBorder(), isDense: true),
                items: [
                  for (final e in _estados)
                    DropdownMenuItem(value: e, child: Text(e)),
                ],
                onChanged: (v) => setL(() => estado = v ?? estado),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notas,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota de seguimiento (opcional)',
                  helperText: 'Se agrega con fecha y quién la escribió.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
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
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http.post(Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode({
            'accion': 'oficio_estado',
            'fila': o['fila'],
            'estado': estado,
            'notas': notas.text.trim(),
            'actor': correo ?? 'Administración',
          })).timeout(const Duration(seconds: 40));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        _aviso(d['error']?.toString() ?? 'No se pudo guardar.');
        return;
      }
      await _cargarLista();
    } catch (e) {
      _aviso('Error de conexión: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Oficios foliados'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Nuevo oficio'),
            Tab(text: 'Seguimiento'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_formulario(), _seguimiento()],
      ),
    );
  }

  Widget _campo(TextEditingController c, String label,
      {String? ayuda, int lineas = 1, bool requerido = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: lineas,
        decoration: InputDecoration(
          labelText: requerido ? '$label *' : label,
          helperText: ayuda,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _formulario() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: cessumGold, width: 3)),
          ),
          child: const Text(
              'El oficio sale con membrete, folio del consecutivo institucional '
              'y código QR de verificación. Queda registrado y se descarga en '
              'Word para terminar de darle forma si hace falta.',
              style: TextStyle(fontSize: 12.5, height: 1.4)),
        ),
        _campo(_asunto, 'Asunto', requerido: true,
            ayuda: 'Una línea: de qué trata el oficio.'),
        _campo(_destinatario, 'Destinatario', requerido: true,
            ayuda: 'Nombre completo o nombre de la dependencia.'),
        _campo(_cargo, 'Cargo o dependencia del destinatario'),
        _campo(_cuerpo, 'Sentido del oficio', lineas: 10, requerido: true,
            ayuda: 'Qué se comunica, solicita o informa. Escríbelo como quieres '
                'que aparezca: los saltos de línea se respetan como párrafos. '
                'Esto no se genera solo — un oficio dice lo que la institución '
                'decide decir.'),
        _campo(_despedida, 'Despedida'),
        _campo(_ccp, 'c.c.p. (opcional)',
            ayuda: 'A quién se envía copia.'),
        DropdownButtonFormField<String>(
          initialValue: _firmante,
          decoration: const InputDecoration(
            labelText: 'Quién firma',
            helperText:
                'Poner al Rector en un oficio que firmó Vicerrectoría no es un '
                'detalle de formato.',
            helperMaxLines: 2,
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'rector', child: Text('Rector')),
            DropdownMenuItem(
                value: 'vicerrector', child: Text('Vicerrector Académico')),
            DropdownMenuItem(
                value: 'directora', child: Text('Directora Unidad Navojoa')),
          ],
          onChanged: (v) => setState(() => _firmante = v ?? 'rector'),
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          value: _firmar,
          onChanged: (v) => setState(() => _firmar = v ?? true),
          activeColor: cessumRed,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Incluir firma y sello',
              style: TextStyle(fontSize: 13.5)),
          subtitle: const Text(
              'Sin marcar, deja la línea en blanco para firmar a mano.',
              style: TextStyle(fontSize: 11.5)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _emitiendo ? null : _emitir,
            icon: const Icon(Icons.article_outlined, size: 18),
            label: Text(_emitiendo ? 'Emitiendo…' : 'Emitir oficio foliado',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        if (_emitiendo)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _seguimiento() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(
            controller: _q,
            onSubmitted: (_) => _cargarLista(),
            decoration: InputDecoration(
              hintText: 'Buscar por folio, asunto, destinatario o firmante',
              prefixIcon: const Icon(Icons.search, color: cessumRed),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, size: 18),
                onPressed: _cargarLista,
              ),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),
        ),
        if (_porEstado.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final e in _porEstado)
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: Chip(
                      label: Text('${e['estado']} · ${e['cuantos']}',
                          style: const TextStyle(fontSize: 12)),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator(color: cessumRed))
              : _error.isNotEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No se pudo cargar: $_error',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cessumMuted(context))),
                      ),
                    )
                  : _oficios.isEmpty
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Text(
                                'Todavía no se ha emitido ningún oficio desde '
                                'el sistema.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cessumMuted(context))),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _cargarLista,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                            itemCount: _oficios.length,
                            itemBuilder: (_, i) => _tarjeta(_oficios[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Color _colorEstado(String e) {
    final s = e.toLowerCase();
    if (s.contains('respond')) return const Color(0xFF1E8E3E);
    if (s.contains('entreg')) return const Color(0xFF1565C0);
    if (s.contains('esper')) return const Color(0xFFB07D12);
    if (s.contains('cancel')) return Colors.grey;
    return cessumRed;
  }

  Widget _tarjeta(Map<String, dynamic> o) {
    final estado = (o['estado'] ?? 'Emitido').toString();
    final c = _colorEstado(estado);
    final enlace = (o['enlace'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${o['folio']}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(estado,
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${o['asunto']}',
              style: const TextStyle(fontSize: 13, height: 1.3)),
          const SizedBox(height: 3),
          Text(
              'Para: ${o['destinatario']}'
              '${(o['cargo'] ?? '').toString().isNotEmpty ? ' · ${o['cargo']}' : ''}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          Text('Firma: ${o['firmante']} · ${o['fecha']}',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if ((o['notas'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text((o['notas']).toString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, height: 1.35, color: cessumMuted(context))),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (enlace.startsWith('http'))
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(enlace),
                      webOnlyWindowName: '_blank'),
                  style: TextButton.styleFrom(foregroundColor: cessumGold),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Abrir', style: TextStyle(fontSize: 12.5)),
                ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _cambiarEstado(o),
                icon: const Icon(Icons.update, size: 16),
                label: const Text('Seguimiento',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

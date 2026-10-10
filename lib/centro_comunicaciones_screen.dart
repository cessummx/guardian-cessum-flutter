// centro_comunicaciones_screen.dart · CESSUM · (24-sep-2026)
//
// CENTRO DE COMUNICACIONES · fase 2 de los centros inteligentes.
// Un solo redactor para escribir a alumnos o docentes con un constructor de
// audiencia (programa, generación, grupo, modalidad, solo en riesgo, solo
// con adeudo). Regla de la casa: ANTES de enviar se muestra cuántos y
// quiénes; el Guardián no envía nada sin confirmar=ENVIAR. Redacción con IA
// (ruta general texto_ia_mejorar) e historial de envíos.
// Base: GET comunicaciones_audiencia, POST comunicaciones_enviar,
// GET comunicaciones_historial (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

class CentroComunicacionesScreen extends StatefulWidget {
  /// (fase 4) Puede abrirse prellenado, p. ej. desde Cobranza: audiencia «solo con adeudo» y un borrador.
  final bool soloAdeudo;
  final String? asuntoInicial;
  final String? mensajeInicial;
  const CentroComunicacionesScreen({super.key, this.soloAdeudo = false, this.asuntoInicial, this.mensajeInicial});

  @override
  State<CentroComunicacionesScreen> createState() => _CentroComunicacionesScreenState();
}

class _CentroComunicacionesScreenState extends State<CentroComunicacionesScreen> with SingleTickerProviderStateMixin {
  static const Color _verde = Color(0xFF1E8E3E);

  late final TabController _tab;
  String _destino = 'alumnos';
  String? _programa;
  final _generacion = TextEditingController();
  final _grupo = TextEditingController();
  String? _modalidad;
  bool _soloRiesgo = false;
  bool _soloAdeudo = false;

  final _asunto = TextEditingController();
  final _mensaje = TextEditingController();

  bool _calculando = false;
  int? _total;
  Map<String, dynamic> _porPrograma = {};
  List<Map<String, dynamic>> _muestra = [];

  bool _mejorando = false;
  String? _anterior;
  bool _enviando = false;

  bool _cargandoHist = false;
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _soloAdeudo = widget.soloAdeudo;
    if ((widget.asuntoInicial ?? '').isNotEmpty) _asunto.text = widget.asuntoInicial!;
    if ((widget.mensajeInicial ?? '').isNotEmpty) _mensaje.text = widget.mensajeInicial!;
    _tab.addListener(() {
      if (_tab.index == 1 && _historial.isEmpty && !_cargandoHist) _cargarHistorial();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _generacion.dispose();
    _grupo.dispose();
    _asunto.dispose();
    _mensaje.dispose();
    super.dispose();
  }

  Map<String, String> _filtros() => {
        'destino': _destino,
        if (_destino == 'alumnos') ...{
          if ((_programa ?? '').isNotEmpty) 'programa': _programa!,
          if (_generacion.text.trim().isNotEmpty) 'generacion': _generacion.text.trim(),
          if (_grupo.text.trim().isNotEmpty) 'grupo': _grupo.text.trim(),
          if ((_modalidad ?? '').isNotEmpty) 'modalidad': _modalidad!,
          if (_soloRiesgo) 'riesgo': '1',
          if (_soloAdeudo) 'adeudo': '1',
        },
      };

  void _invalidar() => setState(() {
        _total = null;
        _muestra = [];
        _porPrograma = {};
      });

  Future<void> _calcular() async {
    setState(() => _calculando = true);
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'comunicaciones_audiencia', ..._filtros()}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo calcular la audiencia.');
      if (!mounted) return;
      setState(() {
        _total = (d['total'] as num?)?.toInt() ?? 0;
        _porPrograma = Map<String, dynamic>.from((d['porPrograma'] as Map?) ?? {});
        _muestra = ((d['muestra'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _calculando = false);
  }

  Future<void> _mejorar() async {
    if (_mensaje.text.trim().length < 5) return;
    setState(() => _mejorando = true);
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'texto_ia_mejorar',
                'texto': _mensaje.text.trim(),
                'proposito': _destino == 'docentes' ? 'comunicado de la administración a los docentes' : 'comunicado de la institución a los alumnos',
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final nuevo = '${d['texto'] ?? ''}'.trim();
      if (d['ok'] == true && nuevo.isNotEmpty) {
        setState(() {
          _anterior = _mensaje.text;
          _mensaje.text = nuevo;
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${d['error'] ?? 'No se pudo mejorar la redacción.'}')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo conectar para mejorar la redacción.')));
      }
    }
    if (mounted) setState(() => _mejorando = false);
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 300));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _enviar() async {
    final asunto = _asunto.text.trim(), mensaje = _mensaje.text.trim();
    if (asunto.isEmpty || mensaje.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escriba el asunto y el mensaje.')));
      return;
    }
    setState(() => _enviando = true);
    Map<String, dynamic> previa;
    try {
      // 1) VISTA PREVIA: el Guardián no envía nada sin confirmar=ENVIAR.
      previa = await _post({'accion': 'comunicaciones_enviar', 'asunto': asunto, 'mensaje': mensaje, ..._filtros()});
      if (previa['ok'] != true) throw Exception(previa['error'] ?? 'No se pudo preparar el envío.');
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
      return;
    }
    if (!mounted) return;
    final total = (previa['total'] as num?)?.toInt() ?? 0;
    final muestra = ((previa['muestra'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (total == 0) {
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La audiencia está vacía: no hay a quién enviar.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enviar a $total destinatario(s)'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Asunto: $asunto', style: TextStyle(fontWeight: FontWeight.w700, color: cessumInk(ctx))),
              const SizedBox(height: 6),
              Text('Cada persona recibirá UN correo, de inmediato. Le llegaría a:',
                  style: TextStyle(fontSize: 13, color: cessumMuted(ctx))),
              const SizedBox(height: 8),
              for (final m in muestra.take(40))
                Text('• ${m['nombre']} · ${m['correo']}', style: TextStyle(fontSize: 12.5, color: cessumInk(ctx))),
              if (total > 40)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('… y ${total - 40} más.', style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
                ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Enviar a $total'),
          ),
        ],
      ),
    );
    if (ok != true) {
      if (mounted) setState(() => _enviando = false);
      return;
    }
    try {
      final res = await _post({'accion': 'comunicaciones_enviar', 'asunto': asunto, 'mensaje': mensaje, 'confirmar': 'ENVIAR', ..._filtros()});
      if (res['ok'] != true) throw Exception(res['error'] ?? 'No se pudo enviar.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _verde,
          content: Text('Enviado a ${res['enviados']} de ${res['total']}${(res['errores'] as num? ?? 0) > 0 ? ' · ${res['errores']} con error' : ''}.')));
      setState(() {
        _asunto.clear();
        _mensaje.clear();
        _anterior = null;
        _historial = [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _enviando = false);
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHist = true);
    try {
      final r = await http.get(Uri.parse('$guardianUrl?accion=comunicaciones_historial')).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() => _historial = ((d['envios'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
    if (mounted) setState(() => _cargandoHist = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Centro de comunicaciones', style: TextStyle(fontWeight: FontWeight.w800)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [Tab(text: 'Redactar y enviar'), Tab(text: 'Historial')],
        ),
      ),
      body: TabBarView(controller: _tab, children: [_redactor(), _historialVista()]),
    );
  }

  Widget _redactor() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _seccion('1 · A QUIÉN'),
        Card(
          elevation: 0,
          color: Theme.of(context).cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).dividerColor)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'alumnos', label: Text('Alumnos'), icon: Icon(Icons.school_outlined)),
                  ButtonSegment(value: 'docentes', label: Text('Docentes'), icon: Icon(Icons.co_present_outlined)),
                ],
                selected: {_destino},
                onSelectionChanged: (s) {
                  setState(() => _destino = s.first);
                  _invalidar();
                },
              ),
              if (_destino == 'alumnos') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _programa,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Programa', border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todos los programas')),
                    ...programasAcademicos.map((p) => DropdownMenuItem<String?>(value: p.nombre, child: Text(p.nombre, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) {
                    setState(() => _programa = v);
                    _invalidar();
                  },
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _generacion,
                      onChanged: (_) => _invalidar(),
                      decoration: const InputDecoration(labelText: 'Generación', hintText: 'Ej. 26-2', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _grupo,
                      onChanged: (_) => _invalidar(),
                      decoration: const InputDecoration(labelText: 'Grupo', hintText: 'Ej. 1', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: _modalidad,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Modalidad', border: OutlineInputBorder(), isDense: true),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todas las modalidades')),
                    ...modalidadesEstudio.map((m) => DropdownMenuItem<String?>(value: m, child: Text(m))),
                  ],
                  onChanged: (v) {
                    setState(() => _modalidad = v);
                    _invalidar();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: cessumRed,
                  title: const Text('Solo alumnos en riesgo (medio o alto)', style: TextStyle(fontSize: 13)),
                  value: _soloRiesgo,
                  onChanged: (v) {
                    setState(() => _soloRiesgo = v);
                    _invalidar();
                  },
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: cessumRed,
                  title: const Text('Solo alumnos con adeudo', style: TextStyle(fontSize: 13)),
                  value: _soloAdeudo,
                  onChanged: (v) {
                    setState(() => _soloAdeudo = v);
                    _invalidar();
                  },
                ),
              ],
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                  onPressed: _calculando ? null : _calcular,
                  icon: _calculando
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.people_outline, size: 18),
                  label: Text(_calculando ? 'Calculando…' : 'Calcular alcance'),
                ),
                const SizedBox(width: 12),
                if (_total != null)
                  Expanded(
                    child: Text('$_total destinatario(s)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _total == 0 ? cessumRed : _verde)),
                  ),
              ]),
              if (_porPrograma.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final e in _porPrograma.entries)
                    Chip(label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 11.5)), visualDensity: VisualDensity.compact),
                ]),
              ],
              if (_muestra.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Primeros: ${_muestra.take(6).map((m) => m['nombre']).join(', ')}${_muestra.length > 6 ? '…' : ''}',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _seccion('2 · QUÉ DECIR'),
        TextField(
          controller: _asunto,
          decoration: InputDecoration(
            labelText: 'Asunto',
            border: const OutlineInputBorder(),
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).cardColor,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _mensaje,
          minLines: 6,
          maxLines: 14,
          maxLength: 2500,
          decoration: InputDecoration(
            labelText: 'Mensaje',
            hintText: 'Escríbalo como lo diría; con «Mejorar redacción con IA» queda en el tono de CESSUM sin cambiar lo que dice.',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
            filled: true,
            fillColor: Theme.of(context).cardColor,
          ),
        ),
        Wrap(alignment: WrapAlignment.end, spacing: 4, children: [
          if (_anterior != null)
            TextButton(
              onPressed: _mejorando
                  ? null
                  : () => setState(() {
                        _mensaje.text = _anterior!;
                        _anterior = null;
                      }),
              child: const Text('Deshacer'),
            ),
          TextButton.icon(
            onPressed: _mejorando ? null : _mejorar,
            icon: _mejorando
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, size: 16),
            label: Text(_mejorando ? 'Mejorando…' : 'Mejorar redacción con IA'),
          ),
        ]),
        const SizedBox(height: 16),
        _seccion('3 · ENVIAR'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
          ),
          child: Text(
            'Antes de enviar se le mostrará cuántas personas y quiénes recibirían el correo. Nada sale sin esa confirmación.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumInk(context)),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _enviando ? null : _enviar,
          icon: _enviando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_outlined),
          label: Text(_enviando ? 'Preparando…' : 'Revisar destinatarios y enviar'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _historialVista() {
    if (_cargandoHist) return const CessumSkeletonList();
    if (_historial.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.history, size: 44, color: cessumFaint(context)),
          const SizedBox(height: 8),
          Text('Todavía no hay envíos desde este centro.', style: TextStyle(color: cessumMuted(context))),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _cargarHistorial, child: const Text('Actualizar')),
        ]),
      );
    }
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargarHistorial,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final h in _historial)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              color: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
              child: ListTile(
                leading: Icon(Icons.mark_email_read_outlined, color: (h['errores'] as num? ?? 0) > 0 ? cessumGold : _verde),
                title: Text('${h['asunto'] ?? ''}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context))),
                subtitle: Text(
                  '${h['fecha']} · ${h['destino']}${'${h['filtros'] ?? ''}'.isNotEmpty ? ' · ${h['filtros']}' : ''}\n'
                  'Enviados ${h['enviados']} de ${h['destinatarios']}${(h['errores'] as num? ?? 0) > 0 ? ' · ${h['errores']} con error' : ''} · por ${h['por']}',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                ),
                isThreeLine: true,
                onTap: () => Helpers.copiarAlPortapapeles(context, '${h['asunto']}', 'Asunto'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
      );
}

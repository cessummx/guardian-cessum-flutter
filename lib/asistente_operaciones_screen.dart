// asistente_operaciones_screen.dart · CESSUM · (24-sep-2026)
//
// ASISTENTE DE OPERACIONES CON IA · fase 3 de los centros inteligentes.
// Se le pregunta en lenguaje natural («¿quién no ha capturado Didáctica?»,
// «¿cuántos alumnos hay en la 26-2 de Pedagogía?», «recuérdales»). El
// Guardián elige y ejecuta la consulta con datos reales, la IA responde con
// cifras y nombres, y si procede PROPONE una acción. Regla de la casa: el
// asistente nunca ejecuta solo. Toda acción pasa por «Ver a quiénes»
// (vista previa sin enviar) y una confirmación con la cifra exacta.
// Base: POST ops_ia_preguntar; acciones: recordatorio_captura_previa /
// recordatorio_captura_enviar y comunicaciones_enviar (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

class AsistenteOperacionesScreen extends StatefulWidget {
  const AsistenteOperacionesScreen({super.key});

  @override
  State<AsistenteOperacionesScreen> createState() => _AsistenteOperacionesScreenState();
}

class _Turno {
  final String rol; // 'admin' | 'asistente'
  final String texto;
  final Map<String, dynamic>? accion;
  final String consulta;
  _Turno(this.rol, this.texto, {this.accion, this.consulta = ''});
}

class _AsistenteOperacionesScreenState extends State<AsistenteOperacionesScreen> {
  static const Color _verde = Color(0xFF1E8E3E);
  static const _sugerencias = [
    '¿Qué es lo más urgente hoy?',
    '¿Quién no ha capturado calificaciones?',
    '¿Cuántas solicitudes llevan más de una semana?',
    '¿Qué grupos no tienen maestro?',
    '¿Cuántos alumnos hay en Pedagogía?',
    'Recuérdales a los docentes que capturen',
  ];

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turno> _turnos = [];
  bool _pensando = false;
  bool _ejecutando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int segundos = 180}) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
        .timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _preguntar([String? texto]) async {
    final q = (texto ?? _ctrl.text).trim();
    if (q.isEmpty || _pensando) return;
    _ctrl.clear();
    setState(() {
      _turnos.add(_Turno('admin', q));
      _pensando = true;
    });
    _bajar();
    try {
      final historial = _turnos.take(_turnos.length - 1).toList().reversed.take(6).toList().reversed
          .map((t) => {'rol': t.rol, 'texto': t.texto})
          .toList();
      final d = await _post({'accion': 'ops_ia_preguntar', 'pregunta': q, 'historial': historial});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo responder.');
      final acc = d['accionPropuesta'] is Map ? Map<String, dynamic>.from(d['accionPropuesta'] as Map) : null;
      setState(() => _turnos.add(_Turno('asistente', '${d['respuesta'] ?? ''}', accion: acc, consulta: '${d['consulta'] ?? ''}')));
    } catch (e) {
      setState(() => _turnos.add(_Turno('asistente', 'No pude responder: ${'$e'.replaceFirst('Exception: ', '')}')));
    }
    if (mounted) setState(() => _pensando = false);
    _bajar();
  }

  void _bajar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  // ---------- Acciones: siempre vista previa, luego confirmación ----------
  Future<void> _verYEjecutar(Map<String, dynamic> accion) async {
    final tipo = '${accion['tipo'] ?? ''}';
    final params = accion['params'] is Map ? Map<String, dynamic>.from(accion['params'] as Map) : <String, dynamic>{};
    setState(() => _ejecutando = true);
    try {
      List<String> lista = [];
      int total = 0;
      String descripcion = '${accion['descripcion'] ?? ''}';
      final correo = await SessionStore.realEmail() ?? '';
      if (tipo == 'recordatorio_captura') {
        final r = await http
            .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'recordatorio_captura_previa', 'correo': correo}))
            .timeout(const Duration(seconds: 120));
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo preparar la vista previa.');
        final docs = _primeraLista(d);
        lista = docs.map((x) => '${x['docente'] ?? x['nombre'] ?? ''} · ${x['correo'] ?? ''}'.trim()).toList();
        total = lista.length;
        descripcion = 'Recordatorio de captura: cada docente con captura pendiente recibirá UN correo.';
      } else if (tipo == 'comunicado') {
        final asunto = '${params['asunto'] ?? ''}'.trim();
        final mensaje = '${params['mensaje'] ?? ''}'.trim();
        if (asunto.isEmpty || mensaje.length < 10) throw Exception('El comunicado propuesto no tiene asunto o mensaje completos. Pídale al asistente que lo redacte.');
        final d = await _post({'accion': 'comunicaciones_enviar', ...params, 'asunto': asunto, 'mensaje': mensaje});
        if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo preparar la vista previa.');
        total = (d['total'] as num?)?.toInt() ?? 0;
        lista = _primeraLista(d).map((x) => '${x['nombre'] ?? ''} · ${x['correo'] ?? ''}').toList();
        descripcion = 'Comunicado «$asunto»: cada destinatario recibirá UN correo.';
      } else {
        throw Exception('Acción no reconocida.');
      }
      if (!mounted) return;
      if (total == 0) {
        setState(() => _ejecutando = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay destinatarios: no se envía nada.')));
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
                Text(descripcion, style: TextStyle(fontSize: 13, color: cessumInk(ctx))),
                const SizedBox(height: 8),
                for (final l in lista.take(40)) Text('• $l', style: TextStyle(fontSize: 12.5, color: cessumInk(ctx))),
                if (total > 40) Text('… y ${total - 40} más.', style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: Text('Enviar a $total')),
          ],
        ),
      );
      if (ok != true) {
        if (mounted) setState(() => _ejecutando = false);
        return;
      }
      Map<String, dynamic> res;
      if (tipo == 'recordatorio_captura') {
        res = await _post({'accion': 'recordatorio_captura_enviar', 'correo': correo, 'simular': false}, segundos: 300);
      } else {
        res = await _post({'accion': 'comunicaciones_enviar', ...params, 'confirmar': 'ENVIAR'}, segundos: 300);
      }
      if (res['ok'] != true) throw Exception(res['error'] ?? 'No se pudo ejecutar.');
      if (!mounted) return;
      final enviados = res['enviados'] ?? res['total'] ?? total;
      setState(() => _turnos.add(_Turno('asistente', 'Listo: enviado a $enviados destinatario(s).')));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: _verde, content: Text('Enviado a $enviados.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _ejecutando = false);
    _bajar();
  }

  List<Map<String, dynamic>> _primeraLista(Map<String, dynamic> d) {
    for (final v in d.values) {
      if (v is List && v.isNotEmpty && v.first is Map) return v.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Asistente de operaciones', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (_turnos.isNotEmpty)
            IconButton(tooltip: 'Nueva conversación', onPressed: () => setState(() => _turnos.clear()), icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: [
              if (_turnos.isEmpty) _bienvenida(),
              for (final t in _turnos) _burbuja(t),
              if (_pensando)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed)),
                    const SizedBox(width: 10),
                    Text('Consultando los datos…', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
                  ]),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(top: BorderSide(color: Theme.of(context).dividerColor))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _preguntar(),
                  decoration: const InputDecoration(hintText: 'Pregunte o pida algo…', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: cessumRed),
                onPressed: _pensando ? null : () => _preguntar(),
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bienvenida() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]), borderRadius: BorderRadius.circular(16)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pregunte con sus palabras', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text('Respondo con datos reales del Guardián. Si me pide hacer algo, se lo propongo y usted decide: nunca envío sin que vea a quiénes y confirme.',
              style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
        ]),
      ),
      const SizedBox(height: 14),
      Text('PARA EMPEZAR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in _sugerencias) ActionChip(label: Text(s, style: const TextStyle(fontSize: 12.5)), onPressed: () => _preguntar(s)),
      ]),
    ]);
  }

  Widget _burbuja(_Turno t) {
    final mio = t.rol == 'admin';
    return Column(crossAxisAlignment: mio ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mio ? cessumRed.withValues(alpha: 0.10) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: mio ? cessumRed.withValues(alpha: 0.35) : Theme.of(context).dividerColor),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(t.texto, style: TextStyle(fontSize: 13.5, height: 1.45, color: cessumInk(context))),
          if (!mio && t.consulta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Fuente: ${t.consulta}', style: TextStyle(fontSize: 10.5, color: cessumFaint(context))),
            ),
          if (!mio)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(iconSize: 16, tooltip: 'Copiar', onPressed: () => Helpers.copiarAlPortapapeles(context, t.texto, 'Respuesta'), icon: const Icon(Icons.copy_outlined)),
            ),
        ]),
      ),
      if (t.accion != null) _tarjetaAccion(t.accion!),
    ]);
  }

  Widget _tarjetaAccion(Map<String, dynamic> a) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt_outlined, size: 18, color: cessumGold),
          const SizedBox(width: 6),
          Text('ACCIÓN PROPUESTA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumInk(context))),
        ]),
        const SizedBox(height: 6),
        Text('${a['descripcion'] ?? ''}', style: TextStyle(fontSize: 13, height: 1.4, color: cessumInk(context))),
        const SizedBox(height: 4),
        Text('No se envía nada hasta que vea a quiénes y confirme.', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(context))),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: _ejecutando ? null : () => _verYEjecutar(a),
            icon: _ejecutando
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Ver a quiénes y confirmar'),
          ),
        ),
      ]),
    );
  }
}

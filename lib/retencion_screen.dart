import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';

// =====================================================================
// RETENCIÓN INTELIGENTE (panel admin)
//   Reutiliza  GET riesgo_panel  para el semáforo de riesgo.
//   GET  retencion_nudges ?actor      -> { mapa: {matricula: 'dd/MM/yyyy'} }
//   POST retencion_nudge  { actor, matricula, correo, nombre, programa,
//                           nivel, razones } -> { mensaje, waUrl }
// El "nudge" envía un correo de ánimo personalizado (IA) y devuelve un
// enlace de WhatsApp listo para que el tutor lo mande.
// =====================================================================

class RetencionScreen extends StatefulWidget {
  const RetencionScreen({super.key});

  @override
  State<RetencionScreen> createState() => _RetencionScreenState();
}

class _RetencionScreenState extends State<RetencionScreen> {
  bool _cargando = true;
  String _error = '';
  String _actor = '';
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _alumnos = [];
  Map<String, String> _contactados = {};
  final Set<String> _enviando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    _actor = (await SessionStore.realEmail()) ?? '';
    try {
      final rp = await http
          .get(Uri.parse('$guardianUrl?accion=riesgo_panel'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(rp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final lista = (data['alumnos'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      Map<String, String> contact = {};
      try {
        final cn = await http
            .get(Uri.parse(
                '$guardianUrl?accion=retencion_nudges&actor=${Uri.encodeComponent(_actor)}'))
            .timeout(const Duration(seconds: 30));
        final cd = jsonDecode(cn.body) as Map<String, dynamic>;
        if (cd['ok'] == true && cd['mapa'] is Map) {
          contact = (cd['mapa'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _resumen = Map<String, dynamic>.from(data['resumen'] ?? {});
        _alumnos = lista;
        _contactados = contact;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el panel (¿permisos de administrador?).';
      });
    }
  }

  Future<void> _enviarAnimo(Map<String, dynamic> a) async {
    final mat = (a['matricula'] ?? '').toString();
    setState(() => _enviando.add(mat));
    try {
      final payload = <String, dynamic>{
        'accion': 'retencion_nudge',
        'actor': _actor,
        'matricula': mat,
        'correo': a['correo'] ?? '',
        'nombre': a['nombre'] ?? '',
        'programa': a['programa'] ?? '',
        'nivel': a['nivel'] ?? '',
        'razones': a['razones'] ?? [],
      };
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _enviando.remove(mat));
      if (data['ok'] == true) {
        setState(() => _contactados[mat] = 'hoy');
        _dialogoEnviado(
            (data['mensaje'] ?? '').toString(), (data['waUrl'] ?? '').toString());
      } else {
        _snack('${data['error'] ?? 'No se pudo enviar.'}', esError: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _enviando.remove(mat));
      _snack('Error de conexión.', esError: true);
    }
  }

  void _dialogoEnviado(String mensaje, String waUrl) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(children: [
          Icon(Icons.mark_email_read_outlined, color: Color(0xFF1E8E3E)),
          SizedBox(width: 8),
          Text('Ánimo enviado'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Se envió por correo. ¿También por WhatsApp?',
                style: TextStyle(fontSize: 13, color: CC.ink)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: CC.hueso, borderRadius: BorderRadius.circular(8)),
              child: Text(mensaje,
                  style: const TextStyle(fontSize: 12, color: CC.ink)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
          if (waUrl.isNotEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('WhatsApp'),
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(waUrl),
                    mode: LaunchMode.externalApplication);
              },
            ),
        ],
      ),
    );
  }

  void _snack(String t, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: esError ? cessumRed : CC.goldDark,
    ));
  }

  Color _colorNivel(String n) =>
      n.toLowerCase() == 'alto' ? cessumRed : CC.goldDark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Retención'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : RefreshIndicator(
              color: cessumRed,
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error.isNotEmpty)
                    Text(_error, style: const TextStyle(color: cessumRed))
                  else ...[
                    _resumenCard(),
                    const SizedBox(height: 14),
                    if (_alumnos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Center(
                            child: Text(
                                '¡Sin alumnos en riesgo! Todos con buen ritmo.',
                                style: TextStyle(color: CC.muted))),
                      )
                    else
                      ..._alumnos.map(_tarjeta),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _resumenCard() {
    final alto = (_resumen['alto'] ?? 0).toString();
    final medio = (_resumen['medio'] ?? 0).toString();
    final total = (_resumen['total'] ?? 0).toString();
    Widget chip(String n, String v, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text(v,
                  style: TextStyle(
                      color: c, fontSize: 22, fontWeight: FontWeight.w800)),
              Text(n, style: TextStyle(color: c, fontSize: 11)),
            ]),
          ),
        );
    return Row(children: [
      chip('Riesgo alto', alto, cessumRed),
      chip('En alerta', medio, CC.goldDark),
      chip('Activos', total, const Color(0xFF1E8E3E)),
    ]);
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final mat = (a['matricula'] ?? '').toString();
    final nivel = (a['nivel'] ?? '').toString();
    final razones = (a['razones'] as List? ?? []).map((e) => e.toString());
    final contactado = _contactados[mat];
    final enviando = _enviando.contains(mat);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CC.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((a['nombre'] ?? '').toString(),
                        style: const TextStyle(
                            color: CC.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        '${(a['programa'] ?? '').toString()} · ${(a['generacion'] ?? '').toString()}',
                        style: const TextStyle(color: CC.muted, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _colorNivel(nivel).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(nivel,
                    style: TextStyle(
                        color: _colorNivel(nivel),
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: razones
                .map((r) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: CC.hueso,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(r,
                          style: const TextStyle(
                              color: CC.ink, fontSize: 11)),
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (contactado != null) ...[
                const Icon(Icons.check_circle,
                    color: Color(0xFF1E8E3E), size: 16),
                const SizedBox(width: 4),
                Text('Contactado $contactado',
                    style: const TextStyle(
                        color: Color(0xFF1E8E3E), fontSize: 11)),
                const Spacer(),
              ] else
                const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10)),
                icon: enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.favorite_outline, size: 18),
                label: Text(contactado != null
                    ? 'Enviar de nuevo'
                    : 'Enviar ánimo'),
                onPressed: enviando ? null : () => _enviarAnimo(a),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

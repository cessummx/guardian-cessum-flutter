// =====================================================================
//  beca_convocatoria_alumno_screen.dart · CESSUM · (27-sep-2026)
//  ARTS. 49-58, ACUERDO 17/11/17 — Convocatoria de becas, lado alumno.
//  Distinta de las becas por código de categoría (USICAMM, indígena,
//  discapacidad...): esta es la beca por convocatoria pública y estudio
//  socioeconómico que exige el Acuerdo, con su propio proceso.
//
//  Guardián: GET beca_convocatorias_listar · POST beca_formal_solicitar
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class BecaConvocatoriaAlumnoScreen extends StatefulWidget {
  final String matricula;
  const BecaConvocatoriaAlumnoScreen({super.key, required this.matricula});

  @override
  State<BecaConvocatoriaAlumnoScreen> createState() => _BecaConvocatoriaAlumnoScreenState();
}

class _BecaConvocatoriaAlumnoScreenState extends State<BecaConvocatoriaAlumnoScreen> {
  bool _cargando = true;
  Map<String, dynamic>? _convocatoria;
  final _promedio = TextEditingController();
  final _motivo = TextEditingController();
  bool _enviando = false;
  String? _folioEnviado;

  Future<String> _actor() async => await SessionStore.realEmail() ?? await SessionStore.validEmail() ?? '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _promedio.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'beca_convocatorias_listar', 'actor': await _actor()});
      final r = await http.get(uri).timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        final lista = ((d['convocatorias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        Map<String, dynamic>? vigente;
        for (final c in lista) {
          if (c['activa'] == true) { vigente = c; break; }
        }
        if (mounted) setState(() => _convocatoria = vigente);
      }
    } catch (_) {}
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _solicitar() async {
    final conv = _convocatoria;
    if (conv == null) return;
    setState(() => _enviando = true);
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'beca_formal_solicitar',
                'actor': correo,
                'correo': correo,
                'matricula': widget.matricula,
                'folioConvocatoria': conv['folio'],
                'promedioGeneral': _promedio.text.trim(),
                'motivoSocioeconomico': _motivo.text.trim(),
              }))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        setState(() => _folioEnviado = '${d['folio']}');
      } else {
        _aviso('${d['error'] ?? 'No se pudo enviar.'}', error: true);
      }
    } catch (_) {
      _aviso('No se pudo enviar. Intenta de nuevo.', error: true);
    }
    if (mounted) setState(() => _enviando = false);
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? cessumRed : Colors.green, content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(backgroundColor: cessumRed, foregroundColor: Colors.white, title: const Text('Becas por convocatoria')),
      body: _cargando ? const Center(child: CircularProgressIndicator(color: cessumRed)) : _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_folioEnviado != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('Tu solicitud quedó registrada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cessumInk(context))),
            const SizedBox(height: 8),
            Text('Folio: $_folioEnviado', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cessumRed)),
            const SizedBox(height: 12),
            Text('Administración la revisará y te avisará el resultado.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cessumMuted(context))),
            const SizedBox(height: 20),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context), child: const Text('Listo')),
          ]),
        ),
      );
    }
    final conv = _convocatoria;
    if (conv == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Por ahora no hay ninguna convocatoria de becas abierta.', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context))),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Convocatoria ${conv['ciclo']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text('Del ${conv['apertura']} al ${conv['cierre']}', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
            if ('${conv['requisitos'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${conv['requisitos']}', style: const TextStyle(fontSize: 13, height: 1.4))),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _promedio,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Tu promedio general', border: OutlineInputBorder(), isDense: true),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _motivo,
        minLines: 4,
        maxLines: 8,
        decoration: const InputDecoration(
          labelText: 'Tu situación socioeconómica',
          hintText: 'Cuéntanos por qué necesitas la beca para continuar o concluir tus estudios',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _enviando ? null : _solicitar,
          icon: _enviando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
          label: const Text('Solicitar beca'),
        ),
      ),
    ]);
  }
}

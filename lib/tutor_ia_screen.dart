import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Tutor IA por materia: agente de estudio que explica temas, genera
/// ejercicios y resuelve dudas de cada materia del plan del alumno.
class TutorIaScreen extends StatefulWidget {
  const TutorIaScreen({super.key});

  @override
  State<TutorIaScreen> createState() => _TutorIaScreenState();
}

class _TutorIaScreenState extends State<TutorIaScreen> {
  final _msgCtrl = TextEditingController();
  final _materiaManual = TextEditingController();
  final _scroll = ScrollController();

  String _correo = '';
  List<String> _materias = [];
  String? _materiaSel;
  bool _cargandoMaterias = true;
  bool _enviando = false;

  // Conversación: {rol: 'alumno'|'tutor', texto: ...}
  final List<Map<String, String>> _mensajes = [];

  @override
  void initState() {
    super.initState();
    _cargarMaterias();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _materiaManual.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargarMaterias() async {
    setState(() => _cargandoMaterias = true);
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(
          '$guardianUrl?accion=tutor_materias&correo=${Uri.encodeComponent(_correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] == true && d['materias'] is List) {
        _materias = (d['materias'] as List).map((e) => e.toString()).toList();
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _cargandoMaterias = false;
      if (_materias.isNotEmpty) _materiaSel = _materias.first;
    });
  }

  String get _materiaActiva {
    if (_materiaSel != null && _materiaSel!.isNotEmpty) return _materiaSel!;
    return _materiaManual.text.trim();
  }

  Future<void> _enviar() async {
    final texto = _msgCtrl.text.trim();
    final materia = _materiaActiva;
    if (texto.isEmpty) return;
    if (materia.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Primero elige o escribe la materia.')));
      return;
    }
    setState(() {
      _mensajes.add({'rol': 'alumno', 'texto': texto});
      _enviando = true;
      _msgCtrl.clear();
    });
    _bajar();

    // Historial reciente (sin el mensaje recién agregado) para dar contexto.
    final historial = _mensajes
        .take(_mensajes.length - 1)
        .map((m) => {'rol': m['rol'], 'texto': m['texto']})
        .toList();

    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'tutor_ia',
                'correo': _correo,
                'materia': materia,
                'mensaje': texto,
                'historial': historial,
              }))
          .timeout(const Duration(seconds: 90));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] == true) {
        setState(() => _mensajes.add({'rol': 'tutor', 'texto': (d['respuesta'] ?? '').toString()}));
      } else {
        setState(() => _mensajes.add({
              'rol': 'tutor',
              'texto': '⚠️ ${(d['error'] ?? 'No se pudo responder.').toString()}'
            }));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _mensajes.add({'rol': 'tutor', 'texto': '⚠️ Error de conexión. Intenta de nuevo.'}));
    }
    if (!mounted) return;
    setState(() => _enviando = false);
    _bajar();
  }

  void _bajar() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Tutor IA'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _selectorMateria(),
          Expanded(
            child: _mensajes.isEmpty ? _bienvenida() : _listaMensajes(),
          ),
          if (_enviando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('El tutor está escribiendo…',
                  style: TextStyle(fontSize: 12, color: Colors.black45)),
            ),
          _barraEntrada(),
        ],
      ),
    );
  }

  Widget _selectorMateria() {
    if (_cargandoMaterias) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      color: cessumRed.withValues(alpha: 0.05),
      child: _materias.isNotEmpty
          ? Row(
              children: [
                const Icon(Icons.menu_book, color: cessumRed, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _materiaSel,
                    underline: const SizedBox(),
                    items: _materias
                        .map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => _materiaSel = v),
                  ),
                ),
              ],
            )
          : TextField(
              controller: _materiaManual,
              decoration: const InputDecoration(
                labelText: 'Escribe la materia que vas a estudiar',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
    );
  }

  Widget _bienvenida() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.smart_toy, size: 56, color: cessumGold),
        const SizedBox(height: 12),
        const Text(
          'Soy tu tutor de estudio',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(
          'Elige una materia y pregúntame lo que quieras: te explico temas, '
          'te pongo ejercicios con solución o te ayudo a repasar.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: cessumMuted(context)),
        ),
        const SizedBox(height: 20),
        _sugerencia('Explícame el tema principal de esta materia'),
        _sugerencia('Ponme 3 ejercicios con solución'),
        _sugerencia('Hazme un resumen con las ideas clave'),
      ],
    );
  }

  Widget _sugerencia(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: () { _msgCtrl.text = texto; _enviar(); },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: cessumGold.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(texto, style: const TextStyle(fontSize: 13, color: Colors.black87)),
      ),
    );
  }

  Widget _listaMensajes() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(14),
      itemCount: _mensajes.length,
      itemBuilder: (_, i) {
        final m = _mensajes[i];
        final esAlumno = m['rol'] == 'alumno';
        return Align(
          alignment: esAlumno ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            decoration: BoxDecoration(
              color: esAlumno ? cessumRed : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: esAlumno ? null : Border.all(color: Colors.black12),
            ),
            child: Text(
              m['texto'] ?? '',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: esAlumno ? Colors.white : Colors.black87,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _barraEntrada() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _msgCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _enviando ? null : _enviar(),
                decoration: InputDecoration(
                  hintText: 'Escribe tu pregunta…',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: Colors.black12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 24,
              backgroundColor: cessumRed,
              child: IconButton(
                onPressed: _enviando ? null : _enviar,
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

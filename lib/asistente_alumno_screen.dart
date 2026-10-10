import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_md.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

/// Asistente del alumno con IA: responde dudas sobre SU propia situación
/// (avance, promedio, credencial, trámites) y orienta sobre el uso de la app.
class AsistenteAlumnoScreen extends StatefulWidget {
  final StudentProfile? perfil;
  const AsistenteAlumnoScreen({super.key, this.perfil});

  @override
  State<AsistenteAlumnoScreen> createState() => _AsistenteAlumnoScreenState();
}

class _Msg {
  final String texto;
  final bool mio;
  _Msg(this.texto, this.mio);
}

class _AsistenteAlumnoScreenState extends State<AsistenteAlumnoScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _msgs = [];
  bool _enviando = false;

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : Colors.black87;
  Color get _textoSuave => cessumMuted(context);
  Color get _borde =>
      cessumIsDark(context) ? Colors.white12 : const Color(0xFFE3E3E6);

  static const List<String> _sugerencias = [
    '¿Cómo voy en mis materias?',
    '¿Cuál es mi promedio?',
    '¿Cómo saco mi credencial?',
    '¿Cómo hago un trámite?',
  ];

  // (24-sep) Sugerencias según SU situación y preguntas que le quedan.
  late List<String> _sugs = List.of(_sugerencias);
  int? _restantes;
  int _limite = 8;

  @override
  void initState() {
    super.initState();
    _inicio();
  }

  /// Al abrir: sugerencias según su situación y cuántas preguntas le quedan.
  /// No gasta ninguna pregunta.
  Future<void> _inicio() async {
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'asistente_alumno',
                'soloInicio': true,
                'correo': correo,
                'matricula': widget.perfil?.matricula ?? '',
              }))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() {
          final s = ((d['sugerencias'] as List?) ?? []).map((e) => '$e').toList();
          if (s.isNotEmpty) _sugs = s;
          _restantes = (d['restantes'] as num?)?.toInt();
          _limite = (d['limite'] as num?)?.toInt() ?? _limite;
        });
      }
    } catch (_) {}
  }

  String get _primerNombre {
    final n = (widget.perfil?.nombreCompleto ?? '').trim();
    return n.isEmpty ? '' : n.split(' ').first;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _enviar([String? texto]) async {
    final pregunta = (texto ?? _ctrl.text).trim();
    if (pregunta.isEmpty || _enviando) return;
    setState(() {
      _msgs.add(_Msg(pregunta, true));
      _enviando = true;
      _ctrl.clear();
    });
    _alFinal();
    try {
      final correo = await SessionStore.validEmail() ?? '';
      // (24-sep) La conversación previa, para que entienda «¿y en esa materia?».
      final previos = _msgs.length > 1 ? _msgs.sublist(0, _msgs.length - 1) : <_Msg>[];
      final historial = previos
          .skip(previos.length > 6 ? previos.length - 6 : 0)
          .map((m) => {'mio': m.mio, 'texto': m.texto})
          .toList();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'asistente_alumno',
                'correo': correo,
                'matricula': widget.perfil?.matricula ?? '',
                'pregunta': pregunta,
                'historial': historial,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['restantes'] is num) {
        setState(() => _restantes = (data['restantes'] as num).toInt());
      }
      if (data['ok'] == true) {
        setState(
            () => _msgs.add(_Msg((data['respuesta'] ?? '').toString(), false)));
      } else {
        setState(() => _msgs.add(_Msg(
            (data['error'] ?? 'No pude responder ahora.').toString(), false)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _msgs.add(_Msg('No me pude conectar. Intenta de nuevo.', false)));
    } finally {
      if (mounted) setState(() => _enviando = false);
      _alFinal();
    }
  }

  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Asistente CESSUM'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty
                ? _bienvenida()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _burbuja(_msgs[i]),
                  ),
          ),
          if (_enviando)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Escribiendo…',
                  style: TextStyle(fontSize: 12, color: _textoSuave)),
            ),
          // (24-sep) Cuántas le quedan, para que no se tope con el límite sin aviso.
          if (_restantes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                _restantes! > 0
                    ? 'Te quedan $_restantes de $_limite preguntas en las próximas horas.'
                    : 'Llegaste al límite de preguntas por ahora; vuelve a intentarlo en unas horas.',
                style: TextStyle(
                    fontSize: 11.5, color: _restantes! > 0 ? _textoSuave : cessumRed),
              ),
            ),
          _barra(),
        ],
      ),
    );
  }

  Widget _bienvenida() {
    final saludo =
        _primerNombre.isEmpty ? '¡Hola!' : '¡Hola, $_primerNombre!';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 10),
        const Icon(Icons.auto_awesome, color: cessumGold, size: 46),
        const SizedBox(height: 10),
        Text(saludo,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          'Soy tu asistente. Pregúntame sobre tu avance, tu credencial, '
          'tus trámites o cómo usar la app.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _textoSuave),
        ),
        const SizedBox(height: 20),
        ..._sugs.map((sg) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  side: const BorderSide(color: cessumGold),
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: _enviando ? null : () => _enviar(sg),
                child: Text(sg, style: TextStyle(color: _textoFuerte)),
              ),
            )),
      ],
    );
  }

  Widget _burbuja(_Msg m) {
    return Align(
      alignment: m.mio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: m.mio ? cessumRed : _superficie,
          borderRadius: BorderRadius.circular(14),
          border: m.mio ? null : Border.all(color: _borde),
        ),
        child: m.mio
            ? SelectableText(
                m.texto,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                ),
              )
            : CessumMd(m.texto, color: _textoFuerte, fontSize: 14),
      ),
    );
  }

  Widget _barra() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: _superficie,
          border: Border(top: BorderSide(color: _borde)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _enviar(),
                decoration: InputDecoration(
                  hintText: 'Escribe tu pregunta…',
                  filled: true,
                  fillColor: cessumIsDark(context)
                      ? const Color(0xFF26241F)
                      : const Color(0xFFF1F1F3),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: cessumRed,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _enviando ? null : () => _enviar(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_md.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Asistente con IA (Claude) para administración: pregunta en lenguaje
/// natural sobre los datos de la institución o pide redactar documentos.
class AsistenteIaScreen extends StatefulWidget {
  const AsistenteIaScreen({super.key});

  @override
  State<AsistenteIaScreen> createState() => _AsistenteIaScreenState();
}

class _Mensaje {
  final String texto;
  final bool mio;
  _Mensaje(this.texto, this.mio);
}

class _AsistenteIaScreenState extends State<AsistenteIaScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<_Mensaje> _mensajes = [];
  bool _enviando = false;

  static const List<String> _sugerencias = [
    '¿Cuántos alumnos en riesgo alto hay y en qué programas?',
    '¿Cómo está la salud de datos hoy?',
    'Redáctame un aviso para recordar el pago de reinscripción.',
    '¿Cuántas solicitudes tengo pendientes?',
  ];

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
      _mensajes.add(_Mensaje(pregunta, true));
      _enviando = true;
      _ctrl.clear();
    });
    _alFinal();
    try {
      // (24-sep) Correo REAL: en «Ver como profesor» validEmail() devuelve el del profesor.
      final actor = await SessionStore.realEmail() ?? '';
      // (24-sep) La conversación previa: «ahora hazlo más corto», «y de ese programa».
      final previos = _mensajes.length > 1 ? _mensajes.sublist(0, _mensajes.length - 1) : <_Mensaje>[];
      final historial = previos
          .skip(previos.length > 6 ? previos.length - 6 : 0)
          .map((m) => {'mio': m.mio, 'texto': m.texto})
          .toList();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'asistente_ia',
                'actor': actor,
                'pregunta': pregunta,
                'historial': historial,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() => _mensajes
            .add(_Mensaje((data['respuesta'] ?? '').toString(), false)));
      } else {
        setState(() => _mensajes.add(_Mensaje(
            '⚠️ ${data['error'] ?? 'No se pudo responder.'}', false)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _mensajes.add(
          _Mensaje('⚠️ No se pudo conectar con el asistente.', false)));
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
            child: _mensajes.isEmpty
                ? _bienvenida()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(14),
                    itemCount: _mensajes.length,
                    itemBuilder: (_, i) => _burbuja(_mensajes[i]),
                  ),
          ),
          if (_enviando)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('El asistente está pensando…',
                  style: TextStyle(fontSize: 12, color: cessumFaint(context))),
            ),
          _barra(),
        ],
      ),
    );
  }

  Widget _bienvenida() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 10),
        const Icon(Icons.auto_awesome, color: cessumGold, size: 46),
        const SizedBox(height: 10),
        const Text('Pregúntame sobre tu institución',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          'Te respondo con tus datos del día o te ayudo a redactar documentos. '
          'Recuerdo lo que vamos hablando, así que puedes pedir «ahora más corto» o «y de ese programa».',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: cessumMuted(context)),
        ),
        const SizedBox(height: 20),
        ..._sugerencias.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  side: const BorderSide(color: cessumGold),
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: _enviando ? null : () => _enviar(s),
                child: Text(s,
                    style: TextStyle(color: cessumInk(context))),
              ),
            )),
      ],
    );
  }

  Widget _burbuja(_Mensaje m) {
    return Align(
      alignment: m.mio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: m.mio ? cessumRed : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: m.mio ? null : Border.all(color: Theme.of(context).dividerColor),
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
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CessumMd(m.texto, color: cessumInk(context), fontSize: 14),
                // (24-sep) Copiar la respuesta: avisos y documentos redactados.
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Copiar',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.copy, size: 16, color: cessumMuted(context)),
                    onPressed: () => Helpers.copiarAlPortapapeles(context, m.texto, 'Respuesta'),
                  ),
                ),
              ]),
      ),
    );
  }

  Widget _barra() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
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
                  fillColor: cessumIsDark(context) ? const Color(0xFF26241F) : const Color(0xFFF1F1F3),
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

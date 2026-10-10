import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_header.dart';
import 'cessum_ui.dart';

/// Buzón de sugerencias / encuesta de satisfacción: el alumno envía una
/// sugerencia, felicitación o queja, con una calificación opcional.
class BuzonScreen extends StatefulWidget {
  final String matricula;
  final String nombre;
  final String correo;
  const BuzonScreen({
    super.key,
    this.matricula = '',
    this.nombre = '',
    this.correo = '',
  });

  @override
  State<BuzonScreen> createState() => _BuzonScreenState();
}

class _BuzonScreenState extends State<BuzonScreen> {
  String _tipo = 'Sugerencia';
  int _calificacion = 0;

  /* (8-sep) EL ANONIMATO SE DECIDE AQUÍ, NO EN EL MENÚ.
   * Había dos tarjetas —«Buzón de sugerencias» y «Buzón anónimo»— que abrían
   * ESTA MISMA pantalla: la primera le pasaba matrícula y nombre, la segunda
   * no le pasaba nada. Es decir, que tu mensaje llevara tu nombre dependía de
   * cuál de las dos tarjetas hubieras tocado, y quien quería escribir en
   * confianza tenía que saber de antemano que existía una segunda más abajo.
   * Equivocarse de puerta significaba mandar tu nombre sin haberlo elegido.
   * Ahora la pantalla es una sola y la decisión se toma antes de enviar, con
   * el estado dicho en texto claro. */
  bool _anonimo = false;

  /// Solo puede firmar quien fue identificado al abrir la pantalla. Si entró
  /// sin datos, el envío es anónimo por fuerza y así se le dice.
  bool get _puedeFirmar =>
      widget.matricula.trim().isNotEmpty || widget.correo.trim().isNotEmpty;
  final TextEditingController _ctrl = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final msg = _ctrl.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe tu mensaje primero.')),
      );
      return;
    }
    setState(() => _enviando = true);
    try {
      final anonimo = _anonimo || !_puedeFirmar;
      /* (24-sep) Iba a «sugerencia_enviar», que esperaba el texto en otro campo
       * y lo guardaba en una hoja que el administrador no lee: ningún mensaje del
       * Buzón llegaba. Ahora va a «buzon_enviar» (la hoja Buzón), y si firma, la
       * identidad la verifica el Guardián con la llave. */
      final payload = {
        'accion': 'buzon_enviar',
        'categoria': _tipo,
        // En anónimo no se manda NADA que identifique: ni matrícula, ni
        // nombre, ni correo. Es la misma promesa que hacía la tarjeta
        // separada, ahora bajo control del alumno.
        'matricula': anonimo ? '' : widget.matricula,
        'nombre': anonimo ? '' : widget.nombre,
        'correo': anonimo ? '' : widget.correo,
        'tipo': _tipo,
        'calificacion': _calificacion > 0 ? _calificacion.toString() : '',
        'mensaje': msg,
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No se pudo enviar.');
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _ctrl.clear();
        _calificacion = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(anonimo
                ? '¡Gracias! Tu mensaje se envió en anónimo.'
                : '¡Gracias! Tu mensaje fue enviado.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
    }
  }

  /// El interruptor y, debajo, lo que va a pasar dicho sin rodeos. Nadie
  /// debería tener que deducir si su nombre viaja o no.
  Widget _selectorIdentidad() {
    final anonimo = _anonimo || !_puedeFirmar;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_puedeFirmar)
            Row(
              children: [
                Expanded(
                  child: Text(
                      anonimo
                          ? 'Enviar en anónimo'
                          : 'Enviar con mi nombre',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  value: anonimo,
                  activeThumbColor: cessumRed,
                  onChanged: _enviando
                      ? null
                      : (v) => setState(() => _anonimo = v),
                ),
              ],
            ),
          Text(
            anonimo
                ? 'No se enviará tu nombre, tu matrícula ni tu correo. Nadie '
                    'podrá saber quién escribió, y por eso tampoco podremos '
                    'responderte.'
                : 'Tu mensaje llegará firmado como ${widget.nombre.isEmpty ? 'tu cuenta' : widget.nombre}. '
                    'Así podemos darle seguimiento y contestarte.',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CessumAppBar(titulo: 'Buzón'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Tu opinión nos ayuda a mejorar',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: cessumRed),
          ),
          const SizedBox(height: 4),
          Text(
            'Cuéntanos una sugerencia, una felicitación o algo que podamos mejorar.',
            style: TextStyle(color: cessumMuted(context)),
          ),
          const SizedBox(height: 16),
          const Text('Tipo de mensaje',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: ['Sugerencia', 'Felicitación', 'Queja'].map((t) {
              return ChoiceChip(
                label: Text(t),
                selected: _tipo == t,
                selectedColor: cessumRed.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _tipo = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const Text('¿Cómo calificarías tu experiencia? (opcional)',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: List.generate(5, (i) {
              final n = i + 1;
              return IconButton(
                onPressed: () => setState(() => _calificacion = n),
                icon: Icon(
                  n <= _calificacion ? Icons.star : Icons.star_border,
                  color: cessumGold,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Escribe tu mensaje aquí…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _selectorIdentidad(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _enviando ? null : _enviar,
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_enviando ? 'Enviando…' : 'Enviar'),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  privacidad_gate.dart · CESSUM · (27-sep-2026)
//  ART. 66, ACUERDO 17/11/17 — Aviso de privacidad versionado.
//  Se revisa cada vez que alguien entra a la app: si hay una versión
//  vigente que esa persona no ha aceptado, se le muestra antes de dejarla
//  pasar. No bloquea si aún no hay ningún aviso publicado.
//
//  Uso: en welcome_screen.dart, justo antes de entrar al menú:
//    await PrivacidadGate.revisarYMostrar(context);
//
//  Guardián: GET privacidad_estado&correo=  · GET privacidad_vigente
//            POST privacidad_aceptar { correo, rol }
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class PrivacidadGate {
  /// Revisa el estado y, si hace falta, muestra el diálogo y espera a que
  /// la persona acepte. No lanza excepciones hacia afuera: si algo falla
  /// en la consulta, simplemente no molesta a nadie.
  static Future<void> revisarYMostrar(BuildContext context, {String rol = 'alumno'}) async {
    try {
      final correo = (await SessionStore.validEmail())?.trim().toLowerCase();
      if (correo == null || correo.isEmpty) return;
      final rEstado = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'privacidad_estado', 'correo': correo}))
          .timeout(const Duration(seconds: 20));
      final dEstado = jsonDecode(rEstado.body) as Map<String, dynamic>;
      if (dEstado['ok'] != true || dEstado['requiereAceptar'] != true) return;

      final rVig = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'privacidad_vigente'}))
          .timeout(const Duration(seconds: 20));
      final dVig = jsonDecode(rVig.body) as Map<String, dynamic>;
      final vig = dVig['vigente'] as Map<String, dynamic>?;
      if (vig == null) return; // no hay nada publicado; no hay qué mostrar

      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: _DialogoPrivacidad(vigente: vig, correo: correo, rol: rol),
        ),
      );
    } catch (_) {
      // Best-effort: si falla la consulta, no se bloquea a nadie por eso.
    }
  }
}

class _DialogoPrivacidad extends StatefulWidget {
  final Map<String, dynamic> vigente;
  final String correo;
  final String rol;
  const _DialogoPrivacidad({required this.vigente, required this.correo, required this.rol});

  @override
  State<_DialogoPrivacidad> createState() => _DialogoPrivacidadState();
}

class _DialogoPrivacidadState extends State<_DialogoPrivacidad> {
  bool _enviando = false;
  bool _leido = false;

  Future<void> _aceptar() async {
    setState(() => _enviando = true);
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'privacidad_aceptar', 'correo': widget.correo, 'rol': widget.rol}))
          .timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) Navigator.of(context).pop();
    } catch (_) {}
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final texto = '${widget.vigente['texto'] ?? ''}';
    final url = '${widget.vigente['url'] ?? ''}';
    return AlertDialog(
      title: const Text('Aviso de privacidad', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (texto.isNotEmpty) Text(texto, style: const TextStyle(fontSize: 13.5, height: 1.5)),
            if (texto.isEmpty && url.isNotEmpty)
              Text('Puedes consultar el aviso completo en: $url', style: const TextStyle(fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 14),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _leido,
              onChanged: (v) => setState(() => _leido = v == true),
              title: const Text('He leído y acepto el aviso de privacidad.', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: (_leido && !_enviando) ? _aceptar : null,
          child: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Aceptar y continuar'),
        ),
      ],
    );
  }
}

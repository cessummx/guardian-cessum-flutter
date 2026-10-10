// =====================================================================
//  acceso_bloqueado_screen.dart · CESSUM · (26-sep-2026)
//  Lo que ve el alumno cuando Administración pausó su acceso a la app:
//  el mensaje del bloqueo, un botón para avisar que ya pagó o pedir
//  revisión, y el contacto de Administración. No puede entrar al menú.
//
//  Guardián: POST acceso_revision { matricula, mensaje }
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

class AccesoBloqueadoScreen extends StatefulWidget {
  final String matricula;
  final String nombre;
  final Map<String, dynamic> info;
  const AccesoBloqueadoScreen({super.key, required this.matricula, required this.nombre, required this.info});

  @override
  State<AccesoBloqueadoScreen> createState() => _AccesoBloqueadoScreenState();
}

class _AccesoBloqueadoScreenState extends State<AccesoBloqueadoScreen> {
  bool _enviando = false;
  bool _enviado = false;

  Future<void> _avisarPago() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avisar a Administración', style: TextStyle(fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Cuéntanos brevemente: ¿ya pagaste, quieres un convenio o hay algo que revisar?', style: TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            minLines: 3,
            maxLines: 6,
            maxLength: 800,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Ej. Ya realicé el pago el día de hoy…'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    final texto = ctl.text.trim();
    ctl.dispose();
    if (ok != true || !mounted) return;
    setState(() => _enviando = true);
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'acceso_revision', 'matricula': widget.matricula, 'mensaje': texto, 'actor': correo}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] == true) {
        setState(() => _enviado = true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green, duration: const Duration(seconds: 6), content: Text('${d['mensaje'] ?? 'Enviado. Administración revisará tu caso.'}')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('${d['error'] ?? 'No se pudo enviar.'}')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: cessumRed, content: Text('No se pudo enviar. Intenta de nuevo.')));
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final whatsapp = '${info['whatsapp'] ?? '6421376117'}';
    final correo = '${info['contacto'] ?? 'administracion@cessum.mx'}';
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(backgroundColor: cessumRed, foregroundColor: Colors.white, title: const Text('Acceso pausado', style: TextStyle(fontWeight: FontWeight.w600)), automaticallyImplyLeading: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const SizedBox(height: 10),
            const Icon(Icons.lock_clock_outlined, size: 64, color: cessumGold),
            const SizedBox(height: 12),
            Text('Hola, ${widget.nombre.split(' ').first}', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cessumInk(context))),
            const SizedBox(height: 6),
            Text('Tu acceso a la app está pausado${'${info['motivo'] ?? ''}'.isNotEmpty ? ' · ${info['motivo']}' : ''}',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: cessumMuted(context))),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14), border: Border.all(color: cessumGold.withValues(alpha: 0.5))),
              child: Text('${info['mensaje'] ?? ''}', style: const TextStyle(fontSize: 14.5, height: 1.5)),
            ),
            if ('${info['hasta'] ?? ''}'.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('Se reactiva el ${info['hasta']}.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _enviando || _enviado ? null : _avisarPago,
              icon: _enviando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(_enviado ? Icons.check : Icons.send),
              label: Text(_enviado ? 'Aviso enviado a Administración' : 'Ya pagué / quiero un convenio'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Helpers.abrirUrlExterna('https://wa.me/52$whatsapp?text=${Uri.encodeComponent('Hola, soy ${widget.nombre} (${widget.matricula}). Mi acceso a la app está pausado y quiero regularizar mi situación.')}', context),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Escribir a Administración por WhatsApp'),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => Helpers.abrirUrlExterna('mailto:$correo?subject=${Uri.encodeComponent('Acceso pausado · ${widget.matricula}')}', context),
              icon: const Icon(Icons.mail_outline, size: 18),
              label: Text(correo),
            ),
            const SizedBox(height: 20),
            Text('Tu inscripción sigue vigente. En cuanto Administración registre tu pago o tu convenio, el acceso se reactiva de inmediato.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
          ]),
        ),
      ),
    );
  }
}

// CUENTA DADA DE BAJA · lo que ve el alumno  (19-ago-2026)
//
// PARA QUIÉN ES ESTA PANTALLA
// Para alguien que abre la app en un mal momento. Quizá dejó de estudiar
// porque se le atravesó algo, quizá cree que fue un error, quizá lleva meses
// pensando en volver y hoy se animó.
//
// Hasta ahora esa persona entraba y no encontraba nada: sus grupos vacíos,
// sus materias sin aparecer, botones que no respondían. Concluía que la
// plataforma se descompuso — y quien quería volver dejaba de intentarlo.
//
// TRES DECISIONES
//
// 1. SE DICE QUÉ PASÓ Y POR QUÉ, con el mismo motivo que dice su expediente.
//    Enterarse por un correo y ver otra cosa en la app destruye la confianza
//    en ambos.
//
// 2. LO PRIMERO NO ES LA BAJA, ES LA PUERTA. El botón de escribir a
//    Vicerrectoría va arriba del motivo: quien abre esto ya sabe que algo
//    pasa; lo que no sabe es que puede arreglarse.
//
// 3. EL CORREO VA REDACTADO. No por comodidad: porque escribirle a una
//    institución que te dio de baja cuesta, y mucha gente lo deja para
//    después y nunca lo hace. Si el mensaje ya está escrito, solo hay que
//    darle enviar.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class CuentaBajaScreen extends StatelessWidget {
  final Map<String, dynamic> datos;
  const CuentaBajaScreen({super.key, required this.datos});

  /// Comprueba el estado de la cuenta. Devuelve null si está activa, o los
  /// datos de la baja si no lo está.
  ///
  /// Falla en silencio a propósito: si la consulta no responde, más vale
  /// dejar entrar a alguien de baja que dejar fuera a un alumno activo por
  /// un problema de red.
  static Future<Map<String, dynamic>?> revisar(String correo) async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'mi_estado_cuenta',
            'correo': correo,
          }))
          .timeout(const Duration(seconds: 20));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && d['activa'] == false) {
        return Map<String, dynamic>.from(d);
      }
    } catch (_) {}
    return null;
  }

  String get _cuerpoCorreo {
    final n = '${datos['nombre'] ?? ''}';
    final m = '${datos['matricula'] ?? ''}';
    final p = '${datos['programa'] ?? ''}';
    return 'Buen día.\n\n'
        'Me dirijo a ustedes porque al entrar a la plataforma encontré que mi '
        'inscripción está dada de baja.\n\n'
        'Mis datos son:\n'
        'Nombre: $n\n'
        'Matrícula: $m\n'
        'Programa: $p\n\n'
        'Les explico mi situación:\n'
        '[escriba aquí qué pasó y si desea reincorporarse]\n\n'
        'Quedo al pendiente de su respuesta.\n\n'
        'Gracias.';
  }

  @override
  Widget build(BuildContext context) {
    final motivo = '${datos['motivo'] ?? ''}';
    final queEscribir = (datos['queEscribir'] as List?) ?? [];
    final correo = '${datos['contacto'] ?? 'vicerrectoria@cessum.mx'}';

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tu inscripción'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${datos['nombre'] ?? ''}',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, height: 1.25)),
          Text(
              '${datos['matricula'] ?? ''} · ${datos['programa'] ?? ''}'
              '${'${datos['generacion'] ?? ''}'.isNotEmpty ? ' · ${datos['generacion']}' : ''}',
              style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          const SizedBox(height: 18),
          Text('${datos['mensaje'] ?? ''}',
              style: const TextStyle(fontSize: 15.5, height: 1.55)),

          // ── La puerta, antes que el motivo ──
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: const Color(0xFF1E7B34).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF1E7B34).withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Esto tiene solución',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E7B34))),
                const SizedBox(height: 6),
                Text('${datos['puedoVolver'] ?? ''}',
                    style: const TextStyle(fontSize: 14, height: 1.55)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E7B34),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () async {
                      final u = Uri(
                        scheme: 'mailto',
                        path: correo,
                        query: 'subject=${Uri.encodeComponent('Solicitud de '
                            'aclaración · Matrícula ${datos['matricula']}')}'
                            '&body=${Uri.encodeComponent(_cuerpoCorreo)}',
                      );
                      await launchUrl(u,
                          mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.mail_outline, size: 20),
                    label: const Text('Escribir a Vicerrectoría',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                // Alternativa por si el correo del teléfono no está
                // configurado: quedarse sin poder escribir por un detalle
                // técnico sería la peor forma de perder a alguien.
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: correo));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Copiado: $correo')));
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar correo',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final w = Uri.parse(
                            'https://wa.me/52${datos['whatsapp'] ?? '6421376117'}'
                            '?text=${Uri.encodeComponent('Buen día. Mi matrícula '
                                'es ${datos['matricula']} y quisiera preguntar '
                                'sobre mi inscripción.')}');
                        await launchUrl(w,
                            mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.chat, size: 16),
                      label: const Text('WhatsApp',
                          style: TextStyle(fontSize: 12.5)),
                    ),
                  ),
                ]),
              ],
            ),
          ),

          // ── Qué conviene contar ──
          if (queEscribir.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: cessumMuted(context).withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Qué nos conviene saber',
                      style: TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ...queEscribir.map((x) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('· ',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              Expanded(
                                  child: Text('$x',
                                      style: const TextStyle(
                                          fontSize: 13, height: 1.5))),
                            ]),
                      )),
                ],
              ),
            ),
          ],

          // ── El motivo, al final ──
          if (motivo.isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MOTIVO REGISTRADO',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: .9,
                          fontWeight: FontWeight.w800,
                          color: cessumGold)),
                  const SizedBox(height: 5),
                  Text(motivo,
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                  if ('${datos['fecha'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text('Registrado el ${datos['fecha']}',
                        style: TextStyle(
                            fontSize: 11.5, color: cessumMuted(context))),
                  ],
                  const SizedBox(height: 8),
                  Text(
                      'Si esto no corresponde a tu caso, díselo a '
                      'Vicerrectoría: se revisa tu expediente y se corrige.',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: cessumMuted(context))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 26),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .popUntil((r) => r.isFirst),
              child: const Text('Salir'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

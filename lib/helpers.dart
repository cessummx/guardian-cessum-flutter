import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'student_profile.dart';

class Helpers {
  // Abre cualquier URL en el navegador externo del celular
  static Future<bool> abrirUrlExterna(String url, BuildContext context) async {
    // (24-sep) Un enlace vacío no es «inválido»: todavía no está disponible.
    if (url.trim().isEmpty || url.trim() == 'null') {
      if (context.mounted) _mostrarError(context, 'Este enlace todavía no está disponible.');
      return false;
    }
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _mostrarError(context, 'No se pudo abrir el enlace');
      }
      return ok;
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, 'El enlace no es válido.');
      }
      return false;
    }
  }

  // Abre WhatsApp al numero de atencion a alumnos.
  // Si hay perfil guardado, el mensaje incluye matricula y programa.
  static Future<void> abrirWhatsApp(BuildContext context) async {
    final perfil = await StudentProfile.load();
    final mensaje = _construirMensajeWhatsApp(perfil);

    await _abrirWhatsAppCon(
      context: context,
      numero: whatsappNumero,
      mensaje: mensaje,
    );
  }

  // Abre WhatsApp al numero de admisiones (nuevos prospectos)
  static Future<void> abrirWhatsAppAdmisiones(BuildContext context) async {
    await _abrirWhatsAppCon(
      context: context,
      numero: whatsappAdmisionesNumero,
      mensaje: whatsappAdmisionesMensaje,
    );
  }

  static String _construirMensajeWhatsApp(StudentProfile? perfil) {
    if (perfil == null) {
      return whatsappMensaje;
    }
    return 'Hola, soy alumno de CESSUM y necesito apoyo.\n\n'
        'Matrícula: ${perfil.matricula}\n'
        'Programa: ${perfil.programa}\n'
        'Modalidad: ${perfil.modalidad}\n'
        'Generación: ${perfil.generacion}';
  }

  static Future<void> _abrirWhatsAppCon({
    required BuildContext context,
    required String numero,
    required String mensaje,
  }) async {
    final mensajeCodificado = Uri.encodeComponent(mensaje);
    final urlApp = 'whatsapp://send?phone=$numero&text=$mensajeCodificado';
    final urlWeb = 'https://wa.me/$numero?text=$mensajeCodificado';

    try {
      final uriApp = Uri.parse(urlApp);
      final puedeApp = await canLaunchUrl(uriApp);
      if (puedeApp) {
        await launchUrl(uriApp, mode: LaunchMode.externalApplication);
        return;
      }
      await launchUrl(Uri.parse(urlWeb), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, 'No se pudo abrir WhatsApp');
      }
    }
  }

  // Abre la marcacion telefonica con el numero pre-cargado
  static Future<void> llamarPorTelefono(
    BuildContext context,
    String numero,
  ) async {
    final uri = Uri(scheme: 'tel', path: numero);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _mostrarError(context, 'No se pudo iniciar la llamada');
      }
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, 'No se pudo abrir el marcador');
      }
    }
  }

  // Abre la app de Gmail nativa, con fallback a navegador.
  // Muestra primero una advertencia para que tengan sesion abierta.
  static Future<void> abrirGmail(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.email, color: cessumRed),
            SizedBox(width: 10),
            Text('Abrir Gmail'),
          ],
        ),
        content: const Text(
          'Se abrirá la app de Gmail. Asegúrate de tener tu sesión iniciada '
          'con tu correo institucional para ver los avisos y comunicados de CESSUM.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abrir'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!context.mounted) return;

    // Intentamos abrir la app nativa de Gmail primero
    final urlApp = Uri.parse('googlegmail://');
    final urlWeb = Uri.parse('https://mail.google.com');

    try {
      final puedeApp = await canLaunchUrl(urlApp);
      if (puedeApp) {
        await launchUrl(urlApp, mode: LaunchMode.externalApplication);
        return;
      }
      // Fallback: navegador
      await launchUrl(urlWeb, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, 'No se pudo abrir Gmail');
      }
    }
  }

  // Abre la app de correo con asunto y cuerpo pre-llenados
  static Future<void> abrirCorreo({
    required BuildContext context,
    required String destinatario,
    required String asunto,
    required String cuerpo,
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: destinatario,
      query: _encodeQuery({
        'subject': asunto,
        'body': cuerpo,
      }),
    );

    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        _mostrarError(context, 'No se pudo abrir tu app de correo');
      }
    } catch (e) {
      if (context.mounted) {
        _mostrarError(context, 'Error al abrir el correo');
      }
    }
  }

  // Solicitud de factura: si hay perfil guardado, lo precargamos en el cuerpo
  static Future<void> abrirCorreoFactura(BuildContext context) async {
    final perfil = await StudentProfile.load();
    if (!context.mounted) return;

    await abrirCorreo(
      context: context,
      destinatario: correoFacturacion,
      asunto: 'Solicitud de factura',
      cuerpo: cuerpoFacturacion(perfil),
    );
  }

  static String _encodeQuery(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  // Copia texto al portapapeles y muestra confirmacion
  static Future<void> copiarAlPortapapeles(
    BuildContext context,
    String texto,
    String etiqueta,
  ) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // (24-sep) Verde: es una confirmación, no un error.
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text('$etiqueta copiado al portapapeles'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static void _mostrarError(BuildContext context, String mensaje) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.grey.shade800,
        content: Text(mensaje),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Genera el cuerpo del correo de solicitud de factura
  // Si hay perfil del alumno, lo pre-llena
  static String cuerpoFacturacion([StudentProfile? perfil]) {
    if (perfil == null) {
      return '''
Buen día, equipo CESSUM:

Por este medio solicito factura con los siguientes datos:

Nombre completo: 
Programa académico: 
Concepto del pago (mensualidad / materia): 
Monto: 
Fecha del pago: 

Adjunto a este correo mi constancia de situación fiscal.

Saludos cordiales.''';
    }

    return '''
Buen día, equipo CESSUM:

Por este medio solicito factura con los siguientes datos:

Nombre completo: 
Matrícula: ${perfil.matricula}
Programa académico: ${perfil.programa}
Modalidad: ${perfil.modalidad}
Generación: ${perfil.generacion}
Concepto del pago (mensualidad / materia): 
Monto: 
Fecha del pago: 

Adjunto a este correo mi constancia de situación fiscal.

Saludos cordiales.''';
  }


  /// Texto de frescura de datos, p. ej. "Actualizado hace 5 min".
  static String haceTexto(DateTime? t) {
    if (t == null) return '';
    final seg = DateTime.now().difference(t).inSeconds;
    if (seg < 60) return 'Actualizado hace un momento';
    final min = seg ~/ 60;
    if (min < 60) return 'Actualizado hace $min min';
    final hr = min ~/ 60;
    if (hr < 24) return 'Actualizado hace $hr h';
    final dias = hr ~/ 24;
    return 'Actualizado hace $dias d';
  }
}

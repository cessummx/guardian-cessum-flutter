import 'package:flutter/material.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Contacto y datos útiles de CESSUM en un solo lugar: líneas de WhatsApp,
/// correo, accesos rápidos y datos para pago, con botones de abrir y copiar.
class ContactoScreen extends StatelessWidget {
  const ContactoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Contacto y datos útiles',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _titulo('¿Necesitas ayuda?'),
          _accion(
            context,
            icono: Icons.support_agent,
            color: const Color(0xFF25D366),
            titulo: 'WhatsApp · Atención a estudiantes',
            subtitulo: 'Dudas de tu trámite, sistema o cuenta',
            onTap: () => Helpers.abrirWhatsApp(context),
          ),
          _accion(
            context,
            icono: Icons.campaign,
            color: const Color(0xFF25D366),
            titulo: 'WhatsApp · Admisiones',
            subtitulo: 'Información de nuevo ingreso y oferta',
            onTap: () => Helpers.abrirWhatsAppAdmisiones(context),
          ),
          _accion(
            context,
            icono: Icons.email,
            color: cessumRed,
            titulo: 'Correo institucional',
            subtitulo: correoInstitucional,
            onTap: () => Helpers.abrirCorreo(
              context: context,
              destinatario: correoInstitucional,
              asunto: 'Contacto desde la app CESSUM',
              cuerpo: '',
            ),
            onCopiar: () => Helpers.copiarAlPortapapeles(
                context, correoInstitucional, 'Correo'),
          ),
          const SizedBox(height: 18),
          _titulo('Accesos rápidos'),
          _accion(
            context,
            icono: Icons.school,
            color: cessumRed,
            titulo: 'Aula Virtual (Moodle)',
            subtitulo: moodleDomain,
            onTap: () => Helpers.abrirUrlExterna(moodleUrl, context),
          ),
          _accion(
            context,
            icono: Icons.public,
            color: cessumGold,
            titulo: 'Sitio web CESSUM',
            subtitulo: 'www.cessum.mx',
            onTap: () => Helpers.abrirUrlExterna(sitioWebUrl, context),
          ),
          _accion(
            context,
            icono: Icons.event,
            color: cessumGold,
            titulo: 'Calendario y clases',
            subtitulo: 'Abre tu calendario',
            onTap: () => Helpers.abrirUrlExterna(calendarioUrl, context),
          ),
          const SizedBox(height: 18),
          _titulo('Datos para pago'),
          _datoCopiable(context, 'Banco', bancoNombre, copiar: false),
          _datoCopiable(context, 'Beneficiario', bancoBeneficiario,
              copiar: false),
          _datoCopiable(context, 'Cuenta', bancoCuenta),
          _datoCopiable(context, 'CLABE', bancoClabe),
          _datoCopiable(context, 'Concepto', bancoConceptoSugerido,
              copiar: false),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Después de realizar el pago, no olvides subir tu comprobante en el formulario de pagos correspondiente a tu generación.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: cessumRed)),
    );
  }

  Widget _accion(
    BuildContext context, {
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
    VoidCallback? onCopiar,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icono, color: color, size: 22),
        ),
        title: Text(titulo,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: Text(subtitulo, style: const TextStyle(fontSize: 11.5)),
        trailing: onCopiar != null
            ? IconButton(
                icon: const Icon(Icons.copy, size: 18, color: Colors.black45),
                onPressed: onCopiar,
              )
            : const Icon(Icons.open_in_new, size: 16, color: Colors.black26),
      ),
    );
  }

  Widget _datoCopiable(BuildContext context, String etiqueta, String valor,
      {bool copiar = true}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(etiqueta,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54)),
            ),
            Expanded(
              child: Text(valor,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            if (copiar)
              IconButton(
                icon: const Icon(Icons.copy, size: 18, color: Colors.black45),
                onPressed: () =>
                    Helpers.copiarAlPortapapeles(context, valor, etiqueta),
              ),
          ],
        ),
      ),
    );
  }
}

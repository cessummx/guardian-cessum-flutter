import 'package:flutter/material.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'welcome_screen.dart';

class NewUserScreen extends StatelessWidget {
  const NewUserScreen({super.key});

  Future<void> _volverABienvenida(BuildContext context) async {
    await WelcomeScreen.clearAll();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final maestrias = programasAcademicos
        .where((p) => p.nivel == 'Maestria')
        .toList();
    final doctorados = programasAcademicos
        .where((p) => p.nivel == 'Doctorado')
        .toList();

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text(
          'Bienvenido a CESSUM',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Cambiar perfil',
            onPressed: () => _volverABienvenida(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Tarjeta de bienvenida
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cessumRed, cessumRed.withValues(alpha: 0.85)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      height: 50,
                      fit: BoxFit.contain,
                      color: Colors.white,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Bienvenido a CESSUM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'Gracias por tu interes en el Centro de Estudios Superiores del Mayo. Te invitamos a conocer nuestra oferta academica de posgrado y a contactarnos para cualquier duda sobre el proceso de inscripcion.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Seccion: Maestrias
          const _TituloSeccion(titulo: 'Maestrias'),
          const SizedBox(height: 8),
          ...maestrias.map((p) => _ProgramaCard(programa: p)),
          const SizedBox(height: 20),

          // Seccion: Doctorados
          const _TituloSeccion(titulo: 'Doctorados'),
          const SizedBox(height: 8),
          ...doctorados.map((p) => _ProgramaCard(programa: p)),
          const SizedBox(height: 28),

          // Seccion: Contactanos
          const _TituloSeccion(titulo: 'Conoce mas'),
          const SizedBox(height: 12),

          // Boton: Ver convocatorias vigentes
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 1,
            ),
            onPressed: () => Helpers.abrirUrlExterna(convocatoriasUrl, context),
            icon: const Icon(Icons.campaign, size: 22),
            label: const Text(
              'Convocatorias vigentes',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),

          // Boton: WhatsApp Admisiones
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 1,
            ),
            onPressed: () => Helpers.abrirWhatsAppAdmisiones(context),
            icon: const Icon(Icons.chat, size: 22),
            label: const Text(
              'WhatsApp Admisiones',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 10),

          // Boton: Llamar Admisiones
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumGold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 1,
            ),
            onPressed: () => Helpers.llamarPorTelefono(
              context,
              telefonoAdmisiones,
            ),
            icon: const Icon(Icons.phone, size: 22),
            label: Text(
              'Llamar ${telefonoAdmisionesFormateado}',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 24),

          // Pie con razon social
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                razonSocialCompleta,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  final String titulo;

  const _TituloSeccion({required this.titulo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        titulo.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cessumRed,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ProgramaCard extends StatelessWidget {
  final Programa programa;

  const _ProgramaCard({required this.programa});

  @override
  Widget build(BuildContext context) {
    final esMaestria = programa.nivel == 'Maestria';
    final color = esMaestria ? cessumRed : cessumGold;
    final icono = esMaestria ? Icons.school : Icons.workspace_premium;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Helpers.abrirUrlExterna(programa.url, context),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icono, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    programa.nombre,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: color, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

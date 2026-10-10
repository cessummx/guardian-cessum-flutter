import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'acerca_comun.dart';   // (24-sep) bloques compartidos con el Acerca de del alumno
import 'auth/auth_gate.dart';
import 'auth/auth_service.dart';
import 'auth/session_store.dart';
import 'splash_screen.dart';
import 'welcome_screen.dart';
import 'helpers.dart';
import 'teacher_profile.dart';
import 'teacher_setup_screen.dart';

/// «Acerca de» del docente.
///
/// (24-sep) Rehecha sobre los bloques compartidos de acerca_comun.dart:
/// institución, en línea, oferta con RVOE y pie ya no están copiados aquí.
/// Corregidos los textos sin acentos y los colores fijos que se perdían en
/// modo oscuro. «Cerrar sesión» expira también la llave de sesión firmada
/// del servidor (lo hace SessionStore.clear()).
class TeacherAboutScreen extends StatefulWidget {
  const TeacherAboutScreen({super.key});

  @override
  State<TeacherAboutScreen> createState() => _TeacherAboutScreenState();
}

class _TeacherAboutScreenState extends State<TeacherAboutScreen> {
  String _version = '';
  TeacherProfile? _perfil;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version} (build ${info.buildNumber})');
    } catch (_) {
      if (mounted) setState(() => _version = 'v1.0.0');
    }
    final perfil = await TeacherProfile.load();
    if (mounted) setState(() => _perfil = perfil);
  }

  void _volverAlMenu() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _editarPerfil() async {
    final actualizado = await Navigator.push<TeacherProfile?>(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherSetupScreen(esEdicion: true, perfilExistente: _perfil),
      ),
    );
    if (actualizado != null && mounted) {
      setState(() => _perfil = actualizado);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: cessumRed,
          content: Text('Perfil actualizado correctamente'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'Se cerrará tu sesión en este dispositivo y volverás a la pantalla '
          'de inicio de sesión. Tendrás que entrar de nuevo con tu correo '
          'institucional.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    await AuthService.instance.signOut();
    await SessionStore.clear(); // expira también la llave del servidor
    await WelcomeScreen.clearAll();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate(child: SplashScreen())),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Acerca de', style: TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(icon: const Icon(Icons.home), tooltip: 'Inicio', onPressed: _volverAlMenu),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Cabecera con logo y versión
          Center(
            child: Column(
              children: [
                const SizedBox(height: 8),
                Image.asset('assets/images/logo.png', height: 110, fit: BoxFit.contain),
                const SizedBox(height: 16),
                Text(
                  'Portal Docente',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: cessumInk(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  _version.isEmpty ? 'Cargando...' : _version,
                  style: TextStyle(fontSize: 13, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Mi perfil docente (solo si hay perfil guardado)
          if (_perfil != null) ...[
            AcercaSeccion(
              titulo: 'Mi perfil docente',
              children: [
                AcercaFila(icono: Icons.school, texto: _perfil!.saludoCompleto),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed,
                        side: const BorderSide(color: cessumRed),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _editarPerfil,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Editar mi perfil', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

          // Institución: bloque compartido
          const AcercaInstitucion(),
          const SizedBox(height: 20),

          // Soporte (lo propio del docente)
          AcercaSeccion(
            titulo: 'Soporte CESSUM',
            children: [
              AcercaFilaAccion(
                icono: Icons.chat,
                etiqueta: 'WhatsApp de soporte',
                valor: formatoWhatsApp(whatsappNumero), // de la constante, no escrito a mano
                color: const Color(0xFF25D366),
                onTap: () => Helpers.abrirWhatsApp(context),
              ),
              AcercaFilaAccion(
                icono: Icons.email,
                etiqueta: 'Correo',
                valor: correoInstitucional,
                color: cessumRed,
                onTap: () => Helpers.abrirCorreo(
                  context: context,
                  destinatario: correoInstitucional,
                  asunto: 'Consulta docente - Aula CESSUM',
                  cuerpo: '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // En línea y oferta académica con RVOE: bloques compartidos
          const AcercaEnLinea(),
          const SizedBox(height: 20),
          const AcercaOferta(),
          const SizedBox(height: 20),

          // Sesión
          AcercaSeccion(
            titulo: 'Sesión',
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      side: const BorderSide(color: cessumRed),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _cerrarSesion,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Cerrar sesión', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          const AcercaPie(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

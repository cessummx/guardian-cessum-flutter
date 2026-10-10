import 'package:flutter/material.dart';

import 'active_profile.dart';
import 'admin_config.dart';
import 'admin_preview_screen.dart';
import 'auth/session_store.dart';
import 'constants.dart';
import 'menu_screen.dart';
import 'new_user_screen.dart';
import 'roles_service.dart';
import 'student_profile.dart';
import 'teacher_menu_screen.dart';
import 'teacher_profile.dart';
import 'version_check.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _esAdmin = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final minDelay = Future.delayed(const Duration(seconds: 2));
    final versionFuture = VersionChecker.check();
    final activeFuture = ActiveProfile.getActive();
    final studentFuture = StudentProfile.load();
    final teacherFuture = TeacherProfile.load();
    final correoFuture = SessionStore.validEmail();

    await minDelay;
    final versionInfo = await versionFuture;
    final active = await activeFuture;
    final student = await studentFuture;
    final teacher = await teacherFuture;
    final correo = await correoFuture;
    await RolesService.precargar();
    _esAdmin = esAdmin(correo);

    if (!mounted) return;

    if (versionInfo != null && versionInfo.updateRequired) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UpdateRequiredScreen(info: versionInfo),
        ),
      );
      return;
    }

    if (versionInfo != null && versionInfo.updateAvailable) {
      _showOptionalUpdateDialog(versionInfo, active, student, teacher);
      return;
    }

    _goNext(active, student, teacher);
  }

  void _showOptionalUpdateDialog(
    VersionInfo info,
    ProfileType? active,
    StudentProfile? student,
    TeacherProfile? teacher,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva version disponible'),
        content: Text(
          info.message.isNotEmpty
              ? info.message
              : 'Hay una nueva version del Aula CESSUM. Te recomendamos actualizar.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _goNext(active, student, teacher);
            },
            child: const Text('Despues'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _goNext(active, student, teacher);
            },
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
  }

  // Logica de navegacion:
  // - Si el ultimo perfil activo fue STUDENT y tiene perfil completo: al menu de estudiante
  // - Si el ultimo perfil activo fue TEACHER y tiene perfil completo: al menu de docente
  // - Si el ultimo perfil activo fue VISITOR: a NewUserScreen
  // - En cualquier otro caso: WelcomeScreen
  void _goNext(
    ProfileType? active,
    StudentProfile? student,
    TeacherProfile? teacher,
  ) {
    // Administrador: SIEMPRE al panel de administrador, sin importar el ultimo
    // perfil usado. Asi puede saltar entre alumnos recargando y nunca queda
    // atrapado en la vista de un alumno.
    if (_esAdmin) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminPreviewScreen()),
      );
      return;
    }

    Widget destino;

    switch (active) {
      case ProfileType.student:
        destino = student != null ? const MenuScreen() : const WelcomeScreen();
        break;
      case ProfileType.teacher:
        destino =
            teacher != null ? const TeacherMenuScreen() : const WelcomeScreen();
        break;
      case ProfileType.visitor:
        destino = const NewUserScreen();
        break;
      case null:
        // Si es un correo de administrador y aun no ha elegido perfil,
        // lo llevamos directo a la Vista de administrador.
        destino =
            _esAdmin ? const AdminPreviewScreen() : const WelcomeScreen();
        break;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destino),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F1E8),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon/logo_completo.png',
                width: 300,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: cessumRed,
                  strokeWidth: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpdateRequiredScreen extends StatelessWidget {
  final VersionInfo info;

  const UpdateRequiredScreen({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F1E8),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/icon/icon.png',
                  height: 140,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 32),
                const Text(
                  'Actualizacion requerida',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  info.message.isNotEmpty
                      ? info.message
                      : 'Para continuar usando Aula CESSUM debes actualizar a la version mas reciente.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 32),
                Text(
                  'Tu version: ${info.currentVersion}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                Text(
                  'Version requerida: ${info.latestVersion}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {},
                  child: const Text(
                    'Actualizar ahora',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
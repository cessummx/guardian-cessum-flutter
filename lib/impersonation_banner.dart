import 'package:flutter/material.dart';

import 'constants.dart';
import 'active_profile.dart';
import 'teacher_profile.dart';
import 'welcome_screen.dart';
import 'auth/session_store.dart';

/// Llave del navegador raíz. La usa el banner para poder "Salir" del modo
/// "Ver como profesor" desde cualquier pantalla (el banner vive por encima
/// del Navigator, así que necesita esta llave para controlarlo).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Franja superior que se muestra en TODA la app mientras un administrador
/// está viendo la plataforma "como" un profesor. Trae el botón "Salir" para
/// volver a la identidad real en un toque. Se envuelve la app en main.dart
/// (MaterialApp.builder), por eso aparece sobre cualquier pantalla.
class ImpersonationBanner extends StatelessWidget {
  final Widget child;
  const ImpersonationBanner({super.key, required this.child});

  Future<void> _salir() async {
    // Cancela la suplantación y limpia el perfil de docente de la vista previa.
    await SessionStore.stopImpersonation();
    await TeacherProfile.clear();
    await ActiveProfile.clear();
    // Regresa al inicio; allí se vuelve a resolver el rol con tu correo real
    // (administrador) y te lleva a tu vista normal.
    rootNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: SessionStore.impersonation,
      builder: (context, correo, _) {
        final activo = correo != null && correo.isNotEmpty;
        if (!activo) return child;
        return Column(
          children: [
            Material(
              color: cessumGold,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FutureBuilder<String?>(
                          future: SessionStore.impersonatedName(),
                          builder: (context, snap) {
                            final etiqueta =
                                (snap.data != null && snap.data!.isNotEmpty)
                                    ? snap.data!
                                    : correo;
                            return Text(
                              'Estás viendo como: $etiqueta',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        onPressed: _salir,
                        icon: const Icon(Icons.logout,
                            size: 16, color: Colors.white),
                        label: const Text(
                          'Salir',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

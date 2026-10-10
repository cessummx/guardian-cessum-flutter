import 'package:flutter/material.dart';

import 'asistente_alumno_screen.dart';
import 'constants.dart';
import 'student_profile.dart';

/// Botón flotante de Ayuda. Abre el Asistente CESSUM desde cualquier pantalla.
/// Úsalo en el Scaffold de la pantalla:  floatingActionButton: AyudaFab(perfil: _perfil),
class AyudaFab extends StatelessWidget {
  final StudentProfile? perfil;
  const AyudaFab({super.key, this.perfil});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: 'ayuda_cessum',
      backgroundColor: cessumGold,
      foregroundColor: Colors.white,
      tooltip: 'Ayuda',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AsistenteAlumnoScreen(perfil: perfil),
        ),
      ),
      child: const Icon(Icons.help_outline),
    );
  }
}

/// Variante extendida (ícono + texto "Ayuda"), útil en pantallas amplias.
class AyudaFabExtendido extends StatelessWidget {
  final StudentProfile? perfil;
  const AyudaFabExtendido({super.key, this.perfil});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'ayuda_cessum_ext',
      backgroundColor: cessumGold,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.help_outline),
      label: const Text('Ayuda'),
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AsistenteAlumnoScreen(perfil: perfil),
        ),
      ),
    );
  }
}

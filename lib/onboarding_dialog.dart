import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

/// Tour de bienvenida del alumno. Se muestra automáticamente la primera vez
/// (marca en SharedPreferences) y también puede abrirse a voluntad desde el
/// menú con [mostrarOnboardingAhora].

/// Muestra el tour SOLO la primera vez (o una vez tras la actualización v2).
Future<void> mostrarOnboardingSiAplica(
    BuildContext context, StudentProfile? perfil) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('onboarding_visto_v2') == true) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OnboardingDialog(nombre: perfil?.nombreCompleto ?? ''),
    );
    await prefs.setBool('onboarding_visto_v2', true);
  } catch (_) {
    // Si algo falla, simplemente no se muestra el tour.
  }
}

/// Abre el tour de bienvenida a petición del alumno (botón "Guía de
/// bienvenida"), sin importar si ya lo había visto.
Future<void> mostrarOnboardingAhora(
    BuildContext context, StudentProfile? perfil) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _OnboardingDialog(nombre: perfil?.nombreCompleto ?? ''),
  );
}

class _Paso {
  final IconData icono;
  final String titulo;
  final String texto;
  const _Paso(this.icono, this.titulo, this.texto);
}

class _OnboardingDialog extends StatefulWidget {
  final String nombre;
  const _OnboardingDialog({required this.nombre});

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  final _pc = PageController();
  int _i = 0;

  late final List<_Paso> _pasos = [
    _Paso(
      Icons.waving_hand,
      widget.nombre.trim().isEmpty
          ? '¡Bienvenido(a) a Aula CESSUM!'
          : '¡Hola, ${widget.nombre.split(' ').first}!',
      'Este es tu portal del estudiante. En un minuto te mostramos lo esencial '
          'para que lo aproveches desde el primer día. Puedes tocar "Saltar" '
          'cuando quieras.',
    ),
    const _Paso(
      Icons.badge,
      'Tu credencial digital',
      'Desde el menú, en "Mi credencial", tienes tu identificación con tu CURP '
          'y un código QR. Lista para cuando necesites identificarte.',
    ),
    const _Paso(
      Icons.grade,
      'Calificaciones y boleta',
      'Consulta tus materias y calificaciones validadas, y descarga tu boleta '
          'cuando la necesites, todo desde el menú principal.',
    ),
    const _Paso(
      Icons.donut_large,
      'Tu avance del plan',
      'En "Mi avance del plan" ves cuánto llevas de tu programa: materias '
          'aprobadas, créditos, tu promedio y lo que te falta por cursar.',
    ),
    const _Paso(
      Icons.account_balance_wallet,
      'Tus pagos, claros',
      'En "Mis pagos" ves cuánto te toca pagar al mes (con tu beca aplicada si '
          'la tienes) y el historial de lo que has pagado.',
    ),
    const _Paso(
      Icons.event_note,
      'Organízate',
      'Usa "Mis recordatorios" y "Mi horario" para no perder ninguna entrega '
          'ni clase. Tú agregas tus recordatorios de tareas, clases o pagos.',
    ),
    const _Paso(
      Icons.support_agent,
      '¿Dudas? Te atendemos',
      'Levanta una solicitud en la Mesa de ayuda (con folio y seguimiento) o '
          'usa el botón de ayuda para resolver tus preguntas al momento.',
    ),
    const _Paso(
      Icons.card_giftcard,
      'Recomienda y gana',
      'Comparte tu código de "Recomienda y gana": tu recomendado paga menos en '
          'su inscripción y tú recibes una bonificación para tu colegiatura.',
    ),
    const _Paso(
      Icons.photo_camera,
      'Completa tu perfil',
      'Sube tu foto en "Mi panel" (toca tu avatar). Así quedará lista para tu '
          'credencial y tus documentos, sin volver a subirla.',
    ),
  ];

  bool get _ultimo => _i == _pasos.length - 1;

  void _siguiente() {
    if (_ultimo) {
      Navigator.of(context).pop();
    } else {
      _pc.nextPage(
          duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 22),
            SizedBox(
              height: 250,
              child: PageView.builder(
                controller: _pc,
                itemCount: _pasos.length,
                onPageChanged: (v) => setState(() => _i = v),
                itemBuilder: (_, idx) {
                  final p = _pasos[idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 38,
                          backgroundColor: cessumRed.withValues(alpha: 0.10),
                          child: Icon(p.icono, size: 38, color: cessumRed),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          p.titulo,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: cessumRed),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          p.texto,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: cessumInk(context)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pasos.length, (k) {
                final activo = k == _i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: activo ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: activo ? cessumGold : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Row(
                children: [
                  if (!_ultimo)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Saltar',
                          style: TextStyle(color: cessumMuted(context))),
                    ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _siguiente,
                    child: Text(_ultimo ? 'Comenzar' : 'Siguiente',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';


/// Kit de microinteracciones CESSUM (reutilizable en toda la app).
///
/// - CessumPressable: hunde suavemente cualquier tarjeta/botón al tocarlo.
/// - cessumFadeRoute: navegación con desvanecido + leve deslizamiento.
/// - cessumExito: confirmación con un "check" animado.

/// Envuelve un widget para que reaccione al tacto con una escala suave.
class CessumPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  const CessumPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.97,
  });

  @override
  State<CessumPressable> createState() => _CessumPressableState();
}

class _CessumPressableState extends State<CessumPressable> {
  bool _down = false;

  void _set(bool v) {
    if (mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scaleDown : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Ruta de navegación con desvanecido suave y un leve empuje hacia arriba.
Route<T> cessumFadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, animation, __) => page,
    transitionsBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Muestra una confirmación con un check animado que se cierra solo.
Future<void> cessumExito(
  BuildContext context,
  String mensaje, {
  Duration duracion = const Duration(milliseconds: 1500),
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black54,
    builder: (_) => _ExitoDialog(mensaje: mensaje),
  );
  await Future.delayed(duracion);
  if (context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}

class _ExitoDialog extends StatelessWidget {
  final String mensaje;
  const _ExitoDialog({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 450),
              curve: Curves.elasticOut,
              builder: (_, v, __) => Transform.scale(
                scale: v,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E8E3E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 36),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

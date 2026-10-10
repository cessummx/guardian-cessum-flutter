import 'package:flutter/material.dart';

import 'constants.dart';
import 'cessum_ui.dart';

/// Estado vacío reutilizable de CESSUM, con el venado MAASO y un mensaje
/// amable. Si el asset del venado no existe, muestra un ícono de respaldo
/// (nunca se ve roto).
///
/// Uso:
///   CessumVacio(
///     titulo: 'Sin trámites por ahora',
///     mensaje: 'Cuando solicites uno, aparecerá aquí.',
///     iconoFallback: Icons.assignment_outlined,
///   )
class CessumVacio extends StatelessWidget {
  final String titulo;
  final String mensaje;
  final IconData iconoFallback;
  final String assetMaaso;
  final Widget? accion;
  final double tamano;

  const CessumVacio({
    super.key,
    required this.titulo,
    this.mensaje = '',
    this.iconoFallback = Icons.inbox_outlined,
    this.assetMaaso = 'assets/images/maaso.png',
    this.accion,
    this.tamano = 130,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ilustracion(),
            const SizedBox(height: 18),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: cessumInk(context),
              ),
            ),
            if (mensaje.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.35, color: cessumMuted(context)),
              ),
            ],
            if (accion != null) ...[
              const SizedBox(height: 18),
              accion!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _ilustracion() {
    // Intenta el venado; si no carga, círculo hueso con el ícono de respaldo.
    return Image.asset(
      assetMaaso,
      width: tamano,
      height: tamano,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.10),
          shape: BoxShape.circle,
        ),
        child: Icon(iconoFallback, size: tamano * 0.42, color: cessumGold),
      ),
    );
  }
}

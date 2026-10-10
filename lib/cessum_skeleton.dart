import 'package:flutter/material.dart';

/// Kit de "skeletons" de carga CESSUM (reutilizable).
/// Bloques grises con efecto shimmer que ocupan la forma del contenido
/// mientras llegan los datos, en lugar del círculo girando.
///
/// Uso básico:
///   const CessumSkeleton(height: 16, width: 140)
/// Lista de filas:
///   const CessumSkeletonLista(filas: 5)

class _DeslizarGradiente extends GradientTransform {
  final double porcentaje;
  const _DeslizarGradiente(this.porcentaje);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * porcentaje, 0, 0);
  }
}

/// Bloque base con animación shimmer.
class CessumSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const CessumSkeleton({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 8,
  });

  @override
  State<CessumSkeleton> createState() => _CessumSkeletonState();
}

class _CessumSkeletonState extends State<CessumSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final p = _c.value * 2 - 1; // de -1 a 1
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: const [
                Color(0xFFE9E7E2),
                Color(0xFFF6F4EF),
                Color(0xFFE9E7E2),
              ],
              stops: const [0.30, 0.50, 0.70],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _DeslizarGradiente(p),
            ),
          ),
        );
      },
    );
  }
}

/// Fila tipo "acceso": círculo + dos líneas. Imita una tarjeta de lista.
class CessumSkeletonFila extends StatelessWidget {
  const CessumSkeletonFila({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: const [
          CessumSkeleton(width: 42, height: 42, radius: 10),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CessumSkeleton(width: 160, height: 13),
                SizedBox(height: 8),
                CessumSkeleton(width: 100, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Varias filas seguidas.
class CessumSkeletonLista extends StatelessWidget {
  final int filas;
  const CessumSkeletonLista({super.key, this.filas = 5});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(filas, (_) => const CessumSkeletonFila()),
      ),
    );
  }
}

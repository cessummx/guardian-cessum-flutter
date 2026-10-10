import 'package:flutter/material.dart';

import 'constants.dart';

/// Indicador de carga con la mascota MAASO. La mascota "respira" (sube y baja
/// suavemente) mientras se cargan los datos. Úsalo en lugar de un
/// CircularProgressIndicator cuando quieras un toque de marca:
///   body: _cargando ? const CargandoVenado() : contenido
class CargandoVenado extends StatefulWidget {
  final String mensaje;
  final double tamano;
  const CargandoVenado({
    super.key,
    this.mensaje = 'Cargando…',
    this.tamano = 120,
  });

  @override
  State<CargandoVenado> createState() => _CargandoVenadoState();
}

class _CargandoVenadoState extends State<CargandoVenado>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _sube;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _sube = Tween<double>(begin: 0, end: -12).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _sube,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, _sube.value),
              child: child,
            ),
            child: Image.asset(
              'assets/images/maaso.png',
              height: widget.tamano,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 130,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: Color(0x33B8842C),
                valueColor: AlwaysStoppedAnimation<Color>(cessumGold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            widget.mensaje,
            style: const TextStyle(
              color: cessumGold,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

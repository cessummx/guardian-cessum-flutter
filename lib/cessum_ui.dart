// =====================================================================
//  cessum_ui.dart  ·  Kit de interfaz CESSUM
//  Componentes reutilizables para todas las mejoras estéticas:
//   - CC            : colores de marca
//   - CessumType    : tipografía (Playfair display + Montserrat cuerpo)
//   - Pressable     : micro-animación de "hundido" al tocar
//   - Skeleton      : cargadores tipo esqueleto (en vez de la ruedita)
//   - CessumEmptyState : estados vacíos con personalidad (venado MAASO)
//   - StatRing      : anillo de progreso (créditos, avance)
//   - GradeChip     : chip de color por estatus de calificación
//   - FlipCard      : tarjeta que se voltea (para la credencial)
//
//  Este archivo es ADITIVO: no toca tu lógica. Importa lo que necesites:
//     import 'cessum_ui.dart';
// =====================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Colores de marca CESSUM.
class CC {
  static const Color red = Color(0xFFB11D29);
  static const Color redAlt = Color(0xFFC8202F);
  static const Color gold = Color(0xFFB8842C);
  static const Color goldDark = Color(0xFFA56B16);
  static const Color hueso = Color(0xFFF5F1E8);
  static const Color ink = Color(0xFF2A2A2A);
  static const Color muted = Color(0xFF8A8A85);

  // Tintes suaves para fondos de iconos / tarjetas.
  static const Color redSoft = Color(0xFFFBE9EB);
  static const Color goldSoft = Color(0xFFF4ECDD);
  static const Color goldCard = Color(0xFFFBF1DC);
  static const Color goldBorder = Color(0xFFE7C98A);
}

/// Color de fondo de pantalla que respeta el tema: claro en modo claro,
/// oscuro en modo oscuro. Uso: Scaffold(backgroundColor: cessumBg(context)).
Color cessumBg(BuildContext context,
    [Color claro = const Color(0xFFF7F7F7)]) {
  return Theme.of(context).brightness == Brightness.dark
      ? Theme.of(context).scaffoldBackgroundColor
      : claro;
}

/// ¿La app está en modo oscuro? Atajo legible.
bool cessumEsOscuro(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Alias de [cessumEsOscuro] con nombre en inglés, usado por varias pantallas.
bool cessumIsDark(BuildContext context) => cessumEsOscuro(context);

/// Color de TEXTO PRINCIPAL que respeta el tema: oscuro en modo claro,
/// blanco en modo oscuro. Úsalo SOLO en textos que van directamente sobre el
/// fondo de la pantalla (no en textos dentro de tarjetas blancas, que deben
/// seguir oscuros). Uso: Text('Hola', style: TextStyle(color: cessumInk(context))).
Color cessumInk(BuildContext context, [Color claro = CC.ink]) =>
    cessumEsOscuro(context) ? Colors.white : claro;

/// Color de TEXTO SECUNDARIO / atenuado que respeta el tema.
Color cessumMuted(BuildContext context, [Color claro = CC.muted]) =>
    cessumEsOscuro(context) ? Colors.white70 : claro;

/// Color de TEXTO/ICONO MUY TENUE (pistas, chevrons, marcas de agua) que
/// respeta el tema. Negro tenue en claro; blanco tenue en oscuro.
Color cessumFaint(BuildContext context) =>
    cessumEsOscuro(context) ? Colors.white38 : Colors.black38;

/// Tipografía con jerarquía: Playfair Display para títulos/números grandes,
/// Montserrat para el cuerpo. Usa: `Text('9.4', style: CessumType.display(28))`.
class CessumType {
  static TextStyle display(double size,
          {Color color = CC.ink, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.playfairDisplay(
          fontSize: size, fontWeight: weight, color: color, height: 1.1);

  static TextStyle heading(double size,
          {Color color = CC.ink, FontWeight weight = FontWeight.w700}) =>
      GoogleFonts.montserrat(
          fontSize: size, fontWeight: weight, color: color, height: 1.2);

  static TextStyle body(double size,
          {Color color = CC.ink, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.montserrat(
          fontSize: size, fontWeight: weight, color: color, height: 1.35);

  static TextStyle label(double size, {Color color = CC.muted}) =>
      GoogleFonts.montserrat(
          fontSize: size, fontWeight: FontWeight.w500, color: color);
}

// ---------------------------------------------------------------------
//  Pressable: envuelve cualquier widget para que "se hunda" al tocarlo.
// ---------------------------------------------------------------------
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  void _set(bool v) {
    if (v && widget.haptic) HapticFeedback.selectionClick();
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
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Skeleton: cargadores tipo esqueleto con pulso suave.
//  Usa Skeleton(width: 120, height: 16) como bloques mientras carga.
// ---------------------------------------------------------------------
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const Skeleton(
      {super.key, this.width, this.height = 14, this.radius = 8});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF3A3A38) : const Color(0xFFD9D6CE);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = 0.35 + (_c.value * 0.45);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: t),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Esqueleto prearmado con forma de tarjeta (icono + 2 líneas).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Skeleton(width: 40, height: 40, radius: 12),
          SizedBox(height: 12),
          Skeleton(width: 140, height: 12),
          SizedBox(height: 8),
          Skeleton(width: 90, height: 12),
        ],
      ),
    );
  }
}

/// Lista de esqueletos lista para usar como pantalla de carga.
/// Uso: `body: _cargando ? const CessumSkeletonList() : ...`
class CessumSkeletonList extends StatelessWidget {
  final int count;
  const CessumSkeletonList({super.key, this.count = 5});
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => const SkeletonCard(),
    );
  }
}

// ---------------------------------------------------------------------
//  CessumEmptyState: estado vacío con personalidad.
//  Pasa svgAsset (el venado MAASO) o deja el icono por defecto.
// ---------------------------------------------------------------------
class CessumEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? svgAsset;
  final Widget? action;
  const CessumEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_rounded,
    this.svgAsset,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleC = isDark ? Colors.white : CC.ink;
    final subC = isDark ? Colors.white70 : CC.muted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 116,
              height: 116,
              decoration: const BoxDecoration(
                  color: CC.goldCard, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: svgAsset != null
                  ? SvgPicture.asset(svgAsset!, width: 64, height: 64)
                  : Icon(icon, size: 52, color: CC.gold),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: CessumType.heading(17, color: titleC)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: CessumType.body(13, color: subC)),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  StatRing: anillo de progreso (0..1) con texto al centro.
// ---------------------------------------------------------------------
class StatRing extends StatelessWidget {
  final double value; // 0..1
  final String centerText;
  final String? label;
  final Color color;
  final double size;
  const StatRing({
    super.key,
    required this.value,
    required this.centerText,
    this.label,
    this.color = CC.red,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final centerC = isDark ? Colors.white : CC.ink;
    final labelC = isDark ? Colors.white70 : CC.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(value.clamp(0.0, 1.0).toDouble(), color),
            child: Center(
              child: Text(centerText,
                  style: CessumType.display(size * 0.26, color: centerC)),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(label!, style: CessumType.label(12, color: labelC)),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;
  _RingPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = (size.shortestSide / 2) - 7;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = color.withValues(alpha: 0.14)
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = color
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, track);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        2 * math.pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

// ---------------------------------------------------------------------
//  GradeChip: chip de color según estatus de calificación.
// ---------------------------------------------------------------------
class GradeChip extends StatelessWidget {
  final String estatus;
  const GradeChip(this.estatus, {super.key});

  @override
  Widget build(BuildContext context) {
    final e = estatus.toLowerCase();
    late Color bg, fg;
    late String txt;
    if (e.contains('valid') && !e.contains('en valid')) {
      bg = const Color(0xFFE1F5EE);
      fg = const Color(0xFF0F6E56);
      txt = 'Validada';
    } else if (e.contains('valid')) {
      bg = const Color(0xFFFAEEDA);
      fg = const Color(0xFF854F0B);
      txt = 'En validación';
    } else if (e.contains('reprob') || e.contains('no acred')) {
      bg = const Color(0xFFFCEBEB);
      fg = const Color(0xFFA32D2D);
      txt = 'Reprobada';
    } else if (e.contains('aprob') || e.contains('acred')) {
      bg = const Color(0xFFEAF3DE);
      fg = const Color(0xFF3B6D11);
      txt = 'Aprobada';
    } else {
      bg = const Color(0xFFF1EFE8);
      fg = const Color(0xFF5F5E5A);
      txt = estatus;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(txt,
          style: GoogleFonts.montserrat(
              fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

// ---------------------------------------------------------------------
//  FlipCard: tap para voltear (frente/reverso). Para la credencial.
// ---------------------------------------------------------------------
class FlipCard extends StatefulWidget {
  final Widget front;
  final Widget back;
  const FlipCard({super.key, required this.front, required this.back});

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  bool _showFront = true;

  void _flip() {
    if (_showFront) {
      _c.forward();
    } else {
      _c.reverse();
    }
    _showFront = !_showFront;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final angle = _c.value * math.pi;
          final isFront = angle <= math.pi / 2;
          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle);
          return Transform(
            alignment: Alignment.center,
            transform: m,
            child: isFront
                ? widget.front
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(math.pi),
                    child: widget.back,
                  ),
          );
        },
      ),
    );
  }
}

/// (ago-5) LÍNEA DE TIEMPO INSTITUCIONAL ✓/○ — el mismo lenguaje visual del
/// kit de correos (correoTimeline_), ahora como widget compartido: puntos
/// verdes (hecho), guinda (paso actual) y grises (por venir), unidos por un
/// hilo vertical. Úsalo para titulación, envíos, convenios o cualquier
/// proceso por etapas. hitos: [{titulo, fecha?, hecho: bool, actual: bool}].
class TimelineCessum extends StatelessWidget {
  final List<Map<String, dynamic>> hitos;
  const TimelineCessum({super.key, required this.hitos});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < hitos.length; i++) _hito(i),
      ],
    );
  }

  Widget _hito(int i) {
    final h = hitos[i];
    final hecho = h['hecho'] == true;
    final actual = h['actual'] == true;
    final col = hecho
        ? const Color(0xFF1E8E3E)
        : (actual ? const Color(0xFFB11D29) : const Color(0xFFC9C2B4));
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (hecho || actual) ? col : Colors.white,
                    border: Border.all(color: col, width: 2.5),
                  ),
                ),
                if (i < hitos.length - 1)
                  Expanded(
                    child: Container(
                        width: 2, color: const Color(0xFFDDD5C6)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: i < hitos.length - 1 ? 14 : 0, top: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${h['titulo']}',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.25,
                          fontWeight:
                              actual ? FontWeight.w800 : FontWeight.w700,
                          color: hecho
                              ? const Color(0xFF1B5E20)
                              : (actual
                                  ? const Color(0xFFB11D29)
                                  : const Color(0xFF9A9A9A)))),
                  if ('${h['fecha'] ?? ''}'.isNotEmpty)
                    Text('${h['fecha']}',
                        style: const TextStyle(
                            fontSize: 10.5, color: Color(0xFF9A9A9A))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

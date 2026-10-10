import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  MESA DE AYUDA · PAGOS  (sep-2026)
//
//  Dos piezas en este archivo:
//   1) El MOTOR DE ANÁLISIS de pagos (analizarPagos): revisa el historial, la
//      colegiatura y el estado de cuenta, y devuelve hallazgos ordenados por
//      gravedad. Corre en el dispositivo, sin red y sin claves: todo lo que
//      afirma sale de los datos que ya trae la pantalla.
//   2) La pantalla MesaAyudaPagosScreen: el alumno elige qué está mal, describe
//      el caso y lo envía por WhatsApp (Atención a Estudiantes) o por correo,
//      con sus datos y lo que ve su app ya adjuntos.
// ═══════════════════════════════════════════════════════════════════════════

const String correoMesaAyudaPagos = 'contacto@cessum.mx';

// ─── Utilidades de datos ────────────────────────────────────────────────────

/// Convierte montos que llegan como número o como texto («$1,350.00»).
num montoCessum(dynamic v) {
  if (v is num) return v;
  final s = (v ?? '').toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
  return num.tryParse(s) ?? 0;
}

/// Formato de pesos sin decimales: $1,350.
String pesosCessum(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}\$$b';
}

const List<String> _mesesEs = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
  'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
];

const Map<String, int> _mesesEn = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// Lee las fechas en los formatos que manda el Guardián: ISO (2026-10-15),
/// dd/MM/yyyy (con o sin hora), texto largo de JavaScript
/// («Thu Oct 15 2026 00:00:00 GMT-0700») y «15 de octubre de 2026».
DateTime? fechaCessum(dynamic v) {
  final t = (v ?? '').toString().trim();
  if (t.isEmpty) return null;
  final iso = DateTime.tryParse(t);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);
  final dmy = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(t);
  if (dmy != null) {
    final d = int.parse(dmy.group(1)!);
    final m = int.parse(dmy.group(2)!);
    final y = int.parse(dmy.group(3)!);
    if (m >= 1 && m <= 12 && d >= 1 && d <= 31) return DateTime(y, m, d);
  }
  final js = RegExp(r'([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})').firstMatch(t);
  if (js != null) {
    final m = _mesesEn[js.group(1)!.toLowerCase()];
    if (m != null) {
      return DateTime(int.parse(js.group(3)!), m, int.parse(js.group(2)!));
    }
  }
  final es = RegExp(r'(\d{1,2})\s+de\s+([a-záéíóú]+)\s+(?:de\s+)?(\d{4})',
          caseSensitive: false)
      .firstMatch(t);
  if (es != null) {
    final idx = _mesesEs.indexOf(es.group(2)!.toLowerCase());
    if (idx >= 0) {
      return DateTime(int.parse(es.group(3)!), idx + 1, int.parse(es.group(1)!));
    }
  }
  return null;
}

/// «jueves 15 de octubre de 2026».
String fechaLargaCessum(DateTime d) {
  const dias = [
    'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'
  ];
  return '${dias[d.weekday - 1]} ${d.day} de ${_mesesEs[d.month - 1]} de ${d.year}';
}

/// «octubre de 2026».
String mesAnioCessum(DateTime d) => '${_mesesEs[d.month - 1]} de ${d.year}';

List<Map<String, dynamic>> listaMapasCessum(dynamic v) =>
    ((v as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

bool _esPorValidar(Map<String, dynamic> p) =>
    (p['estatus'] ?? '').toString().toLowerCase() == 'por validar';

/// El vencimiento más próximo (hoy o después) de una lista del Guardián.
Map<String, dynamic>? proximoVencimientoCessum(
    List<Map<String, dynamic>> lista, DateTime hoy) {
  Map<String, dynamic>? mejor;
  DateTime? mejorF;
  for (final p in lista) {
    final f = fechaCessum(p['fechaLimite']);
    if (f == null || f.isBefore(hoy)) continue;
    if (mejorF == null || f.isBefore(mejorF)) {
      mejor = p;
      mejorF = f;
    }
  }
  return mejor;
}

// ─── Motor de análisis ──────────────────────────────────────────────────────

enum NivelHallazgo { alerta, aviso, info, ok }

class HallazgoPago {
  final NivelHallazgo nivel;
  final String titulo;
  final String detalle;

  /// Si el hallazgo amerita reporte, la clave del motivo de la mesa de ayuda.
  final String? motivoAyuda;

  const HallazgoPago(this.nivel, this.titulo, this.detalle, [this.motivoAyuda]);
}

/// Revisa los datos de pago y devuelve hallazgos ordenados de más a menos
/// grave. No inventa nada: si un dato no viene, esa revisión se omite.
List<HallazgoPago> analizarPagos({
  required List<Map<String, dynamic>> pagos,
  required num montoMensual,
  num montoConBono = 0,
  String modoPago = 'mensual',
  bool esBeca = false,
  num porcentajeBeca = 0,
  bool montoDesconocido = false,
  Map<String, dynamic>? adeudo,
  DateTime? hoy,
}) {
  final h = <HallazgoPago>[];
  final ahora = hoy ?? DateTime.now();
  final hoyD = DateTime(ahora.year, ahora.month, ahora.day);

  if (montoDesconocido) {
    h.add(const HallazgoPago(
        NivelHallazgo.aviso,
        'Tu colegiatura no se pudo calcular automáticamente',
        'No encontramos una tarifa registrada para tu programa y generación. '
            'Repórtalo para que Administración y Finanzas la confirme.',
        'monto'));
  }

  // 1. Estado de cuenta oficial (adeudo_estado).
  final porValidar = pagos.where(_esPorValidar).length;
  if (adeudo != null) {
    final des = Map<String, dynamic>.from(
        (adeudo['desglose'] as Map?) ?? const <String, dynamic>{});
    final venc = listaMapasCessum(des['vencidos']);
    final pv = listaMapasCessum(des['porVencer']);
    if (venc.isNotEmpty) {
      final total = venc.fold<num>(0, (s, p) => s + montoCessum(p['monto']));
      h.add(HallazgoPago(
          NivelHallazgo.alerta,
          venc.length == 1
              ? 'Tienes 1 pago vencido'
              : 'Tienes ${venc.length} pagos vencidos',
          '${total > 0 ? 'Suman ${pesosCessum(total)}, sin contar recargos. ' : ''}'
              'Si ya pagaste y aquí no aparece, repórtalo con tu comprobante.',
          'adeudo'));
      if (porValidar > 0) {
        h.add(HallazgoPago(
            NivelHallazgo.info,
            porValidar == 1
                ? 'Tienes 1 pago en revisión'
                : 'Tienes $porValidar pagos en revisión',
            'Si corresponden a lo vencido, tu estado de cuenta se ajusta en '
                'cuanto se validen.'));
      }
    } else {
      final prox = proximoVencimientoCessum(pv, hoyD);
      if (prox != null) {
        final f = fechaCessum(prox['fechaLimite'])!;
        final m = montoCessum(prox['monto']);
        h.add(HallazgoPago(
            NivelHallazgo.info,
            'Próximo pago: ${prox['concepto'] ?? 'colegiatura'}',
            'Fecha límite: ${fechaLargaCessum(f)}'
                '${m > 0 ? '. Monto: ${pesosCessum(m)}' : ''}.'));
      } else if (adeudo['alDia'] == true) {
        h.add(const HallazgoPago(
            NivelHallazgo.ok,
            'Sin pagos pendientes',
            'Tu estado de cuenta no registra adeudos vencidos ni pagos próximos.'));
      }
    }
  }

  // 2. Pagos que llevan mucho tiempo en revisión.
  int viejos = 0;
  for (final p in pagos.where(_esPorValidar)) {
    final f = fechaCessum(p['fecha']);
    if (f != null && hoyD.difference(f).inDays > 7) viejos++;
  }
  if (viejos > 0) {
    h.add(HallazgoPago(
        NivelHallazgo.aviso,
        viejos == 1
            ? 'Un pago lleva más de una semana en revisión'
            : '$viejos pagos llevan más de una semana en revisión',
        'Normalmente se validan en pocos días. Repórtalo con tu comprobante '
            'a la mano para que lo revisen.',
        'no_aparece'));
  }

  // 3. Análisis de colegiaturas (solo esquema mensual con monto conocido).
  if (modoPago == 'mensual' && montoMensual > 0 && !montoDesconocido) {
    final mats = <MapEntry<DateTime, num>>[];
    for (final p in pagos) {
      if ((p['tipo'] ?? '').toString() != 'Materia') continue;
      final f = fechaCessum(p['fecha']);
      final m = montoCessum(p['monto']);
      if (f != null && m > 0) mats.add(MapEntry(f, m));
    }
    mats.sort((a, b) => a.key.compareTo(b.key));

    if (mats.isEmpty) {
      if (adeudo == null || adeudo['alDia'] == true) {
        h.add(const HallazgoPago(
            NivelHallazgo.info,
            'Aún no tienes colegiaturas registradas',
            'Cada mensualidad se cubre del 1 al 15 del mes que corresponde. '
                'Después del día 15 aplica un recargo del 5%.'));
      }
    } else {
      // Puntualidad.
      final puntuales = mats.where((e) => e.key.day <= 15).length;
      if (mats.length >= 2) {
        h.add(HallazgoPago(
            puntuales == mats.length ? NivelHallazgo.ok : NivelHallazgo.info,
            'Puntualidad: $puntuales de ${mats.length} pagos entre el 1 y el 15',
            puntuales == mats.length
                ? 'Todos tus pagos se registraron dentro del plazo sin recargo.'
                : 'Los pagos registrados después del día 15 llevan recargo del 5%.'));
      }

      // Montos: recargos, pagos menores y pagos múltiples.
      int conRecargo = 0;
      final menores = <String>[];
      int multiples = 0;
      for (final e in mats) {
        final r = e.value / montoMensual;
        final esBono = montoConBono > 0 &&
            (e.value - montoConBono).abs() <= montoConBono * 0.02;
        if (r >= 1.03 && r <= 1.07) {
          conRecargo++;
        } else if (r < 0.95 && !esBono) {
          menores.add('${e.key.day}/${e.key.month}/${e.key.year} por '
              '${pesosCessum(e.value)}');
        } else if (r >= 1.8) {
          multiples++;
        }
      }
      if (conRecargo > 0) {
        h.add(HallazgoPago(
            NivelHallazgo.info,
            conRecargo == 1
                ? '1 pago incluyó recargo'
                : '$conRecargo pagos incluyeron recargo',
            'Coinciden con tu colegiatura más el 5%. Pagar del 1 al 15 evita '
                'ese cargo.'));
      }
      if (menores.isNotEmpty) {
        h.add(HallazgoPago(
            NivelHallazgo.aviso,
            'Hay pagos menores a tu colegiatura',
            'Detectamos: ${menores.take(3).join('; ')}. Tu colegiatura es '
                '${pesosCessum(montoMensual)}. Si fue un pago parcial puede '
                'quedar una diferencia; si el monto registrado es incorrecto, '
                'repórtalo.',
            'monto'));
      }
      if (multiples > 0) {
        h.add(HallazgoPago(
            NivelHallazgo.info,
            multiples == 1
                ? '1 pago equivale a varias mensualidades'
                : '$multiples pagos equivalen a varias mensualidades',
            'Parecen pagos adelantados. Si no fue tu intención, repórtalo.'));
      }

      // Posibles duplicados: mismo mes y mismo monto.
      final grupos = <String, int>{};
      final etiquetas = <String, DateTime>{};
      for (final e in mats) {
        final k = '${e.key.year}-${e.key.month}-${e.value.round()}';
        grupos[k] = (grupos[k] ?? 0) + 1;
        etiquetas[k] = e.key;
      }
      final dup = grupos.entries.where((g) => g.value >= 2).toList();
      if (dup.isNotEmpty) {
        final g = dup.first;
        final monto = num.parse(g.key.split('-').last);
        h.add(HallazgoPago(
            NivelHallazgo.aviso,
            'Posible pago duplicado',
            'En ${mesAnioCessum(etiquetas[g.key]!)} hay ${g.value} pagos de '
                '${pesosCessum(monto)}. Si pagaste dos veces por error, '
                'repórtalo para que se revise.',
            'duplicado'));
      }

      // Cobertura: mensualidades pagadas contra meses transcurridos.
      final primero = mats.first.key;
      final meses = (hoyD.year * 12 + hoyD.month) -
          (primero.year * 12 + primero.month) +
          (hoyD.day > 15 ? 1 : 0);
      if (meses >= 2) {
        final suma = mats.fold<num>(0, (s, e) => s + e.value);
        final equivalentes = (suma / montoMensual + 0.1).floor();
        if (equivalentes >= meses) {
          h.add(HallazgoPago(
              NivelHallazgo.ok,
              'Tus pagos cubren los meses transcurridos',
              'Registras el equivalente a $equivalentes mensualidades en '
                  '$meses meses desde tu primer pago.'));
        } else if (adeudo == null || adeudo['alDia'] == true) {
          h.add(HallazgoPago(
              NivelHallazgo.info,
              'Tu historial registra $equivalentes de $meses mensualidades',
              'Tu estado de cuenta no marca adeudo, pero tu historial muestra '
                  'menos pagos que meses transcurridos. Si algún comprobante '
                  'no aparece, repórtalo.',
              'no_aparece'));
        }
      }
    }
  }

  if (esBeca && porcentajeBeca > 0) {
    h.add(HallazgoPago(
        NivelHallazgo.ok,
        'Beca del $porcentajeBeca% aplicada',
        'Tu colegiatura ya considera el descuento. Si el porcentaje no es el '
            'que te otorgaron, repórtalo.',
        'beca'));
  }

  if (h.isEmpty) {
    h.add(const HallazgoPago(NivelHallazgo.ok, 'Todo en orden',
        'No encontramos nada fuera de lo normal en tus pagos.'));
  }
  h.sort((a, b) => a.nivel.index.compareTo(b.nivel.index));
  return h;
}

// ─── Tarjeta reutilizable del análisis ──────────────────────────────────────

class AnalisisPagosCard extends StatelessWidget {
  final List<HallazgoPago> hallazgos;
  final void Function(HallazgoPago h) onReportar;

  const AnalisisPagosCard(
      {super.key, required this.hallazgos, required this.onReportar});

  static Color colorNivel(NivelHallazgo n) => switch (n) {
        NivelHallazgo.alerta => cessumRed,
        NivelHallazgo.aviso => const Color(0xFFA56B16),
        NivelHallazgo.info => const Color(0xFF1565C0),
        NivelHallazgo.ok => const Color(0xFF1E8E3E),
      };

  static IconData iconoNivel(NivelHallazgo n) => switch (n) {
        NivelHallazgo.alerta => Icons.error_outline,
        NivelHallazgo.aviso => Icons.warning_amber_rounded,
        NivelHallazgo.info => Icons.info_outline,
        NivelHallazgo.ok => Icons.check_circle_outline,
      };

  @override
  Widget build(BuildContext context) {
    final problemas = hallazgos
        .where((x) =>
            x.nivel == NivelHallazgo.alerta || x.nivel == NivelHallazgo.aviso)
        .length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: cessumGold, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Análisis de tu cuenta',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (problemas > 0
                        ? const Color(0xFFA56B16)
                        : const Color(0xFF1E8E3E))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                problemas == 0
                    ? 'Sin observaciones'
                    : problemas == 1
                        ? '1 observación'
                        : '$problemas observaciones',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: problemas > 0
                        ? const Color(0xFFA56B16)
                        : const Color(0xFF1E8E3E)),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              'Revisión automática de tus montos, fechas y estado de cuenta.',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 10),
          ...hallazgos.take(7).map((x) => _fila(context, x)),
        ],
      ),
    );
  }

  Widget _fila(BuildContext context, HallazgoPago x) {
    final c = colorNivel(x.nivel);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(iconoNivel(x.nivel), color: c, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(x.titulo,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13, color: c)),
                const SizedBox(height: 2),
                Text(x.detalle,
                    style: TextStyle(
                        fontSize: 12, height: 1.35, color: cessumInk(context))),
                if (x.motivoAyuda != null &&
                    (x.nivel == NivelHallazgo.alerta ||
                        x.nivel == NivelHallazgo.aviso ||
                        x.motivoAyuda == 'no_aparece'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => onReportar(x),
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          foregroundColor: c),
                      icon: const Icon(Icons.support_agent, size: 16),
                      label: const Text('Reportar en mesa de ayuda',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Motivos de la mesa de ayuda ────────────────────────────────────────────

class MotivoAyuda {
  final String clave;
  final String titulo;
  final IconData icono;
  final String sugerencia;
  const MotivoAyuda(this.clave, this.titulo, this.icono, this.sugerencia);
}

const List<MotivoAyuda> motivosAyudaPagos = [
  MotivoAyuda(
      'recargo',
      'Me aparece un recargo que no me corresponde',
      Icons.money_off,
      'El recargo del 5% solo aplica cuando la colegiatura de un mes se paga '
          'después del día 15. Indica de qué mes se trata.'),
  MotivoAyuda(
      'no_aparece',
      'Mi pago no aparece o sigue «por validar»',
      Icons.hourglass_empty,
      'Indica fecha y monto del depósito y ten tu comprobante a la mano; te lo '
          'pueden pedir para ubicarlo.'),
  MotivoAyuda(
      'adeudo',
      'Me marca un adeudo que ya pagué',
      Icons.report_problem_outlined,
      'Indica qué concepto aparece como vencido y cuándo lo pagaste.'),
  MotivoAyuda(
      'monto',
      'El monto de mi colegiatura no es correcto',
      Icons.calculate_outlined,
      'Escribe el monto que esperabas y de dónde lo tomaste (convocatoria, '
          'correo, acuerdo con administración).'),
  MotivoAyuda(
      'beca',
      'Mi beca o descuento no se aplicó',
      Icons.percent,
      'Indica el porcentaje de beca o el descuento que te otorgaron y desde '
          'qué mes debía aplicarse.'),
  MotivoAyuda(
      'duplicado',
      'Pagué dos veces o de más',
      Icons.copy_all_outlined,
      'Indica las fechas y montos de los pagos repetidos.'),
  MotivoAyuda(
      'comprobante',
      'Necesito comprobante o factura',
      Icons.receipt_long_outlined,
      'Los pagos validados tienen el botón «Comprobante oficial» en tu '
          'historial. La factura (CFDI) se pide antes del cierre del mes.'),
  MotivoAyuda('otro', 'Otro problema con mis pagos', Icons.help_outline,
      'Describe con el mayor detalle posible lo que ves y lo que esperabas.'),
];

// ─── Pantalla ───────────────────────────────────────────────────────────────

/// Mesa de ayuda de pagos. Se abre desde «Mis pagos» y «Mi seguimiento de
/// pagos». [contexto] es lo que la pantalla de origen estaba mostrando (monto,
/// estado de cuenta, avisos), para que Atención a Estudiantes lo vea tal cual
/// sin pedírselo al alumno.
class MesaAyudaPagosScreen extends StatefulWidget {
  final String? motivoInicial;
  final String? detalleInicial;
  final String contexto;

  const MesaAyudaPagosScreen({
    super.key,
    this.motivoInicial,
    this.detalleInicial,
    this.contexto = '',
  });

  @override
  State<MesaAyudaPagosScreen> createState() => _MesaAyudaPagosScreenState();
}

class _MesaAyudaPagosScreenState extends State<MesaAyudaPagosScreen> {
  StudentProfile? _perfil;
  String? _motivo;
  final _desc = TextEditingController();
  late final String _folio;
  bool _verDatos = false;

  @override
  void initState() {
    super.initState();
    _motivo = widget.motivoInicial;
    if ((widget.detalleInicial ?? '').isNotEmpty) {
      _desc.text = 'Lo que muestra mi app: ${widget.detalleInicial}\n\n';
    }
    final n = DateTime.now();
    String dos(int v) => v.toString().padLeft(2, '0');
    _folio = 'MP-${dos(n.year % 100)}${dos(n.month)}${dos(n.day)}-'
        '${dos(n.hour)}${dos(n.minute)}${dos(n.second)}';
    StudentProfile.load().then((p) {
      if (mounted) setState(() => _perfil = p);
    });
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  MotivoAyuda? get _motivoSel {
    for (final m in motivosAyudaPagos) {
      if (m.clave == _motivo) return m;
    }
    return null;
  }

  String get _datosAlumno {
    final p = _perfil;
    if (p == null) return 'Datos del alumno: no disponibles en este dispositivo.';
    return 'Matrícula: ${p.matricula}\n'
        'Programa: ${p.programa}\n'
        'Generación: ${p.generacion}\n'
        'Modalidad: ${p.modalidad}';
  }

  String _reporte() {
    final m = _motivoSel;
    final b = StringBuffer()
      ..writeln('MESA DE AYUDA · PAGOS')
      ..writeln('Folio: $_folio')
      ..writeln()
      ..writeln('Motivo: ${m?.titulo ?? 'Sin especificar'}')
      ..writeln()
      ..writeln('Descripción:')
      ..writeln(_desc.text.trim().isEmpty ? '(sin descripción)' : _desc.text.trim())
      ..writeln()
      ..writeln(_datosAlumno);
    if (widget.contexto.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('Lo que muestra la app:')
        ..writeln(widget.contexto.trim());
    }
    return b.toString().trim();
  }

  String? _validar() {
    if (_motivo == null) return 'Elige qué está mal para poder enviarlo.';
    if (_motivo == 'otro' && _desc.text.trim().length < 10) {
      return 'Describe brevemente el problema.';
    }
    return null;
  }

  Future<void> _enviarWhatsApp() async {
    final err = _validar();
    if (err != null) {
      _aviso(err);
      return;
    }
    final uri = Uri.parse('https://wa.me/$whatsappNumero'
        '?text=${Uri.encodeComponent(_reporte())}');
    await _abrir(uri, 'No se pudo abrir WhatsApp.');
  }

  Future<void> _enviarCorreo() async {
    final err = _validar();
    if (err != null) {
      _aviso(err);
      return;
    }
    final asunto =
        'Mesa de ayuda · Pagos · $_folio · ${_perfil?.matricula ?? ''}'.trim();
    final uri = Uri.parse('mailto:$correoMesaAyudaPagos'
        '?subject=${Uri.encodeComponent(asunto)}'
        '&body=${Uri.encodeComponent(_reporte())}');
    await _abrir(uri, 'No se pudo abrir tu correo. Copia el reporte y envíalo '
        'a $correoMesaAyudaPagos.');
  }

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: _reporte()));
    _aviso('Reporte copiado. Puedes pegarlo en WhatsApp o en un correo.');
  }

  Future<void> _abrir(Uri uri, String error) async {
    try {
      final ok = await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      if (!ok) _aviso(error);
    } catch (_) {
      _aviso(error);
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    final sel = _motivoSel;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mesa de ayuda · Pagos'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.support_agent, color: cessumRed, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '¿Algo no cuadra en tus pagos? Cuéntanos qué pasa. Tu reporte '
                    'llega a Atención a Estudiantes con tus datos y con lo que '
                    'muestra tu app, para que no tengas que explicarlo dos veces.',
                    style: TextStyle(
                        fontSize: 12.5, height: 1.4, color: cessumInk(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text('1. ¿Qué está mal?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 8),
          ...motivosAyudaPagos.map((m) {
            final activo = m.clave == _motivo;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _motivo = m.clave),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: activo
                        ? cessumRed.withValues(alpha: 0.08)
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: activo
                            ? cessumRed
                            : cessumMuted(context).withValues(alpha: 0.25)),
                  ),
                  child: Row(children: [
                    Icon(m.icono,
                        size: 20,
                        color: activo ? cessumRed : cessumMuted(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(m.titulo,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  activo ? FontWeight.w700 : FontWeight.w500)),
                    ),
                    if (activo)
                      const Icon(Icons.check_circle, color: cessumRed, size: 18),
                  ]),
                ),
              ),
            );
          }),
          if (sel != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline,
                      color: Color(0xFFA56B16), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(sel.sugerencia,
                        style: TextStyle(
                            fontSize: 12, height: 1.35, color: cessumInk(context))),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Text('2. Cuéntanos el caso',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 8),
          TextField(
            controller: _desc,
            maxLines: 5,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Por ejemplo: mi primera mensualidad es en octubre y '
                  'la app me dice que aplica recargo.',
              hintStyle: const TextStyle(fontSize: 12.5),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _verDatos = !_verDatos),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(_verDatos ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: cessumMuted(context)),
                const SizedBox(width: 6),
                Text('Datos que se adjuntan automáticamente',
                    style:
                        TextStyle(fontSize: 12.5, color: cessumMuted(context))),
              ]),
            ),
          ),
          if (_verDatos)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: cessumMuted(context).withValues(alpha: 0.2)),
              ),
              child: SelectableText(
                'Folio: $_folio\n\n$_datosAlumno'
                '${widget.contexto.trim().isNotEmpty ? '\n\n${widget.contexto.trim()}' : ''}',
                style: const TextStyle(fontSize: 11.5, height: 1.4),
              ),
            ),
          const SizedBox(height: 18),
          const Text('3. Envíalo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E3E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _enviarWhatsApp,
              icon: const Icon(Icons.chat),
              label: const Text('Enviar por WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _enviarCorreo,
              icon: const Icon(Icons.email_outlined),
              label: const Text('Enviar por correo'),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: _copiar,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copiar reporte', style: TextStyle(fontSize: 12.5)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Guarda tu folio $_folio: sirve para dar seguimiento a tu reporte.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

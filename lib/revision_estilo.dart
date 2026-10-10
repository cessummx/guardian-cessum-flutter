// =====================================================================
//  revision_estilo.dart · CESSUM · App CESSUM
//  TIPO DE REVISIÓN CON IA (6-oct-2026).
//
//  El docente elige CÓMO se califica y se redacta el borrador de la IA:
//   · tres tipos base: Justo, Duro y Calmado;
//   · y todo ajustable: exigencia al calificar, tono, extensión, registro
//     académico, hacia dónde orienta, qué debe incluir, indicaciones
//     propias y palabras o giros que no debe usar.
//  La voz es SIEMPRE académica y de usted. La dureza recae en el criterio
//  y en la evidencia, nunca en la persona, y el tono no altera la
//  calificación (la calificación depende del rigor elegido y de la
//  evidencia de la entrega).
//
//  Lo usan revision_tarea_screen.dart y revisiones_screen.dart. El tipo
//  elegido viaja como «estilo» en revision_borrador (POST) y en
//  entrega_ia_retro (GET). Sin «estilo», el Guardián se comporta como antes.
//  El último tipo elegido se conserva mientras la app siga abierta.
// =====================================================================
import 'package:flutter/material.dart';

import 'constants.dart';
import 'cessum_ui.dart';

int _ix(int v, int mx) => v < 0 ? 0 : (v > mx ? mx : v);

const List<String> _kExigencia = ['Flexible', 'Comprensiva', 'Justa', 'Estricta', 'Muy estricta'];
const List<String> _kTono = ['Directo', 'Sobrio', 'Equilibrado', 'Cercano', 'Sereno'];
const List<String> _kLongitud = ['Breve', 'Estándar', 'Amplia'];

const Map<String, String> _kRegistro = {
  'sobrio': 'Sobrio',
  'argumentativo': 'Argumentativo',
  'dialogico': 'Dialógico',
};

const Map<String, String> _kOrientacion = {
  'auto': 'Automática',
  'tarea': 'Siguiente tarea',
  'sesion': 'Siguiente sesión',
  'proyecto': 'Proyecto del curso',
};

const Map<String, String> _kDescripcion = {
  'justo':
      'Aplica la consigna y la rúbrica con el mismo rasero para toda entrega: reconoce lo logrado con evidencia, nombra con precisión lo que faltó y orienta el siguiente paso.',
  'duro':
      'Máxima exigencia con el criterio, no con la persona: pide evidencia explícita para cada nivel alto, nombra cada faltante sin atenuantes y califica con rigor.',
  'calmado':
      'Mismo rigor que el justo, dicho con serenidad: ordena lo logrado y lo pendiente sin dramatizar y propone un siguiente paso alcanzable, con una pregunta que invita a profundizar.',
};

const List<String> _kAyudaExigencia = [
  'Ante la duda razonable se elige el nivel superior; no se otorga lo que la entrega no sustenta.',
  'Valora el trabajo en conjunto y admite como cumplido lo presente aunque no esté pulido.',
  'Aplica la consigna y la rúbrica tal como están escritas, igual para cualquier entrega.',
  'Pide evidencia concreta para cada nivel alto; ante la duda, el nivel inferior.',
  'El nivel máximo solo si está demostrado de forma explícita y completa; cada faltante se nombra sin atenuarlo.',
];

const List<String> _kAyudaTono = [
  'Enunciados declarativos, sin amortiguadores ni fórmulas de cortesía.',
  'Formal, contenido y neutro; sin efusividad.',
  'Formal y respetuoso, ni frío ni efusivo.',
  'Formal y acogedor; reconoce el esfuerzo con precisión.',
  'Pausado y tranquilizador: lo pendiente como parte del proceso, sin dramatizar ni minimizar.',
];

const Map<String, String> _kAyudaRegistro = {
  'sobrio': 'Enunciativo y conciso: cada juicio en una oración.',
  'argumentativo': 'Cada juicio se justifica con la evidencia de la entrega.',
  'dialogico': 'Incluye una pregunta académica que invita a profundizar o replantear una decisión.',
};

class EstiloRevisionIa {
  /// Último tipo elegido: se conserva mientras la app siga abierta.
  static EstiloRevisionIa actual = EstiloRevisionIa.preset('justo');

  String nivel; // justo | duro | calmado | personalizado
  String tipoBase; // el tipo del que se partió
  int exigencia; // 1 a 5
  int calidez; // 1 a 5
  int longitud; // 1 a 3
  String registro; // sobrio | argumentativo | dialogico
  String orientacion; // auto | tarea | sesion | proyecto
  bool abrirConLogrado;
  bool citarEvidencia;
  bool nombrarCriterio;
  bool remitirAFuentes;
  String indicaciones;
  String evitar;

  EstiloRevisionIa({
    this.nivel = 'justo',
    this.tipoBase = 'justo',
    this.exigencia = 3,
    this.calidez = 3,
    this.longitud = 2,
    this.registro = 'argumentativo',
    this.orientacion = 'auto',
    this.abrirConLogrado = true,
    this.citarEvidencia = true,
    this.nombrarCriterio = true,
    this.remitirAFuentes = false,
    this.indicaciones = '',
    this.evitar = '',
  });

  factory EstiloRevisionIa.preset(String n) {
    switch (n) {
      case 'duro':
        return EstiloRevisionIa(
          nivel: 'duro',
          tipoBase: 'duro',
          exigencia: 5,
          calidez: 1,
          longitud: 2,
          registro: 'sobrio',
          orientacion: 'auto',
          abrirConLogrado: false,
          citarEvidencia: true,
          nombrarCriterio: true,
          remitirAFuentes: true,
        );
      case 'calmado':
        return EstiloRevisionIa(
          nivel: 'calmado',
          tipoBase: 'calmado',
          exigencia: 3,
          calidez: 5,
          longitud: 2,
          registro: 'dialogico',
          orientacion: 'auto',
          abrirConLogrado: true,
          citarEvidencia: true,
          nombrarCriterio: true,
          remitirAFuentes: false,
        );
      default:
        return EstiloRevisionIa();
    }
  }

  EstiloRevisionIa copia() => EstiloRevisionIa(
        nivel: nivel,
        tipoBase: tipoBase,
        exigencia: exigencia,
        calidez: calidez,
        longitud: longitud,
        registro: registro,
        orientacion: orientacion,
        abrirConLogrado: abrirConLogrado,
        citarEvidencia: citarEvidencia,
        nombrarCriterio: nombrarCriterio,
        remitirAFuentes: remitirAFuentes,
        indicaciones: indicaciones,
        evitar: evitar,
      );

  Map<String, dynamic> toJson() => {
        'nivel': nivel,
        'tipoBase': tipoBase,
        'exigencia': exigencia,
        'calidez': calidez,
        'longitud': longitud,
        'registro': registro,
        'orientacion': orientacion,
        'abrirConLogrado': abrirConLogrado,
        'citarEvidencia': citarEvidencia,
        'nombrarCriterio': nombrarCriterio,
        'remitirAFuentes': remitirAFuentes,
        'indicaciones': indicaciones.trim(),
        'evitar': evitar.trim(),
      };

  static String _nombre(String n) => n == 'duro'
      ? 'Duro'
      : n == 'calmado'
          ? 'Calmado'
          : n == 'justo'
              ? 'Justo'
              : 'Personalizado';

  String get etiqueta => nivel == 'personalizado' ? '${_nombre(tipoBase)} · ajustado' : _nombre(nivel);

  /// Rótulo a partir de lo que devuelve el Guardián («estilo» de un borrador).
  static String etiquetaDeJson(dynamic j) {
    if (j is! Map) return '';
    final n = '${j['nivel'] ?? ''}';
    if (n.isEmpty) return '';
    final b = '${j['tipoBase'] ?? 'justo'}';
    return n == 'personalizado' ? '${_nombre(b)} · ajustado' : _nombre(n);
  }

  String get descripcion =>
      nivel == 'personalizado' ? 'Parte de «${_nombre(tipoBase)}» y quedó ajustado a su manera.' : (_kDescripcion[nivel] ?? '');

  String get resumen => 'Exigencia ${_kExigencia[_ix(exigencia - 1, 4)].toLowerCase()} · '
      'tono ${_kTono[_ix(calidez - 1, 4)].toLowerCase()} · '
      '${_kLongitud[_ix(longitud - 1, 2)].toLowerCase()} · '
      'registro ${(_kRegistro[registro] ?? '').toLowerCase()}';

  bool _mismoQue(EstiloRevisionIa o) =>
      exigencia == o.exigencia &&
      calidez == o.calidez &&
      longitud == o.longitud &&
      registro == o.registro &&
      orientacion == o.orientacion &&
      abrirConLogrado == o.abrirConLogrado &&
      citarEvidencia == o.citarEvidencia &&
      nombrarCriterio == o.nombrarCriterio &&
      remitirAFuentes == o.remitirAFuentes &&
      indicaciones.trim().isEmpty &&
      evitar.trim().isEmpty;

  /// Tras cualquier ajuste: si coincide con un tipo base vuelve a llamarse así; si no, queda «personalizado».
  void normalizar() {
    for (final n in const ['justo', 'duro', 'calmado']) {
      if (_mismoQue(EstiloRevisionIa.preset(n))) {
        nivel = n;
        tipoBase = n;
        return;
      }
    }
    nivel = 'personalizado';
  }

  /// Carga los valores de un tipo base. Las indicaciones propias y las palabras a evitar se conservan.
  void aplicarTipo(String n) {
    final p = EstiloRevisionIa.preset(n);
    tipoBase = p.tipoBase;
    exigencia = p.exigencia;
    calidez = p.calidez;
    longitud = p.longitud;
    registro = p.registro;
    orientacion = p.orientacion;
    abrirConLogrado = p.abrirConLogrado;
    citarEvidencia = p.citarEvidencia;
    nombrarCriterio = p.nombrarCriterio;
    remitirAFuentes = p.remitirAFuentes;
    normalizar();
  }
}

// ═════════════════════════════════════════════════════ TARJETA DE ELECCIÓN
class EstiloRevisionIaSelector extends StatelessWidget {
  final EstiloRevisionIa estilo;
  final ValueChanged<EstiloRevisionIa> onCambio;
  final bool habilitado;

  const EstiloRevisionIaSelector({super.key, required this.estilo, required this.onCambio, this.habilitado = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.tune_rounded, color: cessumGold, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Tipo de revisión',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: cessumInk(context))),
          ),
          TextButton.icon(
            onPressed: habilitado
                ? () async {
                    final r = await mostrarEstiloRevisionIa(context, estilo);
                    if (r != null) onCambio(r);
                  }
                : null,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Personalizar'),
          ),
        ]),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in const ['justo', 'duro', 'calmado'])
            ChoiceChip(
              label: Text(EstiloRevisionIa._nombre(t)),
              selected: estilo.tipoBase == t,
              selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: habilitado
                  ? (_) {
                      final n = estilo.copia();
                      n.aplicarTipo(t);
                      onCambio(n);
                    }
                  : null,
            ),
        ]),
        const SizedBox(height: 8),
        Text(estilo.descripcion, style: const TextStyle(fontSize: 12.5, height: 1.4)),
        const SizedBox(height: 2),
        Text(estilo.resumen, style: TextStyle(fontSize: 11.5, height: 1.35, color: cessumMuted(context))),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════ PERSONALIZAR
/// Abre el ajuste fino del tipo de revisión. Devuelve el tipo elegido, o null si se cancela.
Future<EstiloRevisionIa?> mostrarEstiloRevisionIa(BuildContext context, EstiloRevisionIa inicial) {
  final e = inicial.copia();
  // Los controladores no se liberan a mano: el diálogo sigue dibujándose unos cuadros al cerrarse y
  // liberarlos antes provoca el error «controller used after being disposed».
  final indic = TextEditingController(text: e.indicaciones);
  final evitar = TextEditingController(text: e.evitar);
  return showDialog<EstiloRevisionIa>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        void cambio(VoidCallback f) => setD(() {
              f();
              e.normalizar();
            });
        Widget titulo(String t, String valor) => Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 2),
              child: Row(children: [
                Expanded(child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                Text(valor, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: cessumRed)),
              ]),
            );
        Widget ayuda(String t) => Text(t, style: TextStyle(fontSize: 11.5, height: 1.35, color: cessumMuted(ctx)));
        return AlertDialog(
          title: const Text('Tipo de revisión'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                ayuda('Elija un tipo base y ajústelo. La voz siempre es académica y de usted: lo que cambia es el rigor con que se aplica la tarea y el tono con que se dice.'),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final t in const ['justo', 'duro', 'calmado'])
                    ChoiceChip(
                      label: Text(EstiloRevisionIa._nombre(t)),
                      selected: e.tipoBase == t,
                      selectedColor: cessumRed.withValues(alpha: 0.15),
                      onSelected: (_) => cambio(() => e.aplicarTipo(t)),
                    ),
                ]),
                const SizedBox(height: 8),
                Text(_kDescripcion[e.tipoBase] ?? '', style: const TextStyle(fontSize: 12.5, height: 1.4)),
                if (e.nivel == 'personalizado')
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Ajustado a su manera.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumRed)),
                  ),
                titulo('Exigencia al calificar', _kExigencia[_ix(e.exigencia - 1, 4)]),
                Slider(
                  value: e.exigencia.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: cessumRed,
                  label: _kExigencia[_ix(e.exigencia - 1, 4)],
                  onChanged: (v) => cambio(() => e.exigencia = v.round()),
                ),
                ayuda(_kAyudaExigencia[_ix(e.exigencia - 1, 4)]),
                titulo('Tono', _kTono[_ix(e.calidez - 1, 4)]),
                Slider(
                  value: e.calidez.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  activeColor: cessumRed,
                  label: _kTono[_ix(e.calidez - 1, 4)],
                  onChanged: (v) => cambio(() => e.calidez = v.round()),
                ),
                ayuda(_kAyudaTono[_ix(e.calidez - 1, 4)]),
                titulo('Extensión', _kLongitud[_ix(e.longitud - 1, 2)]),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var i = 1; i <= 3; i++)
                    ChoiceChip(
                      label: Text(_kLongitud[i - 1]),
                      selected: e.longitud == i,
                      selectedColor: cessumRed.withValues(alpha: 0.15),
                      onSelected: (_) => cambio(() => e.longitud = i),
                    ),
                ]),
                ayuda('Siempre es un solo párrafo: breve son 4 oraciones, estándar de 4 a 6 y amplia hasta 8.'),
                titulo('Registro académico', _kRegistro[e.registro] ?? ''),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final r in _kRegistro.entries)
                    ChoiceChip(
                      label: Text(r.value),
                      selected: e.registro == r.key,
                      selectedColor: cessumRed.withValues(alpha: 0.15),
                      onSelected: (_) => cambio(() => e.registro = r.key),
                    ),
                ]),
                ayuda(_kAyudaRegistro[e.registro] ?? ''),
                titulo('Hacia dónde orienta', _kOrientacion[e.orientacion] ?? ''),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final o in _kOrientacion.entries)
                    ChoiceChip(
                      label: Text(o.value),
                      selected: e.orientacion == o.key,
                      selectedColor: cessumRed.withValues(alpha: 0.15),
                      onSelected: (_) => cambio(() => e.orientacion = o.key),
                    ),
                ]),
                ayuda('Automática: la IA decide según la tarea, y si ya cerró no pide rehacer nada.'),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: e.abrirConLogrado,
                  activeColor: cessumRed,
                  onChanged: (v) => cambio(() => e.abrirConLogrado = v),
                  title: const Text('Abrir con lo logrado', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Si se apaga, abre con lo que más pesa en la calificación.', style: TextStyle(fontSize: 11.5)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: e.citarEvidencia,
                  activeColor: cessumRed,
                  onChanged: (v) => cambio(() => e.citarEvidencia = v),
                  title: const Text('Citar evidencia concreta de la entrega', style: TextStyle(fontSize: 13)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: e.nombrarCriterio,
                  activeColor: cessumRed,
                  onChanged: (v) => cambio(() => e.nombrarCriterio = v),
                  title: const Text('Nombrar el criterio de cada juicio', style: TextStyle(fontSize: 13)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: e.remitirAFuentes,
                  activeColor: cessumRed,
                  onChanged: (v) => cambio(() => e.remitirAFuentes = v),
                  title: const Text('Remitir a la norma, autor o texto que la tarea cite', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Solo las fuentes que la tarea menciona; no agrega otras.', style: TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: indic,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  onChanged: (v) => cambio(() => e.indicaciones = v),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Indicaciones propias (opcional)',
                    helperText: 'Por ejemplo: «relacione siempre el caso con el marco normativo de la sesión».',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: evitar,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 200,
                  onChanged: (v) => cambio(() => e.evitar = v),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Palabras o giros que no debe usar (opcional)',
                  ),
                ),
                const SizedBox(height: 6),
                ayuda('Ningún tipo cambia lo que la tarea exige ni permite inventar lo que la entrega no tiene: cambia el rigor con que se aplica y la voz con que se dice.'),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(
              onPressed: () => setD(() {
                e.aplicarTipo('justo');
                e.indicaciones = '';
                e.evitar = '';
                indic.text = '';
                evitar.text = '';
                e.normalizar();
              }),
              child: const Text('Restablecer'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                e.indicaciones = indic.text.trim();
                e.evitar = evitar.text.trim();
                e.normalizar();
                Navigator.pop(ctx, e);
              },
              child: const Text('Usar este tipo'),
            ),
          ],
        );
      },
    ),
  );
}

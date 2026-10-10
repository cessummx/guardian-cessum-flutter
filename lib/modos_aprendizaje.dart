import 'package:flutter/material.dart';

import 'constants.dart';

/// Marco funcional/interconductual (Ribes-Iñesta, 1985; Ibáñez Bernal).
/// Tamiz de preferencias de interacción didáctica autoinformadas.
const List<String> kModos = ['obs', 'ling', 'oper', 'dial', 'indag'];

const Map<String, String> kModoNombre = {
  'obs': 'Observacional-demostrativa',
  'ling': 'Lingüística-instruccional',
  'oper': 'Operativo-instrumental',
  'dial': 'Dialógica-argumentativa',
  'indag': 'Indagatoria-sustitutiva',
};

const Map<String, String> kModoDescripcion = {
  'obs': 'Se ajusta mejor a partir de modelos y demostraciones (observar).',
  'ling': 'Se ajusta con mediación verbal: leer y escuchar explicaciones e instrucciones.',
  'oper': 'Se ajusta haciendo: manipular, aplicar y resolver casos.',
  'dial': 'Se ajusta en el intercambio: confrontar criterios y argumentar.',
  'indag': 'Se ajusta construyendo y resolviendo sus propias preguntas.',
};

const Map<String, Color> kModoColor = {
  'obs': cessumGold,
  'ling': Color(0xFF2E6DB4),
  'oper': Color(0xFF2E8B57),
  'dial': cessumRed,
  'indag': Color(0xFF7B4FA3),
};

/// Cada reactivo: una situación con 5 opciones (una por modo).
class ReactivoModo {
  final String situacion;
  final List<MapEntry<String, String>> opciones; // modo -> texto
  const ReactivoModo(this.situacion, this.opciones);
}

const List<ReactivoModo> kReactivos = [
  ReactivoModo('Cuando empiezo un tema nuevo, me funciona mejor…', [
    MapEntry('obs', 'Ver una demostración de cómo se hace'),
    MapEntry('ling', 'Leer o escuchar una explicación ordenada'),
    MapEntry('oper', 'Probarlo yo mismo con un caso'),
    MapEntry('dial', 'Discutirlo con mis compañeros'),
    MapEntry('indag', 'Investigarlo por mi cuenta'),
  ]),
  ReactivoModo('Retengo mejor lo que aprendo cuando…', [
    MapEntry('obs', 'Vi cómo se hace'),
    MapEntry('ling', 'Lo leí o me lo explicaron con claridad'),
    MapEntry('oper', 'Lo apliqué a algo real'),
    MapEntry('dial', 'Lo debatí con otros'),
    MapEntry('indag', 'Yo busqué y armé la respuesta'),
  ]),
  ReactivoModo('Prefiero que me corrijan…', [
    MapEntry('obs', 'Mostrándome el modelo correcto'),
    MapEntry('ling', 'Con una explicación detallada'),
    MapEntry('oper', 'Dejándome reintentar sobre el caso'),
    MapEntry('dial', 'Discutiendo por qué estuvo mal'),
    MapEntry('indag', 'Dándome pistas para descubrirlo'),
  ]),
  ReactivoModo('Demuestro mejor lo que sé…', [
    MapEntry('obs', 'Reproduciendo un procedimiento'),
    MapEntry('ling', 'Explicándolo por escrito u oral'),
    MapEntry('oper', 'Resolviendo un caso real'),
    MapEntry('dial', 'Defendiéndolo en un debate'),
    MapEntry('indag', 'Proponiendo una solución propia'),
  ]),
  ReactivoModo('Lo que más me engancha de una clase es…', [
    MapEntry('obs', 'Las demostraciones y ejemplos'),
    MapEntry('ling', 'Una buena explicación o lectura'),
    MapEntry('oper', 'La práctica y los casos'),
    MapEntry('dial', 'La discusión de ideas'),
    MapEntry('indag', 'Explorar problemas abiertos'),
  ]),
  ReactivoModo('Cuando tengo una duda, primero…', [
    MapEntry('obs', 'Busco un ejemplo o video'),
    MapEntry('ling', 'Releo o pregunto la explicación'),
    MapEntry('oper', 'Pruebo hasta que me sale'),
    MapEntry('dial', 'La planteo al grupo'),
    MapEntry('indag', 'Investigo a fondo por mi cuenta'),
  ]),
  ReactivoModo('Para estudiar un examen, yo…', [
    MapEntry('obs', 'Repaso ejemplos resueltos'),
    MapEntry('ling', 'Resumo y releo mis apuntes'),
    MapEntry('oper', 'Practico ejercicios y casos'),
    MapEntry('dial', 'Estudio comentando con otros'),
    MapEntry('indag', 'Profundizo más allá del temario'),
  ]),
  ReactivoModo('La actividad que más disfruto es…', [
    MapEntry('obs', 'Observar una demostración'),
    MapEntry('ling', 'Una exposición o lectura guiada'),
    MapEntry('oper', 'Un taller práctico'),
    MapEntry('dial', 'Un debate o mesa de discusión'),
    MapEntry('indag', 'Un proyecto de investigación'),
  ]),
];

/// Gráfica de barras horizontales (sin librerías externas).
class BarrasModos extends StatelessWidget {
  final Map<String, int> conteo;
  const BarrasModos({super.key, required this.conteo});

  @override
  Widget build(BuildContext context) {
    int total = 0;
    for (final k in kModos) {
      total += (conteo[k] ?? 0);
    }
    int maxv = 1;
    for (final k in kModos) {
      if ((conteo[k] ?? 0) > maxv) maxv = conteo[k] ?? 0;
    }
    return Column(
      children: kModos.map((k) {
        final v = conteo[k] ?? 0;
        final pct = total > 0 ? (v * 100 / total).round() : 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(kModoNombre[k]!,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                  Text('$v  ·  $pct%',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LayoutBuilder(
                  builder: (c, cons) => Stack(
                    children: [
                      Container(height: 12, color: Colors.black12),
                      Container(
                        height: 12,
                        width: cons.maxWidth * (v / maxv),
                        color: kModoColor[k],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

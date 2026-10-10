// ACERCA DE · BLOQUES COMPARTIDOS (24-sep-2026)
//
// Antes, «Acerca de» del alumno (about_screen.dart), del docente
// (teacher_about_screen.dart) y la página institucional (acerca_screen.dart)
// repetían domicilio, teléfonos, razón social y enlaces: un cambio de número
// obligaba a buscarlo en tres archivos. Aquí viven una sola vez, con colores
// que respetan el modo oscuro. Cada pantalla solo agrega lo de su perfil.
import 'package:flutter/material.dart';

import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

/// RVOE vigentes según el registro oficial, por el nombre EXACTO del programa
/// en programasAcademicos (constants.dart). Si un programa cambia de nombre
/// allá, hay que cambiarlo aquí también.
const Map<String, String> rvoePorPrograma = {
  'Licenciatura en Pedagogía': '2026DGES-09',
  'Maestría en Educación Inclusiva': '1487',
  'Maestría en Educación': '1488',
  'Maestría en Pedagogía': '1480 (no escolarizada) · 1478 (mixta)',
  'Maestría en Psicopedagogía': '1481 (no escolarizada) · 1479 (mixta)',
  'Doctorado en Educación con Énfasis en Investigación': '1485',
  'Doctorado en Ciencias de la Educación': 'DGES-16',
};

/// '5216421305193' → '+52 1 642 130 5193'
String formatoWhatsApp(String n) {
  final d = n.replaceAll(RegExp(r'\D'), '');
  if (d.length != 13) return '+$d';
  return '+${d.substring(0, 2)} ${d.substring(2, 3)} ${d.substring(3, 6)} ${d.substring(6, 9)} ${d.substring(9)}';
}

/// Búsqueda del domicilio oficial en el mapa.
String get urlMapaCessum => 'https://www.google.com/maps/search/?api=1&query='
    '${Uri.encodeComponent('$domicilioCalle, $domicilioColonia, $domicilioCiudad, $domicilioCP')}';

class AcercaSeccion extends StatelessWidget {
  final String titulo;
  final List<Widget> children;
  const AcercaSeccion({super.key, required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            titulo.toUpperCase(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cessumRed, letterSpacing: 0.5),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cessumEsOscuro(context) ? Theme.of(context).cardColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class AcercaFila extends StatelessWidget {
  final IconData icono;
  final String texto;
  const AcercaFila({super.key, required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: cessumMuted(context)),
          const SizedBox(width: 12),
          Expanded(child: Text(texto, style: TextStyle(fontSize: 14, color: cessumInk(context)))),
        ],
      ),
    );
  }
}

class AcercaFilaAccion extends StatelessWidget {
  final IconData icono;
  final String etiqueta;
  final String valor;
  final Color color;
  final VoidCallback onTap;
  const AcercaFilaAccion({
    super.key,
    required this.icono,
    required this.etiqueta,
    required this.valor,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icono, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(etiqueta, style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  const SizedBox(height: 2),
                  Text(valor, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cessumInk(context))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color),
          ],
        ),
      ),
    );
  }
}

/// Razón social, domicilio y «Cómo llegar».
class AcercaInstitucion extends StatelessWidget {
  const AcercaInstitucion({super.key});

  @override
  Widget build(BuildContext context) {
    return AcercaSeccion(
      titulo: 'Institución',
      children: [
        const AcercaFila(icono: Icons.business, texto: razonSocialCompleta),
        const AcercaFila(
          icono: Icons.place,
          texto: '$domicilioCalle, $domicilioColonia\n$domicilioCiudad, $domicilioCP, $domicilioPais',
        ),
        AcercaFilaAccion(
          icono: Icons.map_outlined,
          etiqueta: 'Cómo llegar',
          valor: 'Ver en el mapa',
          color: cessumGold,
          onTap: () => Helpers.abrirUrlExterna(urlMapaCessum, context),
        ),
      ],
    );
  }
}

/// Sitio web y aviso de privacidad.
class AcercaEnLinea extends StatelessWidget {
  const AcercaEnLinea({super.key});

  @override
  Widget build(BuildContext context) {
    return AcercaSeccion(
      titulo: 'En línea',
      children: [
        AcercaFilaAccion(
          icono: Icons.public,
          etiqueta: 'Sitio web',
          valor: 'www.cessum.mx',
          color: cessumGold,
          onTap: () => Helpers.abrirUrlExterna(sitioWebUrl, context),
        ),
        AcercaFilaAccion(
          icono: Icons.privacy_tip,
          etiqueta: 'Aviso de privacidad',
          valor: 'Ver aviso completo',
          color: cessumGold,
          onTap: () => Helpers.abrirUrlExterna(avisoPrivacidadUrl, context),
        ),
      ],
    );
  }
}

/// Oferta académica con el RVOE de cada programa.
class AcercaOferta extends StatelessWidget {
  const AcercaOferta({super.key});

  @override
  Widget build(BuildContext context) {
    return AcercaSeccion(
      titulo: 'Oferta académica',
      children: [
        for (final p in programasAcademicos)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 10),
                child: Icon(Icons.school, size: 18, color: cessumRed),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.nombre, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: cessumInk(context))),
                  if (rvoePorPrograma[p.nombre] != null)
                    Text('RVOE ${rvoePorPrograma[p.nombre]}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

/// Pie con razón social.
class AcercaPie extends StatelessWidget {
  const AcercaPie({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Container(height: 1, width: 60, color: Theme.of(context).dividerColor),
          const SizedBox(height: 16),
          Text(
            razonSocialCompleta,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cessumMuted(context), fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text('Todos los derechos reservados',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cessumFaint(context))),
        ],
      ),
    );
  }
}

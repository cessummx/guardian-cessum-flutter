import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'cessum_header.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'acerca_comun.dart';   // (24-sep) oferta académica con RVOE, compartida

/// Pantalla institucional "Acerca de CESSUM": identidad, mascota, oferta
/// académica, contacto y datos oficiales.
class AcercaScreen extends StatelessWidget {
  const AcercaScreen({super.key});

  /// (24-sep) Si el enlace no se puede abrir, se avisa (antes se callaba).
  Future<void> _abrir(BuildContext context, String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: cessumRed,
        content: Text('No se pudo abrir: $url'),
      ));
    }
  }

  /// Búsqueda del domicilio oficial en el mapa (sale de las constantes).
  static String get _urlMapa => 'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeComponent('$domicilioCalle, $domicilioColonia, $domicilioCiudad, $domicilioCP')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CessumAppBar(titulo: 'Acerca de CESSUM'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: Image.asset('assets/images/maaso_emblema.png', height: 150),
          ),
          SizedBox(height: 18),
          Text(
            'Más que una universidad, una familia.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w600,
              color: cessumGold,
            ),
          ),
          SizedBox(height: 22),
          _seccion('Nuestra mascota: MAASO'),
          Text(
            'En la lengua Mayo, venado se dice maaso. El idioma Mayo pertenece a '
            'la familia yuto-nahua, hablada en el sur de Sonora y norte de '
            'Sinaloa. Entre los pueblos Mayo y Yaqui, el venado es un símbolo '
            'sagrado ligado a la naturaleza, la fertilidad y las ceremonias '
            'tradicionales. Por eso MAASO es el corazón de nuestra identidad.',
            style: TextStyle(fontSize: 14, height: 1.5, color: cessumInk(context)),
          ),
          SizedBox(height: 22),
          // (24-sep) Con el RVOE de cada programa (antes decía «Maestria» sin acento y sin RVOE).
          const AcercaOferta(),
          SizedBox(height: 22),
          _seccion('Contacto'),
          _fila(context, Icons.language, 'Sitio web', sitioWebUrl,
              () => _abrir(context, sitioWebUrl)),
          _fila(context, Icons.chat, 'Admisiones', telefonoAdmisionesFormateado,
              () => _abrir(context, 'https://wa.me/$whatsappAdmisionesNumero')),
          // (24-sep) Alumnos inscritos: su línea es otra (Atención a Estudiantes).
          _fila(context, Icons.support_agent, 'Alumnos', 'WhatsApp de Atención a Estudiantes',
              () => _abrir(context, 'https://wa.me/$whatsappNumero')),
          _fila(context, Icons.email, 'Correo', correoInstitucional,
              () => _abrir(context, 'mailto:$correoInstitucional')),
          SizedBox(height: 22),
          _seccion('Datos oficiales'),
          Text(
            razonSocialCompleta,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
          SizedBox(height: 4),
          Text(
            '$domicilioCalle, $domicilioColonia\n$domicilioCiudad, $domicilioCP',
            style: TextStyle(fontSize: 13, color: cessumMuted(context)),
          ),
          // (24-sep) Cómo llegar: abre el mapa con el domicilio oficial.
          _fila(context, Icons.place_outlined, 'Cómo llegar', 'Ver en el mapa',
              () => _abrir(context, _urlMapa)),
          SizedBox(height: 24),
          Center(
            child: Text(
              'Centro de Estudios Superiores del Mayo',
              style: TextStyle(fontSize: 11, color: cessumFaint(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: cessumRed,
          ),
        ),
      );

  Widget _fila(BuildContext context, IconData icon, String etq, String valor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 18, color: cessumGold),
            SizedBox(width: 10),
            Text('$etq:  ',
                style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600)),
            Expanded(
              child: Text(valor,
                  style: TextStyle(fontSize: 13.5, color: cessumRed)),
            ),
            Icon(Icons.open_in_new, size: 14, color: cessumFaint(context)),
          ],
        ),
      ),
    );
  }
}

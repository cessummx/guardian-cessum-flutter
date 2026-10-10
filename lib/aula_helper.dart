import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
// Carga condicional: en web NO se importa webview_flutter (no existe ahí).
import 'aula_native.dart' if (dart.library.html) 'aula_web_stub.dart'
    as plataforma;

/// Abre el Aula Virtual (Moodle).
/// - Web: en una pestaña nueva del navegador.
/// - Móvil: dentro de la app, en la WebView de siempre.
Future<void> abrirAula(BuildContext context) async {
  if (kIsWeb) {
    await launchUrl(
      Uri.parse(moodleUrl),
      webOnlyWindowName: '_blank',
    );
  } else {
    await plataforma.pushAula(context);
  }
}

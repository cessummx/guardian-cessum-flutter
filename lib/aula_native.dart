import 'package:flutter/material.dart';

import 'webview_screen.dart';

/// Versión móvil: abre el Aula dentro de la app usando la WebView existente.
Future<void> pushAula(BuildContext context) async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const WebViewScreen()),
  );
}

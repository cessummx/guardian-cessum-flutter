import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// En web, Google obliga a usar SU botón oficial. renderButton() devuelve
/// ese widget ya conectado al flujo de inicio de sesión.
Widget buildGoogleSignInButton() {
  return web.renderButton();
}

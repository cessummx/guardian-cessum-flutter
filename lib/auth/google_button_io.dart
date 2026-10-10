import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// En móvil/escritorio se permite UI propia: un botón normal que dispara
/// el flujo de autenticación. (En la app web nunca se usa este archivo.)
Widget buildGoogleSignInButton() {
  return ElevatedButton.icon(
    onPressed: () async {
      try {
        if (GoogleSignIn.instance.supportsAuthenticate()) {
          await GoogleSignIn.instance.authenticate();
        }
      } catch (_) {}
    },
    icon: const Icon(Icons.login),
    label: const Text('Iniciar sesión con Google'),
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFC8202F),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    ),
  );
}

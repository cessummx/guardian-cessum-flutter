import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controla el modo claro/oscuro de toda la app y lo recuerda entre sesiones.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

const String _kThemeKey = 'cessum_tema';

Future<void> cargarTema() async {
  try {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kThemeKey);
    themeNotifier.value = v == 'dark' ? ThemeMode.dark : ThemeMode.light;
  } catch (_) {}
}

Future<void> guardarTema(ThemeMode modo) async {
  themeNotifier.value = modo;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeKey, modo == ThemeMode.dark ? 'dark' : 'light');
  } catch (_) {}
}

/// Controla el TAMAÑO DE LETRA de toda la app (accesibilidad) y lo recuerda
/// entre sesiones. 1.0 = normal; valores mayores agrandan el texto.
final ValueNotifier<double> textScaleNotifier = ValueNotifier(1.0);

const String _kTextScaleKey = 'cessum_text_scale';

Future<void> cargarTextScale() async {
  try {
    final p = await SharedPreferences.getInstance();
    final v = p.getDouble(_kTextScaleKey);
    if (v != null && v >= 0.8 && v <= 1.6) textScaleNotifier.value = v;
  } catch (_) {}
}

Future<void> guardarTextScale(double escala) async {
  final e = escala.clamp(0.8, 1.6);
  textScaleNotifier.value = e;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kTextScaleKey, e);
  } catch (_) {}
}

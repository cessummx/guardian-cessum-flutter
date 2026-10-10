import 'package:shared_preferences/shared_preferences.dart';

// Tipos de perfil que existen en la app
enum ProfileType {
  student,
  teacher,
  visitor, // "Soy nuevo" - prospecto sin perfil guardado
}

const String _activeProfileKey = 'last_active_profile';

class ActiveProfile {
  // Guarda cuál fue el último perfil usado, para que la app abra ahí la próxima vez.
  // (24-sep) Se guarda con el nombre del enum ('student', 'teacher', 'visitor'):
  // son exactamente los mismos textos que antes, así que los perfiles ya
  // guardados se siguen leyendo igual, y un perfil nuevo no requiere tocar
  // dos «switch» a mano.
  static Future<void> setActive(ProfileType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeProfileKey, type.name);
  }

  // Lee el último perfil usado (null si nunca abrieron la app, lo limpiaron
  // o el valor guardado ya no corresponde a ningún perfil).
  static Future<ProfileType?> getActive() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeProfileKey);
    if (raw == null) return null;
    for (final t in ProfileType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }

  // Limpia el último perfil activo (la app pedirá elegir de nuevo al abrir).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeProfileKey);
  }
}

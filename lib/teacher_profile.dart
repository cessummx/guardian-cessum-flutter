import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _teacherKey = 'teacher_profile_v1';

// Titulos academicos permitidos
const List<String> titulosAcademicos = [
  'Dr.',
  'Dra.',
  'Mtro.',
  'Mtra.',
  'Lic.',
  'Ing.',
  'Prof.',
  'Profa.',
];

class TeacherProfile {
  final String titulo;
  final String nombreCompleto;

  const TeacherProfile({
    required this.titulo,
    required this.nombreCompleto,
  });

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'nombreCompleto': nombreCompleto,
      };

  static TeacherProfile? fromJson(Map<String, dynamic> json) {
    final titulo = json['titulo']?.toString();
    final nombreCompleto = json['nombreCompleto']?.toString();

    if (titulo == null ||
        nombreCompleto == null ||
        titulo.isEmpty ||
        nombreCompleto.isEmpty) {
      return null;
    }

    return TeacherProfile(
      titulo: titulo,
      nombreCompleto: nombreCompleto,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_teacherKey, jsonEncode(toJson()));
  }

  static Future<TeacherProfile?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_teacherKey);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return TeacherProfile.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_teacherKey);
  }

  // Saludo completo: "Dr. Carlos Mendez"
  String get saludoCompleto => '$titulo $nombreCompleto';
}
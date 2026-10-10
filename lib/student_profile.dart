import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _perfilKey = 'student_profile_v2';
const String _perfilKeyOld = 'student_profile_v1';

class StudentProfile {
  final String matricula;
  final String nombreCompleto;
  final String programa;
  final String modalidad;
  final String generacion;
  final String curp;
  // true cuando un administrador entró "como este alumno" (vista previa).
  // En ese caso la pantalla Mi progreso permite editar calificaciones.
  final bool esVistaAdmin;

  const StudentProfile({
    required this.matricula,
    required this.nombreCompleto,
    required this.programa,
    required this.modalidad,
    required this.generacion,
    this.curp = '',
    this.esVistaAdmin = false,
  });

  Map<String, dynamic> toJson() => {
        'matricula': matricula,
        'nombreCompleto': nombreCompleto,
        'programa': programa,
        'modalidad': modalidad,
        'generacion': generacion,
        'curp': curp,
        'esVistaAdmin': esVistaAdmin,
      };

  static StudentProfile? fromJson(Map<String, dynamic> json) {
    final matricula = json['matricula']?.toString();
    final nombreCompleto = json['nombreCompleto']?.toString() ?? '';
    final programa = json['programa']?.toString();
    final modalidad = json['modalidad']?.toString();
    final generacion = json['generacion']?.toString();
    // La CURP puede faltar en perfiles guardados antes de esta version;
    // por eso NO se incluye en la validacion de abajo (no bloquea la carga).
    final curp = json['curp']?.toString() ?? '';
    final esVistaAdmin = json['esVistaAdmin'] == true;

    if (matricula == null ||
        programa == null ||
        modalidad == null ||
        generacion == null ||
        matricula.isEmpty ||
        programa.isEmpty ||
        modalidad.isEmpty ||
        generacion.isEmpty) {
      return null;
    }

    return StudentProfile(
      matricula: matricula,
      nombreCompleto: nombreCompleto,
      programa: programa,
      modalidad: modalidad,
      generacion: generacion,
      curp: curp,
      esVistaAdmin: esVistaAdmin,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_perfilKey, jsonEncode(toJson()));
  }

  static Future<StudentProfile?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString(_perfilKey);
      // Compatibilidad con version anterior sin nombreCompleto
      raw ??= prefs.getString(_perfilKeyOld);
      if (raw == null || raw.isEmpty) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return StudentProfile.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_perfilKey);
    await prefs.remove(_perfilKeyOld);
  }

  String get saludoCorto => 'Matricula: $matricula';
  String get descripcionCorta => '$programa - $generacion';
}

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'alumnos_service.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'curps_service.dart';
import 'student_profile.dart';

/// Resultado de intentar vincular automaticamente al alumno con sus datos
/// a partir del correo con el que inicio sesion.
enum AutoLinkResultado {
  /// Se encontro al alumno y se guardo su perfil automaticamente.
  vinculado,

  /// El correo es de un profesor (no es alumno).
  esProfesor,

  /// El correo esta marcado como baja: no debe entrar como alumno activo.
  baja,

  /// El correo no esta en la lista: hay que pedir registro / captura manual.
  noEncontrado,

  /// No habia correo de sesion (p.ej. en movil sin login): seguir flujo normal.
  sinCorreo,
}

/// Conecta el correo de la sesion con la lista de alumnos (alumnos.json)
/// y, si lo encuentra, autocompleta y guarda el StudentProfile.
class StudentAutoLink {
  /// Intenta vincular usando el correo guardado en la sesion.
  /// Devuelve el resultado para que la pantalla decida a donde ir.
  static Future<AutoLinkResultado> intentarVincular(
      {bool preferirAlumno = false}) async {
    final correo = await SessionStore.validEmail();
    if (correo == null || correo.isEmpty) {
      return AutoLinkResultado.sinCorreo;
    }
    return intentarVincularCorreo(correo, preferirAlumno: preferirAlumno);
  }

  /// Igual que [intentarVincular], pero con un correo dado.
  ///
  /// (14-sep) [preferirAlumno] es para quien está en los dos padrones: al
  /// elegir "Soy alumno" se le vincula su perfil de alumno en vez de
  /// rebotarlo al de docente. Antes, los cuatro casos de doble rol que había
  /// terminaban capturando su perfil a mano aunque el padrón lo tuviera.
  static Future<AutoLinkResultado> intentarVincularCorreo(String correo,
      {bool preferirAlumno = false}) async {
    final res =
        await AlumnosService.buscar(correo, preferirAlumno: preferirAlumno);

    switch (res.estado) {
      case EstadoAlumno.activo:
        final a = res.alumno!;
        final curp = await CurpsService.curpDe(a.matricula);
        final perfil = StudentProfile(
          matricula: a.matricula,
          nombreCompleto: a.nombre,
          programa: a.programa,
          modalidad: a.modalidad,
          generacion: a.generacion,
          curp: curp,
        );
        await perfil.save();
        return AutoLinkResultado.vinculado;

      case EstadoAlumno.profesor:
        return AutoLinkResultado.esProfesor;

      case EstadoAlumno.baja:
        return AutoLinkResultado.baja;

      case EstadoAlumno.noEncontrado:
        return AutoLinkResultado.noEncontrado;
    }
  }

  /// Re-sincroniza en segundo plano un perfil de alumno YA guardado con el
  /// padrón (alumnos.json), por matrícula. Corrige Programa/Modalidad/Generación
  /// al formato oficial (con acentos) para que coincidan exactamente con el
  /// backend. Es silenciosa: ante cualquier error o si no hay padrón, deja el
  /// perfil intacto. No toca la vista previa de administrador ni el nombre.
  /// Devuelve el perfil resultante (actualizado o el mismo), o null si no había.
  static Future<StudentProfile?> sincronizarPerfilGuardado() async {
    final cargado = await StudentProfile.load();
    if (cargado == null) return null;
    if (cargado.esVistaAdmin) return cargado;
    // 'base' parte de un perfil ya verificado como no nulo; puede reemplazarse
    // si lo resolvemos por correo más abajo.
    var base = cargado;
    // Si el perfil no trae matrícula o programa, lo resolvemos por el correo
    // con el que inició sesión (igual que la vinculación inicial), para que
    // el programa siempre quede completo desde el padrón.
    if (base.matricula.trim().isEmpty || base.programa.trim().isEmpty) {
      try {
        final correo = await SessionStore.validEmail();
        if (correo != null && correo.isNotEmpty) {
          final res = await AlumnosService.buscar(correo);
          if (res.estado == EstadoAlumno.activo && res.alumno != null) {
            final a = res.alumno!;
            final curp = base.curp.isNotEmpty
                ? base.curp
                : await CurpsService.curpDe(a.matricula);
            base = StudentProfile(
              matricula: a.matricula,
              nombreCompleto:
                  base.nombreCompleto.isNotEmpty ? base.nombreCompleto : a.nombre,
              programa: a.programa,
              modalidad: a.modalidad,
              generacion: a.generacion,
              curp: curp,
            );
            await base.save();
          }
        }
      } catch (_) {}
    }
    if (base.matricula.trim().isEmpty) return base;
    try {
      // 1) Fuente CANÓNICA: datos del backend con los overrides del padrón ya
      //    aplicados (nombre/programa/modalidad/generación corregidos por admin).
      //    Si falla, caemos al alumnos.json estático (AlumnosService).
      String nombre = '';
      String programa = '';
      String modalidad = '';
      String generacion = '';
      bool obtenido = false;
      try {
        final uri = Uri.parse(guardianUrl).replace(queryParameters: {
          'accion': 'alumno_canonico',
          'matricula': base.matricula.trim(),
        });
        final resp = await http.get(uri).timeout(const Duration(seconds: 12));
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['alumno'] is Map) {
          final al = data['alumno'] as Map<String, dynamic>;
          nombre = (al['nombre'] ?? '').toString().trim();
          programa = (al['programa'] ?? '').toString().trim();
          modalidad = (al['modalidad'] ?? '').toString().trim();
          generacion = (al['generacion'] ?? '').toString().trim();
          obtenido =
              programa.isNotEmpty || modalidad.isNotEmpty || nombre.isNotEmpty;
        }
      } catch (_) {
        obtenido = false;
      }

      if (!obtenido) {
        final a =
            await AlumnosService.buscarPorMatricula(base.matricula.trim());
        if (a == null) return base;
        nombre = a.nombre.trim();
        programa = a.programa.trim();
        modalidad = a.modalidad.trim();
        generacion = a.generacion.trim();
      }

      // Si algún campo viene vacío, conservamos el del perfil base.
      nombre = nombre.isNotEmpty ? nombre : base.nombreCompleto;
      programa = programa.isNotEmpty ? programa : base.programa;
      modalidad = modalidad.isNotEmpty ? modalidad : base.modalidad;
      generacion = generacion.isNotEmpty ? generacion : base.generacion;

      final cambia = nombre != base.nombreCompleto ||
          programa != base.programa ||
          modalidad != base.modalidad ||
          generacion != base.generacion;
      if (!cambia) return base;

      final actualizado = StudentProfile(
        matricula: base.matricula,
        nombreCompleto: nombre,
        programa: programa,
        modalidad: modalidad,
        generacion: generacion,
        curp: base.curp,
      );
      await actualizado.save();
      return actualizado;
    } catch (_) {
      return base;
    }
  }
}

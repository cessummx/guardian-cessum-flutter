import 'package:flutter/material.dart';

import 'active_profile.dart';
import 'admin_config.dart';
import 'roles_service.dart';
import 'admin_preview_screen.dart';
import 'alumnos_service.dart';
import 'auth/session_store.dart';
import 'auth/auth_service.dart';
import 'auth/auth_gate.dart';
import 'splash_screen.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'autoevaluacion_tablero_screen.dart';
import 'menu_screen.dart';
import 'acceso_bloqueado_screen.dart';
import 'privacidad_gate.dart';
import 'new_user_screen.dart';
import 'profile_setup_screen.dart';
import 'reingreso_alumno_screen.dart';
import 'student_autolink.dart';
import 'student_profile.dart';
import 'teacher_menu_screen.dart';
import 'teacher_profile.dart';
import 'teacher_setup_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  // Borra todos los perfiles y el active profile. Util para resetear todo.
  static Future<void> clearAll() async {
    await ActiveProfile.clear();
    await StudentProfile.clear();
    await TeacherProfile.clear();
  }


  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // (14-sep) EL DOBLE ROL YA NO SE ESCRIBE A MANO.
  // Aquí vivía una lista de cuatro correos: quien fuera alumno y docente a la
  // vez tenía que estar en ella, así que hacer docente a una alumna obligaba
  // a editar este archivo, compilar y subir. Si alguien no se acordaba de ese
  // detalle, la persona se quedaba sin acceso a la mitad de lo suyo y no
  // había forma de saber por qué. El padrón ya sabe quién está en las dos
  // listas; basta con preguntárselo.
  Future<bool> _esDobleRol() async {
    final correo = (await SessionStore.validEmail())?.trim().toLowerCase();
    if (correo == null) return false;
    return AlumnosService.esDobleRol(correo);
  }

  StudentProfile? _studentProfile;
  TeacherProfile? _teacherProfile;
  bool _esAdmin = false;
  bool _impersonando = false;
  bool _esRespAutoeval = false;
  String _correoAutoeval = '';
  bool _cargando = true;
  // (25-sep) Alumno dado de baja: se detecta al iniciar sesión, ANTES de la
  // selección de perfil. Si también es docente, conserva el acceso de profesor.
  bool _esBaja = false;
  bool _bajaTambienDocente = false;

  /// Devuelve true si el correo de la sesión es de un alumno con BAJA.
  Future<bool> _consultarBaja() async {
    try {
      final real = (await SessionStore.realEmail())?.trim().toLowerCase() ?? '';
      final correo = (await SessionStore.validEmail())?.trim().toLowerCase() ?? '';
      // Un administrador «viendo como» alguien no se bloquea.
      if (correo.isEmpty || (real.isNotEmpty && real != correo)) return false;
      final res = await AlumnosService.buscar(correo, preferirAlumno: true);
      return res.estado == EstadoAlumno.baja;
    } catch (_) {
      return false;
    }
  }

  // (26-sep) BLOQUEO TEMPORAL DE ACCESO. Administración puede pausar el
  // acceso de un alumno (p. ej. por falta de pago) sin darlo de baja. Si el
  // Guardián lo reporta bloqueado, en vez del menú se muestra la pantalla
  // con el mensaje y la opción de avisar que ya pagó. Un administrador
  // «viendo como» alguien no se bloquea.
  Future<Map<String, dynamic>?> _consultarBloqueo() async {
    try {
      final real = (await SessionStore.realEmail())?.trim().toLowerCase() ?? '';
      final correo = (await SessionStore.validEmail())?.trim().toLowerCase() ?? '';
      if (correo.isEmpty || (real.isNotEmpty && real != correo)) return null;
      final mat = _studentProfile?.matricula ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'acceso_estado',
        if (mat.isNotEmpty) 'matricula': mat,
        'correo': correo,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 25));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && d['bloqueado'] == true) return d;
    } catch (_) {}
    return null;
  }

  Future<bool> _detenerSiBloqueado(BuildContext context) async {
    final b = await _consultarBloqueo();
    if (b == null || !context.mounted) return false;
    final nombre = _studentProfile?.nombreCompleto ?? ((await SessionStore.validEmail()) ?? '').split('@').first;
    if (!context.mounted) return true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccesoBloqueadoScreen(matricula: _studentProfile?.matricula ?? '', nombre: nombre, info: b),
      ),
    );
    return true;
  }

  Future<void> _verificarBajaAlEntrar() async {
    if (_esAdmin || _impersonando) return;
    if (!await _consultarBaja()) return;
    final correo = (await SessionStore.validEmail())?.trim().toLowerCase() ?? '';
    final docente = await AlumnosService.esProfesor(correo);
    // El perfil de alumno guardado ya no sirve: se borra para que la app no
    // la mande directo al menú en la siguiente apertura.
    try { await StudentProfile.clear(); } catch (_) {}
    if (!mounted) return;
    setState(() {
      _esBaja = true;
      _bajaTambienDocente = docente;
      _studentProfile = null;
    });
    if (!docente && mounted) await _avisoBajaConReingreso(context);
  }

  @override
  void initState() {
    super.initState();
    _cargarPerfiles();
    _verificarResponsableAutoeval();
  }

  Future<void> _cargarPerfiles() async {
    final s = await StudentProfile.load();
    final t = await TeacherProfile.load();
    // Precargar roles dinámicos para reconocer admins que no están en la lista fija.
    try { await RolesService.precargar(); } catch (_) {}
    // Para decidir si eres administrador usamos tu correo REAL, no el del
    // alumno que estés viendo: al suplantar, validEmail() devuelve el correo
    // del alumno y eso ocultaba la entrada de administrador.
    final realCorreo = await SessionStore.realEmail();
    final efectivo = await SessionStore.validEmail();
    if (!mounted) return;
    setState(() {
      _studentProfile = s;
      _teacherProfile = t;
      _esAdmin = esAdmin(realCorreo) || esAdmin(efectivo);
      _impersonando = SessionStore.impersonation.value != null &&
          SessionStore.impersonation.value!.isNotEmpty;
      _cargando = false;
    });
    // (25-sep) En cuanto se sabe quién es: ¿está dado de baja?
    _verificarBajaAlEntrar();
  }

  // Pregunta al Guardián si este usuario es responsable de alguna carpeta de
  // autoevaluación. Si lo es, mostramos su acceso directo a "Mis carpetas".
  Future<void> _verificarResponsableAutoeval() async {
    try {
      final correo = (await SessionStore.validEmail())?.trim() ?? '';
      if (correo.isEmpty) return;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'autoeval_es_responsable',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true && data['esResponsable'] == true) {
        setState(() {
          _esRespAutoeval = true;
          _correoAutoeval = correo;
        });
      }
    } catch (_) {}
  }

  // Sale del modo "Ver como alumno real" y regresa al panel de administrador.
  Future<void> _volverAAdmin(BuildContext context) async {
    await SessionStore.stopImpersonation();
    await StudentProfile.clear();
    await ActiveProfile.clear();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AdminPreviewScreen()),
      (route) => false,
    );
  }

  Future<void> _onStudent(BuildContext context) async {
    // (25-sep) La baja se revisa SIEMPRE, también con perfil guardado: antes,
    // quien había entrado antes de su baja pasaba directo al menú.
    if (_esBaja || await _consultarBaja()) {
      try { await StudentProfile.clear(); } catch (_) {}
      if (!context.mounted) return;
      setState(() { _esBaja = true; _studentProfile = null; });
      await _avisoBajaConReingreso(context);
      return;
    }
    // (26-sep) Acceso pausado por Administración: se detiene aquí.
    if (await _detenerSiBloqueado(context)) return;
    if (!context.mounted) return;
    // (27-sep) Art. 66, Acuerdo 17/11/17: aviso de privacidad, si hace falta.
    await PrivacidadGate.revisarYMostrar(context);
    if (!context.mounted) return;
    await ActiveProfile.setActive(ProfileType.student);
    if (!context.mounted) return;

    // Si ya tiene perfil guardado, entra directo a su menu.
    if (_studentProfile != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MenuScreen()),
      );
      return;
    }

    // No tiene perfil: intentamos autocompletarlo desde la lista de alumnos
    // (alumnos.json) usando el correo con el que inicio sesion.
    // Eligió "Soy alumno": si está en los dos padrones, se le vincula su
    // perfil de alumno en vez de rebotarlo al de docente.
    final resultado =
        await StudentAutoLink.intentarVincular(preferirAlumno: true);
    if (!context.mounted) return;

    switch (resultado) {
      case AutoLinkResultado.vinculado:
        // Se encontro al alumno y se guardo su perfil: directo a su menu.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MenuScreen()),
        );
        break;

      case AutoLinkResultado.baja:
        await _avisoBajaConReingreso(context);
        break;

      case AutoLinkResultado.esProfesor:
        // Si es doble rol (alumno+profesor), NO lo rebotamos: lo dejamos
        // capturar/usar su perfil de alumno.
        // Con preferirAlumno, quien está en los dos padrones ya entró como
        // alumno más arriba. Aquí solo cae quien es docente y NO aparece como
        // alumno: se le deja capturar su perfil a mano, por si acaba de
        // inscribirse y el padrón todavía no lo refleja.
        if (await _esDobleRol()) {
          if (!context.mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
          );
        } else {
          _mostrarMensaje(
            context,
            'Cuenta de docente',
            'Tu correo esta registrado como personal docente. '
                'Por favor entra con el perfil "Soy profesor".',
          );
        }
        break;

      case AutoLinkResultado.noEncontrado:
        // Si el correo es institucional @cessum.mx pero no aparece en la base,
        // NO se permite captura manual: se envia a soporte tecnico.
        final correoNE =
            (await SessionStore.validEmail())?.trim().toLowerCase() ?? '';
        if (!context.mounted) return;
        if (correoNE.endsWith('@cessum.mx')) {
          _mostrarMensaje(
            context,
            'Usuario no habilitado',
            'Tu correo institucional aun no esta habilitado como alumno en el '
                'sistema. Comunicate con soporte tecnico (soporte@cessum.mx) '
                'para que habiliten tu usuario o revisen por que no apareces '
                'matriculado. Por seguridad, no es posible capturar los datos '
                'de forma manual.',
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
          );
        }
        break;

      case AutoLinkResultado.sinCorreo:
        // Sin correo de sesion (p.ej. movil sin login): captura manual.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
        );
        break;
    }
  }

  /// (ago-28) LA PUERTA DE LA BAJA ERA UN CALLEJÓN SIN SALIDA.
  ///
  /// La pantalla de reingreso existe (`reingreso_alumno_screen.dart`) y el
  /// backend la soporta (`reingreso_elegible`, `reingreso_iniciar`), pero su
  /// única entrada estaba en el menú del alumno — o sea, adentro de la app.
  /// Y a un alumno de baja se le bloquea justo en la puerta. La pantalla
  /// pensada para las bajas era inalcanzable precisamente para ellas: lo
  /// único que veían era "contacta a control escolar", que los manda a
  /// WhatsApp a hacer a mano lo que el sistema ya sabe hacer.
  ///
  /// Ahora el aviso ofrece el botón. Se consulta `reingreso_elegible` con
  /// su matrícula: si procede, entra a solicitarlo; si no —porque pasó el
  /// plazo y el plan de estudios cambió—, se le dice y se le deja el
  /// contacto, que es la respuesta honesta.
  Future<void> _avisoBajaConReingreso(BuildContext context) async {
    String? matricula;
    try {
      final correo = await SessionStore.validEmail();
      if (correo != null && correo.isNotEmpty) {
        final r = await http
            .get(Uri.parse(
                '$guardianUrl?accion=buscar_alumno&q=${Uri.encodeComponent(correo)}'))
            .timeout(const Duration(seconds: 20));
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        final lista = (d['alumnos'] as List<dynamic>?) ?? [];
        if (lista.isNotEmpty) {
          matricula =
              ((lista.first as Map)['matricula'] ?? '').toString().trim();
        }
      }
    } catch (_) {}

    var elegible = false;
    if (matricula != null && matricula.isNotEmpty) {
      try {
        final r = await http
            .get(Uri.parse(
                '$guardianUrl?accion=reingreso_elegible&matricula=${Uri.encodeComponent(matricula)}'))
            .timeout(const Duration(seconds: 20));
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        elegible = d['ok'] == true && d['elegible'] == true;
      } catch (_) {}
    }

    if (!context.mounted) return;
    final mat = matricula ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tu inscripción está dada de baja'),
        content: Text(
          elegible
              ? 'Puedes solicitar tu reingreso desde aquí. Vicerrectoría '
                  'revisará tu solicitud y te dirá qué sigue.'
              : 'Tu correo aparece como baja en nuestros registros. Si crees '
                  'que es un error, o quieres retomar tus estudios, contacta '
                  'a control escolar.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(elegible ? 'Ahora no' : 'Entendido'),
          ),
          if (elegible && mat.isNotEmpty)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ReingresoAlumnoScreen(matricula: mat)),
                );
              },
              child: const Text('Solicitar reingreso'),
            ),
        ],
      ),
    );
  }

  void _mostrarMensaje(BuildContext context, String titulo, String mensaje) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _onTeacher(BuildContext context) async {
    await ActiveProfile.setActive(ProfileType.teacher);
    if (!context.mounted) return;

    // Si ya tiene perfil docente guardado, entra directo (ya fue validado).
    if (_teacherProfile != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TeacherMenuScreen()),
      );
      return;
    }

    // No tiene perfil: verificamos que su correo este en la lista de docentes.
    final correo = await SessionStore.validEmail();
    if (!context.mounted) return;

    // Sin correo de sesion: dejamos capturar a mano (no bloqueamos por error).
    if (correo == null || correo.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TeacherSetupScreen()),
      );
      return;
    }

    final res = await AlumnosService.buscar(correo);
    if (!context.mounted) return;

    switch (res.estado) {
      case EstadoAlumno.profesor:
        // Reconocido como docente: pasa a su perfil (se autocompleta ahi).
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TeacherSetupScreen()),
        );
        break;

      case EstadoAlumno.activo:
        // Si es doble rol (alumno+profesor), NO lo rebotamos: lo dejamos
        // entrar a configurar/usar su perfil de docente.
        if (await _esDobleRol()) {
          if (!context.mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TeacherSetupScreen()),
          );
        } else {
          _mostrarMensaje(
            context,
            'Perfil incorrecto',
            'Tu correo esta registrado como alumno, no como docente. '
                'Por favor entra con el perfil "Soy estudiante".',
          );
        }
        break;

      case EstadoAlumno.baja:
        await _avisoBajaConReingreso(context);
        break;

      case EstadoAlumno.noEncontrado:
        // No esta en la lista de docentes: bloqueado.
        _mostrarMensaje(
          context,
          'No te reconocemos como docente',
          'Tu correo no esta registrado como personal docente de CESSUM. '
              'Si eres profesor y necesitas acceso, contacta a CESSUM.',
        );
        break;
    }
  }

  Future<void> _onVisitor(BuildContext context) async {
    await ActiveProfile.setActive(ProfileType.visitor);
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const NewUserScreen()),
    );
  }

  Future<void> _cerrarSesion(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Seguro que quieres cerrar sesión? Tendrás que volver a entrar '
          'con tu correo institucional @cessum.mx.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!context.mounted) return;

    // Borramos lo esencial primero: perfiles locales y sesión guardada.
    // Esto es lo que de verdad controla si la app te deja entrar o no.
    await WelcomeScreen.clearAll();
    await SessionStore.clear();

    // El signOut de Google puede colgarse en web (disconnect no siempre
    // responde). Por eso NO lo esperamos con await: lo lanzamos en segundo
    // plano con un límite de tiempo, para que nunca bloquee la navegación.
    AuthService.instance
        .signOut()
        .timeout(const Duration(seconds: 3))
        .catchError((_) {});

    if (!context.mounted) return;
    // Vamos directo al portón de entrada. Como ya borramos la sesión local,
    // mostrará la pantalla de inicio de sesión.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthGate(child: SplashScreen())),
      (route) => false,
    );
  }

  /// (25-sep) Pantalla para el alumno dado de baja: en lugar de la selección
  /// de perfil, el aviso y lo que sí puede hacer.
  Widget _pantallaBaja(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.school_outlined, size: 56, color: cessumRed),
            const SizedBox(height: 14),
            Text('Tu inscripción está dada de baja',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cessumInk(context))),
            const SizedBox(height: 10),
            Text(
              'Por eso no puedes entrar como estudiante. Si quieres retomar tus estudios, '
              'puedes solicitar tu reingreso: Vicerrectoría revisará tu caso y te dirá qué sigue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.5, color: cessumMuted(context)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _avisoBajaConReingreso(context),
                icon: const Icon(Icons.refresh),
                label: const Text('Solicitar reingreso'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _cerrarSesion(context),
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ),
            const SizedBox(height: 16),
            Text('Dudas: contacto@cessum.mx',
                style: TextStyle(fontSize: 12.5, color: cessumFaint(context))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator(color: cessumRed))
            : (_esBaja && !_bajaTambienDocente)
            ? _pantallaBaja(context)
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    Image.asset(
                      'assets/images/logo.png',
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: 54,
                      height: 3,
                      decoration: BoxDecoration(
                        color: cessumGold,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Más que una universidad, una familia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        color: cessumGold,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Bienvenido',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: cessumInk(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Selecciona tu perfil',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: cessumMuted(context)),
                    ),
                    const SizedBox(height: 28),

                    // Tarjeta: Volver a administrador (cuando estás viendo
                    // como un alumno real). Te saca de la suplantación.
                    if (_impersonando) ...[
                      _OptionCard(
                        icon: Icons.arrow_back,
                        color: cessumRed,
                        title: 'Volver a administrador',
                        subtitle: 'Estás viendo como un alumno. '
                            'Toca para regresar a tu panel.',
                        configurado: false,
                        onTap: () => _volverAAdmin(context),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Tarjeta: Vista de administrador (solo para contacto@ / soporte@)
                    if (_esAdmin && !_impersonando) ...[
                      _OptionCard(
                        icon: Icons.admin_panel_settings,
                        color: cessumGold,
                        title: 'Vista de administrador',
                        subtitle: 'Previsualizar como estudiante o profesor',
                        configurado: false,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminPreviewScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Tarjeta: Mis carpetas de autoevaluacion (solo responsables)
                    if (_esRespAutoeval && !_impersonando) ...[
                      _OptionCard(
                        icon: Icons.fact_check_outlined,
                        color: cessumRed,
                        title: 'Mis carpetas de autoevaluacion',
                        subtitle: 'Da seguimiento a las carpetas que tienes asignadas.',
                        configurado: false,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AutoevaluacionTableroScreen(
                              soloCorreo: _correoAutoeval,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Tarjeta: Soy estudiante
                    _OptionCard(
                      icon: Icons.school,
                      color: cessumRed,
                      title: 'Soy estudiante',
                      subtitle: _studentProfile != null
                          ? _studentProfile!.nombreCompleto.isNotEmpty
                              ? _studentProfile!.nombreCompleto
                              : 'Matricula: ${_studentProfile!.matricula}'
                          : 'Aula virtual y servicios',
                      configurado: _studentProfile != null,
                      onTap: () => _onStudent(context),
                    ),
                    const SizedBox(height: 14),

                    // Tarjeta: Soy profesor
                    _OptionCard(
                      icon: Icons.cast_for_education,
                      color: cessumRed,
                      title: 'Soy profesor',
                      subtitle: _teacherProfile != null
                          ? _teacherProfile!.saludoCompleto
                          : 'Aula virtual y herramientas docentes',
                      configurado: _teacherProfile != null,
                      onTap: () => _onTeacher(context),
                    ),
                    const SizedBox(height: 14),

                    // Tarjeta: Soy nuevo
                    _OptionCard(
                      icon: Icons.person_add,
                      color: cessumGold,
                      title: 'Soy nuevo',
                      subtitle: 'Conoce la oferta educativa',
                      configurado: false,
                      onTap: () => _onVisitor(context),
                    ),

                    const SizedBox(height: 24),

                    // Cerrar sesión (última opción)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed, width: 1.3),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _cerrarSesion(context),
                        icon: const Icon(Icons.logout, size: 20),
                        label: const Text(
                          'Cerrar sesión',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    Text(
                      'Aula CESSUM',
                      style: TextStyle(
                        color: cessumFaint(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool configurado;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.configurado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: configurado
                  ? color.withValues(alpha: 0.5)
                  : Colors.black12,
              width: configurado ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        if (configurado) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 11,
                                  color: color,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Listo',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

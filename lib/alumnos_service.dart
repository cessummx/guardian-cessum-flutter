import 'dart:convert';

import 'package:http/http.dart' as http;

import 'constants.dart';

/// Datos de un alumno vinculado por su correo institucional.
class AlumnoInfo {
  final String correo;
  final String nombre;
  final String matricula;
  final String generacion;
  final String programa;
  final String modalidad;
  final String estatus;

  const AlumnoInfo({
    required this.correo,
    required this.nombre,
    required this.matricula,
    required this.generacion,
    required this.programa,
    required this.modalidad,
    this.estatus = 'Activo',
  });

  /// true si el alumno está dado de baja (segun el campo estatus del padron).
  bool get esBaja => estatus.trim().toLowerCase() == 'baja';

  factory AlumnoInfo.fromJson(Map<String, dynamic> j) {
    return AlumnoInfo(
      correo: (j['correo'] ?? '').toString(),
      nombre: (j['nombre'] ?? '').toString(),
      matricula: (j['matricula'] ?? '').toString(),
      generacion: (j['generacion'] ?? '').toString(),
      programa: (j['programa'] ?? '').toString(),
      modalidad: (j['modalidad'] ?? '').toString(),
      // Si el padron no trae estatus, se asume Activo (compatibilidad).
      estatus: (j['estatus'] ?? 'Activo').toString(),
    );
  }
}

/// Resultado de buscar un correo en la lista.
enum EstadoAlumno {
  /// El correo es de un profesor / personal docente.
  profesor,

  /// El correo es de un alumno activo: trae sus datos.
  activo,

  /// El correo está marcado como baja: no debe entrar como activo.
  baja,

  /// El correo no está en la lista: candidato a solicitar registro.
  noEncontrado,
}

class ResultadoAlumno {
  final EstadoAlumno estado;
  final AlumnoInfo? alumno;
  final String? nombreProfesor;
  final String? tituloProfesor;

  const ResultadoAlumno(this.estado,
      {this.alumno, this.nombreProfesor, this.tituloProfesor});
}

/// Servicio que lee la lista de alumnos desde el PADRON EN VIVO del Guardian
/// (guardian.php?accion=alumnos_json), que ya entrega altas/bajas/correcciones
/// aplicadas. NO se descarga el archivo estatico: todo cambio hecho en la app
/// se refleja aqui sin regenerar nada a mano.
///
/// Cachea en memoria un rato para no descargar el padron en cada consulta.
/// Tras un alta/baja/edicion, llamar a recargar() para traer lo mas reciente.
///
/// IMPORTANTE: los alumnos con estatus "Baja" siguen bloqueados para ENTRAR
/// (buscar() los reporta como EstadoAlumno.baja), pero desde ago-28 sí
/// aparecen en las listas de administración, marcados. Ver listarAlumnos().
/// Datos de un profesor del padrón (para "ver como profesor").
class ProfesorInfo {
  final String correo;
  final String nombre;
  final String titulo;
  const ProfesorInfo({
    required this.correo,
    required this.nombre,
    required this.titulo,
  });
}

class AlumnosService {
  static Map<String, AlumnoInfo>? _porCorreo;
  static Map<String, AlumnoInfo>? _porMatricula; // matricula -> datos
  static Map<String, Map<String, String>>? _profesores; // correo -> {nombre, titulo}
  static Set<String>? _bajas;
  static Map<String, AlumnoInfo>? _inactivos;
  static DateTime? _cacheTime;

  static const Duration _cacheDuration = Duration(minutes: 30);

  /// Descarga y cachea la lista. Devuelve true si la tiene lista.
  static Future<bool> _asegurarCargada({bool forzar = false}) async {
    final ahora = DateTime.now();
    final valido = _porCorreo != null &&
        _cacheTime != null &&
        ahora.difference(_cacheTime!) < _cacheDuration;
    if (!forzar && valido) return true;

    // (2-sep) EL LÍMITE DE 15 s ERA LA CAUSA DEL «No se pudo cargar la lista
    // de alumnos». El padrón en vivo se arma leyendo hojas completas y, medido
    // en un momento tranquilo, tarda ~7 s; cuando el Guardián trae cola —lo
    // normal a media mañana— pasa de 15 s sin problema. Al vencerse el plazo
    // saltaba al catch, no había cache que reusar y listarAlumnos devolvía
    // una lista vacía: la pantalla decía «no se pudo cargar» aunque el padrón
    // estuviera perfecto. Ahora se espera lo razonable y se reintenta una vez
    // antes de rendirse; y si aun así falla, se conserva el cache anterior.
    http.Response? resp;
    for (var intento = 0; intento < 2 && resp == null; intento++) {
      try {
        if (intento > 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        final r = await http
            .get(Uri.parse(alumnosJsonUrl))
            .timeout(const Duration(seconds: 60));
        if (r.statusCode == 200) resp = r;
      } catch (_) {
        // Se reintenta; si el segundo intento también falla, más abajo se
        // conserva lo que hubiera en cache.
      }
    }
    if (resp == null) return _porCorreo != null;

    try {
      final data =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;

      // (24-sep) Si el Guardián RECHAZA la consulta (p. ej. «sesión requerida»),
      // la respuesta trae ok:false y ninguna lista. Antes se tomaba como un
      // padrón vacío y se guardaba: todos salían «no encontrados» en la
      // bienvenida. Ahora se conserva lo que ya había en cache.
      if (data['ok'] == false || data['alumnos'] is! List) {
        return _porCorreo != null;
      }

      // Set de bajas: arranca con el arreglo "bajas" (compatibilidad con el
      // archivo estatico viejo) y se le suman los alumnos con estatus "Baja".
      final bajasRaw = (data['bajas'] as List<dynamic>?) ?? [];
      final bajas = <String>{
        for (final b in bajasRaw) _norm(b.toString()),
      };

      final lista = (data['alumnos'] as List<dynamic>?) ?? [];
      final mapa = <String, AlumnoInfo>{};
      final mapaMat = <String, AlumnoInfo>{};
      // Alumnos dados de baja: fuera de las listas activas, pero conservados
      // para que la administración pueda encontrarlos.
      final inactivos = <String, AlumnoInfo>{};
      for (final item in lista) {
        final a = AlumnoInfo.fromJson(item as Map<String, dynamic>);

        // (ago-28) LA BAJA BLOQUEA EL ACCESO, NO LA EXISTENCIA.
        // Este `continue` sacaba al alumno de los dos mapas, y con eso
        // desaparecía de TODA la app: del selector "Elegir alumno", del
        // expediente, de la aclaración de pagos. Vicerrectoría no podía
        // abrir el expediente de alguien dado de baja —justo cuando más se
        // busca: para una constancia, un adeudo, o para revertir una baja
        // mal capturada— y la pantalla respondía como si la persona no
        // existiera. Ahora se guardan aparte: siguen sin poder entrar
        // (buscar() los devuelve como baja, igual que antes), pero las
        // listas de administración los pueden mostrar marcados.
        if (a.esBaja) {
          if (a.correo.isNotEmpty) bajas.add(_norm(a.correo));
          if (a.matricula.trim().isNotEmpty) {
            inactivos.putIfAbsent(a.matricula.trim(), () => a);
          } else if (a.correo.isNotEmpty) {
            inactivos.putIfAbsent(_norm(a.correo), () => a);
          }
          continue;
        }

        // Dedup por correo/matrícula quedándose con la PRIMERA aparición.
        // El padrón en vivo pone primero la fila vigente (con overrides de
        // cambio de programa aplicados); es la misma regla que usa el resto
        // de la app. Antes ganaba la ÚLTIMA y un alumno promovido (p. ej. de
        // maestría a doctorado) salía en el buscador con su programa viejo.
        if (a.correo.isNotEmpty) {
          mapa.putIfAbsent(_norm(a.correo), () => a);
        }
        if (a.matricula.trim().isNotEmpty) {
          mapaMat.putIfAbsent(a.matricula.trim(), () => a);
        }
      }

      final profesRaw = (data['profesores'] as List<dynamic>?) ?? [];
      final profes = <String, Map<String, String>>{};
      for (final item in profesRaw) {
        final m = item as Map<String, dynamic>;
        final correo = _norm((m['correo'] ?? '').toString());
        if (correo.isNotEmpty) {
          profes[correo] = {
            'nombre': (m['nombre'] ?? '').toString(),
            'titulo': (m['titulo'] ?? '').toString(),
          };
        }
      }

      // (4-oct-2026) REINGRESOS. Un alumno que se dio de baja y volvió con la MISMA
      // cuenta (caso Katya Ramírez: Pedagogía 24-2 en baja, Educación 26-1 activa)
      // tiene dos filas con el mismo correo. La fila en baja metía su correo en
      // `bajas`, y buscar() lo consulta ANTES que nada: la app la trataba como baja,
      // no sincronizaba su perfil y seguía mostrando el programa viejo. Una baja
      // solo cuenta como baja si NO hay ninguna fila activa con ese correo.
      bajas.removeWhere((c) => mapa.containsKey(c));
      _porCorreo = mapa;
      _porMatricula = mapaMat;
      _bajas = bajas;
      _inactivos = inactivos;
      _profesores = profes;
      _cacheTime = ahora;
      return true;
    } catch (_) {
      // Sin conexión o error: usar lo que haya en cache, si hay.
      return _porCorreo != null;
    }
  }

  /// Normaliza un correo para comparar (minúsculas, sin espacios).
  static String _norm(String correo) => correo.trim().toLowerCase();

  /// (14-sep) ¿Este correo está en los DOS padrones?
  ///
  /// Pasa cada vez más: egresados que se incorporan como docentes, docentes
  /// que cursan un posgrado aquí. Hasta hoy se resolvía con una lista de
  /// cuatro correos escrita dentro de welcome_screen.dart, así que hacer
  /// docente a una alumna obligaba a editar código, compilar y subir; si
  /// alguien no se acordaba de ese detalle, la persona se quedaba sin la
  /// mitad de lo suyo y nadie entendía por qué.
  ///
  /// El padrón ya sabe las dos cosas: basta con preguntárselo.
  static Future<bool> esDobleRol(String correo) async {
    final ok = await _asegurarCargada();
    if (!ok) return false;
    final clave = _norm(correo);
    if (_bajas != null && _bajas!.contains(clave)) return false;
    final esProfe = _profesores?.containsKey(clave) ?? false;
    final esAlumno = _porCorreo?.containsKey(clave) ?? false;
    return esProfe && esAlumno;
  }

  /// Busca un correo en la lista y devuelve su estado y datos.
  ///
  /// [preferirAlumno] resuelve el empate cuando alguien está en los dos
  /// padrones: sin él gana siempre "profesor" —el mapa de profesores se
  /// consulta primero— y esa persona no podía entrar nunca como alumna.
  /// La pantalla de bienvenida lo pasa en true cuando el usuario eligió
  /// "Soy alumno": si él dijo con qué perfil quiere entrar, no hay empate
  /// que resolver.
  static Future<ResultadoAlumno> buscar(String correo,
      {bool preferirAlumno = false}) async {
    final ok = await _asegurarCargada();
    final clave = _norm(correo);

    // Si no se pudo cargar la lista, no bloqueamos al usuario:
    // lo tratamos como "no encontrado" para que el flujo siga.
    if (!ok || _porCorreo == null) {
      return const ResultadoAlumno(EstadoAlumno.noEncontrado);
    }

    if (_bajas != null && _bajas!.contains(clave)) {
      return const ResultadoAlumno(EstadoAlumno.baja);
    }

    final alumno = _porCorreo![clave];

    if (_profesores != null && _profesores!.containsKey(clave)) {
      // Está en los dos padrones y pidió entrar como alumno: se le deja.
      if (preferirAlumno && alumno != null) {
        return ResultadoAlumno(EstadoAlumno.activo, alumno: alumno);
      }
      final p = _profesores![clave]!;
      return ResultadoAlumno(EstadoAlumno.profesor,
          nombreProfesor: p['nombre'], tituloProfesor: p['titulo']);
    }

    if (alumno != null) {
      return ResultadoAlumno(EstadoAlumno.activo, alumno: alumno);
    }

    return const ResultadoAlumno(EstadoAlumno.noEncontrado);
  }

  /// Busca un alumno por su matrícula (para autocompletar el perfil).
  /// Devuelve null si la lista no cargó o la matrícula no está en el padrón.
  ///
  /// Sigue devolviendo SOLO vigentes: la usan profile_setup y el autoenlace
  /// del alumno, donde autocompletar el perfil de alguien dado de baja lo
  /// dejaría entrar con datos que ya no le corresponden. Para consultarlo
  /// desde administración está buscarPorMatriculaIncluyendoBajas().
  static Future<AlumnoInfo?> buscarPorMatricula(String matricula) async {
    final ok = await _asegurarCargada();
    final mat = matricula.trim();
    if (!ok || _porMatricula == null || mat.isEmpty) return null;
    return _porMatricula![mat];
  }

  /// Igual que buscarPorMatricula, pero encuentra también a los dados de
  /// baja. Para pantallas de administración: expedientes, adeudos, trámites
  /// y reversión de bajas mal capturadas.
  static Future<AlumnoInfo?> buscarPorMatriculaIncluyendoBajas(
      String matricula) async {
    final ok = await _asegurarCargada();
    final mat = matricula.trim();
    if (!ok || mat.isEmpty) return null;
    return (_porMatricula ?? const <String, AlumnoInfo>{})[mat] ??
        (_inactivos ?? const <String, AlumnoInfo>{})[mat];
  }

  /// Devuelve la lista completa de alumnos, ordenada por nombre.
  ///
  /// (ago-28) `incluirBajas` viene en true por omisión: las pantallas que
  /// usan esta lista son de administración —elegir alumno, expediente,
  /// aclaración de pagos— y en todas ellas esconder a un alumno de baja
  /// hace daño, porque son justo los casos que hay que atender. El alumno
  /// de baja sigue SIN poder entrar a la app: eso lo decide buscar(), que
  /// no cambió. Quien necesite solo vigentes, pasa false.
  ///
  /// Los egresados nunca estuvieron excluidos y siguen igual: solo la baja
  /// sacaba a alguien de estas listas.
  static Future<List<AlumnoInfo>> listarAlumnos(
      {bool incluirBajas = true}) async {
    final ok = await _asegurarCargada();
    if (!ok || _porCorreo == null) return <AlumnoInfo>[];
    // (ago-22) LA LISTA SALÍA SOLO DEL MAPA POR CORREO.
    // Un alumno sin correo en el padrón nunca entraba a ese mapa, así que
    // desaparecía por completo del selector "Elegir alumno": no era que la
    // búsqueda fallara, es que nunca estuvo en la lista. Sí está en el mapa
    // por matrícula, que es el que se usa en el resto de la app — de ahí que
    // el mismo alumno aparezca en una incidencia y no en el buscador.
    // Ahora se unen los dos, sin duplicar: la matrícula manda como llave y el
    // correo solo se usa cuando no hay matrícula.
    final vistos = <String>{};
    final lista = <AlumnoInfo>[];
    void agregar(AlumnoInfo a) {
      final mat = a.matricula.trim();
      final clave = mat.isNotEmpty ? 'm:$mat' : 'c:${_norm(a.correo)}';
      if (clave == 'c:') return;
      if (!vistos.add(clave)) return;
      lista.add(a);
    }

    for (final a in _porCorreo!.values) {
      agregar(a);
    }
    for (final a in (_porMatricula ?? const <String, AlumnoInfo>{}).values) {
      agregar(a);
    }
    if (incluirBajas) {
      for (final a in (_inactivos ?? const <String, AlumnoInfo>{}).values) {
        agregar(a);
      }
    }
    lista.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return lista;
  }

  /// Devuelve la lista COMPLETA de profesores del padrón, ordenada por nombre.
  /// La usa la vista de administrador para "ver como un profesor real".
  static Future<List<ProfesorInfo>> listarProfesores() async {
    final ok = await _asegurarCargada();
    if (!ok || _profesores == null) return <ProfesorInfo>[];
    final lista = _profesores!.entries
        .map((e) => ProfesorInfo(
              correo: e.key,
              nombre: (e.value['nombre'] ?? '').toString(),
              titulo: (e.value['titulo'] ?? '').toString(),
            ))
        .toList();
    lista.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    return lista;
  }

  /// Fuerza recargar la lista desde el servidor.
  /// Llamar tras un alta/baja/edicion para ver el cambio al instante.
  static Future<void> recargar() => _asegurarCargada(forzar: true);

  /// (25-sep) ¿Este correo está en el padrón de DOCENTES? Lo usa la
  /// bienvenida: un alumno dado de baja que también es docente conserva su
  /// acceso como profesor.
  static Future<bool> esProfesor(String correo) async {
    final ok = await _asegurarCargada();
    if (!ok) return false;
    return _profesores?.containsKey(_norm(correo)) ?? false;
  }
}

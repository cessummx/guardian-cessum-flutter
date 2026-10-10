import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'selector_buscable.dart'; // (24-sep) selectores largos con búsqueda
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'agenda_herramientas.dart';   // (23-sep) alertas, plan del periodo y carga docente
import 'error_reporter.dart';        // (28-sep, Fase 3) reportar lo que hoy se traga en silencio
import 'respuesta_guardian.dart';    // (28-sep, Fase 3) mensajes humanos + reporte automático
import 'auth/session_store.dart';    // (1-oct) usado por agenda_profesores_form.dart (part of)

// (23-sep) El formulario de asignación y la hoja de alumnos viven en su propio
// archivo (misma biblioteca: comparten lo privado, sin cambiar una línea).
part 'agenda_profesores_form.dart';

/// Normaliza un nombre de programa para comparar sin importar acentos,
/// mayúsculas ni espacios de más. Sirve para que "Maestría en Psicopedagogía"
/// y "Maestria en Psicopedagogia" se traten como el MISMO programa.
/// (23-sep) Fecha AAAA-MM-DD de un texto; tolera guiones tipográficos (– — ‑).
/// Antes estaba copiada, idéntica, en la pantalla y en el formulario.
DateTime? _fechaIsoTexto(String s) {
  final t = s.trim().replaceAll(RegExp(r'[\u2010\u2011\u2012\u2013\u2014]'), '-');
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

String _normaPrograma(String s) {
  var x = s.trim().toLowerCase();
  const acc = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const sin = 'aaaaaeeeeiiiiooooouuuun';
  final b = StringBuffer();
  for (final ch in x.split('')) {
    final i = acc.indexOf(ch);
    b.write(i >= 0 ? sin[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ');
}

/// Administración de la AGENDA DE PROFESORES (base de asignaciones).
/// Permite ver, crear, editar y borrar las asignaciones (programa, grupo,
/// materia, día, hora, maestro, links de videollamada y Aula CESSUM), y ver
/// qué grupos todavía no tienen maestro.
class AgendaProfesoresScreen extends StatefulWidget {
  const AgendaProfesoresScreen({super.key});

  @override
  State<AgendaProfesoresScreen> createState() => _AgendaProfesoresScreenState();
}

class _AgendaProfesoresScreenState extends State<AgendaProfesoresScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final TextEditingController _busqueda = TextEditingController();

  bool _cargando = true;
  String? _error;
  DateTime? _ultimaCarga;
  List<Map<String, dynamic>> _asignaciones = [];
  List<Map<String, dynamic>> _sinMaestro = [];
  List<Map<String, dynamic>> _pendientes = [];
  bool _mostrarTerminadas = false;
  final Set<String> _rosterAbierto = {};
  final Map<String, List<Map<String, dynamic>>> _rosterCache = {};
  final Set<String> _rosterCargando = {};
  bool _soloVigentes = true; // oculta materias que ya terminaron
  /* (3-oct-2026) HISTORIAL RECONSTRUIDO. La hoja tiene ~266 filas «Reconstruido desde Moodle»: sirven al kárdex, no a la agenda (día y hora
     aproximados, fechas de inicio de trimestre). El Guardián las marca con `reconstruida: true`. Aquí se ocultan por omisión al mostrar todas,
     llevan distintivo cuando se muestran y NO se colapsan como «impartición conjunta» (compartían docente, fechas y hora y la pantalla las
     apilaba en una sola tarjeta con cuatro materias que nunca se dieron juntas). */
  bool _verReconstruidas = false;
  bool _esReconstruida(Map<String, dynamic> a) => a['reconstruida'] == true;
  /// (ago-15) Filtro por momento. Con 92 asignaciones, encontrar las que
  /// están por arrancar obligaba a bajar hasta el fondo de la lista: quien
  /// prepara aulas y avisa a los docentes trabaja justamente sobre ésas.
  /// Valores: '' (todas las que pasen el filtro de vigencia), 'porIniciar',
  /// 'enCurso'.
  String _momento = '';

  /* (9-sep) FILTROS PARA UNA LISTA DE 101 ASIGNACIONES.
     «Solo vigentes y por iniciar» mezclaba lo que arranca la próxima semana
     con lo que arranca en tres meses, y en pantalla se veían iguales. Con
     33 materias visibles no se distingue lo que hay que preparar YA.
     Se agregan tres cortes que responden a preguntas distintas:
     cuándo empieza, de qué programa es, y de quién es. */
  int _dias = 0;              // 0 = sin límite; 7, 15 o 30 días por delante
  String _programaFiltro = '';
  String _docenteFiltro = '';
  // Catálogo: programa -> { generación -> [grupos] }
  Map<String, Map<String, List<String>>> _catalogo = {};
  // Generaciones EGRESADAS, como llaves "programa||generación" normalizadas.
  // Una generación se considera egresada cuando tiene alumnos, ninguno está
  // Activo y al menos uno es Egresado o Titulado (según clasificacion_alumnos).
  Set<String> _gensEgresadas = {};

  /// Llave normalizada para comparar programa+generación sin que estorben
  /// mayúsculas, acentos o espacios de más.
  static String _keyGen(String programa, String generacion) {
    String n(String s) {
      s = s.trim().toLowerCase();
      const con = 'áàäâéèëêíìïîóòöôúùüûñ';
      const sin = 'aaaaeeeeiiiioooouuuun';
      for (var i = 0; i < con.length; i++) {
        s = s.replaceAll(con[i], sin[i]);
      }
      return s;
    }

    return '${n(programa)}||${n(generacion)}';
  }

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 8, vsync: this);
    _tab.addListener(() {
      if (mounted) setState(() {});
    });
    _cargarTodo();
  }

  @override
  void dispose() {
    _tab.dispose();
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // (ago-15) EN PARALELO, NO EN FILA. Las cinco cargas son peticiones
      // independientes y se estaban esperando una por una: si cada una tarda
      // tres segundos, la pantalla tardaba quince en abrir. Lanzarlas juntas
      // hace que tarde lo que la más lenta, no la suma de todas.
      // El catálogo va primero porque las demás lo usan para resolver
      // nombres de grupos.
      await _cargarCatalogo();
      await Future.wait([
        _cargarAsignaciones(),
        _cargarSinMaestro(),
        _cargarPendientes(),
        _cargarGeneracionesEgresadas(),
      ]);
      if (mounted) {
        setState(() {
          _cargando = false;
          _ultimaCarga = DateTime.now();
        });
      }
      // (ago-15) La insignia se llena sola, pero DESPUÉS de que la pantalla
      // ya se ve y con unos segundos de retraso: es una revisión pesada y no
      // tiene por qué competir con las cargas que sí necesitas de inmediato.
      // Si sales de la pantalla antes, ni siquiera se pide.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _contarGravesEnSilencio();
      });
    } catch (e, s) {
      // (28-sep, Fase 3) Este es el catch de TODA la pantalla: si algo truena
      // aquí, la Agenda de profesores no cargó para nadie. Es el más
      // importante de los 21 catch de este archivo para dejar registrado.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:cargar_todo');
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar. Revisa tu conexión.';
        });
      }
    }
  }

  /// Usa la acción clasificacion_alumnos del Guardián para saber qué
  /// generaciones ya están EGRESADAS (sin alumnos activos y con al menos un
  /// Egresado o Titulado). Si esta carga falla, simplemente no se oculta
  /// nada: la agenda sigue funcionando igual que antes.
  Future<void> _cargarGeneracionesEgresadas() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'clasificacion_alumnos'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return;

      // Por cada programa+generación contamos activos y egresados/titulados.
      final activos = <String, int>{};
      final egresados = <String, int>{};
      final total = <String, int>{};
      for (final raw in (data['alumnos'] as List<dynamic>? ?? [])) {
        final a = Map<String, dynamic>.from(raw as Map);
        final prog = (a['programa'] ?? '').toString();
        final gen = (a['generacion'] ?? '').toString();
        if (prog.trim().isEmpty || gen.trim().isEmpty) continue;
        final k = _keyGen(prog, gen);
        final tipo = (a['tipo'] ?? '').toString().trim().toLowerCase();
        total[k] = (total[k] ?? 0) + 1;
        if (tipo == 'activo') activos[k] = (activos[k] ?? 0) + 1;
        if (tipo == 'egresado' || tipo == 'titulado') {
          egresados[k] = (egresados[k] ?? 0) + 1;
        }
      }
      final res = <String>{};
      total.forEach((k, n) {
        if (n > 0 && (activos[k] ?? 0) == 0 && (egresados[k] ?? 0) > 0) {
          res.add(k);
        }
      });
      _gensEgresadas = res;
    } catch (e, s) {
      // (28-sep, Fase 3) Sigue sin ser fatal para quien usa la pantalla —
      // nada cambia para el usuario — pero ahora SÍ queda registrado si esto
      // empieza a fallar seguido, en vez de desaparecer sin dejar rastro.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:generaciones_egresadas');
    }
  }

  // Fusiona programas que son el MISMO salvo acentos/mayúsculas/espacios, para
  // que sus generaciones y grupos NO queden partidos en dos. Elige como nombre
  // visible el que tenga acentos (el correcto) y, a igualdad, el más largo.
  Map<String, Map<String, List<String>>> _fusionarVariantes(
      Map<String, Map<String, List<String>>> cat) {
    int acentos(String s) {
      const a = 'áàäâãéèëêíìïîóòöôõúùüûñÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑ';
      var n = 0;
      for (final ch in s.split('')) {
        if (a.contains(ch)) n++;
      }
      return n;
    }

    final canon = <String, String>{};
    for (final prog in cat.keys) {
      final k = _normaPrograma(prog);
      final actual = canon[k];
      if (actual == null) {
        canon[k] = prog;
      } else if (acentos(prog) > acentos(actual) ||
          (acentos(prog) == acentos(actual) && prog.length > actual.length)) {
        canon[k] = prog;
      }
    }

    final out = <String, Map<String, List<String>>>{};
    cat.forEach((prog, gens) {
      final nombre = canon[_normaPrograma(prog)]!;
      final dest = out.putIfAbsent(nombre, () => <String, List<String>>{});
      gens.forEach((gen, grupos) {
        final lista = dest.putIfAbsent(gen, () => <String>[]);
        for (final g in grupos) {
          if (!lista.contains(g)) lista.add(g);
        }
      });
    });
    for (final gens in out.values) {
      for (final lista in gens.values) {
        lista.sort();
      }
    }
    return out;
  }

  Future<void> _cargarCatalogo() async {
    // 1) Intento principal: catalogo_grupos.
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'catalogo_grupos'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final cat = <String, Map<String, List<String>>>{};
        for (final p in (data['catalogo'] as List<dynamic>? ?? [])) {
          final pm = Map<String, dynamic>.from(p as Map);
          final prog = (pm['programa'] ?? '').toString();
          final gens = <String, List<String>>{};
          for (final g in (pm['generaciones'] as List<dynamic>? ?? [])) {
            final gm = Map<String, dynamic>.from(g as Map);
            final gen = (gm['generacion'] ?? '').toString();
            final grupos = (gm['grupos'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList();
            gens[gen] = grupos;
          }
          cat[prog] = gens;
        }
        if (cat.isNotEmpty) {
          _catalogo = _fusionarVariantes(cat);
          return;
        }
      }
    } catch (e, s) {
      // (28-sep, Fase 3) Sigue cayendo al respaldo (_cargarCatalogoDesdeGrupos)
      // sin avisar nada al usuario; ahora queda registrado por qué se usó.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:catalogo_grupos');
    }
    // 2) Respaldo infalible: construir el catálogo desde grupos_admin_todos,
    // que lee directo de la hoja (sin caché) y es la MISMA fuente que usa la
    // pantalla de Grupos. Si Grupos funciona, esto también.
    await _cargarCatalogoDesdeGrupos();
  }

  Future<void> _cargarCatalogoDesdeGrupos() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'grupos_admin_todos'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return;
      final cat = <String, Map<String, List<String>>>{};
      for (final r in (data['grupos'] as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(r as Map);
        final prog = (m['programa'] ?? '').toString().trim();
        final gen = (m['generacion'] ?? '').toString().trim();
        final grp = (m['grupo'] ?? '').toString().trim();
        if (prog.isEmpty || grp.isEmpty) continue;
        if (grp.toUpperCase() == 'BAJA') continue;
        cat.putIfAbsent(prog, () => <String, List<String>>{});
        cat[prog]!.putIfAbsent(gen, () => <String>[]);
        if (!cat[prog]![gen]!.contains(grp)) {
          cat[prog]![gen]!.add(grp);
        }
      }
      for (final gens in cat.values) {
        for (final lista in gens.values) {
          lista.sort();
        }
      }
      _catalogo = _fusionarVariantes(cat);
    } catch (e, s) {
      // (28-sep, Fase 3) Este es el RESPALDO del respaldo: si también falla,
      // el catálogo de programas/generaciones/grupos queda vacío y varias
      // partes de la pantalla dejan de poder filtrar. Antes no quedaba
      // ningún rastro de por qué. Sigue sin interrumpir a nadie.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:catalogo_grupos_respaldo');
    }
  }

  Future<void> _cargarAsignaciones() async {
    final uri = Uri.parse(guardianUrl)
        .replace(queryParameters: {'accion': 'asignaciones_listar'});
    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
    _asignaciones = (data['asignaciones'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _cargarPendientes() async {
    final uri = Uri.parse(guardianUrl)
        .replace(queryParameters: {'accion': 'invitaciones_pendientes'});
    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    _pendientes = (data['pendientes'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> _enviarRecordatorio(Map<String, dynamic> p) async {
    final fila = p['fila'];
    if (fila == null || fila == 0) {
      _aviso('No se encontró la invitación.');
      return;
    }
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(
                  {'accion': 'asignacion_invitar', 'fila': fila}))
          .timeout(const Duration(seconds: 25));
      // (28-sep, Fase 3) leerRespuesta distingue HTML/timeout de un rechazo
      // real del servidor, y da un mensaje que dice qué pasó, no solo
      // "Error". Reporta sola cuando la respuesta no se pudo interpretar.
      final r = leerRespuesta(resp, accion: 'asignacion_invitar');
      if (!r.ok) { _aviso(r.mensaje); return; }
      _aviso('Recordatorio enviado a ${(p['docente'] ?? p['correo'] ?? '').toString()}.');
    } catch (e, s) {
      // Solo cae aquí un fallo de RED (sin conexión, timeout de verdad): la
      // respuesta del servidor, si llegó, ya la interpretó leerRespuesta.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:enviar_recordatorio');
      _aviso('No se pudo enviar el recordatorio: revise su conexión.');
    }
  }

  /// (28-sep) Recordatorio redactado con IA — SOLO propone. Muestra el
  /// borrador en un diálogo editable; el correo no sale hasta que la
  /// persona pulsa "Enviar este mensaje" con el texto que decidió dejar.
  Future<void> _redactarConIA(Map<String, dynamic> p) async {
    final fila = p['fila'];
    if (fila == null || fila == 0) {
      _aviso('No se encontró la invitación.');
      return;
    }
    // 1) Pedir el borrador (no envía nada).
    Map<String, dynamic> borrador = {};
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'invitacion_recordatorio_ia', 'fila': '$fila'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final r = leerRespuesta(resp, accion: 'invitacion_recordatorio_ia');
      if (!r.ok) { _aviso(r.mensaje); return; }
      borrador = r.datos;
    } catch (e, s) {
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:recordatorio_ia');
      _aviso('No se pudo redactar: revise su conexión.');
      return;
    }
    if (!mounted) return;

    final asuntoCtrl = TextEditingController(text: (borrador['asunto'] ?? '').toString());
    final cuerpoCtrl = TextEditingController(text: (borrador['cuerpo'] ?? '').toString());
    bool enviando = false;
    String? errorEnvio;

    // 2) Mostrarlo, editable. Nada se envía hasta que la persona lo decida aquí.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Recordatorio para ${(p['docente'] ?? 'el docente').toString()}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Para: ${(p['correo'] ?? '').toString()}',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  const SizedBox(height: 10),
                  TextField(
                    controller: asuntoCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Asunto', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: cuerpoCtrl,
                    maxLines: 8,
                    decoration: const InputDecoration(
                        labelText: 'Mensaje', border: OutlineInputBorder(), alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 8),
                  Text(
                      (borrador['aviso'] ?? 'Borrador generado con IA: revíselo antes de enviarlo. '
                              'No se envió nada.')
                          .toString(),
                      style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: cessumMuted(context))),
                  if (errorEnvio != null) ...[
                    const SizedBox(height: 8),
                    Text(errorEnvio!, style: const TextStyle(fontSize: 12.5, color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumGold, foregroundColor: Colors.white),
              onPressed: enviando
                  ? null
                  : () async {
                      if (asuntoCtrl.text.trim().isEmpty || cuerpoCtrl.text.trim().isEmpty) {
                        setLocal(() => errorEnvio = 'El asunto y el mensaje no pueden quedar vacíos.');
                        return;
                      }
                      setLocal(() { enviando = true; errorEnvio = null; });
                      try {
                        final resp2 = await http
                            .post(Uri.parse(guardianUrl),
                                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                                body: jsonEncode({
                                  'accion': 'invitacion_recordatorio_enviar',
                                  'fila': fila,
                                  'asunto': asuntoCtrl.text.trim(),
                                  'cuerpo': cuerpoCtrl.text.trim(),
                                  'confirmar': '1',
                                }))
                            .timeout(const Duration(seconds: 30));
                        final r2 = leerRespuesta(resp2, accion: 'invitacion_recordatorio_enviar');
                        if (!r2.ok) {
                          setLocal(() { enviando = false; errorEnvio = r2.mensaje; });
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        _aviso('Recordatorio enviado a ${(p['docente'] ?? p['correo'] ?? '').toString()}.');
                        await _cargarPendientes();
                      } catch (e, s) {
                        ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:recordatorio_ia_enviar');
                        setLocal(() { enviando = false; errorEnvio = 'No se pudo enviar: revise su conexión.'; });
                      }
                    },
              icon: enviando
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 16),
              label: Text(enviando ? 'Enviando…' : 'Enviar este mensaje'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabPendientes() {
    if (_pendientes.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay invitaciones sin respuesta. ✔',
              style: TextStyle(color: cessumMuted(context))),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(14),
      itemCount: _pendientes.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${_pendientes.length} invitación(es) sin respuesta.',
              style: TextStyle(color: cessumMuted(context), fontSize: 13),
            ),
          );
        }
        final p = _pendientes[i - 1];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade400, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((p['docente'] ?? '(sin nombre)').toString(),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: cessumInk(context))),
              const SizedBox(height: 2),
              _linea(Icons.mail_outline, (p['correo'] ?? '').toString()),
              _linea(Icons.menu_book_outlined, (p['materia'] ?? '').toString()),
              _linea(Icons.school_outlined, (p['programa'] ?? '').toString()),
              _linea(Icons.groups_outlined,
                  'Gen. ${p['generacion']}  •  ${p['grupo']}'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: cessumGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => _enviarRecordatorio(p),
                  icon: const Icon(Icons.notifications_active, size: 18),
                  label: const Text('Enviar recordatorio'),
                ),
              ),
              const SizedBox(height: 8),
              // (28-sep) Alternativa al reenvío de siempre: la IA propone un
              // mensaje propio; la persona lo revisa, lo edita si hace falta
              // y decide enviarlo — no se manda nada solo por pulsar aquí.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumGold,
                      side: BorderSide(color: cessumGold),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => _redactarConIA(p),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Redactar con IA'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      side: const BorderSide(color: cessumRed),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  onPressed: () => _retirarInvitacion({
                    'filaInvitacion': p['fila'],
                    'docenteInvitado': p['docente'],
                  }),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Borrar invitación'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _keyGrupo(Map<String, dynamic> g) =>
      '${g['programa']}||${g['generacion']}||${g['grupo']}';

  Future<void> _toggleAlumnos(Map<String, dynamic> g) async {
    final k = _keyGrupo(g);
    if (_rosterAbierto.contains(k)) {
      setState(() => _rosterAbierto.remove(k));
      return;
    }
    setState(() => _rosterAbierto.add(k));
    if (_rosterCache.containsKey(k)) return;
    setState(() => _rosterCargando.add(k));
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alumnos',
        'programa': (g['programa'] ?? '').toString(),
        'generacion': (g['generacion'] ?? '').toString(),
        'grupo': (g['grupo'] ?? '').toString(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _rosterCache[k] = (data['alumnos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e, s) {
      // (28-sep, Fase 3) Sigue mostrando la lista vacía —no vale la pena un
      // diálogo de error por esto— pero ahora queda registrado.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:roster_grupo');
      _rosterCache[k] = [];
    }
    if (mounted) setState(() => _rosterCargando.remove(k));
  }

  Future<void> _retirarInvitacion(Map<String, dynamic> g) async {
    final fila = g['filaInvitacion'];
    if (fila == null || fila == 0) {
      _aviso('No se encontró la invitación para retirar.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirar invitación'),
        content: Text(
            '¿Retirar la invitación enviada a ${(g['docenteInvitado'] ?? 'la maestra').toString()}? El grupo volverá a quedar disponible para reasignar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Retirar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(
                  {'accion': 'asignacion_eliminar', 'fila': fila}))
          .timeout(const Duration(seconds: 25));
      // (28-sep, Fase 3) Mensaje humano + reporte solo si la respuesta no se
      // pudo interpretar (el rechazo del propio Guardián ya trae su motivo).
      final r = leerRespuesta(resp, accion: 'asignacion_eliminar');
      if (!r.ok) { _aviso(r.mensaje); return; }
      _aviso('Invitación retirada. El grupo quedó disponible.');
      await _cargarTodo();
    } catch (e, s) {
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:retirar_invitacion');
      _aviso('No se pudo retirar la invitación: revise su conexión.');
    }
  }

  Future<void> _cargarSinMaestro() async {
    final uri = Uri.parse(guardianUrl)
        .replace(queryParameters: {'accion': 'grupos_sin_maestro'});
    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true) return;
    _sinMaestro = (data['grupos'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  // Crea el Aula (Moodle) + matricula al grupo + genera el Meet e invita a
  // profesor y alumnos con su correo institucional. Llama a aula_meet_crear.
  // (17-sep) UNA SOLA REGLA PARA TODOS LOS PUNTOS.
  // El botón de la lista miraba solo el grupo, y el de licenciatura se llama
  // «1 - sabatino», así que ofrecía Meet a un grupo presencial. Aquí queda en
  // un lugar: presencial es la mixta y TODA licenciatura.
  // (28-sep, Fase 1) Usaba su propia copia de quitar acentos; ahora la
  // misma _normaPrograma que usan _reglaDe y el resto del archivo.
  bool _sinMeet(Map<String, dynamic> a) {
    final grupo = (a['grupo'] ?? '').toString().toLowerCase();
    final prog = _normaPrograma((a['programa'] ?? '').toString());
    return grupo.contains('mixt') || prog.contains('licenciatura');
  }

  Future<void> _crearAulaMeet(Map<String, dynamic> a) async {
    final materia = (a['materia'] ?? '').toString();
    final programa = (a['programa'] ?? '').toString();
    final generacion = (a['generacion'] ?? '').toString();
    final grupo = (a['grupo'] ?? '').toString();
    if (materia.isEmpty || programa.isEmpty || grupo.isEmpty) {
      _aviso('Faltan datos de la asignación.');
      return;
    }
    // Mixta = presencial intensivo: solo se crea el Aula (Moodle), sin Meet.
    // (16-sep) LICENCIATURA TAMPOCO LLEVA MEET. Sus sesiones son presenciales
    // los sábados en Navojoa; el Meet se ofrecía solo porque la regla miraba
    // el grupo —«1 - sabatino»— y no el programa. Crear una sala que nadie va
    // a usar confunde al docente y le manda a los alumnos un enlace que no
    // corresponde a su clase.
    final esMixta = _sinMeet(a);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(esMixta ? 'Crear Aula' : 'Crear Aula + Meet'),
        content: Text(
          esMixta
              ? 'Se creará (o reutilizará) el Aula en Moodle para "$materia" '
                  'y se matriculará al grupo. No se genera Meet: las sesiones '
                  'de este grupo son presenciales.\n\n'
                  '$programa · Gen. $generacion · Grupo $grupo\n\n¿Continuar?'
              : 'Se creará (o reutilizará) el Aula en Moodle para "$materia", '
                  'se matriculará al grupo y se generará el Meet, invitando al profesor '
                  'y a los alumnos con su correo institucional.\n\n'
                  '$programa · Gen. $generacion · Grupo $grupo\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(esMixta ? 'Creando Aula y matriculando…' : 'Creando Aula, matriculando y generando Meet…')),
        ]),
      ),
    );
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'aula_meet_crear',
        'programa': programa,
        'generacion': generacion,
        'grupo': grupo,
        'materia': materia,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 180));
      if (mounted) Navigator.pop(context);
      // (28-sep, Fase 3) Esta llamada puede tardar hasta 3 minutos (crea Aula
      // + matricula + genera Meet). Si el servidor tarda MÁS que eso, la
      // operación puede haber quedado hecha aunque la app nunca vea la
      // respuesta — leerRespuesta lo dice explícitamente en vez de un
      // "Error: TimeoutException" que no explica nada.
      final r = leerRespuesta(resp, accion: 'aula_meet_crear');
      if (!r.ok) {
        _aviso('No se pudo: ${r.mensaje}');
        return;
      }
      final data = r.datos;
      final aula = (data['aula'] ?? '').toString();
      final aulaUrl = (data['aulaUrl'] ?? '').toString();
      final matric = data['matriculados'] ?? 0;
      final totAl = data['totalAlumnos'] ?? 0;
      final meet = (data['meet'] ?? '').toString();
      final meetError = (data['meetError'] ?? '').toString();
      // (9-sep) El Guardián siempre reportó si la estructura del aula se creó
      // o por qué no; este diálogo se lo callaba. Así, un aula nacida vacía se
      // descubría días después, al entrar a Moodle, en vez de aquí mismo.
      final estructura = (data['estructura'] ?? '').toString();
      final estructuraOk = estructura.startsWith('Estructura creada');
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(esMixta ? 'Aula creada' : 'Aula + Meet'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aula: $aula',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('Matriculados: $matric de $totAl'),
                const SizedBox(height: 10),
                if (!esMixta && meet.isNotEmpty) ...[
                  const Text('Meet:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SelectableText(meet),
                ] else if (!esMixta)
                  Text('Meet: no se generó.\n$meetError',
                      style: TextStyle(color: cessumGold)),
                if (aulaUrl.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Aula (Moodle):',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SelectableText(aulaUrl),
                ],
                if (estructura.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: estructuraOk
                          ? const Color(0xFFE9F5EC)
                          : const Color(0xFFFDECEC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          estructuraOk ? Icons.check_circle : Icons.warning_amber_rounded,
                          size: 18,
                          color: estructuraOk ? const Color(0xFF1E8E3E) : cessumRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            estructuraOk
                                ? 'Secciones y banners: $estructura'
                                : 'El aula nació SIN secciones: $estructura',
                            style: const TextStyle(fontSize: 12.5, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
      _cargarAsignaciones();
    } catch (e, s) {
      // Solo cae aquí un fallo de RED (sin conexión, timeout duro): la
      // respuesta, si llegó, ya la interpretó leerRespuesta arriba.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:aula_meet_crear');
      if (mounted) Navigator.pop(context);
      _aviso('No se pudo completar: revise su conexión y compruebe en Moodle '
          'si el aula ya se creó antes de intentarlo otra vez.');
    }
  }

  Future<void> _eliminar(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar asignación'),
        content: Text(
            '¿Eliminar "${a['materia']}" de ${a['programa']} · ${a['grupo']}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: cessumRed),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(
                  {
                    'accion': 'asignacion_eliminar',
                    'fila': a['fila'],
                    // (2-oct) El Guardián comprueba que esa fila SIGA siendo esta materia y este grupo antes de borrar:
                    // si alguien eliminó o agregó una fila arriba mientras tanto, se borraba OTRA asignación.
                    'materia': (a['materia'] ?? '').toString(),
                    'grupo': (a['grupo'] ?? '').toString(),
                  }))
          .timeout(const Duration(seconds: 25));
      final r = leerRespuesta(resp, accion: 'asignacion_eliminar');
      if (!r.ok) { _aviso(r.mensaje); return; }
      _aviso('Asignación eliminada.');
      await _cargarTodo();
    } catch (e, s) {
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:eliminar');
      _aviso('No se pudo eliminar: revise su conexión.');
    }
  }

  /* (9-sep) Trae de una sola llamada el teléfono y el PIN del Meet (del
     evento de Calendar) y el id del curso en Moodle (del link del aula).
     Nunca lanza: si algo falla devuelve ok:false y el diálogo lo explica,
     porque no poder prellenar no es motivo para no dejar notificar. */
  Future<Map<String, dynamic>> _datosMeet(dynamic fila) async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=meet_datos&fila=$fila'))
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data;
    } catch (e, s) {
      // (28-sep, Fase 3) Sigue devolviendo {ok:false} —quien la llama ya
      // sabe interpretarlo— pero ahora queda registrado.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:datos_meet');
      return <String, dynamic>{'ok': false};
    }
  }

  // (1-oct-2026) Versión de _crearAulaMeet para usarse DENTRO del diálogo de
  // Notificar inicio: no muestra su propio diálogo de progreso (ya hay uno
  // abierto) y solo dice si quedó listo, para refrescar el enlace ahí mismo.
  Future<bool> _crearAulaMeetInline(Map<String, dynamic> a) async {
    final materia = (a['materia'] ?? '').toString();
    final programa = (a['programa'] ?? '').toString();
    final generacion = (a['generacion'] ?? '').toString();
    final grupo = (a['grupo'] ?? '').toString();
    if (materia.isEmpty || programa.isEmpty || grupo.isEmpty) {
      _aviso('Faltan datos de la asignación.');
      return false;
    }
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'aula_meet_crear',
        'programa': programa,
        'generacion': generacion,
        'grupo': grupo,
        'materia': materia,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 180));
      final r = leerRespuesta(resp, accion: 'aula_meet_crear');
      if (!r.ok) {
        _aviso('No se pudo crear el Meet: ${r.mensaje}');
        return false;
      }
      _aviso('Aula y Meet listos.');
      return true;
    } catch (e, s) {
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:aula_meet_crear_inline');
      _aviso('No se pudo crear el Meet: $e');
      return false;
    }
  }

  Future<void> _notificarInicio(Map<String, dynamic> a) async {
    final yaNotif = (a['inicioNotificado'] ?? '').toString().trim();
    if (yaNotif.isNotEmpty) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ya se notificó'),
          content: Text(
              'Esta materia ya tiene un inicio notificado el $yaNotif.\n\n'
              '¿Quieres notificar de nuevo de todas formas?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Notificar otra vez'),
            ),
          ],
        ),
      );
      if (seguir != true) return;
    }
    // (1-oct-2026) La fecha llega en ISO (aaaa-mm-dd) desde la asignación,
    // pero la etiqueta del campo dice (dd/mm/aaaa) — se muestra en ese
    // mismo formato para que coincidan; al guardar, el Guardián acepta
    // ambos (_fechaMs_ interpreta los dos), así que no hace falta
    // reconvertir de vuelta.
    String _aDdMmAaaa(String v) {
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v.trim());
      if (m == null) return v;
      return '${m.group(3)}/${m.group(2)}/${m.group(1)}';
    }

    final inicioCtrl =
        TextEditingController(text: _aDdMmAaaa((a['inicio'] ?? '').toString()));
    final terminoCtrl =
        TextEditingController(text: _aDdMmAaaa((a['termino'] ?? '').toString()));

    // (9-sep) LOS TRES CAMPOS SE LLENAN SOLOS.
    // Antes se pedían teléfono, PIN e id de Moodle como si nadie los
    // tuviera, y el aula y el Meet ya estaban creados: los datos existían,
    // solo que en dos lugares distintos. El id de Moodle está dentro del
    // link del aula que guarda la asignación; el teléfono y el PIN están
    // en el evento de Calendar. La ruta meet_datos junta los tres.
    //
    // Se consulta ANTES de abrir el diálogo, a propósito: pintarlo vacío y
    // rellenarlo un segundo después haría que quien escribe rápido perdiera
    // lo que acaba de teclear.
    var datosMeet = await _datosMeet(a['fila']);
    final mAula =
        RegExp(r'[?&]id=(\d+)').firstMatch((a['linkAula'] ?? '').toString());
    final moodleAuto = (datosMeet['moodleId'] ?? '').toString().trim();

    final telCtrl =
        TextEditingController(text: (datosMeet['tel'] ?? '').toString());
    final pinCtrl =
        TextEditingController(text: (datosMeet['pin'] ?? '').toString());
    final moodleCtrl = TextEditingController(
        text: moodleAuto.isNotEmpty ? moodleAuto : (mAula?.group(1) ?? ''));

    // (1-oct-2026) El enlace de Meet se MUESTRA, nunca se captura a mano:
    // sale de meet_datos (linkLlamada de la asignación, o del evento de
    // Calendar como respaldo). "requiereMeet" es la misma regla que ya usa
    // el botón de la lista (_sinMeet): en Mixta y Licenciatura no aplica.
    String meetLink = (datosMeet['meet'] ?? '').toString().trim();
    final bool requiereMeet = !_sinMeet(a);
    final bool tieneTelefono = datosMeet['tieneTelefono'] == true;

    // Cuando no se pudo traer algo, el diálogo lo DICE. Los campos siguen
    // ahí y se pueden escribir: un dato que no llegó no debe cerrarle el
    // paso a quien sí lo tiene a la mano.
    final notaMeet = (datosMeet['ok'] == true)
        ? (datosMeet['nota'] ?? '').toString()
        : 'No se pudieron leer los datos del Meet; captúralos si los tienes.';

    bool prueba = false;
    bool enviando = false;
    // (1-oct-2026, corrección de fondo) ANTES el diálogo se bloqueaba por
    // completo durante el envío: no se podía tocar fuera a cerrarlo
    // (barrierDismissible: false) Y el botón Cancelar se deshabilitaba
    // (onPressed: enviando ? null : ...). Si el correo SÍ salía del lado
    // del servidor pero, por cualquier motivo, el cierre automático del
    // diálogo (Navigator.pop tras la respuesta) no llegaba a ejecutarse
    // —el reporte de "cinco minutos cargando, el correo de prueba sí
    // llegó"—, no quedaba ninguna salida: ni tocar fuera, ni el botón.
    // Ahora SIEMPRE hay una salida: tocar fuera cierra el diálogo, y el
    // botón nunca se deshabilita —cambia de "Cancelar" a "Cerrar" mientras
    // se envía, dejando claro que ya no cancela nada que esté en curso del
    // lado del servidor, solo quita la ventana de la pantalla.
    final grupoTexto = (a['grupo'] ?? '').toString() == '2' ? 'Sabatino' : 'Entre semana';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // (1-oct-2026) Encabezado institucional, en vez del título
                // plano de antes — el mismo trato visual que ya reciben
                // otros diálogos grandes de la app (Convenios, por ejemplo).
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                  decoration: const BoxDecoration(
                    color: cessumRed,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.campaign_outlined, color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Notificar inicio de materia',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('${a['materia']}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // (1-oct-2026) Detalle de la sesión en una tarjeta
                        // propia, con los datos uno por línea con su
                        // etiqueta — antes era un párrafo corrido.
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cessumBg(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _filaDetalle(Icons.school_outlined,
                                  '${a['programa']} · ${a['generacion']}'),
                              const SizedBox(height: 6),
                              _filaDetalle(Icons.groups_outlined,
                                  'Grupo ${a['grupo'] ?? ''} · $grupoTexto'),
                              const SizedBox(height: 6),
                              _filaDetalle(Icons.person_outline, 'Docente: ${a['docente']}'),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                decoration: BoxDecoration(
                                  color: cessumGold.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.mail_outline, size: 14, color: cessumGold),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Se enviará a todos los alumnos del grupo y al docente.',
                                        style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // (1-oct-2026) El enlace de Meet se MUESTRA, nunca se
                        // captura a mano. Si no aplica (Mixta/Licenciatura), no
                        // se dice nada de Meet en absoluto.
                        if (requiereMeet)
                          if (meetLink.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cessumGold.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.videocam_outlined, size: 18, color: cessumGold),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(meetLink,
                                        style: const TextStyle(fontSize: 12.5),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  IconButton(
                                    tooltip: 'Copiar enlace',
                                    icon: const Icon(Icons.copy, size: 18),
                                    onPressed: () => Helpers.copiarAlPortapapeles(
                                        ctx, meetLink, 'Enlace de Meet'),
                                  ),
                                  IconButton(
                                    tooltip: 'Abrir enlace',
                                    icon: const Icon(Icons.open_in_new, size: 18),
                                    onPressed: () => launchUrl(Uri.parse(meetLink),
                                        mode: LaunchMode.externalApplication),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cessumRed.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Esta materia todavía no tiene enlace de Meet.',
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.add_call, size: 16),
                                      label: const Text('Crear Aula + Meet',
                                          style: TextStyle(fontSize: 12.5)),
                                      onPressed: () async {
                                        setLocal(() => enviando = true);
                                        final creado = await _crearAulaMeetInline(a);
                                        if (creado) {
                                          final nuevo = await _datosMeet(a['fila']);
                                          setLocal(() {
                                            datosMeet = nuevo;
                                            meetLink = (nuevo['meet'] ?? '').toString().trim();
                                            enviando = false;
                                          });
                                        } else {
                                          setLocal(() => enviando = false);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        if (requiereMeet) const SizedBox(height: 10),
                        TextField(
                          controller: inicioCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Fecha de inicio (dd/mm/aaaa) *',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: terminoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Fecha de término (dd/mm/aaaa) *',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        // (1-oct-2026) Si el Meet no tiene marcación telefónica, no
                        // tiene caso mostrar estos dos campos vacíos con una nota
                        // explicándolo: se ocultan directamente.
                        if (tieneTelefono) ...[
                          const SizedBox(height: 10),
                          TextField(
                            controller: telCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono del Meet (opcional)',
                              hintText: '(MX) +52 55 ...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: pinCtrl,
                            decoration: const InputDecoration(
                              labelText: 'PIN del Meet (opcional)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: moodleCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ID del curso en Moodle (opcional)',
                            hintText: 'Ej. 453',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        // (1-oct-2026) La nota de "sin marcación telefónica" ya
                        // queda explicada por la AUSENCIA de los campos tel/PIN
                        // arriba — mostrarla también sería redundante.
                        if (notaMeet.isNotEmpty && !notaMeet.contains('marcación telefónica')) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14, color: cessumFaint(context)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  notaMeet,
                                  style: TextStyle(
                                      fontSize: 11, height: 1.3, color: cessumMuted(context)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 4),
                        Container(
                          decoration: BoxDecoration(
                            color: prueba ? cessumGold.withValues(alpha: 0.10) : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SwitchListTile(
                            value: prueba,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            activeThumbColor: cessumGold,
                            title: const Text('Modo prueba',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: const Text(
                                'Solo lo reciben el docente y administración',
                                style: TextStyle(fontSize: 11)),
                            onChanged: enviando ? null : (v) => setLocal(() => prueba = v),
                          ),
                        ),
                        if (enviando) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: cessumGold.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 15, height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: cessumGold),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Enviando… si tarda, puedes cerrar esta ventana: '
                                    'el envío sigue su curso del lado del servidor.',
                                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // (1-oct-2026) NUNCA deshabilitado: siempre hay una
                      // salida. Mientras se envía, el texto cambia a
                      // "Cerrar" para dejar claro que no cancela el envío
                      // en curso, solo quita la ventana de la pantalla.
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(enviando ? 'Cerrar' : 'Cancelar'),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: enviando
                            ? null
                            : () async {
                                if (inicioCtrl.text.trim().isEmpty ||
                                    terminoCtrl.text.trim().isEmpty) {
                                  _aviso('Captura las fechas de inicio y término.');
                                  return;
                                }
                                setLocal(() => enviando = true);
                                try {
                                  final payload = {
                                    'accion': 'inicio_materia_notificar',
                                    'programa': a['programa'],
                                    'generacion': a['generacion'],
                                    'grupo': a['grupo'],
                                    'materia': a['materia'],
                                    'clave': a['clave'] ?? '',
                                    'ciclo': a['ciclo'] ?? '',
                                    'dia': a['dia'] ?? '',
                                    'hora': a['hora'] ?? '',
                                    'inicio': inicioCtrl.text.trim(),
                                    'termino': terminoCtrl.text.trim(),
                                    // (1-oct-2026) El mismo enlace que se MUESTRA en
                                    // el diálogo, no el crudo de la asignación: si
                                    // venía vacío ahí pero meet_datos lo resolvió por
                                    // Calendar (o se acaba de crear con el botón de
                                    // arriba), el correo debe llevar ESE.
                                    'linkLlamada': meetLink,
                                    'meetTel': telCtrl.text.trim(),
                                    'meetPin': pinCtrl.text.trim(),
                                    'linkAula': a['linkAula'] ?? '',
                                    'moodleId': moodleCtrl.text.trim(),
                                    'docente': a['docente'] ?? '',
                                    'correoDocente': a['correo'] ?? '',
                                    'modoPrueba': prueba,
                                  };
                                  final resp = await http
                                      .post(Uri.parse(guardianUrl),
                                          headers: {
                                            'Content-Type': 'text/plain;charset=utf-8'
                                          },
                                          body: jsonEncode(payload))
                                      .timeout(const Duration(seconds: 120));
                                  // (28-sep, Fase 3) Este catch envolvía DOS envíos: la
                                  // notificación (a todo el grupo) y el guardado de
                                  // fechas. Si la notificación tenía éxito pero fallaba
                                  // el guardado, el mensaje decía "No se pudo enviar" —
                                  // FALSO: el correo ya había salido. Alguien podía
                                  // reintentar y notificar dos veces al mismo grupo.
                                  // Ahora cada paso tiene su propio mensaje.
                                  final r1 = leerRespuesta(resp, accion: 'inicio_materia_notificar');
                                  if (!r1.ok) {
                                    throw Exception(r1.mensaje);
                                  }
                                  final data = r1.datos;
                                  // guardar las fechas en la asignación
                                  final resp2 = await http
                                      .post(Uri.parse(guardianUrl),
                                          headers: {
                                            'Content-Type': 'text/plain;charset=utf-8'
                                          },
                                          body: jsonEncode({
                                            'accion': 'asignacion_guardar',
                                            ...a,
                                            'inicio': inicioCtrl.text.trim(),
                                            'termino': terminoCtrl.text.trim(),
                                          }))
                                      .timeout(const Duration(seconds: 30));
                                  final r2 = leerRespuesta(resp2, accion: 'asignacion_guardar_fechas');
                                  // (1-oct-2026, corrección de fondo) Antes
                                  // este cierre dependía de "ctx.mounted" —
                                  // si por cualquier razón ese contexto ya
                                  // no estaba vigente, Navigator.pop nunca
                                  // se ejecutaba y el diálogo se quedaba
                                  // atorado con "enviando=true" para
                                  // siempre, sin botón para salir (el reporte
                                  // real: el correo de prueba SÍ llegaba,
                                  // pero la ventana nunca se quitaba). Ahora
                                  // "enviando" se restaura SIEMPRE primero,
                                  // así que incluso si el pop no alcanza a
                                  // cerrar el diálogo, el botón "Cerrar"
                                  // vuelve a estar disponible de inmediato.
                                  setLocal(() => enviando = false);
                                  final envioMsg = prueba
                                      ? 'Correo de PRUEBA enviado al docente y administración.'
                                      : 'Notificación enviada a ${data['alumnos']} alumno(s) y al docente.';
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _aviso(r2.ok
                                      ? envioMsg
                                      : '$envioMsg\n\nOjo: las fechas NO se guardaron '
                                          '(${r2.mensaje}). La notificación ya salió — '
                                          'no la reenvíes; solo corrige las fechas desde '
                                          'Editar.');
                                  await _cargarTodo();
                                } catch (e, st) {
                                  ErrorReporter.reportar(e, st, pantallaForzada: 'agenda:notificar_inicio');
                                  setLocal(() => enviando = false);
                                  _aviso('No se pudo enviar: ${e.toString().replaceFirst('Exception: ', '')}');
                                }
                              },
                        child: enviando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Enviar al grupo'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaDetalle(IconData icono, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 15, color: cessumMuted(context)),
        const SizedBox(width: 7),
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 12.5, height: 1.3))),
      ],
    );
  }


  /// (ago-15) Cuántos problemas GRAVES tiene la programación. Se calcula al
  /// cargar y se muestra en la insignia del botón: si hay algo roto, se ve
  /// sin tener que ir a buscarlo.
  int _gravesProg = 0;

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  /// Revisión completa: errores de captura y choques. Cada hallazgo trae el
  /// número de fila, y desde el diálogo se abre esa asignación para
  /// corregirla sin buscarla a mano.
  Future<void> _contarGravesEnSilencio() async {
    try {
      final uri = Uri.parse(guardianUrl).replace(
          queryParameters: {'accion': 'programacion_revisar'});
      final r = await http.get(uri).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted || d['ok'] != true) return;
      setState(() => _gravesProg =
          (d['graves'] is num) ? (d['graves'] as num).toInt() : 0);
    } catch (e, s) {
      // (28-sep, Fase 3) Sin insignia se sigue pudiendo trabajar igual —no
      // vale la pena molestar a quien usa la pantalla— pero ahora sí queda
      // registrado si el conteo de graves deja de funcionar.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:graves_en_silencio');
    }
  }

  Future<void> _revisarProgramacion() async {
    Map<String, dynamic> d = {};
    try {
      final uri = Uri.parse(guardianUrl).replace(
          queryParameters: {'accion': 'programacion_revisar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      // (28-sep, Fase 3) leerRespuesta distingue HTML/timeout de un rechazo
      // real del servidor y avisa sola si la respuesta no se pudo interpretar.
      final rr = leerRespuesta(resp, accion: 'programacion_revisar');
      if (!rr.ok) {
        if (mounted) _aviso(rr.mensaje);
        return;
      }
      d = rr.datos;
    } catch (e, s) {
      // Solo cae aquí un fallo de RED: la respuesta, si llegó, ya la vio leerRespuesta.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:programacion_revisar');
      _aviso('No pude revisar: revise su conexión.');
      return;
    }
    if (!mounted) return;
    final hall = (d['hallazgos'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() => _gravesProg = (d['graves'] is num)
        ? (d['graves'] as num).toInt()
        : 0);
    if (hall.isEmpty) {
      _aviso('La programación está limpia: sin errores ni choques.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revisión de la programación',
            style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${d['veredicto'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 13, height: 1.35,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                for (final h in hall) _bloqueHallazgo(h, ctx),
                const SizedBox(height: 6),
                Text('${d['nota'] ?? ''}',
                    style: TextStyle(
                        fontSize: 11, height: 1.3,
                        fontStyle: FontStyle.italic,
                        color: cessumMuted(context))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _bloqueHallazgo(Map<String, dynamic> h, BuildContext ctx) {
    final grave = '${h['gravedad']}' == 'grave';
    final ejs = (h['ejemplos'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final col = grave ? const Color(0xFFC62828) : cessumGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: grave ? const Color(0xFFFDF3F3) : const Color(0xFFFBF6EE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: col.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${h['titulo']}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: col)),
              ),
              // (ago-15) Se distingue lo VIVO de lo histórico. Un choque en
              // una materia que terminó hace un mes no es una emergencia, y
              // contarlo igual hace que el número deje de significar algo.
              Text(
                  _n(h['yaTerminados']) > 0
                      ? '${_n(h['vigentes'])} de ${_n(h['total'])}'
                      : '${_n(h['total'])}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _n(h['vigentes']) > 0 ? col : cessumFaint(context))),
            ],
          ),
          if (_n(h['yaTerminados']) > 0)
            Text('${_n(h['yaTerminados'])} en materias que ya terminaron',
                style: TextStyle(
                    fontSize: 10.5, color: cessumFaint(context))),
          const SizedBox(height: 3),
          Text('${h['porQue'] ?? ''}',
              style: const TextStyle(fontSize: 11.5, height: 1.35)),
          Padding(
            padding: const EdgeInsets.only(top: 3, bottom: 6),
            child: Text('→ ${h['comoSeArregla'] ?? ''}',
                style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600)),
          ),
          for (final e in ejs) _filaHallazgo(e, ctx),
        ],
      ),
    );
  }

  /// Un caso concreto, con botón para abrirlo. Esa es la parte que hace fácil
  /// el trabajo: ver el problema y corregirlo sin buscar la fila a mano.
  Widget _filaHallazgo(Map<String, dynamic> e, BuildContext ctx) {
    final partes = <String>[];
    for (final k in const [
      'materia', 'grupo', 'docente', 'valor', 'hora', 'inicio', 'tipo', 'dia',
      'materiaA', 'materiaB', 'enlace'
    ]) {
      final v = '${e[k] ?? ''}'.trim();
      if (v.isNotEmpty) partes.add(v);
    }
    final filas = <int>[];
    for (final k in const ['fila', 'filaA', 'filaB', 'tambienEnFila']) {
      final v = e[k];
      if (v is num) filas.add(v.toInt());
    }
    final cuando = '${e['cuando'] ?? ''}';
    final urgente = cuando == 'en curso' || cuando == 'arranca pronto';
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(partes.join('  ·  '),
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: urgente ? cessumInk(context) : cessumFaint(context))),
                // Cuándo corre esa materia. Sin esto, "fila 28" y "fila 25"
                // se ven igual de urgentes y una ya terminó.
                if ('${e['cuandoDice'] ?? ''}'.isNotEmpty)
                  Text('${e['cuandoDice']}',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight:
                              urgente ? FontWeight.w700 : FontWeight.w400,
                          color: urgente
                              ? const Color(0xFFC62828)
                              : cessumFaint(context))),
              ],
            ),
          ),
          for (final f in filas)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _abrirPorFila(f);
                },
                child: Text('Fila $f',
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
        ],
      ),
    );
  }

  /// Abre el editor de la asignación de esa fila. Si no está cargada —por
  /// ejemplo porque está filtrada— se dice, en vez de no hacer nada.
  void _abrirPorFila(int fila) {
    Map<String, dynamic>? encontrada;
    for (final a in _asignaciones) {
      final f = a['fila'];
      if (f is num && f.toInt() == fila) {
        encontrada = Map<String, dynamic>.from(a);
        break;
      }
    }
    if (encontrada == null) {
      _aviso('La fila $fila no está en la lista cargada. Quita los filtros y '
          'vuelve a intentar.');
      return;
    }
    _abrirForm(existente: encontrada);
  }

  Future<void> _abrirForm({
    Map<String, dynamic>? existente,
    String? prog,
    String? gen,
    String? grupo,
  }) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _AsignacionForm(
          catalogo: _catalogo,
          egresadas: _gensEgresadas,
          asignaciones: _asignaciones,
          existente: existente,
          presetPrograma: prog,
          presetGeneracion: gen,
          presetGrupo: grupo,
        ),
      ),
    );
    if (cambio == true) await _cargarTodo();
  }

  /// Copia las asignaciones filtradas (TSV) para pegar en Excel.
  void _copiarExcel() {
    final lista = _asignacionesFiltradas;
    if (lista.isEmpty) return;
    final b = StringBuffer()
      ..writeln('Programa\tGeneración\tGrupo\tClave\tMateria\tDocente\tCorreo');
    for (final a in lista) {
      b.writeln([
        a['programa'] ?? '',
        a['generacion'] ?? '',
        a['grupo'] ?? '',
        a['clave'] ?? '',
        a['materia'] ?? '',
        a['docente'] ?? '',
        a['correo'] ?? '',
      ].join('\t'));
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Asignaciones (${lista.length})');
  }

  String _hoyISO() {
    final n = DateTime.now();
    String p(int x) => x.toString().padLeft(2, '0');
    return '${n.year}-${p(n.month)}-${p(n.day)}';
  }

  // Vigente = sin fecha de término, o que termina hoy o después (incluye las
  // que aún no inician). Solo se ocultan las que YA terminaron.
  bool _vigente(Map<String, dynamic> a) {
    final termino = (a['termino'] ?? '').toString().trim();
    if (termino.length < 10) return true;
    return termino.compareTo(_hoyISO()) >= 0;
  }

  /// Valores distintos de un campo, para llenar los desplegables con lo que
  /// existe de verdad en la base y no con una lista fija que se queda vieja.
  /// Se toman de las asignaciones ya acotadas por vigencia, así que no se
  /// ofrece un maestro cuyas materias terminaron todas.
  List<String> _valoresDe(String campo) {
    final base = _soloVigentes
        ? _asignaciones.where(_vigente)
        : _asignaciones;
    final set = <String>{};
    for (final a in base) {
      final v = (a[campo] ?? '').toString().trim();
      if (v.isNotEmpty) set.add(v);
    }
    final l = set.toList()..sort();
    return l;
  }

  List<Map<String, dynamic>> get _asignacionesFiltradas {
    final q = _busqueda.text.trim().toLowerCase();
    Iterable<Map<String, dynamic>> base = _asignaciones;
    if (_soloVigentes) base = base.where(_vigente);
    if (!_verReconstruidas) base = base.where((a) => !_esReconstruida(a));   // (3-oct-2026) el historial no es agenda
    if (_momento.isNotEmpty) {
      base = base.where((a) {
        final e = _estadoVigencia(a).label;
        return _momento == 'porIniciar'
            ? e == 'Aún no inicia'
            : e == 'Vigente';
      });
    }
    // Empieza dentro de N días: lo que de verdad hay que preparar ahora.
    // Cuenta desde hoy, así que incluye lo que ya está en curso.
    if (_dias > 0) {
      final hoy = DateTime.now();
      final hoyD = DateTime(hoy.year, hoy.month, hoy.day);
      final tope = hoyD.add(Duration(days: _dias));
      base = base.where((a) {
        final ini = _fechaVig((a['inicio'] ?? '').toString());
        if (ini == null) return false;   // sin fecha no se puede afirmar
        return !ini.isAfter(tope);
      });
    }
    if (_programaFiltro.isNotEmpty) {
      base = base.where(
          (a) => (a['programa'] ?? '').toString() == _programaFiltro);
    }
    if (_docenteFiltro.isNotEmpty) {
      base = base.where(
          (a) => (a['docente'] ?? '').toString() == _docenteFiltro);
    }
    if (q.isNotEmpty) {
      base = base.where((a) {
        final txt = [
          a['programa'], a['generacion'], a['grupo'], a['materia'],
          a['docente'], a['correo'], a['clave']
        ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
        return txt.contains(q);
      });
    }
    final out = base.toList();
    // (ago-2026) COLAPSO VISUAL: las materias de un BLOQUE CONJUNTO (varias
    // materias, una impartición) y los GRUPOS JUNTOS (una materia, varios
    // grupos) se muestran como UNA sola tarjeta. Crear aula ya crea UNA
    // (el backend reusa por el id del bloque/los grupos).
    final vistosIds = <String, int>{};
    final agrupadas = <Map<String, dynamic>>[];
    for (final a in out) {
      final blq = (a['bloqueConjunto'] ?? '').toString().trim();
      final gj = (a['gruposJuntos'] ?? '').toString().trim();
      var id = blq.isNotEmpty ? 'B|$blq' : (gj.isNotEmpty ? 'G|$gj' : '');
      // (ago-2026) RESPALDO sin id: en Mixta, mismo docente + programa +
      // generación + grupo + mismas fechas y hora = impartición conjunta
      // aunque la base no traiga el id del bloque (p. ej. backend sin
      // republicar o filas creadas sueltas). Es la definición operativa
      // de "dos cursos juntos en uno".
      if (id.isEmpty && !_esReconstruida(a) &&
          (a['grupo'] ?? '').toString().toLowerCase().contains('mixt') &&
          (a['correo'] ?? '').toString().trim().isNotEmpty) {
        id = 'F|${a['correo']}|${a['programa']}|${a['generacion']}|'
            '${a['grupo']}|${a['inicio']}|${a['termino']}|${a['hora']}';
      }
      if (id.isEmpty) {
        agrupadas.add(a);
        continue;
      }
      final idx = vistosIds[id];
      if (idx == null) {
        vistosIds[id] = agrupadas.length;
        final c = Map<String, dynamic>.from(a);
        c['_materiasJuntas'] = <String>[(a['materia'] ?? '').toString()];
        c['_gruposUnidos'] = <String>[
          '${a['generacion'] ?? ''} · ${a['grupo'] ?? ''}'
        ];
        c['_esBloqueConjunto'] = blq.isNotEmpty;
        agrupadas.add(c);
      } else {
        final c = agrupadas[idx];
        final mats = (c['_materiasJuntas'] as List).cast<String>();
        final mNva = (a['materia'] ?? '').toString();
        if (mNva.isNotEmpty && !mats.contains(mNva)) mats.add(mNva);
        final grs = (c['_gruposUnidos'] as List).cast<String>();
        final gNvo = '${a['generacion'] ?? ''} · ${a['grupo'] ?? ''}';
        if (!grs.contains(gNvo)) grs.add(gNvo);
      }
    }
    if (!_soloVigentes) {
      agrupadas.sort(
          (a, b) => (_vigente(a) ? 0 : 1).compareTo(_vigente(b) ? 0 : 1));
    }
    return agrupadas;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Agenda de profesores'),
        actions: [
          if (_tab.index == 0)
            IconButton(
                onPressed:
                    _asignacionesFiltradas.isEmpty ? null : _copiarExcel,
                icon: const Icon(Icons.copy_all),
                tooltip: 'Copiar para Excel'),
          IconButton(
              onPressed: _cargando ? null : _cargarTodo,
              icon: const Icon(Icons.refresh)),
          // (ago-15) La revisión de la programación, aquí mismo. Estaba solo
          // por URL, y una herramienta que exige pegar una dirección no se
          // usa: las filas rotas llevaban meses sin que nadie las viera.
          IconButton(
              onPressed: _cargando ? null : _revisarProgramacion,
              icon: Badge(
                isLabelVisible: _gravesProg > 0,
                label: Text('$_gravesProg'),
                child: const Icon(Icons.health_and_safety_outlined),
              ),
              tooltip: 'Revisar la programación'),
          // (23-sep) Grupos que se quedarán sin clase e invitaciones sin respuesta.
          IconButton(
            tooltip: 'Alertas: grupos sin siguiente materia e invitaciones sin respuesta',
            icon: const Icon(Icons.notification_important_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AgendaAlertasScreen(
                  onProgramar: (p, g, gr) => _abrirForm(prog: p, gen: g, grupo: gr),
                ),
              ),
            ).then((_) => _cargarTodo()),
          ),
          // (23-sep) Materias y horas por profesor.
          IconButton(
            tooltip: 'Carga docente',
            icon: const Icon(Icons.bar_chart),
            onPressed: _cargando
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AgendaCargaDocenteScreen(asignaciones: _asignaciones)),
                    ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Asignaciones (${_asignaciones.length})'),
            Tab(text: 'Sin maestro (${_sinMaestro.length})'),
            Tab(text: 'Sin respuesta (${_pendientes.length})'),
            const Tab(text: 'Disponibilidad'),
            const Tab(text: 'Mixta'),
            const Tab(text: 'Por grupo'),
            const Tab(text: 'Por profesor'),
            const Tab(text: 'Próxima materia'),
          ],
        ),
      ),
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              onPressed: () => _abrirForm(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva asignación'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : Column(
                  children: [
                    if (_ultimaCarga != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            Helpers.haceTexto(_ultimaCarga),
                            style: TextStyle(
                                fontSize: 11.5, color: cessumFaint(context)),
                          ),
                        ),
                      ),
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: [_tabAsignaciones(), _tabSinMaestro(), _tabPendientes(), _tabDisponibilidad(), _tabMixta(), _tabPorGrupo(), _tabPorProfesor(), _tabProximaMateria()],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _cargarTodo,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabAsignaciones() {
    final lista = _asignacionesFiltradas;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _busqueda,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar por programa, grupo, materia o maestro',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        // (9-sep) La fila de filtros creció y ya no cabe: se desplaza en
        // horizontal en vez de encimarse en pantallas angostas.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              FilterChip(
                label: Text(_soloVigentes
                    ? 'Solo vigentes y por iniciar'
                    : 'Mostrando todas'),
                selected: _soloVigentes,
                selectedColor: cessumGold.withValues(alpha: 0.20),
                checkmarkColor: cessumRed,
                onSelected: (v) => setState(() => _soloVigentes = v),
              ),
              const SizedBox(width: 8),
              if (!_soloVigentes) ...[
                FilterChip(
                  label: Text(_verReconstruidas ? 'Con historial reconstruido' : 'Sin historial reconstruido'),
                  selected: _verReconstruidas,
                  selectedColor: const Color(0xFF90A4AE).withValues(alpha: 0.25),
                  checkmarkColor: const Color(0xFF455A64),
                  onSelected: (v) => setState(() => _verReconstruidas = v),
                ),
                const SizedBox(width: 8),
              ],
              // Los dos momentos que de verdad se trabajan por separado:
              // preparar lo que arranca, y atender lo que ya corre.
              FilterChip(
                avatar: const Icon(Icons.schedule_send, size: 16),
                label: const Text('Por iniciar'),
                selected: _momento == 'porIniciar',
                selectedColor: cessumGold.withValues(alpha: 0.25),
                checkmarkColor: cessumRed,
                onSelected: (v) =>
                    setState(() => _momento = v ? 'porIniciar' : ''),
              ),
              const SizedBox(width: 6),
              FilterChip(
                avatar: const Icon(Icons.play_circle_outline, size: 16),
                label: const Text('En curso'),
                selected: _momento == 'enCurso',
                selectedColor: const Color(0xFF1E8E3E).withValues(alpha: 0.18),
                checkmarkColor: const Color(0xFF1E8E3E),
                onSelected: (v) =>
                    setState(() => _momento = v ? 'enCurso' : ''),
              ),
              const SizedBox(width: 6),
              // Empieza pronto: el corte que separa lo urgente de lo lejano.
              ...[7, 15, 30].map((d) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text('$d días'),
                      selected: _dias == d,
                      selectedColor: cessumRed.withValues(alpha: 0.16),
                      checkmarkColor: cessumRed,
                      onSelected: (v) => setState(() => _dias = v ? d : 0),
                    ),
                  )),
              const SizedBox(width: 12),
              Text('${_asignacionesFiltradas.length} materia(s)',
                  style: TextStyle(color: cessumMuted(context), fontSize: 12)),
            ],
          ),
          ),
        ),
        // (9-sep) Programa y docente: con 101 asignaciones, buscar por texto
        // obliga a recordar el nombre exacto. Los desplegables se llenan con
        // lo que hay en la base, así que nunca ofrecen algo que no exista.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _programaFiltro.isEmpty ? null : _programaFiltro,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Programa',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todos')),
                    ..._valoresDe('programa').map((p) =>
                        DropdownMenuItem(value: p, child: Text(p))),
                  ],
                  onChanged: (v) =>
                      setState(() => _programaFiltro = v ?? ''),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                // (24-sep) Con búsqueda: es la lista completa de docentes.
                child: CessumSelectorBuscable<String>(
                  label: 'Maestro',
                  valor: _docenteFiltro.isEmpty ? null : _docenteFiltro,
                  opciones: _valoresDe('docente').toList(),
                  etiqueta: (d) => d,
                  textoNinguno: 'Todos',
                  onChanged: (v) => setState(() => _docenteFiltro = v ?? ''),
                ),
              ),
              if (_programaFiltro.isNotEmpty ||
                  _docenteFiltro.isNotEmpty ||
                  _dias > 0 ||
                  _momento.isNotEmpty)
                IconButton(
                  tooltip: 'Quitar filtros',
                  icon: const Icon(Icons.filter_alt_off, color: cessumRed),
                  onPressed: () => setState(() {
                    _programaFiltro = '';
                    _docenteFiltro = '';
                    _dias = 0;
                    _momento = '';
                  }),
                ),
            ],
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? Center(
                  child: Text('No hay asignaciones.',
                      style: TextStyle(color: cessumMuted(context))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _tarjetaAsignacion(lista[i]),
                ),
        ),
      ],
    );
  }

  Widget _tarjetaAsignacion(Map<String, dynamic> a) {
    final sinMaestro = (a['correo'] ?? '').toString().trim().isEmpty;
    final inactiva = (a['activa'] ?? 'SI').toString().toUpperCase() == 'NO';
    final zombi = _zombiDe(a);
    final terminada = !_vigente(a);
    // Programada a futuro: agendada en modo prospectivo (nota marcada o estado).
    final aFuturo = (a['notas'] ?? '')
            .toString()
            .toUpperCase()
            .contains('PROGRAMADA A FUTURO') ||
        (a['invitacionEstado'] ?? '')
            .toString()
            .toLowerCase()
            .contains('futuro');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: terminada ? const Color(0xFFF1EFEC) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: zombi
                ? const Color(0xFFE65100)
                : (sinMaestro ? cessumGold : cessumMuted(context).withValues(alpha: 0.18)),
            width: (zombi || sinMaestro) ? 1.4 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    (((a['_materiasJuntas'] as List?)?.length ?? 0) > 1)
                        ? (a['_materiasJuntas'] as List).join(' + ')
                        : (a['materia'] ?? '').toString(),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context))),
              ),
              if (terminada)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('Terminada',
                      style: TextStyle(fontSize: 11, color: cessumRed)),
                ),
              if (aFuturo)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFF6A1B9A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('Programada a futuro',
                      style:
                          TextStyle(fontSize: 11, color: Color(0xFF6A1B9A))),
                )
              else if (zombi)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      border: Border.all(color: const Color(0xFFE65100)),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('⚠ Inactiva con periodo vigente',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE65100))),
                )
              else if (inactiva)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: cessumMuted(context).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('Inactiva',
                      style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                ),
              if ((a['inicioNotificado'] ?? '').toString().isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1E8E3E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle,
                        size: 13, color: Color(0xFF1E8E3E)),
                    SizedBox(width: 4),
                    Text('Ya notificado',
                        style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1E8E3E),
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (((a['_materiasJuntas'] as List?)?.length ?? 0) > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                  'Impartición conjunta · '
                  '${(a['_materiasJuntas'] as List).length} materias · '
                  'una sola aula y un solo pago',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7B1FA2))),
            ),
          if (((a['_gruposUnidos'] as List?)?.length ?? 0) > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                  'Grupos juntos: ${(a['_gruposUnidos'] as List).join('  •  ')}',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1565C0))),
            ),
          _linea(Icons.school_outlined, (a['programa'] ?? '').toString()),
          _linea(Icons.groups_outlined,
              'Gen. ${a['generacion']}  •  ${a['grupo']}'),
          if (_esReconstruida(a))
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text('Historial reconstruido desde Moodle · día, hora y fechas aproximados',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF455A64))),
            ),
          if ((a['dia'] ?? '').toString().isNotEmpty ||
              (a['hora'] ?? '').toString().isNotEmpty)
            _linea(Icons.schedule,
                '${a['dia']}  •  ${a['hora']}'.trim() +
                    // (3-oct-2026) si el Guardián normalizó la hora, se ve también cómo está escrita en la hoja
                    ((a['horaOriginal'] ?? '').toString().isNotEmpty && a['horaOriginal'] != a['hora'] && a['horaEstado'] != 'igual'
                        ? '   (en la hoja: ${a['horaOriginal']})' : '') +
                    (a['horaEstado'] == 'parcial' ? '   · falta la hora de término' : '')),
          if (a['tipoSesionesInconsistente'] == true)
            _linea(Icons.warning_amber_outlined,
                'La hoja decía «${a['tipoSesionesOriginal']}» y el grupo es ${a['tipoSesiones']}: revisar'),
          _lineaVigencia(a),
          _linea(
              sinMaestro ? Icons.person_off_outlined : Icons.person_outline,
              sinMaestro
                  ? 'Sin maestro asignado'
                  : '${a['docente']}  (${a['correo']})'),
          Row(
            children: [
              Icon(
                  (a['linkLlamada'] ?? '').toString().isNotEmpty
                      ? Icons.videocam
                      : Icons.videocam_off,
                  size: 16,
                  color: (a['linkLlamada'] ?? '').toString().isNotEmpty
                      ? cessumRed
                      : cessumFaint(context)),
              const SizedBox(width: 6),
              Icon(
                  (a['linkAula'] ?? '').toString().isNotEmpty
                      ? Icons.cast_for_education
                      : Icons.school_outlined,
                  size: 16,
                  color: (a['linkAula'] ?? '').toString().isNotEmpty
                      ? cessumGold
                      : cessumFaint(context)),
              const SizedBox(width: 6),
              Text(
                [
                  if ((a['linkLlamada'] ?? '').toString().isNotEmpty)
                    'videollamada',
                  if ((a['linkAula'] ?? '').toString().isNotEmpty) 'aula',
                ].isEmpty
                    ? 'sin links'
                    : [
                        if ((a['linkLlamada'] ?? '').toString().isNotEmpty)
                          'videollamada',
                        if ((a['linkAula'] ?? '').toString().isNotEmpty) 'aula',
                      ].join(' · '),
                style: TextStyle(fontSize: 12, color: cessumFaint(context)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if ((a['inicioNotificado'] ?? '').toString().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E8E3E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Ya se notificó el inicio el ${a['inicioNotificado']}. '
                'Evita enviarlo de nuevo para no duplicar.',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E8E3E),
                    fontWeight: FontWeight.w600),
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 2,
            children: [
              TextButton.icon(
                onPressed: () => _crearAulaMeet(a),
                style: TextButton.styleFrom(foregroundColor: cessumRed),
                icon: const Icon(Icons.school, size: 18),
                label: Text(_sinMeet(a) ? 'Crear aula' : 'Aula + Meet'),
              ),
              TextButton.icon(
                onPressed: () => _notificarInicio(a),
                style: TextButton.styleFrom(foregroundColor: cessumGold),
                icon: const Icon(Icons.campaign, size: 18),
                label: const Text('Notificar inicio'),
              ),
              TextButton.icon(
                onPressed: () => _abrirForm(existente: a),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Editar'),
              ),
              TextButton.icon(
                onPressed: () => _eliminar(a),
                style: TextButton.styleFrom(foregroundColor: cessumRed),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Eliminar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Cuándo termina una generación, según su clave y el nivel del programa.
  /// "26-1" arranca en enero de 2026 y "26-2" a mitad de año; una maestría
  /// dura dos años y un doctorado tres. Es la misma regla que usa el
  /// servidor, replicada aquí para no pedirle otra consulta.
  DateTime? _finDeGeneracion(String programa, String generacion) {
    final m = RegExp(r'(\d{2})\s*[-_/]\s*(\d+)').firstMatch(generacion);
    if (m == null) return null;
    final anio = 2000 + int.parse(m.group(1)!);
    final periodo = int.parse(m.group(2)!);
    final p = programa.toLowerCase();
    final esDoctorado = p.contains('doctorado');
    // (28-sep, Fase 1) Comparaba contra el texto CON ACENTO sin normalizar:
    // un programa sin acentos calculaba la duración de la generación como si
    // fuera un posgrado normal (24 meses) en vez de los 12 de Maestría en
    // Educación. _reglaDe vive en agenda_profesores_form.dart, misma
    // librería (part of): se reutiliza en vez de reimplementar la
    // comparación aquí. El grupo no importa para esto — _tieneHorarioFijo
    // depende solo del programa — así que se manda vacío.
    final esMEdu = _reglaDe(programa, '').horarioFijo;
    final mesInicio = esMEdu ? (periodo - 1) * 3 + 1 : (periodo >= 2 ? 6 : 1);
    final duracion = esMEdu ? 12 : (esDoctorado ? 36 : 24);
    return DateTime(anio, (mesInicio - 1) + duracion + 1, 1);
  }

  bool _genTerminada(Map<String, dynamic> g) {
    // MIXTA: no se rige por el egreso del padrón. Sus periodos son de verano
    // y el último cae ~2 años después del inicio de la generación, así que un
    // grupo mixta puede seguir vigente aunque sus alumnos figuren como
    // egresados. Se considera terminado SOLO si ya no tiene ninguna
    // asignación con término en el futuro.
    final grupo = (g['grupo'] ?? '').toString().toLowerCase();
    if (grupo.contains('mixt')) {
      final prog = (g['programa'] ?? '').toString();
      final gen = (g['generacion'] ?? '').toString();
      final kg = _keyGen(prog, gen);
      final hoy = DateTime.now();
      final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);
      var hayFuturo = false;
      var hayFechas = false;
      for (final a in _asignaciones) {
        if (_keyGen((a['programa'] ?? '').toString(),
                (a['generacion'] ?? '').toString()) !=
            kg) continue;
        if (!(a['grupo'] ?? '').toString().toLowerCase().contains('mixt')) {
          continue;
        }
        final fin = _fechaIso((a['termino'] ?? '').toString());
        if (fin == null) continue;
        hayFechas = true;
        if (!fin.isBefore(hoy0)) hayFuturo = true;
      }
      // (ago-15) QUE NO HAYA MATERIAS FUTURAS NO SIGNIFICA QUE LA GENERACIÓN
      // ACABÓ. Significa que nadie le ha agendado las siguientes — que es
      // exactamente cuando hay que verla, no cuando hay que esconderla.
      // Doctorado en Ciencias de la Educación 26-1 y Psicopedagogía 26-1
      // salían "ya terminada" y egresan hasta 2028: entraron este año, sus
      // primeras materias ya cerraron y las que siguen no están programadas.
      // Ahora se coteja contra el fin real de la generación: mientras no
      // llegue esa fecha, el grupo sigue vivo aunque su agenda esté vacía.
      final finGen = _finDeGeneracion(prog, gen);
      if (finGen != null && finGen.isAfter(hoy0)) return false;
      // Con fechas y al menos un término futuro → NO terminada.
      if (hayFechas) return !hayFuturo;
      // (ago-15) SIN NINGUNA ASIGNACIÓN NO ESTÁ TERMINADA, ESTÁ EMPEZANDO.
      // Un grupo mixta recién abierto no tiene materias agendadas todavía,
      // así que no hay términos futuros y la regla lo daba por concluido —
      // justo en el momento en que hay que programarle maestros. Pasó con
      // Doctorado en Ciencias de la Educación 26-1 y Psicopedagogía 26-1,
      // que egresan hasta 2028.
      // Sin fechas legibles tampoco se marca: evita el mismo falso positivo.
      return false;
    }
    return _gensEgresadas.contains(_keyGen(
        (g['programa'] ?? '').toString(), (g['generacion'] ?? '').toString()));
  }

  // ===================================================================
  //  DISPONIBILIDAD (V-agenda): materias VIGENTES + choques por día/hora.
  //  Vigente = activa 'SI' y término en el futuro (fecha ISO yyyy-MM-dd).
  //  Choque = mismo día de la semana + franjas de hora que se enciman.
  //  Mixta (día vacío) se lista aparte: es un bloque de fechas, no choca
  //  por día de la semana. Horas no interpretables -> ámbar, sin choque.
  // ===================================================================

  // Interpreta un texto de hora del primer HH:MM y sus marcas am/pm.
  // Devuelve [hora, minuto, traeSufijo(0/1), esPM(0/1), esAM(0/1)] o null.
  List<int>? _baseHora(String bruto) {
    final t = bruto.trim().toLowerCase();
    final m = RegExp(r'(\d{1,2})(?::(\d{2}))?').firstMatch(t);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '');
    final mi = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (h == null || h > 23 || mi > 59) return null;
    final pm = RegExp(r'p\.?\s?m', caseSensitive: false).hasMatch(t);
    final am = RegExp(r'a\.?\s?m', caseSensitive: false).hasMatch(t);
    return [h, mi, (pm || am) ? 1 : 0, pm ? 1 : 0, am ? 1 : 0];
  }

  int _candMin(int h, int mi, {int? forcePM}) {
    var hh = h;
    if (forcePM == 1 && hh < 12) hh += 12;
    if (forcePM == 0 && hh == 12) hh = 0;
    return hh * 60 + mi;
  }

  // Interpreta "inicio-fin" o "inicio a fin" a [iniMin, finMin]. Prueba las
  // lecturas posibles de am/pm y se queda con la única coherente
  // (inicio < fin y duración <= 6 h). Devuelve null si no se puede (typos,
  // fechas basura de Sheets, formatos ambiguos) -> se marca en ámbar.
  List<int>? _rangoHora(String bruto) {
    final t = bruto.trim();
    if (t.isEmpty) return null;
    final tl = t.toLowerCase();
    if (tl.contains('1899') || tl.contains('gmt') || t.contains('::')) {
      return null;
    }
    final partes = t.split(RegExp(r'\s*-\s*|\s+a\s+', caseSensitive: false));
    if (partes.length != 2) return null;
    final b0 = _baseHora(partes[0]);
    final b1 = _baseHora(partes[1]);
    if (b0 == null || b1 == null) return null;

    List<int> opciones(List<int> b) {
      // b = [h, mi, tiene, pm, am]
      if (b[2] == 1) {
        return [_candMin(b[0], b[1], forcePM: b[3] == 1 ? 1 : 0)];
      }
      return [_candMin(b[0], b[1], forcePM: 0), _candMin(b[0], b[1], forcePM: 1)];
    }

    final o0 = opciones(b0);
    final o1 = opciones(b1);
    List<int>? mejor;
    for (final a in o0) {
      for (final c in o1) {
        if (a < c && (c - a) <= 360) {
          if (mejor == null || (c - a) < (mejor[1] - mejor[0])) {
            mejor = [a, c];
          }
        }
      }
    }
    return mejor;
  }

  bool _mixtaDe(Map<String, dynamic> a) =>
      (a['grupo'] ?? '').toString().toLowerCase().contains('mixt') ||
      (a['tipoSesiones'] ?? '').toString().toLowerCase().contains('mixt');

  // (ago-2026) ZOMBI: asignación INACTIVA cuyo periodo sigue vigente
  // (término hoy o después). Combinación anómala — normalmente una fila que
  // se apagó en un reacomodo y nadie volvió a encender: el docente no la ve
  // en su panel ni puede capturar acta. Se marca en ámbar para que no se
  // esconda (caso real: Ajustes razonables 26-1 de Tomary, activa=NO con
  // invitación Aceptada y término 9-ago).
  bool _zombiDe(Map<String, dynamic> a) {
    if ((a['activa'] ?? 'SI').toString().toUpperCase() != 'NO') return false;
    final term = (a['termino'] ?? '').toString().trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(term);
    if (m == null) return false; // sin término legible no alarmamos
    final t = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!));
    final hoy = DateTime.now();
    final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);
    return !t.isBefore(hoy0);
  }

  // Vigente = activa 'SI' y término hoy o después.
  bool _vigenteDe(Map<String, dynamic> a) {
    if ((a['activa'] ?? '').toString().toUpperCase() != 'SI') return false;
    final term = (a['termino'] ?? '').toString().trim();
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(term);
    if (m == null) return true; // sin término legible: no la descartamos
    final t = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
        int.parse(m.group(3)!));
    final hoy = DateTime.now();
    final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);
    return !t.isBefore(hoy0);
  }

  static const _ordenDias = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo'
  ];

  // ===================================================================
  //  POR GRUPO: programación completa de un grupo — lo que ya pasó, lo
  //  que está en curso y lo AGENDADO A FUTURO — para programar con visión.
  // ===================================================================
  String _grupoTLSel = '';
  String _docenteTLSel = '';

  String _etapaAsig(Map a) {
    final ini = _fechaIso((a['inicio'] ?? '').toString());
    final fin = _fechaIso((a['termino'] ?? '').toString());
    final hoy = DateTime.now();
    final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);
    if (ini == null || fin == null) return 'Sin fechas';
    if (hoy0.isBefore(ini)) return 'Futura';
    if (hoy0.isAfter(fin)) return 'Terminada';
    return 'En curso';
  }

  // ===================================================================
  //  PRÓXIMA MATERIA: grupos cuyo curso actual corre o terminó pero la
  //  SIGUIENTE materia aún no tiene maestro. Sabatino requiere DOS
  //  maestros (dos materias en paralelo); entre semana/Educación, uno.
  //  Mixta se excluye (tiene su propio visor por temporadas).
  // ===================================================================
  // Normaliza horas a formato 12h español: "20:00-21:00" → "8:00 a 9:00 p.m.";
  // "11:00-13:00" → "11:00 a.m. a 1:00 p.m.". Lo ya escrito en 12h se respeta.
  String _horaAmPm(String h) {
    var t = h.trim();
    if (t.isEmpty) return t;
    if (t.toLowerCase().contains('m.') || t.toLowerCase().contains('am') ||
        t.toLowerCase().contains('pm')) {
      return t; // ya viene en 12h
    }
    final tokens = RegExp(r'(\d{1,2}):(\d{2})')
        .allMatches(t)
        .map((m) => [int.parse(m.group(1)!), int.parse(m.group(2)!)])
        .toList();
    if (tokens.isEmpty) return t;
    String doce(List<int> hm) {
      final h24 = hm[0];
      final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
      return '$h12:${hm[1].toString().padLeft(2, '0')}';
    }

    String mer(List<int> hm) => hm[0] < 12 ? 'a.m.' : 'p.m.';
    if (tokens.length == 1) {
      return '${doce(tokens[0])} ${mer(tokens[0])}';
    }
    final a = tokens[0];
    final b = tokens[1];
    if (mer(a) == mer(b)) {
      return '${doce(a)} a ${doce(b)} ${mer(b)}';
    }
    return '${doce(a)} ${mer(a)} a ${doce(b)} ${mer(b)}';
  }

  Widget _tabProximaMateria() {
    final hoy = DateTime.now();
    final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);
    final porGrupo = <String, List<Map<String, dynamic>>>{};
    for (final a in _asignaciones) {
      if ((a['estado'] ?? '').toString().toLowerCase() == 'rechazada') {
        continue;
      }
      if ((a['activa'] ?? '').toString().toUpperCase() == 'NO') continue;
      final gr = (a['grupo'] ?? '').toString().trim();
      if (gr.toLowerCase().contains('mixt')) continue;
      final prog = (a['programa'] ?? '').toString().trim();
      final gen = (a['generacion'] ?? '').toString().trim();
      if (prog.isEmpty || gr.isEmpty) continue;
      if (_gensEgresadas.contains(_keyGen(prog, gen))) continue;
      porGrupo.putIfAbsent('$prog||$gen||$gr', () => []).add(a);
    }
    final tarjetas = <Map<String, dynamic>>[];
    porGrupo.forEach((k, lista) {
      DateTime? finActual; // término más lejano de lo YA iniciado
      final enCurso = <String>[];
      var futuras = 0;
      final futurasNombres = <String>[];
      for (final a in lista) {
        final ini = _fechaIso((a['inicio'] ?? '').toString());
        final fin = _fechaIso((a['termino'] ?? '').toString());
        if (ini == null || fin == null) continue;
        if (hoy0.isBefore(ini)) {
          futuras++;
          futurasNombres.add((a['materia'] ?? '').toString());
        } else {
          if (finActual == null || fin.isAfter(finActual)) finActual = fin;
          if (!hoy0.isAfter(fin)) {
            enCurso.add((a['materia'] ?? '').toString());
          }
        }
      }
      if (finActual == null) return; // sin fechas legibles: no se juzga
      final partes = k.split('||');
      final esSab =
          k.toLowerCase().contains('sabat');
      final requeridas = esSab ? 2 : 1;
      if (futuras >= requeridas) return; // la próxima ya está cubierta
      final dias = finActual.difference(hoy0).inDays;
      if (dias > 35) return; // aún hay margen de sobra
      tarjetas.add({
        'programa': partes[0],
        'generacion': partes.length > 1 ? partes[1] : '',
        'grupo': partes.length > 2 ? partes[2] : '',
        'finActual': finActual,
        'dias': dias,
        'enCurso': enCurso,
        'esSab': esSab,
        'futuras': futuras,
        'requeridas': requeridas,
        'futurasNombres': futurasNombres,
      });
    });
    tarjetas.sort(
        (a, b) => (a['dias'] as int).compareTo(b['dias'] as int));
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text(
          'GRUPOS SIN MAESTRO PARA LA PRÓXIMA MATERIA',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: cessumRed,
              letterSpacing: 0.4),
        ),
        const SizedBox(height: 4),
        Text(
          'El curso actual sigue su marcha, pero la materia que sigue aún no '
          'tiene maestro agendado. Sabatino necesita DOS (dos materias en '
          'paralelo). Se listan los grupos cuya programación termina en 35 '
          'días o menos, los más urgentes primero.',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        const SizedBox(height: 12),
        if (tarjetas.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                'Todo cubierto: ningún grupo se queda sin maestro para su '
                'próxima materia en las siguientes 5 semanas. 🎉',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
              ),
            ),
          )
        else
          for (final t in tarjetas) _tarjetaProxima(t),
      ],
    );
  }

  Widget _tarjetaProxima(Map<String, dynamic> t) {
    final dias = t['dias'] as int;
    final vencida = dias < 0;
    final esSab = t['esSab'] == true;
    final futuras = t['futuras'] as int;
    final parcial = esSab && futuras == 1;
    final enCurso = (t['enCurso'] as List).cast<String>();
    final futNoms = (t['futurasNombres'] as List).cast<String>();
    final color = vencida
        ? cessumRed
        : (dias <= 10 ? cessumRed : cessumGold);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${t['programa']}',
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700)),
          Text('Gen. ${t['generacion']} · ${t['grupo']}',
              style:
                  const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(
            vencida
                ? 'La programación VENCIÓ hace ${-dias} día(s) '
                    '(${_fechaCorta(t['finActual'] as DateTime)}).'
                : 'El curso actual termina el '
                    '${_fechaCorta(t['finActual'] as DateTime)} '
                    '(en $dias día(s)).',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color),
          ),
          if (enCurso.isNotEmpty)
            Text('En curso: ${enCurso.join(' · ')}',
                style: TextStyle(
                    fontSize: 11.5, color: cessumInk(context))),
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              parcial
                  ? 'Sabatino: 1 de 2 maestros cubiertos para la próxima '
                      '(${futNoms.join(", ")})'
                  : (esSab
                      ? 'Sin maestros para la próxima (se requieren 2)'
                      : 'Sin maestro para la próxima materia'),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              onPressed: () => _abrirForm(
                prog: (t['programa'] ?? '').toString(),
                gen: (t['generacion'] ?? '').toString(),
                grupo: (t['grupo'] ?? '').toString(),
              ),
              icon: const Icon(Icons.event_available, size: 18),
              label: Text(parcial
                  ? 'Programar el segundo maestro'
                  : 'Programar la próxima materia'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabPorGrupo() {
    final grupos = <String, Map<String, String>>{};
    for (final a in _asignaciones) {
      final p = (a['programa'] ?? '').toString().trim();
      final g = (a['generacion'] ?? '').toString().trim();
      final gr = (a['grupo'] ?? '').toString().trim();
      if (p.isEmpty || gr.isEmpty) continue;
      grupos['$p||$g||$gr'] = {'programa': p, 'generacion': g, 'grupo': gr};
    }
    final llaves = grupos.keys.toList()..sort();
    final sel = grupos[_grupoTLSel];
    final lista = <Map<String, dynamic>>[];
    if (sel != null) {
      for (final a in _asignaciones) {
        if ((a['programa'] ?? '').toString().trim() != sel['programa']) continue;
        if ((a['generacion'] ?? '').toString().trim() != sel['generacion']) {
          continue;
        }
        if ((a['grupo'] ?? '').toString().trim() != sel['grupo']) continue;
        lista.add(a);
      }
      lista.sort((x, y) {
        final fx = _fechaIso((x['inicio'] ?? '').toString());
        final fy = _fechaIso((y['inicio'] ?? '').toString());
        if (fx == null && fy == null) return 0;
        if (fx == null) return 1;
        if (fy == null) return -1;
        return fx.compareTo(fy);
      });
    }
    var fut = 0, cur = 0, ter = 0;
    for (final a in lista) {
      final e = _etapaAsig(a);
      if (e == 'Futura') {
        fut++;
      } else if (e == 'En curso') {
        cur++;
      } else if (e == 'Terminada') {
        ter++;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: cessumRed,
            side: const BorderSide(color: cessumRed),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          ),
          onPressed: () => _elegirGrupoTL(llaves, grupos),
          icon: const Icon(Icons.groups),
          label: Text(
            sel == null
                ? 'Elegir grupo…'
                : '${sel['programa']} · ${sel['generacion']} · ${sel['grupo']}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        if (sel == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Text(
              'Elige un grupo para ver TODA su programación en línea de '
              'tiempo: lo que ya pasó, lo que está en curso y lo agendado a '
              'futuro. Ideal para planear el siguiente periodo sin encimar '
              'materias.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
            ),
          )
        else ...[
          Text(
            '${lista.length} materia(s) · $ter terminada(s) · '
            '$cur en curso · $fut futura(s)',
            style: TextStyle(fontSize: 12, color: cessumMuted(context)),
          ),
          const SizedBox(height: 8),
          for (final a in lista) _filaTL(a),
        ],
      ],
    );
  }

  Future<void> _elegirGrupoTL(
      List<String> llaves, Map<String, Map<String, String>> grupos) async {
    final busca = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = busca.text.trim().toLowerCase();
          final vis = llaves
              .where((k) => q.isEmpty || k.toLowerCase().contains(q))
              .toList();
          return AlertDialog(
            title: const Text('Elegir grupo'),
            content: SizedBox(
              width: 440,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    controller: busca,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Buscar programa, generación o grupo…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: vis.isEmpty
                        ? const Center(child: Text('Sin coincidencias.'))
                        : ListView.builder(
                            itemCount: vis.length,
                            itemBuilder: (_, i) {
                              final g = grupos[vis[i]]!;
                              return ListTile(
                                dense: true,
                                title: Text(g['programa'] ?? ''),
                                subtitle: Text(
                                    '${g['generacion']} · ${g['grupo']}'),
                                onTap: () => Navigator.pop(ctx, vis[i]),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
            ],
          );
        },
      ),
    );
    busca.dispose();
    if (r != null) setState(() => _grupoTLSel = r);
  }

  // (1-oct-2026) PESTAÑA "POR PROFESOR" — se elige un docente y se ve TODO
  // su panorama: sus asignaciones (grupos, materias, modalidades, horarios,
  // vigentes/futuras/terminadas) y, debajo, su disponibilidad real: los
  // días y franjas que YA tiene ocupados con sus materias vigentes, para
  // ver de un vistazo qué le queda libre. Mismo patrón que "Por grupo".
  Widget _tabPorProfesor() {
    final docentes = <String, Map<String, String>>{};
    for (final a in _asignaciones) {
      final correo = (a['correo'] ?? '').toString().trim().toLowerCase();
      final nombre = (a['docente'] ?? '').toString().trim();
      if (correo.isEmpty && nombre.isEmpty) continue;
      final llave = correo.isNotEmpty ? correo : nombre.toLowerCase();
      docentes[llave] = {'nombre': nombre.isEmpty ? correo : nombre, 'correo': correo};
    }
    final llaves = docentes.keys.toList()
      ..sort((a, b) =>
          (docentes[a]!['nombre'] ?? '').compareTo(docentes[b]!['nombre'] ?? ''));
    final sel = docentes[_docenteTLSel];

    final lista = <Map<String, dynamic>>[];
    if (sel != null) {
      for (final a in _asignaciones) {
        final correo = (a['correo'] ?? '').toString().trim().toLowerCase();
        final nombre = (a['docente'] ?? '').toString().trim().toLowerCase();
        final mismoCorreo = sel['correo']!.isNotEmpty && correo == sel['correo'];
        final mismoNombre =
            sel['correo']!.isEmpty && nombre == (sel['nombre'] ?? '').toLowerCase();
        if (!mismoCorreo && !mismoNombre) continue;
        lista.add(a);
      }
      lista.sort((x, y) {
        final fx = _fechaIso((x['inicio'] ?? '').toString());
        final fy = _fechaIso((y['inicio'] ?? '').toString());
        if (fx == null && fy == null) return 0;
        if (fx == null) return 1;
        if (fy == null) return -1;
        return fx.compareTo(fy);
      });
    }

    var fut = 0, cur = 0, ter = 0;
    for (final a in lista) {
      final e = _etapaAsig(a);
      if (e == 'Futura') {
        fut++;
      } else if (e == 'En curso') {
        cur++;
      } else if (e == 'Terminada') {
        ter++;
      }
    }

    // Disponibilidad: solo lo VIGENTE de este docente, agrupado por día —
    // mismo criterio que la pestaña "Disponibilidad" general.
    final vigentes = lista.where(_vigenteDe).toList();
    final mixtasVig = vigentes.where(_mixtaDe).toList();
    final semanalesVig = vigentes.where((a) => !_mixtaDe(a)).toList();
    final porDia = <String, List<Map<String, dynamic>>>{};
    for (final a in semanalesVig) {
      final d = (a['dia'] ?? '').toString().trim();
      (porDia[d.isEmpty ? '(sin día)' : d] ??= []).add(a);
    }
    for (final lst in porDia.values) {
      lst.sort((x, y) {
        final rx = _rangoHora((x['hora'] ?? '').toString());
        final ry = _rangoHora((y['hora'] ?? '').toString());
        if (rx == null && ry == null) return 0;
        if (rx == null) return 1;
        if (ry == null) return -1;
        return rx[0].compareTo(ry[0]);
      });
    }
    final diasOrdenados = porDia.keys.toList()
      ..sort((a, b) {
        final ia = _ordenDias.indexOf(a);
        final ib = _ordenDias.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: cessumRed,
            side: const BorderSide(color: cessumRed),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          ),
          onPressed: () => _elegirDocenteTL(llaves, docentes),
          icon: const Icon(Icons.person_search),
          label: Text(
            sel == null ? 'Elegir profesor…' : (sel['nombre'] ?? ''),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 10),
        if (sel == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Text(
              'Elige un profesor para ver todas sus posibilidades: los '
              'grupos y modalidades que ya tiene asignados, y los días/'
              'horas que le quedan libres para una materia nueva.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
            ),
          )
        else ...[
          Text(
            '${lista.length} materia(s) · $ter terminada(s) · '
            '$cur en curso · $fut futura(s)',
            style: TextStyle(fontSize: 12, color: cessumMuted(context)),
          ),
          const SizedBox(height: 8),
          for (final a in lista) _filaTL(a),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cessumRed.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_available, color: cessumRed),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Disponibilidad — ${vigentes.length} materia(s) vigente(s) '
                    'ocupando su horario (${mixtasVig.length} mixta(s), fuera '
                    'de franja fija).',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (diasOrdenados.isEmpty && mixtasVig.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'No tiene ninguna materia vigente ahora mismo: está libre '
                'en cualquier día y horario.',
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
              ),
            )
          else ...[
            for (final dia in diasOrdenados) ..._bloqueDia(dia, porDia[dia]!),
            if (mixtasVig.isNotEmpty) ...[
              const SizedBox(height: 8),
              _tituloDia('Mixtas (bloque de fechas)', mixtasVig.length),
              const SizedBox(height: 6),
              for (final a in mixtasVig) _filaMixta(a),
            ],
          ],
        ],
      ],
    );
  }

  Future<void> _elegirDocenteTL(
      List<String> llaves, Map<String, Map<String, String>> docentes) async {
    final busca = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = busca.text.trim().toLowerCase();
          final vis = llaves
              .where((k) =>
                  q.isEmpty || (docentes[k]!['nombre'] ?? '').toLowerCase().contains(q))
              .toList();
          return AlertDialog(
            title: const Text('Elegir profesor'),
            content: SizedBox(
              width: 440,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    controller: busca,
                    autofocus: true,
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre…',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: vis.isEmpty
                        ? const Center(child: Text('Sin coincidencias.'))
                        : ListView.builder(
                            itemCount: vis.length,
                            itemBuilder: (_, i) {
                              final d = docentes[vis[i]]!;
                              return ListTile(
                                dense: true,
                                title: Text(d['nombre'] ?? ''),
                                subtitle: (d['correo'] ?? '').isNotEmpty
                                    ? Text(d['correo']!)
                                    : null,
                                onTap: () => Navigator.pop(ctx, vis[i]),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
            ],
          );
        },
      ),
    );
    busca.dispose();
    if (r != null) setState(() => _docenteTLSel = r);
  }

  Widget _filaTL(Map<String, dynamic> a) {
    final etapa = _etapaAsig(a);
    final color = etapa == 'Futura'
        ? const Color(0xFF1E6FD9)
        : etapa == 'En curso'
            ? const Color(0xFF1E8E3E)
            : etapa == 'Terminada'
                ? Colors.grey.shade600
                : cessumGold;
    final doc = (a['docente'] ?? '').toString().trim();
    final dia = (a['dia'] ?? '').toString().trim();
    final hora = (a['hora'] ?? '').toString().trim();
    final ini = (a['inicio'] ?? '').toString().trim();
    final fin = (a['termino'] ?? '').toString().trim();
    final estado = (a['estado'] ?? '').toString().trim();
    final partes = <String>[
      if (dia.isNotEmpty || hora.isNotEmpty)
        [dia, _horaAmPm(hora)].where((x) => x.isNotEmpty).join(' '),
      if (ini.isNotEmpty || fin.isNotEmpty) 'del $ini al $fin',
      if (estado.isNotEmpty) estado,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (a['materia'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(etapa,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(doc.isEmpty ? 'Sin docente' : doc,
              style: TextStyle(
                  fontSize: 12,
                  color: doc.isEmpty ? cessumGold : cessumInk(context))),
          if (partes.isNotEmpty)
            Text(partes.join(' · '),
                style:
                    const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _tabDisponibilidad() {
    final vigentes = _asignaciones.where(_vigenteDe).toList();
    final mixtas = vigentes.where(_mixtaDe).toList();
    final semanales = vigentes.where((a) => !_mixtaDe(a)).toList();

    // Agrupa por día de la semana.
    final porDia = <String, List<Map<String, dynamic>>>{};
    for (final a in semanales) {
      final d = (a['dia'] ?? '').toString().trim();
      (porDia[d.isEmpty ? '(sin día)' : d] ??= []).add(a);
    }

    // Ordena cada día por hora de inicio (las no interpretables al final).
    for (final lista in porDia.values) {
      lista.sort((x, y) {
        final rx = _rangoHora((x['hora'] ?? '').toString());
        final ry = _rangoHora((y['hora'] ?? '').toString());
        if (rx == null && ry == null) return 0;
        if (rx == null) return 1;
        if (ry == null) return -1;
        return rx[0].compareTo(ry[0]);
      });
    }

    final diasOrdenados = porDia.keys.toList()
      ..sort((a, b) {
        final ia = _ordenDias.indexOf(a);
        final ib = _ordenDias.indexOf(b);
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumRed.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_available, color: cessumRed),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${vigentes.length} materias vigentes '
                  '(${semanales.length} por día · ${mixtas.length} mixtas). '
                  'Rojo = choque real: mismo grupo o mismo docente, mismo día, horas y fechas encimadas.',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final dia in diasOrdenados) ..._bloqueDia(dia, porDia[dia]!),
        if (mixtas.isNotEmpty) ...[
          const SizedBox(height: 8),
          _tituloDia('Mixtas (bloque de fechas)', mixtas.length),
          const SizedBox(height: 6),
          for (final a in mixtas) _filaMixta(a),
        ],
      ],
    );
  }

  Widget _tituloDia(String dia, int n) => Row(
        children: [
          Text(dia,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: cessumRed)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: cessumRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20)),
            child: Text('$n',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: cessumRed)),
          ),
        ],
      );

  // Devuelve el bloque de un día: título + filas, marcando choques.
  List<Widget> _bloqueDia(String dia, List<Map<String, dynamic>> lista) {
    // CHOQUE REAL (jul-2026): mismo día + horas encimadas Y ADEMÁS
    //   (a) mismo grupo (programa+generación+grupo) o mismo docente, y
    //   (b) vigencias traslapadas (si a alguna le faltan fechas, se asume
    //       traslape para no ocultar un choque potencial).
    // Dos grupos distintos con docentes distintos a la misma hora es
    // operación normal de la institución, no un choque. Y misma hora en
    // periodos de fechas que no se tocan tampoco choca.
    String norm(dynamic x) => (x ?? '').toString().trim().toLowerCase();
    bool vigTraslapan(Map a, Map b) {
      final ai = _fechaIso((a['inicio'] ?? '').toString());
      final af = _fechaIso((a['termino'] ?? '').toString());
      final bi = _fechaIso((b['inicio'] ?? '').toString());
      final bf = _fechaIso((b['termino'] ?? '').toString());
      if (ai == null || af == null || bi == null || bf == null) return true;
      return !ai.isAfter(bf) && !bi.isAfter(af);
    }
    bool mismoActor(Map a, Map b) {
      final ga =
          '${norm(a['programa'])}|${norm(a['generacion'])}|${norm(a['grupo'])}';
      final gb =
          '${norm(b['programa'])}|${norm(b['generacion'])}|${norm(b['grupo'])}';
      if (ga == gb) return true;
      final ca = norm(a['correo']);
      final cb = norm(b['correo']);
      if (ca.isNotEmpty && ca == cb) return true;
      final da = norm(a['docente']);
      final db = norm(b['docente']);
      return da.isNotEmpty && da == db;
    }
    final choca = List<bool>.filled(lista.length, false);
    for (var i = 0; i < lista.length; i++) {
      final ri = _rangoHora((lista[i]['hora'] ?? '').toString());
      if (ri == null) continue;
      for (var j = i + 1; j < lista.length; j++) {
        final rj = _rangoHora((lista[j]['hora'] ?? '').toString());
        if (rj == null) continue;
        if (!mismoActor(lista[i], lista[j])) continue;
        if (!vigTraslapan(lista[i], lista[j])) continue;
        // Se enciman si inicio de una < fin de la otra en ambos sentidos.
        if (ri[0] < rj[1] && rj[0] < ri[1]) {
          choca[i] = true;
          choca[j] = true;
        }
      }
    }
    return [
      const SizedBox(height: 6),
      _tituloDia(dia, lista.length),
      const SizedBox(height: 6),
      for (var i = 0; i < lista.length; i++) _filaSemanal(lista[i], choca[i]),
      const SizedBox(height: 10),
    ];
  }

  Widget _filaSemanal(Map<String, dynamic> a, bool choca) {
    final horaTxt = (a['hora'] ?? '').toString().trim();
    final interpretable = _rangoHora(horaTxt) != null;
    final docente = (a['docente'] ?? '').toString().trim();
    final materia = (a['materia'] ?? '').toString().trim();
    final prog = (a['programa'] ?? '').toString().trim();
    final grupo = (a['grupo'] ?? '').toString().trim();
    final gen = (a['generacion'] ?? '').toString().trim();

    final Color fondo = choca
        ? const Color(0xFFFFEBEE)
        : (!interpretable ? const Color(0xFFFFF7E6) : Colors.white);
    final Color borde = choca
        ? cessumRed
        : (!interpretable ? const Color(0xFFD9C189) : cessumMuted(context).withValues(alpha: 0.18));

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: interpretable
                      ? cessumRed.withOpacity(0.1)
                      : const Color(0xFFEAD9A6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  horaTxt.isEmpty ? '(sin hora)' : horaTxt,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: interpretable ? cessumRed : const Color(0xFF7A5B00)),
                ),
              ),
              if (choca) ...[
                const SizedBox(width: 8),
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: cessumRed),
                const Text(' Choque',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cessumRed)),
              ] else if (!interpretable) ...[
                const SizedBox(width: 8),
                const Text('Horario no interpretable',
                    style:
                        TextStyle(fontSize: 11, color: Color(0xFF7A5B00))),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(docente.isEmpty ? '(sin maestro)' : docente,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600)),
          Text(materia,
              style: TextStyle(fontSize: 12.5, color: cessumInk(context))),
          Text('$prog · $gen · $grupo',
              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ],
      ),
    );
  }

  Widget _filaMixta(Map<String, dynamic> a) {
    final docente = (a['docente'] ?? '').toString().trim();
    final materia = (a['materia'] ?? '').toString().trim();
    final prog = (a['programa'] ?? '').toString().trim();
    final gen = (a['generacion'] ?? '').toString().trim();
    final hora = (a['hora'] ?? '').toString().trim();
    final ini = (a['inicio'] ?? '').toString().trim();
    final term = (a['termino'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC9BCE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.date_range, size: 15, color: Color(0xFF6A4FB0)),
              const SizedBox(width: 6),
              Text('$ini → $term',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6A4FB0))),
              const SizedBox(width: 8),
              Text(hora, style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(docente.isEmpty ? '(sin maestro)' : docente,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600)),
          Text(materia,
              style: TextStyle(fontSize: 12.5, color: cessumInk(context))),
          Text('$prog · $gen',
              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ],
      ),
    );
  }

  // ===================================================================
  //  VISOR MIXTA: bloques por grupo, temporada deducida de las fechas,
  //  materias esperadas (verano 3 · invierno 1 · primavera 1) vs las que
  //  ya tienen maestro, para ver de un vistazo qué falta agendar.
  // ===================================================================

  // Temporada deducida del mes de INICIO del periodo.
  //  verano: jun-ago · invierno: dic-feb · primavera: mar-may · otoño: sep-nov
  String _temporadaDe(DateTime? ini) {
    if (ini == null) return '';
    final m = ini.month;
    if (m >= 6 && m <= 8) return 'Verano';
    if (m == 12 || m <= 2) return 'Invierno';
    if (m >= 3 && m <= 5) return 'Primavera';
    return 'Otoño';
  }

  // Materias esperadas por temporada (regla CESSUM).
  int _esperadasTemporada(String temporada) {
    switch (temporada) {
      case 'Verano':
        return 3;
      case 'Invierno':
        return 1;
      case 'Primavera':
        return 1;
      default:
        return 3; // Otoño/desconocida: se asume bloque de verano
    }
  }

  DateTime? _fechaIso(String s) => _fechaIsoTexto(s);   // (23-sep) una sola implementación, abajo

  String _fechaCorta(DateTime? d) {
    if (d == null) return '—';
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    return '${d.day} ${meses[d.month - 1]} ${d.year}';
  }

  bool _mixtaAsig(Map<String, dynamic> a) =>
      (a['grupo'] ?? '').toString().toLowerCase().contains('mixt') ||
      (a['tipoSesiones'] ?? '').toString().toLowerCase().contains('mixt');

  bool _tieneMaestro(Map<String, dynamic> a) {
    final d = (a['docente'] ?? '').toString().trim();
    final estado = (a['invitacionEstado'] ?? '').toString().trim().toLowerCase();
    // Cuenta como "con maestro" si hay docente y la invitación no fue rechazada.
    return d.isNotEmpty && estado != 'rechazada';
  }

  Widget _tabMixta() {
    // Solo asignaciones Mixta activas.
    final mixtas = _asignaciones.where((a) {
      final activa = (a['activa'] ?? '').toString().toUpperCase() == 'SI';
      return activa && _mixtaAsig(a);
    }).toList();

    if (mixtas.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No hay grupos en modalidad Mixta activos.',
              style: TextStyle(color: cessumMuted(context))),
        ),
      );
    }

    // Agrupar por programa||generación||grupo.
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final a in mixtas) {
      final k = '${a['programa']}||${a['generacion']}||${a['grupo']}';
      (grupos[k] ??= []).add(a);
    }

    // Construir tarjetas ordenadas por generación (desc) y programa.
    final claves = grupos.keys.toList()..sort((a, b) => b.compareTo(a));

    int totalFaltan = 0;
    final tarjetas = <Widget>[];
    for (final k in claves) {
      final lista = grupos[k]!;
      final m0 = lista.first;
      // Fecha de inicio del bloque = la más temprana del grupo.
      DateTime? iniBloque, finBloque;
      for (final a in lista) {
        final i = _fechaIso((a['inicio'] ?? '').toString());
        final f = _fechaIso((a['termino'] ?? '').toString());
        if (i != null && (iniBloque == null || i.isBefore(iniBloque))) {
          iniBloque = i;
        }
        if (f != null && (finBloque == null || f.isAfter(finBloque))) {
          finBloque = f;
        }
      }
      final temporada = _temporadaDe(iniBloque);
      final esperadas = _esperadasTemporada(temporada);
      final conMaestro = lista.where(_tieneMaestro).length;
      final faltan = (esperadas - conMaestro).clamp(0, esperadas);
      totalFaltan += faltan;

      tarjetas.add(_tarjetaMixta(
        m0: m0,
        lista: lista,
        temporada: temporada,
        esperadas: esperadas,
        conMaestro: conMaestro,
        faltan: faltan,
        iniBloque: iniBloque,
        finBloque: finBloque,
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F0FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFC9BCE8)),
          ),
          child: Row(
            children: [
              const Icon(Icons.grid_view_rounded, color: Color(0xFF6A4FB0)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${claves.length} grupo(s) Mixta · '
                  '${totalFaltan == 0 ? "todo agendado ✓" : "$totalFaltan materia(s) por agendar"}. '
                  'Esperadas por temporada: Verano 3 · Invierno 1 · Primavera 1.',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...tarjetas,
      ],
    );
  }

  Widget _tarjetaMixta({
    required Map<String, dynamic> m0,
    required List<Map<String, dynamic>> lista,
    required String temporada,
    required int esperadas,
    required int conMaestro,
    required int faltan,
    required DateTime? iniBloque,
    required DateTime? finBloque,
  }) {
    final programa = (m0['programa'] ?? '').toString();
    final gen = (m0['generacion'] ?? '').toString();
    final grupo = (m0['grupo'] ?? '').toString();
    final completo = faltan == 0;

    // Ordena las materias del bloque por fecha de inicio, para que salgan en
    // orden cronológico (Semana 1, 2, 3...). Las sin fecha van al final.
    final _listaOrd = [...lista]..sort((x, y) {
      final ix = _fechaIso((x['inicio'] ?? '').toString());
      final iy = _fechaIso((y['inicio'] ?? '').toString());
      if (ix == null && iy == null) return 0;
      if (ix == null) return 1;
      if (iy == null) return -1;
      return ix.compareTo(iy);
    });

    final Color acento = completo ? const Color(0xFF1E8E3E) : cessumRed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: acento.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado del bloque.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: acento.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('$programa · $gen',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: acento,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        completo ? 'Completo' : 'Faltan $faltan',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$grupo · $temporada · '
                  '${_fechaCorta(iniBloque)} → ${_fechaCorta(finBloque)}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
                const SizedBox(height: 6),
                // Barra de progreso esperadas vs con maestro.
                Row(
                  children: [
                    for (var i = 0; i < esperadas; i++)
                      Container(
                        width: 26,
                        height: 8,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: i < conMaestro
                              ? acento
                              : acento.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text('$conMaestro de $esperadas con maestro',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ],
            ),
          ),
          // Detalle materia por materia.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var _i = 0; _i < _listaOrd.length; _i++)
                  _filaMateriaMixta(_listaOrd[_i], _i, temporada),
                if (faltan > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '➜ Falta(n) $faltan materia(s) por asignar en este bloque '
                      '(esperadas $esperadas para $temporada).',
                      style: TextStyle(
                          fontSize: 12,
                          color: cessumRed,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaMateriaMixta(Map<String, dynamic> a, int indice, String temporada) {
    final materia = (a['materia'] ?? '').toString();
    final con = _tieneMaestro(a);
    final docente = (a['docente'] ?? '').toString().trim();
    final estado = (a['invitacionEstado'] ?? '').toString().trim();
    final ini = _fechaIso((a['inicio'] ?? '').toString());
    final fin = _fechaIso((a['termino'] ?? '').toString());
    // En Verano las materias van encadenadas por semana: etiqueta Semana N
    // según su orden cronológico. En otras temporadas no se numera.
    final etiquetaSemana = temporada == 'Verano' ? 'Semana ${indice + 1}' : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            con ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: con ? const Color(0xFF1E8E3E) : cessumFaint(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (etiquetaSemana.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6A4FB0).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(etiquetaSemana,
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6A4FB0))),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(materia,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                Text(
                  con
                      ? '$docente${estado.isNotEmpty ? " · $estado" : ""}'
                      : 'Sin maestro',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: con ? cessumInk(context) : cessumRed,
                  ),
                ),
                Text('${_fechaCorta(ini)} → ${_fechaCorta(fin)}',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabSinMaestro() {
    final activas = <Map<String, dynamic>>[];
    final terminadas = <Map<String, dynamic>>[];
    for (final gg in _sinMaestro) {
      if (_genTerminada(gg)) {
        terminadas.add(gg);
      } else {
        activas.add(gg);
      }
    }
    final visibles = _mostrarTerminadas
        ? <Map<String, dynamic>>[...activas, ...terminadas]
        : activas;
    if (visibles.isEmpty && terminadas.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Todos los grupos con alumnos tienen al menos un maestro asignado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumMuted(context), height: 1.4),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: visibles.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  '${activas.length} grupo(s) activo(s) con alumnos todavía sin maestro.',
                  style: TextStyle(fontSize: 13, color: cessumMuted(context)),
                ),
              ),
              if (terminadas.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ocultas ${terminadas.length} de generaciones ya terminadas.',
                          style: TextStyle(
                              fontSize: 12.5, color: cessumMuted(context)),
                        ),
                      ),
                      Switch(
                        value: _mostrarTerminadas,
                        activeThumbColor: cessumRed,
                        onChanged: (v) =>
                            setState(() => _mostrarTerminadas = v),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }
        final g = visibles[i - 1];
        final invitado = g['invitado'] == true;
        final faltan = (g['faltan'] is num)
            ? (g['faltan'] as num).toInt()
            : (invitado ? 0 : 1);
        final docInv = (g['docenteInvitado'] ?? '').toString();
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: invitado ? const Color(0xFFF2F2F2) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: invitado ? Colors.grey.shade400 : cessumGold,
                width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((g['programa'] ?? '').toString(),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: cessumInk(context))),
              if (_genTerminada(g))
                Container(
                  margin: const EdgeInsets.only(top: 3, bottom: 1),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Generación ya terminada',
                      style: TextStyle(
                          fontSize: 11,
                          color: cessumMuted(context),
                          fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 4),
              _linea(Icons.groups_outlined,
                  'Gen. ${g['generacion']}  •  ${g['grupo']}'),
              _linea(Icons.people_outline, '${g['alumnos']} alumno(s)'),
              const SizedBox(height: 6),
              InkWell(
                onTap: () => _toggleAlumnos(g),
                child: Row(
                  children: [
                    Icon(
                        _rosterAbierto.contains(_keyGrupo(g))
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: cessumRed),
                    const SizedBox(width: 4),
                    Text(
                        _rosterAbierto.contains(_keyGrupo(g))
                            ? 'Ocultar alumnos'
                            : 'Ver alumnos',
                        style: const TextStyle(
                            color: cessumRed,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              ),
              if (_rosterAbierto.contains(_keyGrupo(g)))
                _rosterCargando.contains(_keyGrupo(g))
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: Center(
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cessumRed))))
                    : Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: (_rosterCache[_keyGrupo(g)] ?? []).isEmpty
                              ? [
                                  Text('Sin alumnos en este grupo.',
                                      style: TextStyle(
                                          color: cessumMuted(context),
                                          fontSize: 12))
                                ]
                              : (_rosterCache[_keyGrupo(g)] ?? [])
                                  .map((a) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 2),
                                        child: Text(
                                            '•  ${a['nombre'] ?? ''}  ·  ${a['matricula'] ?? ''}',
                                            style: const TextStyle(
                                                fontSize: 12.5)),
                                      ))
                                  .toList(),
                        ),
                      ),
              if (invitado) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF6E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cessumGold.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top,
                          size: 16, color: Color(0xFFA56B16)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          docInv.isNotEmpty
                              ? 'Invitación enviada a $docInv (esperando respuesta)'
                              : 'Invitación enviada (esperando respuesta)',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFFA56B16),
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed,
                        side: const BorderSide(color: cessumRed),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () => _retirarInvitacion(g),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Retirar invitación'),
                  ),
                ),
              ],
              if (faltan > 0) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: () => _abrirForm(
                      prog: (g['programa'] ?? '').toString(),
                      gen: (g['generacion'] ?? '').toString(),
                      grupo: (g['grupo'] ?? '').toString(),
                    ),
                    icon: const Icon(Icons.event_available, size: 18),
                    label: const Text('Programar maestro para este grupo'),
                  ),
                ),
                // (23-sep) Todas las materias que le faltan, de una vez.
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed,
                        padding: const EdgeInsets.symmetric(vertical: 11)),
                    onPressed: () async {
                      final cambio = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AgendaPlanPeriodoScreen(
                            programa: (g['programa'] ?? '').toString(),
                            generacion: (g['generacion'] ?? '').toString(),
                            grupo: (g['grupo'] ?? '').toString(),
                          ),
                        ),
                      );
                      if (cambio == true) await _cargarTodo();
                    },
                    icon: const Icon(Icons.view_timeline_outlined, size: 18),
                    label: const Text('Planear el periodo completo'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Vigencia de la materia (temporalidad) ──────────────────────────
  // Convierte "dd/mm/aaaa", "dd-mm-aaaa" o "aaaa-mm-dd" a DateTime (solo fecha).
  DateTime? _fechaVig(String s) {
    final t = s.trim();
    if (t.length < 8) return null;
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (iso != null) {
      final y = int.tryParse(iso.group(1)!) ?? 0;
      final m = int.tryParse(iso.group(2)!) ?? 0;
      final d = int.tryParse(iso.group(3)!) ?? 0;
      if (y > 0 && m > 0 && d > 0) return DateTime(y, m, d);
    }
    final dmy = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})').firstMatch(t);
    if (dmy != null) {
      final d = int.tryParse(dmy.group(1)!) ?? 0;
      final m = int.tryParse(dmy.group(2)!) ?? 0;
      final y = int.tryParse(dmy.group(3)!) ?? 0;
      if (y > 0 && m > 0 && d > 0) return DateTime(y, m, d);
    }
    return null;
  }

  // Etiqueta + color del estatus de vigencia frente a la fecha de hoy.
  ({String label, Color color, IconData icon}) _estadoVigencia(
      Map<String, dynamic> a) {
    final ini = _fechaVig((a['inicio'] ?? '').toString());
    final fin = _fechaVig((a['termino'] ?? '').toString());
    final hoy = DateTime.now();
    final hoyD = DateTime(hoy.year, hoy.month, hoy.day);
    if (ini == null && fin == null) {
      return (
        label: 'Sin fechas',
        color: const Color(0xFF9E9E9E),
        icon: Icons.help_outline
      );
    }
    if (fin != null && fin.isBefore(hoyD)) {
      return (
        label: 'Finalizada',
        color: const Color(0xFF9E9E9E),
        icon: Icons.history
      );
    }
    if (ini != null && ini.isAfter(hoyD)) {
      return (
        label: 'Aún no inicia',
        color: cessumGold,
        icon: Icons.schedule_send
      );
    }
    return (
      label: 'Vigente',
      color: const Color(0xFF1E8E3E),
      icon: Icons.play_circle_outline
    );
  }

  // Línea de temporalidad (inicio → término) con la etiqueta de estatus.
  Widget _lineaVigencia(Map<String, dynamic> a) {
    final ini = (a['inicio'] ?? '').toString().trim();
    final fin = (a['termino'] ?? '').toString().trim();
    final texto = (ini.isEmpty && fin.isEmpty)
        ? 'Sin temporalidad definida'
        : 'Vigencia: ${ini.isEmpty ? '—' : ini}  →  ${fin.isEmpty ? '—' : fin}';
    final est = _estadoVigencia(a);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_outlined, size: 16, color: Colors.black38),
          const SizedBox(width: 8),
          Expanded(
              child: Text(texto,
                  style: TextStyle(
                      fontSize: 13, color: cessumMuted(context), height: 1.3))),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: est.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(est.icon, size: 13, color: est.color),
              const SizedBox(width: 4),
              Text(est.label,
                  style: TextStyle(
                      fontSize: 11,
                      color: est.color,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _linea(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cessumFaint(context)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(texto,
                  style: TextStyle(
                      fontSize: 13, color: cessumMuted(context), height: 1.3))),
        ],
      ),
    );
  }
}

// ===================== FORMULARIO DE ASIGNACIÓN =====================

const String _kOtro = '__otro__';

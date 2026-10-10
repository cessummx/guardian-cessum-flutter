import 'dart:convert';
import 'decisiones_screen.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'huerfanos_screen.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'csv_export.dart';
import 'cambiar_programa_screen.dart';

/// Panel de administrador: detecta inconsistencias en los datos
/// (matrículas duplicadas, claves faltantes, generaciones mal escritas,
/// alumnos en grupos inexistentes, calificaciones fuera de rango, etc.).
class SaludDatosScreen extends StatefulWidget {
  const SaludDatosScreen({super.key});

  @override
  State<SaludDatosScreen> createState() => _SaludDatosScreenState();
}

class _SaludDatosScreenState extends State<SaludDatosScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _r = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Map<String, dynamic>? _respaldo;
  List<Map<String, dynamic>> _desc = [];
  String? _alineandoMat;
  String? _bajaMat;
  bool _alineandoTodos = false;

  bool _esDiferencia(String t) =>
      t == 'programa_difiere' ||
      t == 'generacion_difiere' ||
      t == 'grupo_difiere';

  bool get _hayDiferencias =>
      _desc.any((p) => _esDiferencia('${p['tipo'] ?? ''}'));

  void _avisoDesc(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
    ));
  }

  Future<void> _usarGrupos(String mat) async {
    if (mat.isEmpty) return;
    setState(() => _alineandoMat = mat);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'descuadre_alinear',
                'actor': actor,
                'matricula': mat,
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _avisoDesc('Padrón alineado a grupos.');
        await _cargarDescuadres();
      } else {
        _avisoDesc('${data['error'] ?? 'No se pudo alinear.'}', error: true);
      }
    } catch (_) {
      _avisoDesc('No me pude conectar. Intenta de nuevo.', error: true);
    } finally {
      if (mounted) setState(() => _alineandoMat = null);
    }
  }

  Future<void> _darBaja(String mat, String nombre) async {
    if (mat.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dar de baja'),
        content: Text(
            '¿Dar de baja a ${nombre.isEmpty ? mat : nombre}?\n\n'
            'Quedará marcado como Baja (estatus y grupo) y dejará de aparecer '
            'como alumno activo. Se puede revertir editando su registro.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dar de baja'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _bajaMat = mat);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'alumno_baja',
                'actor': actor,
                'matricula': mat,
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _avisoDesc('Alumno dado de baja.');
        await _cargarDescuadres();
      } else {
        _avisoDesc('${data['error'] ?? 'No se pudo dar de baja.'}',
            error: true);
      }
    } catch (_) {
      _avisoDesc('No me pude conectar. Intenta de nuevo.', error: true);
    } finally {
      if (mounted) setState(() => _bajaMat = null);
    }
  }

  Future<void> _alinearTodos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alinear todos con grupos'),
        content: const Text(
          'Esto pondrá el programa, generación y grupo del PADRÓN iguales a la '
          'inscripción real (grupos) para TODOS los que difieren.\n\n'
          'Úsalo solo si confías en que los grupos son la inscripción correcta. '
          'Los casos dudosos mejor arréglalos uno por uno. ¿Continuar?',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, alinear todos'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _alineandoTodos = true);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'descuadres_alinear_todos',
                'actor': actor,
              }))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _avisoDesc('Listo: ${data['alineados'] ?? 0} alineados, '
            '${data['saltados'] ?? 0} sin grupo.');
        await _cargarDescuadres();
      } else {
        _avisoDesc('${data['error'] ?? 'No se pudo alinear.'}', error: true);
      }
    } catch (_) {
      _avisoDesc('No me pude conectar. Intenta de nuevo.', error: true);
    } finally {
      if (mounted) setState(() => _alineandoTodos = false);
    }
  }

  Future<void> _cargarDescuadres() async {
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'descuadres',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      final lista = (data['problemas'] is List) ? data['problemas'] as List : [];
      setState(() => _desc =
          lista.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (_) {}
  }

  Future<void> _cargarRespaldo() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'salud_respaldo_info'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _respaldo = data['hay'] == true ? data : null);
    } catch (_) {}
  }

  Future<void> _restaurar() async {
    final info = _respaldo;
    if (info == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deshacer última limpieza'),
        content: Text(
          'Se restaurarán ${info['filas']} fila(s) de Calificaciones tal como '
          'estaban antes de la última limpieza '
          '(${info['accion']} · ${info['fecha']}).\n\n'
          'Esto reemplaza el estado actual de la hoja. ¿Continuar?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumGold),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'salud_restaurar',
                'actor': actor,
                'confirmar': true,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text('Restaurado: ${data['filas'] ?? 0} fila(s).'),
        ));
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'No se pudo');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'salud_datos_json',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _r = data;
        _cargando = false;
      });
      _cargarRespaldo();
      _cargarDescuadres();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar ($e)';
      });
    }
  }

  int _n(dynamic v) {
    if (v is int) return v;
    if (v is List) return v.length;
    if (v is num) return v.toInt();
    return 0;
  }

  List<String> _lista(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }

  void _exportar() {
    final filas = <List<Object?>>[];
    void agregar(String cat, List<String> items) {
      if (items.isEmpty) {
        filas.add([cat, '(sin problemas)']);
      } else {
        for (final it in items) {
          filas.add([cat, it]);
        }
      }
    }

    agregar('Matrículas duplicadas (padrón)', _lista(_r['matriculasDup']));
    agregar('Alumnos en grupos inexistentes', _lista(_r['gruposInexistentes']));
    agregar('Calificaciones fuera de rango', _lista(_r['fueraRango']));
    agregar('Registros duplicados', _lista(_r['duplicados']));
    agregar('Alumnos sin correo (sí están en el padrón)', _lista(_r['sinCorreo']));
    agregar('Matrículas que no existen como alumno',
        _lista(_r['sinCorreoNiPadron']));
    agregar('Calificaciones sin correo en la fila',
        _lista(_r['sinCorreoEnFila']));
    agregar('Alumnos sin modalidad', _lista(_r['sinModalidad']));
    agregar('Programas no reconocidos (Calificaciones)',
        _lista(_r['programasNoReconocidos']));
    agregar('Programas no reconocidos (padrón)',
        _lista(_r['padronProgramaInvalido']));
    filas.add(['Generaciones mal escritas', '${_n(_r['generacionesFecha'])}']);
    filas.add(['Registros sin clave de materia', '${_n(_r['sinClave'])}']);
    descargarCsv(
        'salud_datos.csv', construirCsv(['Categoría', 'Detalle'], filas));
  }

  Future<void> _corregir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar espacios y claves'),
        content: const Text(
          'Se limpiarán espacios de más en nombres, programas y materias; '
          'las claves de materia pasarán a MAYÚSCULAS y los correos a minúsculas. '
          'No cambia calificaciones ni elimina registros. ¿Continuar?',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final solicitante = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'salud_corregir',
              'solicitante': solicitante,
            }),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context); // cierra el indicador
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Listo: ${data['cambios']} corrección(es) aplicada(s).'),
          backgroundColor: const Color(0xFF1E8E3E),
        ));
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'No autorizado');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  Future<void> _aplicarAccion({
    required String tipo,
    required String titulo,
    required String advertencia,
  }) async {
    String impactoTexto(Map<String, dynamic> data) {
      final partes = <String>[];
      final afectados = int.tryParse('${data['afectadosPreview'] ?? 0}') ?? 0;
      partes.add('Casos que cambiarían: $afectados.');
      final alumnos = int.tryParse('${data['alumnosAfectados'] ?? 0}') ?? 0;
      if (alumnos > 0) partes.add('Alumnos afectados: $alumnos.');
      final identicas = int.tryParse('${data['copiasIdenticas'] ?? 0}') ?? 0;
      final distintas = int.tryParse('${data['calificacionesDistintas'] ?? 0}') ?? 0;
      if (identicas > 0 || distintas > 0) {
        partes.add('Copias idénticas: $identicas · calificaciones distintas: $distintas.');
      }
      final debajo = int.tryParse('${data['porDebajo'] ?? 0}') ?? 0;
      final arriba = int.tryParse('${data['porArriba'] ?? 0}') ?? 0;
      if (debajo > 0 || arriba > 0) {
        partes.add('Por debajo de 6: $debajo · por arriba de 10: $arriba.');
      }
      final nota = (data['advertencia'] ?? data['nota'] ?? '').toString().trim();
      if (nota.isNotEmpty) partes.add(nota);
      return partes.join('\n\n');
    }

    Future<Map<String, dynamic>> ejecutar(String actor, bool aplicar) async {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'salud_accion',
                'tipo': tipo,
                'actor': actor,
                'confirmar': true,
                'aplicar': aplicar ? '1' : '0',
              }))
          .timeout(const Duration(seconds: 120));
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }

    final revisar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(
          '$advertencia\n\nPrimero haré una prueba en seco. En esta etapa no se escribirá ni se borrará nada.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revisar impacto'),
          ),
        ],
      ),
    );
    if (revisar != true) return;

    final actor = await SessionStore.realEmail() ?? '';
    Map<String, dynamic> previa;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      previa = await ejecutar(actor, false);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo hacer la prueba en seco: $e'),
          backgroundColor: cessumRed));
      return;
    }

    if (previa['ok'] != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: ${previa['error'] ?? 'No autorizado'}'),
          backgroundColor: cessumRed));
      return;
    }

    final impacto = impactoTexto(previa);
    final bloqueada = previa['aplicacionBloqueada'] == true ||
        previa['bloqueada'] == true;
    final afectados =
        int.tryParse('${previa['afectadosPreview'] ?? 0}') ?? 0;

    if (bloqueada) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.shield_outlined, color: cessumRed, size: 34),
          title: const Text('Acción bloqueada por seguridad'),
          content: Text(impacto, style: const TextStyle(fontSize: 13.5)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    if (afectados == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('La prueba en seco no encontró cambios que aplicar.'),
        backgroundColor: Color(0xFF1E8E3E),
      ));
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.fact_check_outlined, color: cessumRed, size: 34),
        title: const Text('Confirmar cambios'),
        content: Text(
          '$impacto\n\nAntes de escribir se creará un respaldo completo y, al terminar, el sistema volverá a comprobar el resultado.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar cambios'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final data = await ejecutar(actor, true);
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] != true || data['aplicado'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: ${data['error'] ?? 'El backend no confirmó que los cambios fueran aplicados.'}'),
            backgroundColor: cessumRed));
        return;
      }
      final n = int.tryParse('${data['cambiosAplicados'] ?? 0}') ?? 0;
      final ver = (data['verificacion'] as Map?)?.cast<String, dynamic>();
      final pendientes = int.tryParse('${ver?['pendientes'] ?? 0}') ?? 0;
      final msg = pendientes == 0
          ? 'Listo: $n cambio(s) aplicado(s), con respaldo y verificación posterior.'
          : 'Se aplicaron $n cambio(s), pero la verificación aún detecta $pendientes pendiente(s). Revísalos antes de continuar.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor:
            pendientes == 0 ? const Color(0xFF1E8E3E) : const Color(0xFFB7791F),
        content: Text(msg),
      ));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  Future<void> _abrirDecisiones() async {
    final actor = await SessionStore.realEmail() ?? '';
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DecisionesScreen(actor: actor)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Salud de datos'),
        actions: [
          // (ago-27) Entrada al Centro de decisiones. Esta pantalla dice qué
          // está mal; aquella dice qué hacer y qué pasa si no se hace.
          IconButton(
              onPressed: _cargando ? null : _abrirDecisiones,
              tooltip: 'Centro de decisiones',
              icon: const Icon(Icons.rule)),
          IconButton(
              onPressed: _cargando ? null : _abrirLocalizador,
              tooltip: 'Localizar alumno',
              icon: const Icon(Icons.person_search)),
          IconButton(
              onPressed: _cargando || _r.isEmpty ? null : _exportar,
              tooltip: 'Exportar CSV',
              icon: const Icon(Icons.download)),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.fact_check, color: cessumGold),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Se revisaron ${_n(_r['total'])} registros de calificaciones '
                              'y el padrón de alumnos.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed, width: 1.3),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _corregir,
                        icon: const Icon(Icons.cleaning_services, size: 18),
                        label: const Text('Limpiar espacios y claves'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_respaldo != null) _bannerRespaldo(),
                    _tarjetaDescuadres(),
                    _tarjeta('Matrículas duplicadas (padrón)',
                        'Misma matrícula con nombres distintos.',
                        _lista(_r['matriculasDup'])),
                    // (ago-22) Primero CORREGIR, después borrar. Un grupo que
                    // no existe casi siempre es la etiqueta mal escrita, no una
                    // calificación de más: el botón de arriba la repara con el
                    // grupo real del alumno y no pierde nada.
                    _tarjeta(
                        'Alumnos en grupos inexistentes',
                        'Aparecen en un grupo que no está en las asignaciones. '
                        'Casi siempre es la etiqueta mal capturada, no una '
                        'calificación sobrante.',
                        // (ago-24) Con los alumnos a la vista. El reporte decía
                        // qué grupo falla pero no de quién era la fila, así que
                        // el hallazgo no se podía atender: nadie sabía a quién
                        // corregirle. Ahora cada caso lista sus matrículas.
                        _gruposInexistentesConAlumnos(),
                        accionTipo: 'homologar_grupo_calif',
                        accionLabel: 'Corregir al grupo real del alumno',
                        advertencia:
                            'Se cambiará la etiqueta del grupo en esas filas por el grupo en el que el alumno SÍ está inscrito según la base de Grupos, y solo cuando ese grupo exista en las asignaciones. No se borra ninguna calificación y no se adivina entre dos opciones: lo que no se pueda resolver se reporta y se queda igual. ¿Aplicar?'),
                    _tarjeta(
                        'Grupos inexistentes que no se pudieron corregir',
                        'Último recurso: borra las filas. Úsalo solo después de '
                        'intentar corregirlas y de revisar la prueba en seco.',
                        const [],
                        accionTipo: 'grupos_inexistentes',
                        accionLabel: 'Eliminar filas de grupos inexistentes',
                        advertencia:
                            'Esta es una acción destructiva. Primero se hará una prueba en seco con el número de filas y alumnos afectados; solo después podrás confirmar. Antes de borrar se creará un respaldo completo.'),
                    _tarjeta(
                        'Calificaciones fuera de rango',
                        'Valores menores a 6 o mayores a 10.',
                        _lista(_r['fueraRango']),
                        accionTipo: 'fuera_rango',
                        accionLabel: 'Revisar casos fuera de rango',
                        advertencia:
                            'Estos casos requieren revisión. Salud de datos ya no elimina la fila académica completa por una calificación fuera de escala. La prueba mostrará cuántos casos existen y bloqueará cualquier borrado automático.'),
                    _tarjeta(
                        'Registros duplicados',
                        'Misma matrícula y materia repetidas.',
                        _lista(_r['duplicados']),
                        accionTipo: 'dedup',
                        accionLabel: 'Eliminar duplicados',
                        advertencia:
                            'Primero se hará una prueba en seco. Revisa especialmente las parejas con calificaciones distintas, porque pueden ser recursamientos legítimos. Solo después podrás confirmar y se creará un respaldo completo.'),
                    _tarjetaConflictos(),
                    // (ago-22) Antes esto era UN solo cajón con 287 alumnos y
                    // el texto decía que no podían recibir su boleta. Falso
                    // para casi todos: su correo sí está en el padrón, solo
                    // faltaba en la fila de calificación. Ahora son dos
                    // tarjetas, y la cosmética se arregla sola.
                    // (ago-24) Antes esto mezclaba dos problemas distintos:
                    // alumnos reales a los que falta capturarles el correo, y
                    // matrículas que ni siquiera existen como alumno. Lo
                    // segundo no se arregla escribiendo un correo.
                    _tarjeta(
                        'Alumnos sin correo (sí están en el padrón)',
                        'Existen como alumnos pero nadie les capturó correo. No '
                        'reciben boleta ni pueden entrar a la app.',
                        _lista(_r['sinCorreo'])),
                    _tarjeta(
                        'Matrículas que no existen como alumno',
                        'Tienen calificaciones pero no aparecen en el padrón. No '
                        'es un correo lo que falta: hay que explicar de dónde '
                        'salió esa fila antes de tocarla.',
                        _lista(_r['sinCorreoNiPadron'])),
                    // (ago-24) MATRÍCULAS DUPLICADAS, YA CLASIFICADAS.
                    // Antes marcaba 14 como error y la mayoría eran legítimas
                    // —maestría y doctorado del mismo alumno—. Un chequeo que
                    // llora lobo enseña a ignorarlo, y entonces el caso grave
                    // pasa desapercibido.
                    _tarjetaDuplicadas(),
                    // (ago-24) NOMBRES MAL CAPTURADOS. Es el dato que se
                    // imprime en constancias y actas: un documento oficial que
                    // dice "Paulinalbarra Martínez Seis" no se puede entregar.
                    _tarjetaNombres(),
                    // (ago-24) Esa tarjeta solo LISTA. Aquí está el lugar para
                    // decidir: cada caso necesita una salida distinta y ninguna
                    // se puede automatizar sin cometer un error caro.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cessumRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const HuerfanosScreen()),
                          ),
                          icon: const Icon(Icons.rule, size: 18),
                          label: const Text(
                              'Resolver matrículas huérfanas una por una',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    _tarjeta(
                        'Calificaciones sin correo en la fila',
                        'El alumno SÍ tiene correo en el padrón; solo falta en '
                        'la fila. Se rellena sin tocar ningún dato existente.',
                        _lista(_r['sinCorreoEnFila']),
                        accionTipo: 'rellenar_correos',
                        accionLabel: 'Rellenar correos desde el padrón',
                        advertencia:
                            'Se completará la columna Correo de las filas que la tengan VACÍA, con el correo del padrón. No se pisa ningún correo ya capturado. ¿Aplicar?'),
                    _tarjeta('Alumnos sin modalidad (padrón)',
                        'Conviene registrar Virtual o Mixta en alumnos.json.',
                        _lista(_r['sinModalidad'])),
                    _tarjetaProgramas(),
                    _tarjetaCambioPrograma(),
                    _contadorSimple('Generaciones mal escritas (como fecha)',
                        _n(_r['generacionesFecha']),
                        accionTipo: 'generaciones',
                        accionLabel: 'Normalizar generaciones',
                        advertencia:
                            'Se convertirán en la base las generaciones guardadas como fecha (ej. "Wed Mar 25 2026…") a un texto legible. ¿Aplicar?'),
                    _contadorSimple(
                        'Registros sin clave de materia', _n(_r['sinClave']),
                        accionTipo: 'rellenar_claves',
                        accionLabel: 'Rellenar claves desde filas hermanas',
                        advertencia:
                            'Se completará la clave de materia de las filas que la tengan VACÍA, copiándola de otra fila del MISMO programa y la MISMA materia que sí la tenga. No se inventa ninguna clave: si nadie la tiene, esa fila se queda como está. ¿Aplicar?'),
                  ],
                ),
    );
  }

  Future<void> _abrirLocalizador() async {
    final ctrl = TextEditingController();
    Map<String, dynamic>? res;
    bool buscando = false;
    bool vinculando = false;
    String? err;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          Future<void> buscar() async {
            final q = ctrl.text.trim();
            if (q.length < 3) {
              setSt(() => err = 'Escribe al menos 3 letras o la matrícula.');
              return;
            }
            setSt(() {
              buscando = true;
              err = null;
              res = null;
            });
            try {
              final actor = await SessionStore.realEmail() ?? '';
              final resp = await http
                  .post(Uri.parse(guardianUrl),
                      headers: {'Content-Type': 'text/plain;charset=utf-8'},
                      body: jsonEncode({
                        'accion': 'localizar_alumno',
                        'actor': actor,
                        'q': q,
                      }))
                  .timeout(const Duration(seconds: 60));
              final data = jsonDecode(resp.body) as Map<String, dynamic>;
              setSt(() {
                buscando = false;
                if (data['ok'] == true) {
                  res = data;
                } else {
                  err = data['error']?.toString() ?? 'No se pudo';
                }
              });
            } catch (e) {
              setSt(() {
                buscando = false;
                err = 'Error: $e';
              });
            }
          }

          Future<void> vincular() async {
            final cont = (res?['continuidad'] as Map?) ?? {};
            final ident = cont['identidadSugerida']?.toString() ?? '';
            final mats = (cont['matriculas'] as List?) ?? [];
            final otras = mats
                .map((e) => (e as Map)['matricula'].toString())
                .where((m) => m != ident)
                .toList();
            if (ident.isEmpty || otras.isEmpty) return;
            setSt(() => vinculando = true);
            try {
              final actor = await SessionStore.realEmail() ?? '';
              for (final m in otras) {
                await http
                    .post(Uri.parse(guardianUrl),
                        headers: {
                          'Content-Type': 'text/plain;charset=utf-8'
                        },
                        body: jsonEncode({
                          'accion': 'vincular_matriculas',
                          'actor': actor,
                          'identidad': ident,
                          'vinculada': m,
                          'nombre': ctrl.text.trim(),
                        }))
                    .timeout(const Duration(seconds: 60));
              }
              setSt(() => vinculando = false);
              await buscar();
            } catch (e) {
              setSt(() {
                vinculando = false;
                err = 'Error al vincular: $e';
              });
            }
          }

          final vivo = (res?['vivo'] as Map?) ?? {};
          final resp = (res?['respaldo'] as Map?) ?? {};
          final padron = (res?['padron'] as List?) ?? [];
          final cont = (res?['continuidad'] as Map?) ?? {};
          final mats = (cont['matriculas'] as List?) ?? [];

          return AlertDialog(
            title: const Text('Localizar alumno'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      onSubmitted: (_) => buscar(),
                      decoration: const InputDecoration(
                        hintText: 'Nombre o matrícula',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        style:
                            FilledButton.styleFrom(backgroundColor: cessumRed),
                        onPressed: buscando ? null : buscar,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Buscar'),
                      ),
                    ),
                    if (buscando)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                            child: CircularProgressIndicator(color: cessumRed)),
                      ),
                    if (err != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(err!,
                            style: const TextStyle(color: cessumRed)),
                      ),
                    if (res != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cessumGold.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cessumGold),
                        ),
                        child: Text(res!['diagnostico']?.toString() ?? '',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 12),
                      _locSeccion('En el padrón',
                          padron.map((p) {
                            final m = p as Map;
                            return '${m['matricula']} · ${m['nombre']}'
                                '${(m['modalidad'] ?? '').toString().isNotEmpty ? ' · ${m['modalidad']}' : ''}';
                          }).toList(),
                          'No está en el padrón.'),
                      _locSeccion(
                          'En Calificaciones (${vivo['total'] ?? 0})',
                          ((vivo['grupos'] as List?) ?? [])
                              .map((e) => e.toString())
                              .toList(),
                          'Sin filas en Calificaciones.'),
                      _locSeccion(
                          'En el último respaldo (${resp['total'] ?? 0})',
                          ((resp['grupos'] as List?) ?? [])
                              .map((e) => e.toString())
                              .toList(),
                          'Sin filas en el respaldo.'),
                      if (mats.length > 1) ...[
                        const Divider(height: 18),
                        const Text('Matrículas de esta persona',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 4),
                        ...mats.map((e) {
                          final m = e as Map;
                          final esId = m['esIdentidad'] == true;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                    esId
                                        ? Icons.star
                                        : Icons.subdirectory_arrow_right,
                                    size: 15,
                                    color: esId ? cessumGold : Colors.grey),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${m['matricula']}'
                                    '${(m['programa'] ?? '').toString().isNotEmpty ? ' · ${m['programa']}' : ''}'
                                    '${(m['generacion'] ?? '').toString().isNotEmpty ? ' · ${m['generacion']}' : ''}'
                                    '${esId ? '  (identidad — más antigua)' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (cont['sugerirVincular'] == true) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cessumRed,
                                side: const BorderSide(color: cessumRed),
                              ),
                              onPressed: vinculando ? null : vincular,
                              icon: vinculando
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: cessumRed))
                                  : const Icon(Icons.link, size: 18),
                              label: Text(vinculando
                                  ? 'Vinculando…'
                                  : 'Vincular como misma persona '
                                      '(identidad: ${cont['identidadSugerida']})'),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Une estas matrículas como una sola persona. '
                              'Las calificaciones y pagos de cada grado siguen '
                              'separados.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              if (res != null &&
                  (vivo['total'] ?? 0) == 0 &&
                  (resp['total'] ?? 0) > 0)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cessumGold),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _restaurar();
                  },
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Deshacer limpieza'),
                ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  Widget _locSeccion(String titulo, List<String> items, String vacio) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 2),
          if (items.isEmpty)
            Text(vacio,
                style: const TextStyle(fontSize: 12, color: Colors.grey))
          else
            ...items.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('• $e', style: const TextStyle(fontSize: 12)),
                )),
        ],
      ),
    );
  }

  Widget _tarjetaDescuadres() {
    final items = _desc;
    final vacio = items.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: vacio
                ? Colors.black12
                : cessumRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  vacio
                      ? Icons.verified_outlined
                      : Icons.report_problem_outlined,
                  color: vacio ? const Color(0xFF1E8E3E) : cessumRed,
                  size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Descuadres padrón ↔ grupos',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
              ),
              if (!vacio)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: cessumRed,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${items.length}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
              'Alumnos cuyo programa, generación o grupo no coincide entre el '
              'padrón y la base de grupos. Es lo que hace que "no se reflejen" '
              'los cambios.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          if (!vacio && _hayDiferencias)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _alineandoTodos ? null : _alinearTodos,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumGold,
                    side: const BorderSide(color: cessumGold),
                  ),
                  icon: _alineandoTodos
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumGold))
                      : const Icon(Icons.sync_alt, size: 18),
                  label: Text(_alineandoTodos
                      ? 'Alineando…'
                      : 'Alinear todos con grupos'),
                ),
              ),
            ),
          if (vacio)
            const Text('Todo cuadra. Sin descuadres.',
                style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1E8E3E),
                    fontWeight: FontWeight.w600))
          else
            ...items.map(_filaDescuadre),
        ],
      ),
    );
  }

  Widget _filaDescuadre(Map<String, dynamic> p) {
    final tipo = '${p['tipo'] ?? ''}';
    const etiquetas = {
      'solo_padron': 'Sin grupo',
      'solo_grupos': 'Falta en padrón',
      'programa_difiere': 'Programa',
      'generacion_difiere': 'Generación',
      'grupo_difiere': 'Grupo',
    };
    final etiqueta = etiquetas[tipo] ?? tipo;
    final padron = '${p['padron'] ?? ''}';
    final grupos = '${p['grupos'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumRed.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    '${p['nombre'] ?? ''}  ·  ${p['matricula'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(etiqueta,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF7A5210))),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${p['detalle'] ?? ''}',
              style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          if (padron.isNotEmpty || grupos.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
                'Padrón: ${padron.isEmpty ? '—' : padron}\n'
                'Grupos: ${grupos.isEmpty ? '—' : grupos}',
                style:
                    const TextStyle(fontSize: 11.5, color: Colors.black87)),
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_esDiferencia(tipo) && grupos.isNotEmpty) ...[
                _alineandoMat == '${p['matricula'] ?? ''}'
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cessumGold)))
                    : ElevatedButton.icon(
                        onPressed: () =>
                            _usarGrupos('${p['matricula'] ?? ''}'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cessumGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                        ),
                        icon: const Icon(Icons.sync_alt, size: 16),
                        label: const Text('Usar grupos'),
                      ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CambiarProgramaScreen(
                          matriculaInicial: '${p['matricula'] ?? ''}'),
                    ),
                  );
                  _cargar();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                icon: const Icon(Icons.build_outlined, size: 16),
                label: const Text('Corregir'),
              ),
              _bajaMat == '${p['matricula'] ?? ''}'
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumRed)))
                  : ElevatedButton.icon(
                      onPressed: () => _darBaja(
                          '${p['matricula'] ?? ''}', '${p['nombre'] ?? ''}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                      ),
                      icon: const Icon(Icons.person_off, size: 16),
                      label: const Text('Baja'),
                    ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerRespaldo() {
    final info = _respaldo!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold),
      ),
      child: Row(
        children: [
          const Icon(Icons.restore, color: cessumGold),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Puedes deshacer la última limpieza',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    '${info['accion']} · ${info['fecha']} · '
                    '${info['filas']} fila(s) respaldadas',
                    style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: cessumGold),
            onPressed: _restaurar,
            child: const Text('Deshacer'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolverConflictosLote(String modo) async {
    final etq = modo == 'alta'
        ? 'la más alta'
        : (modo == 'reciente'
            ? 'la capturada más recientemente'
            : 'la validada');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolver todos los conflictos'),
        content: Text(
          'En cada conflicto se conservará $etq y se eliminarán las demás. '
          'Se respalda antes (puedes deshacer). ¿Continuar?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Resolver todos'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'resolver_conflictos_lote',
                'actor': actor,
                'modo': modo,
                'confirmar': true,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text(
              '${data['resueltos'] ?? 0} conflicto(s) resuelto(s) · '
              '${data['eliminadas'] ?? 0} fila(s) eliminada(s).'),
        ));
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'No se pudo');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  Future<void> _resolverConflicto(
      String matricula, String materia, String cal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conservar esta calificación'),
        content: Text(
          'Para $matricula en "$materia" se conservará la calificación $cal '
          'y se eliminarán las demás de esa materia. Se respalda antes '
          '(puedes deshacer). ¿Continuar?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Conservar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'resolver_conflicto',
                'actor': actor,
                'matricula': matricula,
                'materia': materia,
                'calificacion': cal,
                'confirmar': true,
              }))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text(
              'Conservada $cal · ${data['eliminadas'] ?? 0} fila(s) eliminada(s).'),
        ));
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'No se pudo');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  Widget _tarjetaConflictos() {
    final data = (_r['conflictosData'] as List?) ?? [];
    final n = data.length;
    final ok = n == 0;
    final color = ok ? const Color(0xFF1E8E3E) : cessumRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(
              ok ? Icons.check_circle : Icons.warning_amber_rounded,
              color: color),
          title: const Text('Calificaciones en conflicto (notas distintas)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'Misma materia con notas diferentes. Elige cuál conservar.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$n',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: color, fontSize: 13)),
          ),
          children: ok
              ? const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sin conflictos.',
                        style: TextStyle(
                            fontSize: 12.5, color: Color(0xFF1E8E3E))),
                  )
                ]
              : [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cessumRed,
                              side: const BorderSide(color: cessumRed),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () =>
                                _resolverConflictosLote('reciente'),
                            child: const Text('Resolver todos: más reciente',
                                style: TextStyle(fontSize: 11.5)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cessumRed,
                              side: const BorderSide(color: cessumRed),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () =>
                                _resolverConflictosLote('validada'),
                            child: const Text('Resolver todos: validada',
                                style: TextStyle(fontSize: 11.5)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cessumRed,
                              side: const BorderSide(color: cessumRed),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: () => _resolverConflictosLote('alta'),
                            child: const Text('Resolver todos: más alta',
                                style: TextStyle(fontSize: 11.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...data.take(60).map((e) {
                  final c = e as Map;
                  final mat = (c['matricula'] ?? '').toString();
                  final nombre = (c['nombre'] ?? '').toString();
                  final materia = (c['materia'] ?? '').toString();
                  final ops = (c['opciones'] as List?) ?? [];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: cessumRed.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre.isEmpty ? mat : nombre,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5)),
                        Text('$mat · $materia',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade600)),
                        const SizedBox(height: 6),
                        ...ops.map((o) {
                          final op = o as Map;
                          final cal = (op['cal'] ?? '').toString();
                          final est = (op['estatus'] ?? '').toString();
                          final cap = (op['cap'] ?? '').toString();
                          final fecha = (op['fecha'] ?? '').toString();
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$cal'
                                    '${est.isNotEmpty ? ' · $est' : ''}'
                                    '${fecha.isNotEmpty ? ' · capturada el $fecha' : ''}'
                                    '${cap.isNotEmpty ? ' · $cap' : ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: cessumRed,
                                    side: const BorderSide(color: cessumRed),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    minimumSize: const Size(0, 32),
                                  ),
                                  onPressed: () =>
                                      _resolverConflicto(mat, materia, cal),
                                  child: const Text('Conservar',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                }).toList(),
                ],
        ),
      ),
    );
  }

  // ===== Programas no reconocidos: lista con acción de corrección =====
  List<String> _programasOficiales() =>
      ((_r['programasOficiales'] as List?) ?? [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();

  Widget _tarjetaProgramas() {
    final calif = (_r['programasNoReconocidosData'] as List?) ?? [];
    final padron = (_r['padronProgramaInvalidoData'] as List?) ?? [];
    final n = calif.length + padron.length;
    final ok = n == 0;
    final color = ok ? const Color(0xFF1E8E3E) : cessumRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(
              ok ? Icons.check_circle : Icons.rule_folder, color: color),
          title: const Text('Programas no reconocidos',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'No están en cartas.json (mal escritos o inexistentes). '
              'Corrígelos al nombre oficial.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$n',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: color, fontSize: 13)),
          ),
          children: ok
              ? const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Todos los programas coinciden con cartas.json.',
                        style: TextStyle(
                            fontSize: 12.5, color: Color(0xFF1E8E3E))),
                  )
                ]
              : [
                  if (calif.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text('En Calificaciones',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey)),
                      ),
                    ),
                    ...calif.take(40).map((e) {
                      final c = e as Map;
                      final prog = (c['programa'] ?? '').toString();
                      final filas = c['filas'] ?? 0;
                      final ej = (c['ejemplo'] ?? '').toString();
                      return _filaPrograma(
                        titulo: prog,
                        sub: '$filas fila(s)${ej.isNotEmpty ? ' · ej. $ej' : ''}',
                        onCorregir: () => _corregirProgramaCalif(prog),
                      );
                    }),
                  ],
                  if (padron.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 6),
                        child: Text('En el padrón',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey)),
                      ),
                    ),
                    ...padron.take(40).map((e) {
                      final c = e as Map;
                      final mat = (c['matricula'] ?? '').toString();
                      final nombre = (c['nombre'] ?? '').toString();
                      final prog = (c['programa'] ?? '').toString();
                      return _filaPrograma(
                        titulo: '$mat · $nombre',
                        sub: 'Programa actual: $prog',
                        onCorregir: () =>
                            _corregirProgramaPadron(mat, nombre, prog),
                      );
                    }),
                  ],
                ],
        ),
      ),
    );
  }

  // Detección fina: programa del padrón distinto al de calificaciones.
  Widget _tarjetaCambioPrograma() {
    final revisar = (_r['cambioProgramaRevisar'] as List?) ?? [];
    final cont = (_r['cambioProgramaContinuidad'] as List?) ?? [];
    final aut = (_r['cambioProgramaAutorizado'] as List?) ?? [];
    final mez = (_r['cambioProgramaMezcla'] as List?) ?? [];
    final n = revisar.length;
    final ok = n == 0;
    final color = ok ? const Color(0xFF1E8E3E) : cessumGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(
              ok ? Icons.check_circle : Icons.compare_arrows, color: color),
          title: const Text('Programa del padrón vs. calificaciones',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: const Text(
              'Alumnos cuyo programa actual no coincide con el de sus '
              'calificaciones. Separa continuidad de posible inconsistencia.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$n',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: color, fontSize: 13)),
          ),
          children: (revisar.isEmpty && cont.isEmpty && aut.isEmpty && mez.isEmpty)
              ? const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        'El programa del padrón coincide con el de las '
                        'calificaciones en todos los casos.',
                        style: TextStyle(
                            fontSize: 12.5, color: Color(0xFF1E8E3E))),
                  )
                ]
              : [
                  if (revisar.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text('Revisar (posible inconsistencia)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: cessumRed)),
                      ),
                    ),
                    ...revisar.take(40).map((e) {
                      final c = e as Map;
                      final mat = (c['matricula'] ?? '').toString();
                      final nombre = (c['nombre'] ?? '').toString();
                      final prog = (c['programaPadron'] ?? '').toString();
                      final cals =
                          ((c['programasCalif'] as List?) ?? []).join(', ');
                      final nota = (c['nota'] ?? '').toString();
                      return _filaPrograma(
                        titulo: '$mat · $nombre',
                        sub: 'Padrón: $prog  ·  Calif: $cals',
                        nota: nota,
                        onCorregir: () =>
                            _corregirProgramaPadron(mat, nombre, prog),
                      );
                    }),
                  ],
                  // (ago-22) Tercer cajón: el cambio existe Y está aprobado en
                  // la hoja CambioPrograma. Antes caía en rojo junto con los
                  // que nadie autorizó, así que Vicerrectoría revisaba una y
                  // otra vez casos que ella misma había resuelto.
                  if (aut.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 6),
                        child: Text('Cambio de programa autorizado',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E8E3E))),
                      ),
                    ),
                    ...aut.take(40).map((e) {
                      final c = e as Map;
                      final mat = (c['matricula'] ?? '').toString();
                      final nombre = (c['nombre'] ?? '').toString();
                      final prog = (c['programaPadron'] ?? '').toString();
                      final cals =
                          ((c['programasCalif'] as List?) ?? []).join(', ');
                      final nota = (c['nota'] ?? '').toString();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$mat · $nombre — $cals → $prog',
                                style: const TextStyle(
                                    fontSize: 11.5, color: Colors.black87)),
                            if (nota.isNotEmpty)
                              Text(nota,
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF1E8E3E))),
                          ],
                        ),
                      );
                    }),
                  ],
                  // (ago-22) MEZCLA: el programa del padrón SÍ coincide con
                  // alguna de sus calificaciones, pero tiene materias de otro
                  // programa además. No es inconsistencia — es historial — pero
                  // hace que su expediente se vea revuelto y que el plan que se
                  // le pinta pueda no ser el suyo.
                  if (mez.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 6),
                        child: Text(
                            'Con materias de otro programa (formación continua '
                            'o plan anterior)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFB07D12))),
                      ),
                    ),
                    ...mez.take(40).map((e) {
                      final c = e as Map;
                      final mat = (c['matricula'] ?? '').toString();
                      final nombre = (c['nombre'] ?? '').toString();
                      final prog = (c['programaPadron'] ?? '').toString();
                      final otros =
                          ((c['programasCalif'] as List?) ?? []).join(', ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$mat · $nombre',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87)),
                            Text('Padrón: $prog  ·  también tiene de: $otros',
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF8A5A00))),
                            if ((c['filasFuera'] ?? 0) is num &&
                                (c['filasFuera'] as num) > 0)
                              Text(
                                  '${c['filasFuera']} materia(s) fuera de su '
                                  'plan vigente',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.black45)),
                          ],
                        ),
                      );
                    }),
                  ],
                  if (cont.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 6),
                        child: Text('Continuidad (informativo)',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey)),
                      ),
                    ),
                    ...cont.take(40).map((e) {
                      final c = e as Map;
                      final mat = (c['matricula'] ?? '').toString();
                      final nombre = (c['nombre'] ?? '').toString();
                      final prog = (c['programaPadron'] ?? '').toString();
                      final cals =
                          ((c['programasCalif'] as List?) ?? []).join(', ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('$mat · $nombre — $cals → $prog',
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.grey)),
                        ),
                      );
                    }),
                  ],
                ],
        ),
      ),
    );
  }

  Widget _filaPrograma({
    required String titulo,
    required String sub,
    required VoidCallback onCorregir,
    String nota = '',
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cessumRed.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(sub,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
                if (nota.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(nota,
                      style: const TextStyle(
                          fontSize: 11,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: cessumRed)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: cessumRed,
              side: const BorderSide(color: cessumRed),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onCorregir,
            child: const Text('Corregir', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // Diálogo para elegir el programa OFICIAL destino.
  Future<String?> _elegirProgramaOficial(String encabezado) async {
    final ofi = _programasOficiales();
    if (ofi.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No pude leer la lista de programas oficiales (cartas.json).')));
      return null;
    }
    String? sel;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Programa oficial'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(encabezado,
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: sel,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'Elige el programa correcto',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: ofi
                    .map((p) => DropdownMenuItem<String>(
                          value: p,
                          child: Text(p,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setSt(() => sel = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed:
                  sel == null ? null : () => Navigator.pop(ctx, sel),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _corregirProgramaCalif(String de) async {
    final a = await _elegirProgramaOficial(
        'Cambiar "$de" (en Calificaciones) por el programa oficial. '
        'Se actualizan todas las filas con ese programa.');
    if (a == null) return;
    await _aplicarCorreccionPrograma(
        accion: 'programa_calif_renombrar', extra: {'de': de, 'a': a});
  }

  Future<void> _corregirProgramaPadron(
      String matricula, String nombre, String actualProg) async {
    final a = await _elegirProgramaOficial(
        'Corregir el programa de $matricula · $nombre (actual: "$actualProg"). '
        'Se guarda como corrección del padrón.');
    if (a == null) return;
    await _aplicarCorreccionPrograma(
        accion: 'padron_set_programa',
        extra: {'matricula': matricula, 'programa': a});
  }

  Future<void> _aplicarCorreccionPrograma({
    required String accion,
    required Map<String, dynamic> extra,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': accion, 'actor': actor, ...extra}))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        final cambios = data['cambios'];
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF1E8E3E),
          content: Text(cambios != null
              ? 'Listo · $cambios fila(s) actualizada(s).'
              : 'Corrección aplicada.'),
        ));
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'No se pudo');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  /// Cada grupo inexistente con los alumnos afectados debajo.
  List<String> _gruposInexistentesConAlumnos() {
    final data = (_r['gruposInexistentesData'] as List?) ?? [];
    if (data.isEmpty) return _lista(_r['gruposInexistentes']);
    final out = <String>[];
    for (final e in data) {
      final m = Map<String, dynamic>.from(e as Map);
      final gruposOk = ((m['gruposDelPrograma'] as List?) ?? []).join(', ');
      final gen = (m['generacion'] ?? '').toString().trim();
      out.add('${m['programa']}'
          '${gen.isNotEmpty ? ' · $gen' : ''}'
          ' · ${m['grupo']}'
          '${gruposOk.isNotEmpty ? '  →  en asignaciones hay: $gruposOk' : '  →  ese programa no tiene ninguna asignación'}');
      final alumnos = ((m['alumnos'] as List?) ?? [])
          .map((a) => Map<String, dynamic>.from(a as Map))
          .toList();
      for (final a in alumnos) {
        final nom = (a['nombre'] ?? '').toString().trim();
        out.add('      ${a['matricula']}'
            '${nom.isNotEmpty ? ' · $nom' : ''}');
      }
      final filas = (m['filas'] ?? 0);
      if (alumnos.length < 40 && filas is num && filas > alumnos.length) {
        out.add('      … y ${filas.toInt() - alumnos.length} fila(s) más');
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _nombres = [];
  bool _nombresPedidos = false;

  Future<void> _cargarNombres() async {
    if (_nombresPedidos) return;
    _nombresPedidos = true;
    try {
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'nombres_sospechosos',
        'tope': '120',
      });
      final r = await http.get(u).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() {
          _nombres = ((d['casos'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
      // Sin respuesta no se pinta la tarjeta: mejor no mostrarla que mostrarla
      // vacía y hacer creer que no hay nombres mal capturados.
    }
  }

  Widget _tarjetaNombres() {
    if (_nombres.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cargarNombres());
      return const SizedBox.shrink();
    }
    final corregibles = _nombres.where((n) => n['corregible'] == true).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.badge_outlined, size: 18, color: cessumRed),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Nombres mal capturados',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
            Text('${_nombres.length}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
          ]),
          const SizedBox(height: 4),
          Text(
              'Este nombre es el que se imprime en constancias y actas. '
              '$corregibles se pueden corregir de un toque; el resto hay que '
              'escribirlos a mano.',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          for (final nm in _nombres.take(25)) _renglonNombre(nm),
          if (_nombres.length > 25)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('… y ${_nombres.length - 25} más',
                  style:
                      const TextStyle(fontSize: 11.5, color: Colors.black45)),
            ),
        ],
      ),
    );
  }

  Widget _renglonNombre(Map<String, dynamic> nm) {
    final corregible = nm['corregible'] == true;
    final senales = ((nm['senales'] as List?) ?? []).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${nm['matricula']} · ${nm['nombre']}',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor: corregible ? cessumRed : Colors.black54,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _editarNombre(nm),
                child: Text(corregible ? 'Corregir' : 'Escribir',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Text(senales,
              style: const TextStyle(
                  fontSize: 11, height: 1.3, color: Color(0xFF8A5A00))),
          if (corregible)
            Text('Quedaría: ${nm['propuesta']}',
                style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E8E3E))),
        ],
      ),
    );
  }

  Future<void> _editarNombre(Map<String, dynamic> nm) async {
    final ctrl = TextEditingController(
        text: ((nm['propuesta'] ?? '').toString().isNotEmpty
            ? nm['propuesta']
            : nm['nombre'])
            .toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Corregir el nombre', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Matrícula ${nm['matricula']}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Ahora dice: ${nm['nombre']}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre correcto',
                  helperText:
                      'Se cambia en Calificaciones y en el padrón a la vez. '
                      'Dejarlos distintos hace que el mismo alumno aparezca '
                      'como dos personas.',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                  'Los documentos ya emitidos no cambian: llevan impreso el '
                  'nombre que tenían.',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final correo = await SessionStore.validEmail();
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'nombre_corregir',
                'matricula': nm['matricula'],
                'nombreViejo': nm['nombre'],
                'nombreNuevo': ctrl.text.trim(),
                'actor': correo ?? '',
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((d['ok'] == true
                  ? (d['nota'] ?? 'Corregido.')
                  : (d['error'] ?? 'No se pudo.'))
              .toString()),
          duration: const Duration(seconds: 5)));
      if (d['ok'] == true) {
        _nombresPedidos = false;
        _nombres = [];
        await _cargarNombres();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
      }
    }
  }

  List<Map<String, dynamic>> _dupMat = [];
  Map<String, dynamic> _dupResumen = {};
  bool _dupPedidas = false;

  Future<void> _cargarDuplicadas() async {
    if (_dupPedidas) return;
    _dupPedidas = true;
    try {
      final u = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'matriculas_duplicadas'});
      final r = await http.get(u).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() {
          _dupMat = ((d['casos'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _dupResumen = Map<String, dynamic>.from(
              (d['resumen'] as Map?) ?? const <String, dynamic>{});
        });
      }
    } catch (_) {}
  }

  Color _colorGravedad(String g) {
    if (g == 'ALTA') return cessumRed;
    if (g == 'media') return const Color(0xFFB07D12);
    return const Color(0xFF1E8E3E);
  }

  Widget _tarjetaDuplicadas() {
    if (_dupMat.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _cargarDuplicadas());
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.people_alt_outlined, size: 18, color: cessumRed),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Matrículas con más de una fila',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
            Text('${_dupMat.length}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text(
              'No todas son un error. '
              '${_dupResumen['dos personas'] ?? 0} son personas distintas '
              'compartiendo matrícula — eso sí es grave.',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          for (final c in _dupMat) _renglonDuplicada(c),
        ],
      ),
    );
  }

  Widget _renglonDuplicada(Map<String, dynamic> c) {
    final col = _colorGravedad((c['gravedad'] ?? '').toString());
    final detalle = ((c['detalle'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final sug = (c['sugerencia'] ?? '').toString();
    final marcable = sug.startsWith('Marcar EGRESADO');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  '${c['matricula']} · ${detalle.isNotEmpty ? detalle.first['nombre'] : ''}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: col.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${c['clase']}',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: col)),
            ),
          ]),
          const SizedBox(height: 3),
          for (final f in detalle)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 1),
              child: Text(
                  '·  ${f['programa']} · ${f['generacion']} · '
                  '${f['grupo']} (${f['estatus']})',
                  style: const TextStyle(fontSize: 11.5, height: 1.3)),
            ),
          const SizedBox(height: 3),
          Text(sug,
              style: TextStyle(fontSize: 11.5, height: 1.3, color: col)),
          if (marcable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1E8E3E),
                    visualDensity: VisualDensity.compact),
                onPressed: () => _marcarInscripcion(c, detalle),
                icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                label: const Text('Marcar egresado',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _marcarInscripcion(
      Map<String, dynamic> c, List<Map<String, dynamic>> detalle) async {
    // Qué inscripción se marca lo elige quien decide, no la pantalla: dar por
    // concluida la equivocada le quitaría a alguien el programa que sí cursa.
    var elegido = detalle.isNotEmpty ? detalle.first : <String, dynamic>{};
    var estatus = 'EGRESADO';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setL) => AlertDialog(
          title: const Text('Cerrar una inscripción',
              style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['matricula']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('¿Cuál inscripción se cierra?',
                    style: TextStyle(fontSize: 12.5)),
                for (final f in detalle)
                  RadioListTile<Map<String, dynamic>>(
                    value: f,
                    groupValue: elegido,
                    onChanged: (v) => setL(() => elegido = v ?? elegido),
                    activeColor: cessumRed,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${f['programa']}',
                        style: const TextStyle(fontSize: 12.5)),
                    subtitle: Text(
                        '${f['generacion']} · ${f['grupo']} (${f['estatus']})',
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                const SizedBox(height: 8),
                for (final op in const [
                  ['EGRESADO', 'Concluyó. Puede recibir constancia, kardex y título.'],
                  ['BAJA', 'Abandonó. Su historial se conserva.'],
                ])
                  RadioListTile<String>(
                    value: op[0],
                    groupValue: estatus,
                    onChanged: (v) => setL(() => estatus = v ?? estatus),
                    activeColor: cessumRed,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(op[0],
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    subtitle: Text(op[1],
                        style: const TextStyle(fontSize: 11.5)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final correo = await SessionStore.validEmail();
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'inscripcion_estatus',
                'matricula': c['matricula'],
                'programa': elegido['programa'],
                'estatus': estatus,
                'actor': correo ?? '',
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((d['ok'] == true
                  ? (d['nota'] ?? 'Listo.')
                  : (d['error'] ?? 'No se pudo.'))
              .toString()),
          duration: const Duration(seconds: 5)));
      if (d['ok'] == true) {
        _dupPedidas = false;
        _dupMat = [];
        await _cargarDuplicadas();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error de conexión: $e')));
      }
    }
  }

  Widget _tarjeta(String titulo, String desc, List<String> items,
      {String? accionTipo, String? accionLabel, String? advertencia}) {
    final n = items.length;
    final ok = n == 0;
    final color = ok ? const Color(0xFF1E8E3E) : cessumRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: const [
          BoxShadow(color: Color(0x11000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
              color: color),
          title: Text(titulo,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          subtitle: Text(desc,
              style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$n',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: color, fontSize: 13)),
          ),
          children: ok
              ? const [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sin problemas.',
                        style: TextStyle(
                            fontSize: 12.5, color: Color(0xFF1E8E3E))),
                  )
                ]
              : [
                  ...items.take(100).map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('•  ',
                                style: TextStyle(color: Colors.grey)),
                            Expanded(
                              child: Text(e,
                                  style: const TextStyle(fontSize: 12.5)),
                            ),
                          ],
                        ),
                      )),
                  if (accionTipo != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cessumRed,
                          side: const BorderSide(color: cessumRed),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        onPressed: () => _aplicarAccion(
                          tipo: accionTipo,
                          titulo: accionLabel ?? 'Aplicar corrección',
                          advertencia: advertencia ?? '¿Aplicar a la base?',
                        ),
                        icon: const Icon(Icons.auto_fix_high, size: 18),
                        label: Text(accionLabel ?? 'Corregir'),
                      ),
                    ),
                  ],
                ],
        ),
      ),
    );
  }

  Widget _contadorSimple(String titulo, int n,
      {String? accionTipo, String? accionLabel, String? advertencia}) {
    final ok = n == 0;
    final color = ok ? const Color(0xFF1E8E3E) : cessumRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(titulo,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Text('$n',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: color, fontSize: 16)),
            ],
          ),
          if (accionTipo != null && n > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: () => _aplicarAccion(
                  tipo: accionTipo,
                  titulo: accionLabel ?? 'Aplicar corrección',
                  advertencia: advertencia ?? '¿Aplicar a la base?',
                ),
                icon: const Icon(Icons.auto_fix_high, size: 18),
                label: Text(accionLabel ?? 'Corregir'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

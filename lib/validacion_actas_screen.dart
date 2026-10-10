import 'dart:convert';

import 'dart:html' as html;   // para incrustar el acta en la ventana
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Panel de VALIDACIÓN de actas (solo admin / vicerrectoría).
/// Muestra las actas que están "En validación" y permite validarlas.
/// Al validar, las calificaciones de esa acta pasan a ser definitivas.
class ValidacionActasScreen extends StatefulWidget {
  const ValidacionActasScreen({super.key});

  @override
  State<ValidacionActasScreen> createState() => _ValidacionActasScreenState();
}

// Convierte una generación cruda (que Sheets pudo guardar como fecha) a su
// forma legible 'd-M' (la que se eligió en captura). Si ya es legible, la deja.
String _genLegible(String g) {
  final s = g.trim();
  if (s.isEmpty) return s;
  const meses = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
  };
  final mTxt = RegExp(r'\b([A-Za-z]{3})\s+(\d{1,2})\s+\d{4}').firstMatch(s);
  if (mTxt != null) {
    final mes = meses[mTxt.group(1)!.toLowerCase()];
    final dia = int.tryParse(mTxt.group(2)!);
    if (mes != null && dia != null) return '$dia-$mes';
  }
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (iso != null) {
    final mes = int.tryParse(iso.group(2)!);
    final dia = int.tryParse(iso.group(3)!);
    if (mes != null && dia != null) return '$dia-$mes';
  }
  return s;
}

class _Acta {
  final String programa;
  final String generacion;
  final String generacionTxt;
  final String grupo;
  final String materia;
  final String ciclo;
  final String periodo;
  final String docente;
  final int totalAlumnos;
  final int enValidacion;
  final int validadas;
  final String estatusGeneral;
  final int? diasRestantes;
  final String fechaCaptura;
  final String fechaValidacion;
  const _Acta({
    required this.programa,
    required this.generacion,
    required this.generacionTxt,
    required this.grupo,
    required this.materia,
    required this.ciclo,
    required this.periodo,
    required this.docente,
    required this.totalAlumnos,
    required this.enValidacion,
    required this.validadas,
    required this.estatusGeneral,
    this.diasRestantes,
    this.fechaCaptura = '',
    this.fechaValidacion = '',
  });
}

class _ValidacionActasScreenState extends State<ValidacionActasScreen> {
  bool _validandoLote = false;
  List<_Acta> _actas = [];
  final TextEditingController _busqueda = TextEditingController();
  String _filtro = '';
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  String _norm(String s) {
    s = s.toLowerCase().trim();
    const con = 'áàäâéèëêíìïîóòöôúùüûñ';
    const sin = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
  }

  // Coincide si TODAS las palabras escritas aparecen en los datos del acta.
  bool _coincide(_Acta a) {
    final q = _norm(_filtro);
    if (q.isEmpty) return true;
    final blob = _norm('${a.materia} ${a.programa} ${a.generacionTxt} '
        'gen ${a.generacionTxt} grupo ${a.grupo} ${a.grupo} '
        '${a.ciclo} ${a.periodo} ${a.docente}');
    for (final palabra in q.split(RegExp(r'\s+'))) {
      if (palabra.isEmpty) continue;
      if (!blob.contains(palabra)) return false;
    }
    return true;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'actas_validacion'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final lista = (data['actas'] as List<dynamic>? ?? []);
      final actas = lista.map((e) {
        final m = e as Map<String, dynamic>;
        return _Acta(
          programa: (m['programa'] ?? '').toString(),
          generacion: (m['generacion'] ?? '').toString(),
          generacionTxt: _genLegible(
              (m['generacionTxt'] ?? m['generacion'] ?? '').toString()),
          grupo: (m['grupo'] ?? '').toString(),
          materia: (m['materia'] ?? '').toString(),
          ciclo: (m['ciclo'] ?? '').toString(),
          periodo: (m['periodo'] ?? '').toString(),
          docente: (m['docente'] ?? '').toString(),
          totalAlumnos: (m['totalAlumnos'] ?? 0) is int
              ? m['totalAlumnos'] as int
              : int.tryParse('${m['totalAlumnos']}') ?? 0,
          enValidacion: (m['enValidacion'] ?? 0) is int
              ? m['enValidacion'] as int
              : int.tryParse('${m['enValidacion']}') ?? 0,
          validadas: (m['validadas'] ?? 0) is int
              ? m['validadas'] as int
              : int.tryParse('${m['validadas']}') ?? 0,
          estatusGeneral: (m['estatusGeneral'] ?? '').toString(),
          diasRestantes: m['diasRestantes'] == null
              ? null
              : int.tryParse('${m['diasRestantes']}'),
          fechaCaptura: (m['fechaCaptura'] ?? '').toString(),
          fechaValidacion: (m['fechaValidacion'] ?? '').toString(),
        );
      }).toList();
      if (mounted) {
        setState(() {
          _actas = actas;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error =
              'No se pudieron cargar las actas. Revisa tu conexión e intenta de nuevo.';
        });
      }
    }
  }

  /// El acta en una ventana sobre la lista, con las acciones debajo.
  ///
  /// Se mantiene el enlace para abrirla aparte: un acta de treinta alumnos se
  /// revisa mejor a pantalla completa, y hay quien prefiere imprimirla.
  void _verActaEnVentana(_Acta a, String pdf) {
    // El resto de la pantalla usa este mismo criterio: 'En validación' es lo
    // que está esperando dictamen.
    final pendiente = a.estatusGeneral == 'En validación';
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final ancho = MediaQuery.of(ctx).size.width;
        final alto = MediaQuery.of(ctx).size.height;
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
              horizontal: ancho > 900 ? 40 : 10, vertical: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: ancho > 1100 ? 1000 : ancho,
            height: alto * 0.92,
            child: Column(children: [
              // Encabezado: de qué acta se trata, sin tener que recordarlo.
              Container(
                color: cessumRed,
                padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
                child: Row(children: [
                  const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(a.materia,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                          Text(
                              '${a.programa} · Gen. ${a.generacionTxt} · '
                              'Grupo ${a.grupo} · ${a.totalAlumnos} alumno(s)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 11.5)),
                        ]),
                  ),
                  IconButton(
                    tooltip: 'Abrir en otra pestaña',
                    onPressed: () => launchUrl(Uri.parse(pdf),
                        mode: LaunchMode.externalApplication,
                        webOnlyWindowName: '_blank'),
                    icon: const Icon(Icons.open_in_new,
                        color: Colors.white, size: 20),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ]),
              ),
              Expanded(child: _VisorActaPdf(src: pdf)),
              // Las acciones, debajo del documento que se acaba de leer.
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(ctx).cardColor,
                  border: Border(top: BorderSide(color: cessumMuted(context).withValues(alpha: 0.18))),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: pendiente
                    ? Row(children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E8E3E),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _validar(a);
                            },
                            icon: const Icon(Icons.verified, size: 20),
                            label: const Text('Validar acta',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: TextButton.styleFrom(
                              foregroundColor: cessumMuted(context),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 14)),
                          child: const Text('Cerrar'),
                        ),
                      ])
                    : Row(children: [
                        Icon(Icons.verified_outlined,
                            size: 18, color: const Color(0xFF1E8E3E)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              a.fechaValidacion.isNotEmpty
                                  ? 'Validada el ${a.fechaValidacion}'
                                  : 'Esta acta está ${a.estatusGeneral.toLowerCase()}',
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cerrar'),
                        ),
                      ]),
              ),
            ]),
          ),
        );
      },
    );
  }

  Future<void> _verPdf(_Acta a) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'acta_preview',
        'programa': a.programa,
        'generacion': a.generacion,
        'grupo': a.grupo,
        'materia': a.materia,
        'ciclo': a.ciclo,
        'periodo': a.periodo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      final pdf = (data['pdfUrl'] ?? '').toString();
      if (data['ok'] == true && pdf.isNotEmpty) {
        /* (4-sep) EL ACTA SE ABRE AQUÍ, NO EN OTRA PESTAÑA.
           Antes había que salir de la pantalla para verla, y volver para
           validarla: quien revisa treinta actas hace sesenta saltos, y en el
           camino se pierde cuál estaba revisando. Ahora se ve en una ventana
           sobre la lista, con el botón de validar debajo del documento. */
        _verActaEnVentana(a, pdf);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo abrir el acta: '
              '${data['error'] ?? 'inténtalo de nuevo.'}'),
          backgroundColor: cessumRed));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo abrir el acta. Revisa tu conexión.'),
        backgroundColor: cessumRed));
    }
  }

  Future<void> _eliminar(_Acta a) async {
    final correo = (await SessionStore.realEmail()) ?? '';
    if (!mounted) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar acta'),
        content: Text(
          'Vas a ELIMINAR por completo el acta de "${a.materia}" '
          '(${a.programa}, Gen. ${a.generacionTxt}, Grupo ${a.grupo}).\n\n'
          'Esto borra las ${a.totalAlumnos} calificación(es) de la base Y del '
          'registro del docente (kardex). No es lo mismo que rechazar: aquí no '
          'queda rastro. Úsalo solo para limpiar intentos o basura.\n\n'
          'Esta acción no se puede deshacer.',
          style: const TextStyle(height: 1.4),
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
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'acta_eliminar',
        'programa': a.programa,
        'generacion': a.generacion,
        'grupo': a.grupo,
        'materia': a.materia,
        'ciclo': a.ciclo,
        'periodo': a.periodo,
        'actor': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Acta eliminada (${data['filas'] ?? 0} calificaciones).'),
          backgroundColor: const Color(0xFF1E8E3E)));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo eliminar: ${data['error'] ?? ''}'),
          backgroundColor: cessumRed));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo eliminar. Revisa tu conexión.'),
        backgroundColor: cessumRed));
    }
  }

  Future<void> _validar(_Acta a) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validar acta'),
        content: Text(
          '¿Seguro que quieres validar el acta de "${a.materia}" '
          '(${a.programa}, Gen. ${a.generacionTxt}, Grupo ${a.grupo})?\n\n'
          'Al validarla, las ${a.totalAlumnos} calificación(es) pasan a ser '
          'definitivas y dejarán de aparecer "en proceso de validación" para '
          'los alumnos.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E8E3E),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Validar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!mounted) return;

    // Mostramos un indicador mientras valida.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );

    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'validar_acta',
        'programa': a.programa,
        'generacion': a.generacion,
        'grupo': a.grupo,
        'materia': a.materia,
        'ciclo': a.ciclo,
        'periodo': a.periodo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context); // cerrar el indicador

      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Acta validada: ${data['validadas']} calificación(es).'),
            backgroundColor: const Color(0xFF1E8E3E),
          ),
        );
        _cargar(); // recargar la lista
      } else {
        throw Exception(data['error'] ?? 'No se pudo validar');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // cerrar el indicador
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al validar: $e'),
          backgroundColor: cessumRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Validación de actas'),
        actions: [
          IconButton(
            icon: _validandoLote
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.done_all),
            tooltip: 'Validar toda una generación',
            onPressed:
                (_cargando || _validandoLote) ? null : _validarPorGeneracion,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _actas.isEmpty
                  ? _vistaVacia()
                  : _vistaLista(),
    );
  }

  Future<void> _validarPorGeneracion() async {
    // generaciones con actas pendientes
    final pendientes =
        _actas.where((a) => a.estatusGeneral == 'En validación').toList();
    if (pendientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay actas pendientes para validar en lote.'),
      ));
      return;
    }
    final Map<String, _Acta> porGen = {};
    for (final a in pendientes) {
      porGen.putIfAbsent('${a.programa}||${a.generacion}', () => a);
    }
    final claves = porGen.keys.toList();
    final elegido = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Validar toda una generación'),
        children: claves.map((k) {
          final a = porGen[k]!;
          final cuantas = pendientes
              .where((x) => '${x.programa}||${x.generacion}' == k)
              .length;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, k),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${a.programa}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('Gen. ${a.generacionTxt} · $cuantas acta(s) pendiente(s)',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
    if (elegido == null) return;
    final a = porGen[elegido]!;
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar validación en lote'),
        content: Text(
            'Se validarán TODAS las actas pendientes de:\n\n${a.programa}\nGeneración ${a.generacionTxt}\n\nEsta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Validar todas'),
          ),
        ],
      ),
    );
    if (confirma != true) return;

    setState(() => _validandoLote = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'validar_actas_lote',
                'confirmar': 'ENVIAR', // (22-sep) ya se confirmó en el diálogo
                'programa': a.programa,
                'generacion': a.generacion,
              }))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(
              '${data['actasValidadas']} acta(s) validada(s), ${data['calificaciones']} calificación(es).'),
        ));
      }
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _validandoLote = false);
    }
  }

  Widget _vistaLista() {
    final base =
        _filtro.trim().isEmpty ? _actas : _actas.where(_coincide).toList();
    // Primero las que están en validación (pendientes), luego las validadas.
    final pendientes =
        base.where((a) => a.estatusGeneral == 'En validación').toList();
    final validadas =
        base.where((a) => a.estatusGeneral != 'En validación').toList();

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buscador(),
          const SizedBox(height: 12),
          if (base.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'Sin resultados para "${_busqueda.text.trim()}".',
                  style: TextStyle(color: cessumMuted(context)),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 4),
              child: Text(
                '${pendientes.length} acta(s) pendiente(s) de validación.',
                style: TextStyle(fontSize: 13, color: cessumMuted(context)),
              ),
            ),
            ...pendientes.map((a) => _tarjeta(a, pendiente: true)),
            if (validadas.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(
                  _filtro.trim().isEmpty
                      ? 'Actas ya validadas'
                      : 'Actas ya validadas (${validadas.length})',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: cessumMuted(context)),
                ),
              ),
              ...validadas.map((a) => _tarjeta(a, pendiente: false)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buscador() {
    return TextField(
      controller: _busqueda,
      onChanged: (v) => setState(() => _filtro = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar por materia, programa, generación, grupo o ciclo…',
        prefixIcon: const Icon(Icons.search, color: cessumRed),
        suffixIcon: _busqueda.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear),
                tooltip: 'Limpiar',
                onPressed: () => setState(() {
                  _busqueda.clear();
                  _filtro = '';
                }),
              ),
        filled: true,
        fillColor: Theme.of(context).cardColor,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cessumMuted(context).withValues(alpha: 0.18)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cessumMuted(context).withValues(alpha: 0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cessumRed),
        ),
      ),
    );
  }

  Widget _tarjeta(_Acta a, {required bool pendiente}) {
    final colorEstatus =
        pendiente ? const Color(0xFFB8842C) : const Color(0xFF1E8E3E);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  a.materia,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cessumInk(context),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorEstatus.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pendiente ? 'En validación' : 'Validada',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colorEstatus,
                  ),
                ),
              ),
            ],
          ),
          if (pendiente && a.diasRestantes != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (a.diasRestantes! <= 0
                        ? const Color(0xFFB11D29)
                        : const Color(0xFFB8842C))
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (a.diasRestantes! <= 0
                          ? const Color(0xFFB11D29)
                          : const Color(0xFFB8842C))
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                a.diasRestantes! < 0
                    ? '⚠ Plazo de validación VENCIDO (capturada el ${a.fechaCaptura})'
                    : a.diasRestantes! == 0
                        ? '⚠ El plazo de validación vence HOY (capturada el ${a.fechaCaptura})'
                        : 'Vence en ${a.diasRestantes} día(s) — capturada el ${a.fechaCaptura} (plazo: 3 días)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: a.diasRestantes! <= 0
                      ? const Color(0xFFB11D29)
                      : const Color(0xFF8A6118),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _renglon(Icons.school_outlined, a.programa),
          _renglon(Icons.groups_outlined,
              'Gen. ${a.generacionTxt}  •  Grupo ${a.grupo}  •  Ciclo ${a.ciclo}  •  Periodo ${a.periodo}'),
          if (a.docente.isNotEmpty)
            _renglon(Icons.person_outline, a.docente),
          _renglon(Icons.people_alt_outlined,
              '${a.totalAlumnos} alumno(s)'),
          if (!pendiente && a.fechaValidacion.isNotEmpty)
            _renglon(Icons.verified_outlined,
                'Validada el ${a.fechaValidacion}'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _verPdf(a),
              icon: const Icon(Icons.picture_as_pdf, size: 20),
              label: const Text('Ver acta (PDF)'),
            ),
          ),
          if (pendiente) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => _validar(a),
                icon: const Icon(Icons.verified, size: 20),
                label: const Text('Validar acta'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: cessumRed,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => _eliminar(a),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Eliminar acta (limpiar)'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _renglon(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cessumFaint(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                  fontSize: 13, color: cessumMuted(context), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaVacia() {
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.inbox_outlined, color: cessumFaint(context), size: 48),
          const SizedBox(height: 12),
          Text(
            'No hay actas pendientes de validación.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumMuted(context), height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Cuando un docente capture calificaciones, sus actas aparecerán aquí.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumFaint(context), fontSize: 12, height: 1.4),
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
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Incrusta el PDF del acta dentro de la ventana. Cada dirección registra su
/// propia vista, así que abrir dos actas distintas no reusa el mismo marco.
class _VisorActaPdf extends StatefulWidget {
  final String src;
  const _VisorActaPdf({required this.src});
  @override
  State<_VisorActaPdf> createState() => _VisorActaPdfState();
}

class _VisorActaPdfState extends State<_VisorActaPdf> {
  static final Set<String> _registradas = {};
  late final String _vista;

  @override
  void initState() {
    super.initState();
    _vista = 'acta-pdf-${widget.src.hashCode}';
    if (!_registradas.contains(_vista)) {
      _registradas.add(_vista);
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(_vista, (int _) {
        final el = html.IFrameElement()
          ..src = widget.src
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
        return el;
      });
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _vista);
}

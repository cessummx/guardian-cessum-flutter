// ADMIN: Convenios (ago-2026). Crear convenios (título + términos +
// alcance), promoverlos por correo a los alumnos dirigidos, ver el avance
// de firmas (firmados y pendientes) y cerrarlos.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
// (ago-12) Para abrir el PDF. Esta pantalla no importaba url_launcher ni
// helpers, así que launchUrl no existía aquí y el botón habría reventado al
// compilar.
import 'helpers.dart';
import 'convenio_pago_screen.dart';

class ConveniosAdminScreen extends StatefulWidget {
  const ConveniosAdminScreen({super.key});

  @override
  State<ConveniosAdminScreen> createState() => _ConveniosAdminScreenState();
}

class _ConveniosAdminScreenState extends State<ConveniosAdminScreen> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _convenios = [];
  List<Map<String, dynamic>> _alumnos = [];
  List<Map<String, dynamic>> _catFirmantes = [];
  String _miCorreo = '';
  // (29-sep) Solicitudes de convenio de pago enviadas por alumnos.
  List<Map<String, dynamic>> _solicitudes = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(String qs, {int seg = 90}) async {
    final r = await http
        .get(Uri.parse('$guardianUrl?$qs'))
        .timeout(Duration(seconds: seg));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _aviso(String m, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: ok ? const Color(0xFF1E8E3E) : cessumRed,
        content: Text(m)));
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      await _cargarCatFirmantes();
      final d = await _get('accion=convenios_admin_listar');
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      Map<String, dynamic>? dSol;
      try { dSol = await _get('accion=convenio_solicitudes_listar&actor=$_miCorreo'); } catch (_) {}
      if (!mounted) return;
      setState(() {
        _convenios = ((d['convenios'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _solicitudes = ((dSol?['solicitudes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _cargarCatFirmantes() async {
    if (_catFirmantes.isNotEmpty) return;
    try {
      final d = await _get('accion=convenio_firmantes_cat');
      _catFirmantes = (((d['firmantes'] as List?) ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}
    _miCorreo = (await SessionStore.validEmail() ?? '').toLowerCase();
  }

  Future<void> _cargarAlumnos() async {
    if (_alumnos.isNotEmpty) return;
    final d = await _get('accion=clasificacion_alumnos', seg: 90);
    _alumnos = (((d['alumnos'] as List?) ?? []))
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((a) =>
            (a['tipo'] ?? '') != 'Baja' &&
            (a['matricula'] ?? '').toString().isNotEmpty)
        .toList();
  }

  // (1-oct-2026) El asistente de Convenio de pago (con sus 7 plantillas ya
  // redactadas: falta de pago, reinscripción diferida, recursamiento,
  // reingreso, titulación, graduación, personalizado) solo era alcanzable
  // desde "Solicitudes de alumnos" — el admin no podía iniciarlo de forma
  // proactiva, sin esperar a que el alumno lo pidiera primero. Este
  // selector es el único cambio: antes de abrir el formulario, se elige
  // qué asistente usar. ConvenioPagoScreen ya funciona sin matrícula
  // inicial (trae su propio buscador de alumno), así que no hace falta
  // tocar nada más de su lógica.
  Future<void> _elegirTipoYCrear() async {
    final tipo = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('¿Qué tipo de convenio?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined, color: cessumRed),
              title: const Text('Convenio de pago',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                  'Falta de pago, reinscripción, recursamiento, reingreso, titulación o graduación — '
                  'con el plan de pagos y las cláusulas ya redactadas; usted solo ajusta montos y fechas.'),
              onTap: () => Navigator.pop(ctx, 'pago'),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: cessumRed),
              title: const Text('Convenio institucional',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Título y términos libres, para cualquier otra situación.'),
              onTap: () => Navigator.pop(ctx, 'generico'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || tipo == null) return;
    if (tipo == 'pago') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ConvenioPagoScreen()),
      );
      _cargar();
      return;
    }
    _crear();
  }

  Future<void> _crear() async {
    try {
      await _cargarAlumnos();
    } catch (_) {}
    if (!mounted) return;
    final titulo = TextEditingController();
    final terminos = TextEditingController();
    await _cargarCatFirmantes();
    var alcance = 'Grupo'; // Todos | Grupo | Alumnos
    final instSel = <String>{'Vicerrectoría Académica'};
    String? progSel;
    String? genSel;
    String? grupoSel;
    final firmantes = <Map<String, dynamic>>[];
    final programas = _alumnos
        .map((a) => (a['programa'] ?? '').toString())
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final gens = _alumnos
            .where((a) =>
                progSel == null || (a['programa'] ?? '') == progSel)
            .map((a) => (a['generacion'] ?? '').toString())
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final grupos = _alumnos
            .where((a) =>
                (progSel == null || (a['programa'] ?? '') == progSel) &&
                (genSel == null || (a['generacion'] ?? '') == genSel))
            .map((a) => (a['grupo'] ?? '').toString())
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        return Dialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 620, maxHeight: 700),
            child: Column(
              children: [
                // Encabezado institucional con logo
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  decoration: const BoxDecoration(
                    color: cessumRed,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.asset('assets/images/logo.png',
                            height: 34,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.school,
                                color: cessumRed,
                                size: 34)),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nuevo convenio',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800)),
                            Text(
                                'CESSUM · Centro de Estudios Superiores del Mayo',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                      IconButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          icon: const Icon(Icons.close,
                              color: Colors.white)),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CONTENIDO DEL CONVENIO',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: cessumGold)),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cessumGold.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color:
                                    cessumGold.withValues(alpha: 0.4)),
                          ),
                          child: const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('¿CÓMO SE FORMA UN CONVENIO?',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF8A5A0F))),
                              SizedBox(height: 6),
                              Text(
                                  '1) Título: el nombre del expediente (ej. "Convenio de '
                                  'Regularización Académica · MPNE 25-2 · Nombre").\n'
                                  '2) Términos: pega AQUÍ el texto ÍNTEGRO del convenio '
                                  '(declaraciones y cláusulas) — es lo que se firma; el bloque '
                                  'de firmas NO se pega, la plataforma lo dibuja solo.\n'
                                  '3) Firmantes (alumnos): a quién le aparece en su app para '
                                  'leer, observar y firmar.\n'
                                  '4) Firmantes institucionales: quiénes firman por CESSUM.\n'
                                  'Ciclo: Crear → Vista previa → firmas institucionales → '
                                  'Promover (le avisa por correo) → el alumno lee, hace '
                                  'observaciones si quiere, y firma.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      height: 1.5,
                                      color: Colors.black87)),
                            ],
                          ),
                        ),
                        // (24-sep) Borrador con IA con los datos reales del alumno.
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: cessumGold),
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('Redactar con IA para un alumno'),
                            onPressed: () async {
                              final sel = await _elegirAlumnoDialogo(ctx);
                              if (sel == null || !ctx.mounted) return;
                              final propCtl = TextEditingController();
                              final seguir = await showDialog<bool>(
                                context: ctx,
                                builder: (c2) => AlertDialog(
                                  title: Text('Convenio para ${sel['nombre'] ?? sel['matricula']}',
                                      style: const TextStyle(fontSize: 16)),
                                  content: SizedBox(
                                    width: 460,
                                    child: TextField(
                                      controller: propCtl,
                                      minLines: 3,
                                      maxLines: 6,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        labelText: '¿Para qué es el convenio?',
                                        hintText: 'Ej. Ruta para concluir tras el cambio a no escolarizada; '
                                            'Técnicas de escritura en modalidad autogestiva del 28/09 al 01/11.',
                                      ),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Cancelar')),
                                    FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: cessumRed),
                                      onPressed: () => Navigator.pop(c2, true),
                                      child: const Text('Redactar'),
                                    ),
                                  ],
                                ),
                              );
                              final proposito = propCtl.text.trim();
                              propCtl.dispose();
                              if (seguir != true || !ctx.mounted) return;
                              showDialog<void>(
                                context: ctx,
                                barrierDismissible: false,
                                builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)),
                              );
                              Map<String, dynamic> d;
                              try {
                                d = await _get(
                                    'accion=convenio_ia_borrador&matricula=${Uri.encodeComponent('${sel['matricula']}')}'
                                    '&proposito=${Uri.encodeComponent(proposito)}',
                                    seg: 180);
                              } catch (_) {
                                d = {'ok': false, 'error': 'No se pudo conectar.'};
                              }
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (d['ok'] != true) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    backgroundColor: cessumRed, content: Text('${d['error'] ?? 'No se pudo redactar.'}')));
                                return;
                              }
                              setLocal(() {
                                titulo.text = '${d['titulo'] ?? ''}';
                                terminos.text = '${d['terminos'] ?? ''}';
                                alcance = 'Alumnos';
                                if (!firmantes.any((f) => f['matricula'] == sel['matricula'])) firmantes.add(sel);
                              });
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  duration: const Duration(seconds: 6),
                                  content: Text('Borrador listo: se detectaron ${d['acuerdosDetectados'] ?? 0} compromiso(s). '
                                      'Revíselo completo antes de guardar.')));
                            },
                          ),
                        ),
                        TextField(
                            controller: titulo,
                            decoration: const InputDecoration(
                                labelText: 'Título del convenio',
                                prefixIcon: Icon(Icons.title, size: 18),
                                border: OutlineInputBorder(),
                                isDense: true)),
                        const SizedBox(height: 10),
                        TextField(
                            controller: terminos,
                            maxLines: 12,
                            decoration: const InputDecoration(
                                labelText:
                                    'Términos completos (lo que el firmante leerá y aceptará)',
                                alignLabelWithHint: true,
                                border: OutlineInputBorder())),
                        const SizedBox(height: 16),
                        const Text('FIRMANTES (¿a quién va dirigido?)',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: cessumGold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final a in ['Todos', 'Grupo', 'Alumnos'])
                              ChoiceChip(
                                label: Text(a == 'Todos'
                                    ? 'Todos los alumnos'
                                    : a == 'Grupo'
                                        ? 'Programa / grupo'
                                        : 'Alumnos específicos'),
                                selected: alcance == a,
                                selectedColor:
                                    cessumRed.withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: alcance == a
                                        ? cessumRed
                                        : Colors.black87),
                                onSelected: (_) =>
                                    setLocal(() => alcance = a),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (alcance == 'Grupo') ...[
                          DropdownButtonFormField<String>(
                            initialValue: progSel,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Programa',
                                prefixIcon:
                                    Icon(Icons.school, size: 18),
                                border: OutlineInputBorder(),
                                isDense: true),
                            items: [
                              const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('(todos los programas)')),
                              for (final p in programas)
                                DropdownMenuItem(
                                    value: p,
                                    child: Text(p,
                                        overflow:
                                            TextOverflow.ellipsis)),
                            ],
                            onChanged: (v) => setLocal(() {
                              progSel = v;
                              genSel = null;
                              grupoSel = null;
                            }),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: genSel,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Generación',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                                items: [
                                  const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('(todas)')),
                                  for (final g in gens)
                                    DropdownMenuItem(
                                        value: g, child: Text(g)),
                                ],
                                onChanged: (v) => setLocal(() {
                                  genSel = v;
                                  grupoSel = null;
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: grupoSel,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Grupo',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                                items: [
                                  const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('(todos)')),
                                  for (final g in grupos)
                                    DropdownMenuItem(
                                        value: g, child: Text(g)),
                                ],
                                onChanged: (v) =>
                                    setLocal(() => grupoSel = v),
                              ),
                            ),
                          ]),
                        ] else if (alcance == 'Alumnos') ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                                foregroundColor: cessumRed,
                                side:
                                    const BorderSide(color: cessumRed)),
                            onPressed: () async {
                              final sel =
                                  await _elegirAlumnoDialogo(ctx);
                              if (sel != null &&
                                  !firmantes.any((f) =>
                                      f['matricula'] ==
                                      sel['matricula'])) {
                                setLocal(() => firmantes.add(sel));
                              }
                            },
                            icon: const Icon(Icons.person_add_alt,
                                size: 17),
                            label: const Text('Agregar firmante'),
                          ),
                          const SizedBox(height: 8),
                          if (firmantes.isEmpty)
                            const Text(
                                'Sin firmantes aún: agrega uno o más alumnos.',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.black54)),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final f in firmantes)
                                Chip(
                                  label: Text(
                                      '${f['nombre']} (${f['matricula']})',
                                      style: const TextStyle(
                                          fontSize: 11.5)),
                                  deleteIcon: const Icon(Icons.close,
                                      size: 15),
                                  onDeleted: () =>
                                      setLocal(() => firmantes.remove(f)),
                                ),
                            ],
                          ),
                        ] else
                          const Text(
                              'El convenio se dirigirá a TODOS los alumnos activos.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 16),
                        const Text('FIRMANTES INSTITUCIONALES',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: cessumGold)),
                        const SizedBox(height: 6),
                        const Text(
                            'Además del alumno, estas autoridades firmarán '
                            'desde su propia sesión en la app:',
                            style: TextStyle(
                                fontSize: 11.5, color: Colors.black54)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final fc in _catFirmantes)
                              FilterChip(
                                label: Text('${fc['cargo']}',
                                    style:
                                        const TextStyle(fontSize: 11.5)),
                                selected:
                                    instSel.contains(fc['cargo']),
                                selectedColor:
                                    cessumRed.withValues(alpha: 0.15),
                                checkmarkColor: cessumRed,
                                onSelected: (v) => setLocal(() {
                                  if (v) {
                                    instSel.add('${fc['cargo']}');
                                  } else {
                                    instSel.remove('${fc['cargo']}');
                                  }
                                }),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar')),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: cessumGold,
                              side:
                                  const BorderSide(color: cessumGold)),
                          onPressed: () {
                            final cat = {
                              for (final fc in _catFirmantes)
                                '${fc['cargo']}':
                                    '${fc['nombre'] ?? ''}'
                            };
                            _dialogoDocumento(
                              titulo: titulo.text.trim().isEmpty
                                  ? '(Sin título aún)'
                                  : titulo.text.trim(),
                              terminos: terminos.text.trim().isEmpty
                                  ? '(Aún no has pegado los términos del convenio.)'
                                  : terminos.text,
                              firmas: [
                                for (final cargo in instSel)
                                  {
                                    'nombre': cat[cargo] ?? '',
                                    'cargo': cargo,
                                    'firmado': false,
                                  }
                              ],
                              pie:
                                  'VISTA PREVIA DEL BORRADOR — todavía no se crea nada. '
                                  'Así exactamente lo leerán la alumna y los firmantes.',
                            );
                          },
                          icon: const Icon(Icons.visibility, size: 18),
                          label: const Text('Vista previa')),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: cessumRed,
                              foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.history_edu, size: 18),
                          label: const Text('Crear convenio')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
    if (ok != true) return;
    if (titulo.text.trim().isEmpty || terminos.text.trim().isEmpty) {
      _aviso('Título y términos son obligatorios.', ok: false);
      return;
    }
    if (alcance == 'Alumnos' && firmantes.isEmpty) {
      _aviso('Agrega al menos un alumno firmante.', ok: false);
      return;
    }
    final quien = await SessionStore.validEmail();
    final d = await _post({
      'accion': 'convenio_crear',
      'titulo': titulo.text.trim(),
      'terminos': terminos.text.trim(),
      'programa': alcance == 'Grupo' ? (progSel ?? '') : '',
      'generacion': alcance == 'Grupo' ? (genSel ?? '') : '',
      'grupo': alcance == 'Grupo' ? (grupoSel ?? '') : '',
      'matriculas': alcance == 'Alumnos'
          ? firmantes.map((f) => f['matricula']).join(',')
          : '',
      'firmantesInst': instSel.join(';'),
      'actor': quien ?? '',
    });
    if (d['ok'] == true) {
      _aviso('Convenio creado. Usa "Promover" para avisar por correo.');
      _cargar();
    } else {
      _aviso('${d['error']}', ok: false);
    }
  }

  Future<Map<String, dynamic>?> _elegirAlumnoDialogo(
      BuildContext ctxPadre) {
    return showDialog<Map<String, dynamic>>(
      context: ctxPadre,
      builder: (ctx) {
        var filtro = '';
        return StatefulBuilder(builder: (ctx, setLocal) {
          final vis = _alumnos.where((a) {
            if (filtro.isEmpty) return false;
            return '${a['nombre']} ${a['matricula']}'
                .toLowerCase()
                .contains(filtro.toLowerCase());
          }).take(30).toList();
          return AlertDialog(
            title: const Text('Buscar alumno firmante'),
            content: SizedBox(
              width: 460,
              height: 380,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Nombre o matrícula…',
                      isDense: true,
                      border: OutlineInputBorder()),
                  onChanged: (v) => setLocal(() => filtro = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtro.isEmpty
                      ? const Center(
                          child: Text('Escribe para buscar…',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black45)))
                      : ListView(children: [
                          for (final a in vis)
                            ListTile(
                              dense: true,
                              title: Text('${a['nombre']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '${a['matricula']} · ${a['programa']} ${a['generacion']} · ${a['grupo']}',
                                  style:
                                      const TextStyle(fontSize: 11.5)),
                              onTap: () => Navigator.pop(ctx, a),
                            ),
                        ]),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
            ],
          );
        });
      },
    );
  }

  Future<void> _promover(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promover convenio'),
        content: Text(
            'Se enviará el correo "Convenio por firmar" a los alumnos '
            'dirigidos que AÚN NO firman '
            '(${(c['objetivo'] ?? 0) - (c['firmados'] ?? 0)} pendientes de '
            '${c['objetivo']}). ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar correos')),
        ],
      ),
    );
    if (ok != true) return;
    final d = await _get(
        'accion=convenio_promover&id=${Uri.encodeComponent((c['id'] ?? '').toString())}',
        seg: 300);
    if (d['ok'] == true) {
      _aviso('Promovido: ${d['promovidos']} correo(s) enviados'
          '${(d['sinCorreo'] ?? 0) != 0 ? ' · ${d['sinCorreo']} sin correo' : ''}.');
    } else {
      _aviso('${d['error']}', ok: false);
    }
  }

  Future<void> _verFirmas(Map<String, dynamic> c) async {
    final d = await _get(
        'accion=convenio_firmas&id=${Uri.encodeComponent((c['id'] ?? '').toString())}');
    if (d['ok'] != true) {
      _aviso('${d['error']}', ok: false);
      return;
    }
    final firmados = ((d['firmados'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final pendientes = ((d['pendientes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${d['titulo']}',
            style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 520,
          height: 440,
          child: ListView(
            children: [
              Text('FIRMARON (${firmados.length})',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E8E3E))),
              for (final f in firmados)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('✓ ${f['alumno']} (${f['matricula']}) · ${f['fecha']}',
                      style: const TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: 12),
              Text('PENDIENTES (${pendientes.length})',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cessumGold)),
              for (final f in pendientes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('• ${f['alumno']} (${f['matricula']})',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                ),
            ],
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

  /// (ago-12) PANTALLA EDITABLE ANTES DEL PDF. El usuario necesita quitar
  /// cláusulas o corregir redacción antes de imprimir, sin que eso altere el
  /// convenio que el alumno ya firmó. Por eso el guardado es una decisión
  /// aparte: por omisión el PDF se genera con el texto editado y el convenio
  /// original se queda como está.
  Future<void> _revisarYExportar(Map<String, dynamic> c) async {
    final id = '${c['id'] ?? ''}';
    Map<String, dynamic> info = {};
    try {
      info = await _get('accion=convenio_texto_pdf&id=${Uri.encodeComponent(id)}');
    } catch (e) {
      _aviso('No pude cargar el texto: $e');
      return;
    }
    if (!mounted) return;
    if (info['ok'] != true) {
      _aviso('${info['error'] ?? 'No se pudo cargar'}');
      return;
    }
    final titulo = TextEditingController(text: '${info['titulo'] ?? ''}');
    final texto = TextEditingController(text: '${info['terminos'] ?? ''}');
    final firmas = _n(info['firmasAlumno']);
    final aviso = '${info['aviso'] ?? ''}';
    var guardar = false;
    var trabajando = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Revisar antes de exportar',
              style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (aviso.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFBF6EE),
                          border: Border.all(color: CC.goldBorder),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(aviso,
                          style: const TextStyle(
                              fontSize: 11.5, height: 1.35)),
                    )
                  else
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFEFF7EF),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(
                          '✓ Firmado por $firmas alumno(s) y '
                          '${_n(info['firmasInstitucionales'])} firma(s) '
                          'institucional(es). El PDF los incluye con el sello.',
                          style: const TextStyle(
                              fontSize: 11.5, height: 1.35)),
                    ),
                  TextField(
                    controller: titulo,
                    decoration: const InputDecoration(
                        labelText: 'Título del documento',
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: texto,
                    maxLines: 18,
                    style: const TextStyle(fontSize: 12.5, height: 1.4),
                    decoration: const InputDecoration(
                      labelText: 'Texto del convenio',
                      helperText:
                          'Quita o corrige lo que necesites. El PDF sale con '
                          'esto tal cual, respetando los saltos de línea.',
                      helperMaxLines: 2,
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    value: guardar,
                    onChanged: trabajando
                        ? null
                        : (v) => setSt(() => guardar = v ?? false),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                        'Guardar también estos cambios en el convenio',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: guardar
                            ? const Color(0xFFFDE7E7)
                            : const Color(0xFFF4F2ED),
                        border: Border.all(
                            color: guardar
                                ? const Color(0xFFE0A6A6)
                                : Colors.black12),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        guardar
                            ? '⚠ El convenio guardado cambiará. Ojo si ya lo '
                                'firmaron: el documento que aceptó el alumno '
                                'dejaría de coincidir con el que está en el '
                                'sistema.'
                            : 'El convenio guardado NO se modifica. Solo el '
                                'PDF que se genera ahora sale con tus '
                                'cambios.',
                        style: const TextStyle(fontSize: 11.5, height: 1.35)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: trabajando ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: trabajando
                  ? null
                  : () async {
                      setSt(() => trabajando = true);
                      final body = <String, dynamic>{
                        'accion': 'convenio_pdf',
                        'id': id,
                        'titulo': titulo.text.trim(),
                        'terminos': texto.text,
                        'actor': _miCorreo,
                        if (guardar) 'guardar': '1',
                      };
                      try {
                        final r = await _post(body);
                        if (r['ok'] != true) {
                          setSt(() => trabajando = false);
                          _aviso('${r['error'] ?? 'No se pudo generar'}');
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        final url = '${r['pdfUrl'] ?? ''}';
                        if (url.startsWith('http') && mounted) {
                          Helpers.abrirUrlExterna(url, context);
                        }
                        // Si se pidió guardar y no se logró, hay que decirlo:
                        // dar por guardado algo que falló es peor que no
                        // haberlo ofrecido.
                        final errG = '${r['guardadoError'] ?? ''}';
                        if (guardar && r['guardadoEnConvenio'] != true) {
                          _aviso('PDF generado, pero NO se guardó en el '
                              'convenio${errG.isNotEmpty ? ': $errG' : '.'}');
                        } else {
                          _aviso('PDF generado con ${_n(r['firmasAlumno'])} '
                              'firma(s) de alumno'
                              '${r['selloIncluido'] == true ? ' y sello' : ''}'
                              '${guardar ? ' · convenio actualizado' : ''}.');
                        }
                      } catch (e) {
                        setSt(() => trabajando = false);
                        _aviso('$e');
                      }
                    },
              icon: trabajando
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf, size: 17),
              label: const Text('Generar PDF'),
            ),
          ],
        ),
      ),
    );
    titulo.dispose();
    texto.dispose();
  }

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  Future<void> _vistaPrevia(Map<String, dynamic> c) async {
    Map<String, dynamic>? full;
    try {
      final r = await _get('accion=convenio_texto&id=${Uri.encodeComponent((c['id'] ?? '').toString())}');
      if (r['ok'] == true) full = r;
    } catch (_) {}
    if (!mounted) return;
    _dialogoDocumento(
      titulo: '${c['titulo']}',
      terminos: (full?['terminos'] ??
              '(no pude cargar el texto — verifica que el Code.gs publicado sea el último)')
          .toString(),
      firmas: (((full?['firmantesInst'] as List?) ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      pie: 'Así lo verá el firmante antes de aceptar.',
    );
  }

  // (ago-3) Documento pergamino reutilizable: lo usan la vista previa de
  // convenios YA creados y la vista previa del BORRADOR antes de crear.
  void _dialogoDocumento({
    required String titulo,
    required String terminos,
    required List<Map<String, dynamic>> firmas,
    required String pie,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
          child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                color: cessumRed,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8)),
                  child: Image.asset('assets/images/logo.png',
                      height: 26,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.school,
                          color: cessumRed,
                          size: 26)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon:
                        const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: const Color(0xFFFAF8F5),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        terminos,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.6,
                            fontFamily: 'serif'),
                      ),
                      if (firmas.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        const Divider(),
                        const Text('F I R M A S',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                fontFamily: 'serif')),
                        const SizedBox(height: 10),
                        for (final fi in firmas)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                if (fi['firmado'] == true &&
                                    '${fi['firmaUrl']}'.isNotEmpty)
                                  Image.network('${fi['firmaUrl']}',
                                      height: 46,
                                      errorBuilder: (_, __, ___) =>
                                          const SizedBox(height: 8)),
                                Container(
                                    width: 240,
                                    height: 1,
                                    color: Colors.black54),
                                Text('${fi['nombre']}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'serif')),
                                Text('${fi['cargo']}',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontFamily: 'serif')),
                                Text(
                                    fi['firmado'] == true
                                        ? 'Firmado el ${fi['fecha']}'
                                        : 'Pendiente de firma',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontStyle: FontStyle.italic,
                                        color: fi['firmado'] == true
                                            ? const Color(0xFF1E8E3E)
                                            : const Color(0xFFE65100))),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              child: Text(pie,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.black45)),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _verObservaciones(Map<String, dynamic> c) async {
    final d = await _get(
        'accion=convenio_observaciones&id=${Uri.encodeComponent((c['id'] ?? '').toString())}');
    if (d['ok'] != true) {
      _aviso('${d['error']}', ok: false);
      return;
    }
    final obs = ((d['observaciones'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    // agrupar por matrícula (un hilo por alumno)
    final hilos = <String, List<Map<String, dynamic>>>{};
    for (final o in obs) {
      hilos.putIfAbsent((o['matricula'] ?? '').toString(), () => []).add(o);
    }
    if (!mounted) return;
    if (hilos.isEmpty) {
      _aviso('Sin observaciones de firmantes todavía.');
      return;
    }
    final mat = hilos.length == 1
        ? hilos.keys.first
        : await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Hilos de observaciones'),
              children: [
                for (final k in hilos.keys)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, k),
                    child: Text(
                        '${hilos[k]!.first['nombre'] ?? ''} ($k) · ${hilos[k]!.length} mensaje(s)',
                        style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          );
    if (mat == null || !mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => _ChatObservacionesAdmin(
        convenioId: (c['id'] ?? '').toString(),
        titulo: (c['titulo'] ?? '').toString(),
        matricula: mat,
      ),
    );
  }

  Future<void> _editarConvenio(Map<String, dynamic> c) async {
    Map<String, dynamic>? full;
    try {
      final r = await _get(
          'accion=convenio_texto&id=${Uri.encodeComponent((c['id'] ?? '').toString())}');
      if (r['ok'] == true) full = r;
    } catch (_) {}
    if (!mounted) return;
    final titulo =
        TextEditingController(text: (c['titulo'] ?? '').toString());
    final terminos =
        TextEditingController(text: (full?['terminos'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar convenio (nueva versión)'),
        content: SizedBox(
          width: 600,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: titulo,
                decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 10),
            Expanded(
              child: TextField(
                  controller: terminos,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                      labelText: 'Términos (versión final)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder())),
            ),
            const SizedBox(height: 6),
            const Text(
                'Quien ya firmó conserva en su constancia el texto que '
                'aceptó; quienes falten firmarán esta versión.',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar versión')),
        ],
      ),
    );
    if (ok != true) return;
    final d = await _post({
      'accion': 'convenio_editar',
      'id': (c['id'] ?? '').toString(),
      'titulo': titulo.text.trim(),
      'terminos': terminos.text.trim(),
    });
    if (d['ok'] == true) {
      _aviso('Convenio actualizado a la nueva versión.');
      _cargar();
    } else {
      _aviso('${d['error']}', ok: false);
    }
  }

  Future<void> _cerrar(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar convenio'),
        content: Text('¿Cerrar "${c['titulo']}"? Ya no aparecerá a los '
            'alumnos ni aceptará firmas (las recibidas se conservan).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, cerrar')),
        ],
      ),
    );
    if (ok != true) return;
    final d = await _post({
      'accion': 'convenio_cerrar',
      'id': (c['id'] ?? '').toString(),
    });
    if (d['ok'] == true) {
      _aviso('Convenio cerrado.');
      _cargar();
    } else {
      _aviso('${d['error']}', ok: false);
    }
  }

  // (29-sep) Solicitudes de convenio de pago enviadas por alumnos — se
  // revisan abriendo el mismo asistente de convenios (ConvenioPagoScreen),
  // ya prellenado con su matrícula y su mensaje: no hay una pantalla de
  // "aceptar" aparte, es el mismo flujo de crear convenio de siempre.
  Widget _seccionSolicitudes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.inbox_outlined, size: 18, color: cessumRed),
          const SizedBox(width: 6),
          Text('Solicitudes de alumnos (${_solicitudes.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        for (final s in _solicitudes) _tarjetaSolicitud(s),
      ],
    );
  }

  Widget _tarjetaSolicitud(Map<String, dynamic> s) {
    final snap = Map<String, dynamic>.from(s['adeudoSnapshot'] as Map? ?? {});
    final total = (snap['total'] ?? 0).toString();
    final estado = '${s['estado'] ?? 'Pendiente'}';
    final acordado = estado == 'Acordado';
    final esContrapropuestaAdmin = estado == 'Contrapropuesta admin';
    final prop = Map<String, dynamic>.from(s['propuestaActual'] as Map? ?? {});
    final tieneProp = (prop['montoPorPago'] ?? 0) > 0;
    // (2-oct-2026) Informe financiero real, guardado al momento de la
    // solicitud. Es un snapshot (puede haber cambiado desde entonces) — se
    // muestra como referencia rápida; el dato fresco se recalcula al abrir
    // el asistente ("Revisar y armar").
    final inf = Map<String, dynamic>.from(s['informeFinanciero'] as Map? ?? {});
    final infCalculable = inf['calculable'] == true;

    Color colorEstado;
    switch (estado) {
      case 'Acordado': colorEstado = const Color(0xFF1E7B34); break;
      case 'Contrapropuesta admin': colorEstado = const Color(0xFF1565C0); break;
      default: colorEstado = cessumGold;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colorEstado.withValues(alpha: 0.4))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text('${s['nombre']}  ·  ${s['matricula']}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: colorEstado.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(estado, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: colorEstado)),
              ),
            ]),
            Text('${s['programa']} ${s['generacion']}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 6),
            Text('"${s['mensaje']}"',
                style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            // Propuesta vigente, estructurada — quien la hizo al último.
            if (tieneProp)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: colorEstado.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      (prop['quien'] == 'admin' ? 'Tu propuesta: ' : 'Propone: ') +
                          '${prop['numeroPagos']} pago(s) de \$${(prop['montoPorPago'] as num).toStringAsFixed(2)}'
                          ' (total \$${(prop['montoTotal'] as num? ?? 0).toStringAsFixed(2)})'
                          '${(prop['fechaInicio'] ?? '').toString().isNotEmpty ? ', desde ${prop['fechaInicio']}' : ''}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  if ((prop['comentario'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('${prop['comentario']}', style: const TextStyle(fontSize: 11.5)),
                    ),
                ]),
              )
            else
              Text(
                  'Pide ${s['pagosDeseados'] ?? '?'} pago(s), desde ${s['fechaInicioDeseada'] ?? 'lo antes posible'}',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 6),
            // Adeudo manual (Vencimientos) e informe financiero real, lado a lado.
            Wrap(spacing: 10, runSpacing: 4, children: [
              Text('Adeudo (Vencimientos): \$$total', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cessumRed)),
              Text(
                  infCalculable
                      ? 'Informe financiero: \$${(inf['adeudoCalculado'] as num? ?? 0).toStringAsFixed(2)} (${inf['materiasFaltantes'] ?? 0}/${inf['materiasExigibles'] ?? 0} materias)'
                      : 'Informe financiero: no calculable',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1565C0))),
            ]),
            Text('enviada ${s['fechaSolicitud']}', style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (!acordado)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                  onPressed: () => _rechazarSolicitud(s),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Rechazar'),
                ),
              if (!acordado && !esContrapropuestaAdmin)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1565C0)),
                  onPressed: () => _contraproponerSolicitud(s),
                  icon: const Icon(Icons.forum_outlined, size: 16),
                  label: const Text('Contraproponer'),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: acordado ? const Color(0xFF1E7B34) : cessumRed),
                onPressed: () => _revisarSolicitud(s),
                icon: Icon(acordado ? Icons.task_alt : Icons.open_in_new, size: 16),
                label: Text(acordado ? 'Formalizar convenio' : 'Revisar y armar convenio'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _revisarSolicitud(Map<String, dynamic> s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConvenioPagoScreen(
          matriculaInicial: '${s['matricula']}',
          solicitudId: '${s['id']}',
          mensajeInicial: '${s['mensaje']}',
        ),
      ),
    );
    _cargar();
  }

  Future<void> _rechazarSolicitud(Map<String, dynamic> s) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se le avisará a ${s['nombre']} por qué no procede así.',
                style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 10),
            TextField(
              controller: motivo,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                  hintText: 'Motivo que verá el alumno…',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () {
              if (motivo.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final d = await _post({
      'accion': 'convenio_solicitud_rechazar',
      'id': s['id'],
      'motivo': motivo.text.trim(),
      'actor': _miCorreo,
    });
    if (d['ok'] == true) {
      _aviso('Solicitud rechazada; se avisó al alumno.');
      _cargar();
    } else {
      _aviso('${d['error'] ?? 'No se pudo rechazar.'}', ok: false);
    }
  }

  // (2-oct-2026) PANEL ESTRUCTURADO DE NEGOCIACIÓN — en vez de solo
  // "Rechazar" o "Revisar y armar desde cero", el admin puede devolver una
  // contrapropuesta concreta sin perder la solicitud. El alumno la ve en su
  // pantalla y decide: aceptarla tal cual (pasa a "Acordado", listo para
  // formalizar) o proponer otra cosa (vuelve a "Pendiente").
  Future<void> _contraproponerSolicitud(Map<String, dynamic> s) async {
    final montoCtrl = TextEditingController();
    final pagosCtrl = TextEditingController(text: '3');
    final fechaCtrl = TextEditingController();
    final comentarioCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Contraproponer a ${s['nombre']}', style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pedía: ${s['pagosDeseados'] ?? '—'} pago(s), desde ${s['fechaInicioDeseada'] ?? '—'}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              const SizedBox(height: 10),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto por pago', prefixText: '\$ ', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pagosCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Número de pagos', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: fechaCtrl,
                decoration: const InputDecoration(labelText: 'Fecha de inicio (opcional)', hintText: 'Ej. 15 de octubre', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: comentarioCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Comentario para el alumno (opcional)', isDense: true, border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1565C0)),
            onPressed: () {
              final m = double.tryParse(montoCtrl.text.trim()) ?? 0;
              if (m <= 0) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Enviar contrapropuesta'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final d = await _post({
      'accion': 'convenio_solicitud_contraproponer',
      'id': s['id'],
      'montoPorPago': montoCtrl.text.trim(),
      'numeroPagos': pagosCtrl.text.trim(),
      'fechaInicio': fechaCtrl.text.trim(),
      'comentario': comentarioCtrl.text.trim(),
      'actor': _miCorreo,
    });
    if (d['ok'] == true) {
      _aviso('Contrapropuesta enviada al alumno.');
      _cargar();
    } else {
      _aviso('${d['error'] ?? 'No se pudo enviar la contrapropuesta.'}', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Convenios',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _elegirTipoYCrear,
        icon: const Icon(Icons.post_add),
        label: const Text('Nuevo convenio'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      if (_solicitudes.isNotEmpty) ...[
                        _seccionSolicitudes(),
                        const Divider(height: 28),
                      ],
                      if (_convenios.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                              'Aún no hay convenios. Crea el primero con '
                              'el botón de abajo.',
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.black54)),
                        ),
                      for (final c in _convenios) _tarjeta(c),
                    ],
                  ),
                ),
    );
  }

  String _miCargoPendiente(Map<String, dynamic> c) {
    final pend = ((c['instPendientes'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    if (pend.isEmpty || _miCorreo.isEmpty) return '';
    for (final fc in _catFirmantes) {
      if ((fc['correo'] ?? '').toString().toLowerCase() == _miCorreo &&
          pend.contains((fc['cargo'] ?? '').toString())) {
        return (fc['cargo'] ?? '').toString();
      }
    }
    return '';
  }

  Future<void> _firmarInst(Map<String, dynamic> c, String cargo) async {
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Firmar convenio'),
        content: Text(
            'Vas a estampar la firma de "$cargo" en el convenio '
            '"${c['titulo']}". ¿Confirmas?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Firmar')),
        ],
      ),
    );
    if (conf != true) return;
    final d = await _post({
      'accion': 'convenio_firmar_inst',
      'convenioId': (c['id'] ?? '').toString(),
      'correo': _miCorreo,
    });
    if (d['ok'] == true) {
      _aviso(
          'Firmado como $cargo (${d['firmadasInst']}/${d['totalInst']} institucionales).');
      _cargar();
    } else {
      _aviso('${d['error']}', ok: false);
    }
  }

  // (ago-3) ACUERDOS DEL CONVENIO: compromisos con fecha, responsable y
  // semáforo; recordatorios automáticos (7 días antes, el día, vencidos).
  Future<void> _verAcuerdos(Map<String, dynamic> c) async {
    final id = (c['id'] ?? '').toString();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setLocal) => AlertDialog(
          title: Text('Acuerdos · ${c['titulo']}',
              style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 520,
            height: 400,
            child: FutureBuilder<Map<String, dynamic>>(
              future: _get('accion=convenio_acuerdos&id=$id'),
              builder: (ctx3, snap) {
                if (!snap.hasData) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: cessumRed));
                }
                final acs = ((snap.data!['acuerdos'] as List?) ?? [])
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
                return Column(children: [
                  Expanded(
                    child: acs.isEmpty
                        ? const Center(
                            child: Text(
                                'Sin acuerdos registrados todavía.',
                                style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12)))
                        : ListView(children: [
                            for (final a in acs)
                              _acuerdoTile(a, setLocal, () {
                                Navigator.pop(ctx2);
                                _verAcuerdos(c);
                              }),
                          ]),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: cessumGold,
                            side: const BorderSide(color: cessumGold)),
                        onPressed: () async {
                          final d = await _get(
                              'accion=convenio_acuerdos_extraer&id=$id&aplicar=1',
                              seg: 60);
                          if (!ctx2.mounted) return;
                          if (d['ok'] == true) {
                            _aviso(
                                'Extraídos del texto: ${d['registrados']} nuevos'
                                '${(d['yaExistian'] ?? 0) != 0 ? ' (${d['yaExistian']} ya estaban)' : ''}.');
                            Navigator.pop(ctx2);
                            _verAcuerdos(c);
                          } else {
                            _aviso('${d['error']}', ok: false);
                          }
                        },
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text('Extraer del texto',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx2);
                          await _agregarAcuerdo(c);
                          _verAcuerdos(c);
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar',
                            style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  ]),
                ]);
              },
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('Cerrar')),
          ],
        ),
      ),
    );
  }

  Widget _acuerdoTile(Map<String, dynamic> a, void Function(void Function()) setLocal, VoidCallback recargar) {
    final sem = (a['semaforo'] ?? '').toString();
    final color = sem == 'rojo'
        ? cessumRed
        : sem == 'ambar'
            ? cessumGold
            : sem == 'verde'
                ? const Color(0xFF1E8E3E)
                : Colors.black38;
    final cumplido = (a['estado'] ?? '') == 'Cumplido';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a['acuerdo']}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        decoration: cumplido
                            ? TextDecoration.lineThrough
                            : null)),
                Text(
                    '${a['responsable'] == 'alumno' ? '🎓 Alumno' : '🏛 Institución'} · ${a['fecha']}'
                    '${cumplido ? ' · ✓ cumplido el ${a['fechaCumplido']}' : a['diasRestantes'] == null ? '' : (a['diasRestantes'] as num) < 0 ? ' · VENCIDO hace ${-(a['diasRestantes'] as num)} día(s)' : ' · faltan ${a['diasRestantes']} día(s)'}',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
          ),
          if (!cumplido)
            IconButton(
              tooltip: 'Marcar cumplido',
              icon: const Icon(Icons.check_circle_outline,
                  size: 20, color: Color(0xFF1E8E3E)),
              onPressed: () async {
                final quien = await SessionStore.validEmail();
                final d = await _post({
                  'accion': 'convenio_acuerdo_cumplir',
                  'fila': a['fila'],
                  'actor': quien ?? '',
                });
                if (d['ok'] == true) setLocal(() => a['estado'] = 'Cumplido');
              },
            ),
          IconButton(
            tooltip: 'Borrar acuerdo',
            icon: const Icon(Icons.delete_outline,
                size: 19, color: Colors.black38),
            onPressed: () async {
              final d = await _get(
                  'accion=convenio_acuerdo_borrar&fila=${a['fila']}');
              if (d['ok'] == true) {
                _aviso('Acuerdo borrado.');
                recargar(); // filas se recorren: recargar evita borrar otra por error
              } else {
                _aviso('${d['error']}', ok: false);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _agregarAcuerdo(Map<String, dynamic> c) async {
    final texto = TextEditingController();
    final fecha = TextEditingController();
    var resp = 'institucion';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setLocal) => AlertDialog(
          title: const Text('Nuevo acuerdo'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: texto,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Compromiso acordado *',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                  controller: fecha,
                  decoration: const InputDecoration(
                      labelText: 'Fecha compromiso (dd/mm/aaaa)',
                      helperText:
                          'Con fecha hay recordatorios: 7 días antes, el día y si vence.',
                      border: OutlineInputBorder(),
                      isDense: true)),
              const SizedBox(height: 10),
              Row(children: [
                const Text('Responsable: ',
                    style: TextStyle(fontSize: 12)),
                ChoiceChip(
                  label: const Text('🏛 Institución',
                      style: TextStyle(fontSize: 11.5)),
                  selected: resp == 'institucion',
                  onSelected: (_) =>
                      setLocal(() => resp = 'institucion'),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('🎓 Alumno',
                      style: TextStyle(fontSize: 11.5)),
                  selected: resp == 'alumno',
                  onSelected: (_) => setLocal(() => resp = 'alumno'),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx2, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || texto.text.trim().isEmpty) return;
    final quien = await SessionStore.validEmail();
    await _post({
      'accion': 'convenio_acuerdo_crear',
      'convenioId': (c['id'] ?? '').toString(),
      'acuerdo': texto.text.trim(),
      'responsable': resp,
      'fecha': fecha.text.trim(),
      'actor': quien ?? '',
    });
  }

  Widget _tarjeta(Map<String, dynamic> c) {
    final activo = (c['estado'] ?? '') == 'Activo';
    final objetivo = (c['objetivo'] ?? 0) as num;
    final firmados = (c['firmados'] ?? 0) as num;
    final avance = objetivo > 0 ? firmados / objetivo : 0.0;
    final instTotal = (c['instTotal'] ?? 0) as num;
    final instFirmadas = (c['instFirmadas'] ?? 0) as num;
    final miCargo = activo ? _miCargoPendiente(c) : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: activo
                ? cessumRed.withValues(alpha: 0.35)
                : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${c['titulo']}',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                  color: (activo
                          ? const Color(0xFF1E8E3E)
                          : Colors.black38)
                      .withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${c['estado']}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: activo
                          ? const Color(0xFF1E8E3E)
                          : Colors.black45)),
            ),
          ]),
          Text(
            'Dirigido a: ${c['programa']}'
            '${(c['generacion'] ?? '').toString().isNotEmpty ? ' · ${c['generacion']}' : ''}'
            '${(c['grupo'] ?? '').toString().isNotEmpty ? ' · ${c['grupo']}' : ''}'
            ' · creado el ${c['fecha']}',
            style: const TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
          if (instTotal > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                  '🖋 Firmas institucionales: $instFirmadas de $instTotal'
                  '${instFirmadas >= instTotal ? ' ✓ completas' : ''}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: instFirmadas >= instTotal
                          ? const Color(0xFF1E8E3E)
                          : cessumGold)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: avance.toDouble(),
                  minHeight: 8,
                  backgroundColor: Colors.black12,
                  color: const Color(0xFF1E8E3E),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('$firmados / $objetivo firmas',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (activo)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed),
                    visualDensity: VisualDensity.compact),
                onPressed: () => _promover(c),
                icon: const Icon(Icons.campaign, size: 16),
                label: const Text('Promover',
                    style: TextStyle(fontSize: 12)),
              ),
            if (miCargo.isNotEmpty)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8E3E),
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _firmarInst(c, miCargo),
                icon: const Icon(Icons.draw, size: 16),
                label: Text('Firmar como $miCargo',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              onPressed: () => _verFirmas(c),
              icon: const Icon(Icons.fact_check, size: 16),
              label: const Text('Ver firmas',
                  style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              onPressed: () => _verAcuerdos(c),
              icon: const Icon(Icons.event_note, size: 16),
              label: const Text('Acuerdos',
                  style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
              onPressed: () => _vistaPrevia(c),
              icon: const Icon(Icons.visibility, size: 16),
              label: const Text('Vista previa',
                  style: TextStyle(fontSize: 12)),
            ),
            // (ago-12) Antes de exportar, se revisa y se edita. El PDF sale
            // con lo que quede en pantalla.
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed),
                  visualDensity: VisualDensity.compact),
              onPressed: () => _revisarYExportar(c),
              icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('Revisar y exportar PDF',
                  style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumGold,
                  side: const BorderSide(color: cessumGold),
                  visualDensity: VisualDensity.compact),
              onPressed: () => _verObservaciones(c),
              icon: const Icon(Icons.forum, size: 16),
              label: const Text('Observaciones',
                  style: TextStyle(fontSize: 12)),
            ),
            if (activo)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () => _editarConvenio(c),
                icon: const Icon(Icons.edit_document, size: 16),
                label: const Text('Editar',
                    style: TextStyle(fontSize: 12)),
              ),
            if (activo)
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: Colors.black45,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _cerrar(c),
                icon: const Icon(Icons.lock, size: 16),
                label:
                    const Text('Cerrar', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ],
      ),
    );
  }
}

/// Hilo de observaciones (lado institución): responder al alumno.
class _ChatObservacionesAdmin extends StatefulWidget {
  final String convenioId;
  final String titulo;
  final String matricula;
  const _ChatObservacionesAdmin(
      {required this.convenioId,
      required this.titulo,
      required this.matricula});

  @override
  State<_ChatObservacionesAdmin> createState() =>
      _ChatObservacionesAdminState();
}

class _ChatObservacionesAdminState extends State<_ChatObservacionesAdmin> {
  bool _cargando = true;
  bool _enviando = false;
  List<Map<String, dynamic>> _msgs = [];
  final _txt = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _txt.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'convenio_observaciones',
            'id': widget.convenioId,
            'matricula': widget.matricula,
          }))
          .timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _msgs = ((d['observaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _enviar() async {
    final m = _txt.text.trim();
    if (m.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'convenio_observacion',
                'convenioId': widget.convenioId,
                'matricula': widget.matricula,
                'autor': 'institucion',
                'nombre': 'Vicerrectoría Académica',
                'mensaje': m,
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        _txt.clear();
        await _cargar();
      }
    } catch (_) {}
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: cessumRed,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.forum, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Observaciones · ${widget.matricula} · ${widget.titulo}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close,
                      color: Colors.white, size: 20)),
            ]),
          ),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [for (final m in _msgs) _burbuja(m)],
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border:
                  Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _txt,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Responder como Vicerrectoría…',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: cessumRed,
                child: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : IconButton(
                        onPressed: _enviar,
                        icon: const Icon(Icons.send,
                            color: Colors.white, size: 18)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _burbuja(Map<String, dynamic> m) {
    final esInst = (m['autor'] ?? '') == 'institucion';
    final color = esInst ? cessumRed : cessumGold;
    return Align(
      alignment: esInst ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              esInst
                  ? '🏛 ${(m['nombre'] ?? '').toString().isEmpty ? 'Institución' : m['nombre']}'
                  : '🎓 ${(m['nombre'] ?? '').toString().isEmpty ? 'Alumno(a)' : m['nombre']} · ${m['matricula']}',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: color),
            ),
            Text('${m['mensaje']}',
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
            Text('${m['fecha']}',
                style:
                    const TextStyle(fontSize: 9.5, color: Colors.black38)),
          ],
        ),
      ),
    );
  }
}

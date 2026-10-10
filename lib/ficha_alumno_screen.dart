import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'mi_pagos_screen.dart';

/// Ficha 360 del alumno (admin): por matrícula reúne identidad,
/// calificaciones, trámites, incidencias, justificaciones y accesos.
class FichaAlumnoScreen extends StatefulWidget {
  const FichaAlumnoScreen({super.key});

  @override
  State<FichaAlumnoScreen> createState() => _FichaAlumnoScreenState();
}

class _FichaAlumnoScreenState extends State<FichaAlumnoScreen> {
  final _matCtrl = TextEditingController();
  Map<String, dynamic>? _ficha;
  bool _cargando = false;
  bool _generandoKardex = false;
  String? _error;

  @override
  void dispose() {
    _matCtrl.dispose();
    super.dispose();
  }

  Future<void> _descargarKardex() async {
    final mat = (_ficha?['matricula'] ?? '').toString();
    if (mat.isEmpty || _generandoKardex) return;

    // Si el alumno tiene más de un programa (p. ej. maestría y doctorado),
    // preguntamos de cuál generar el kardex.
    final programa = await _elegirProgramaParaDoc(mat);
    if (programa == null) return; // canceló

    setState(() => _generandoKardex = true);
    try {
      var url =
          '$guardianUrl?accion=kardex_alumno&matricula=${Uri.encodeComponent(mat)}';
      if (programa.isNotEmpty) {
        url += '&programa=${Uri.encodeComponent(programa)}';
      }
      final uri = Uri.parse(url);
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && (data['pdf'] ?? '').toString().isNotEmpty) {
        if (!mounted) return;
        await Helpers.abrirUrlExterna((data['pdf'] ?? '') as String, context);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo generar el kardex: '
                '${data['error'] ?? 'sin calificaciones validadas'}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo conectar con el sistema.')));
    } finally {
      if (mounted) setState(() => _generandoKardex = false);
    }
  }

  /// Devuelve el programa elegido para el documento:
  ///  - ''   => generar con todos / programa único (sin filtro)
  ///  - texto => generar solo ese programa
  ///  - null  => el usuario canceló
  Future<String?> _elegirProgramaParaDoc(String mat) async {
    List<Map<String, String>> progs = [];
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=alumno_programas&matricula=${Uri.encodeComponent(mat)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        progs = ((data['programas'] as List<dynamic>? ?? [])).map((e) {
          final m = e as Map<String, dynamic>;
          return {
            'programa': (m['programa'] ?? '').toString(),
            'generacion': (m['generacion'] ?? '').toString(),
          };
        }).where((m) => (m['programa'] ?? '').isNotEmpty).toList();
      }
    } catch (_) {}

    // 0 o 1 programa: no preguntamos, se genera normal.
    if (progs.length <= 1) return '';

    if (!mounted) return null;
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿De qué programa?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                  'Este alumno tiene más de un programa. Elige cuál incluir.',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
            ),
            for (final p in progs)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx, p['programa']),
                  child: Text(
                    p['generacion']!.isNotEmpty
                        ? '${p['programa']}  ·  Gen. ${p['generacion']}'
                        : p['programa']!,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Todos (historial completo)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancelar')),
        ],
      ),
    );
  }

  Future<void> _buscar() async {
    final q = _matCtrl.text.trim();
    if (q.isEmpty) return;
    // Si son puros dígitos, es matrícula → ficha directa.
    // Si trae letras, es nombre → buscamos coincidencias.
    final esMatricula = RegExp(r'^\d{4,}$').hasMatch(q);
    if (esMatricula) {
      _cargarFicha(q);
      return;
    }
    if (q.length < 2) {
      setState(() => _error = 'Escribe al menos 2 letras del nombre.');
      return;
    }
    setState(() {
      _cargando = true;
      _error = null;
      _ficha = null;
    });
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=buscar_alumno&q=${Uri.encodeComponent(q)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final res = ((data['resultados'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      if (res.isEmpty) {
        setState(() {
          _cargando = false;
          _error = 'Sin coincidencias para "$q".';
        });
        return;
      }
      if (res.length == 1) {
        _cargarFicha('${res.first['matricula']}');
        return;
      }
      // Varias coincidencias: que elija.
      setState(() => _cargando = false);
      final sel = await _elegirCoincidencia(res);
      if (sel != null && sel.isNotEmpty) _cargarFicha(sel);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo buscar: $e';
      });
    }
  }

  Future<String?> _elegirCoincidencia(List<Map<String, dynamic>> res) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${res.length} coincidencias',
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 360,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: res.length,
            itemBuilder: (c, i) {
              final a = res[i];
              final baja = a['baja'] == true;
              return ListTile(
                dense: true,
                title: Text('${a['nombre']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  'Matrícula ${a['matricula']}'
                  '${(a['programa'] ?? '').toString().isNotEmpty ? ' · ${a['programa']}' : ''}'
                  '${baja ? ' · BAJA' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                onTap: () => Navigator.pop(ctx, '${a['matricula']}'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
        ],
      ),
    );
  }

  Future<void> _cargarFicha(String mat) async {
    if (mat.isEmpty) return;
    setState(() {
      _cargando = true;
      _error = null;
      _ficha = null;
    });
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=ficha_alumno&matricula=${Uri.encodeComponent(mat)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se encontró la ficha.');
      }
      if (!mounted) return;
      setState(() {
        _ficha = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar: $e';
      });
    }
  }

  Widget _accionMini(IconData icono, String texto, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icono, size: 16, color: cessumRed),
      label: Text(texto, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Future<void> _buscarPorNombre() async {
    final sel = await showDialog<String>(
      context: context,
      builder: (_) => const _BuscadorNombreDialog(),
    );
    if (sel != null && sel.isNotEmpty) {
      _matCtrl.text = sel;
      _buscar();
    }
  }

  Color _colorEstatus(String e) {
    switch (e) {
      case 'Validada':
      case 'Atendido':
      case 'Resuelta':
      case 'Aprobada':
        return Colors.green.shade700;
      case 'Rechazado':
      case 'Rechazada':
        return cessumRed;
      default:
        return cessumGold;
    }
  }

  Widget _chip(String texto) {
    final c = _colorEstatus(texto);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(texto.isEmpty ? 'Pendiente' : texto,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Widget _seccion(String titulo, int cuantos, List<Widget> hijos) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ExpansionTile(
        title: Text('$titulo ($cuantos)',
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: hijos.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Sin registros.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.black45)),
                )
              ]
            : hijos,
      ),
    );
  }

  Widget _fila(String izq, String der, {Widget? chip}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(izq,
                style: const TextStyle(fontSize: 12.5, height: 1.35)),
          ),
          if (der.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(der,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          if (chip != null)
            Padding(padding: const EdgeInsets.only(left: 8), child: chip),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _ficha;
    final cals = (f?['calificaciones'] as List?) ?? [];
    final tras = (f?['tramites'] as List?) ?? [];
    final incs = (f?['incidencias'] as List?) ?? [];
    final justs = (f?['justificaciones'] as List?) ?? [];
    final accs = (f?['accesos'] as List?) ?? [];
    final titu = f?['titulacion'] as Map<String, dynamic>?;
    final riesgo = f?['riesgo'] as Map<String, dynamic>?;
    final pagos = (f?['pagos'] as List?) ?? [];
    final moodle = f?['moodle'] as Map<String, dynamic>?;
    final mInsc = (moodle?['inscripciones'] as List?) ?? [];
    final mTar = (moodle?['tareas'] as List?) ?? [];
    final mAct = moodle?['actividad'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Ficha del alumno',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Buscar por nombre',
            icon: const Icon(Icons.person_search),
            onPressed: _buscarPorNombre,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _matCtrl,
                  keyboardType: TextInputType.text,
                  onSubmitted: (_) => _buscar(),
                  decoration: const InputDecoration(
                    labelText: 'Matrícula o nombre del alumno',
                    hintText: 'Ej. 25070354 o "María José"',
                    border: OutlineInputBorder(),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                onPressed: _cargando ? null : _buscar,
                icon: _cargando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search, size: 18),
                label: const Text('Buscar'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: cessumRed)),
          if (f != null) ...[
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (f['nombre'] ?? 'Sin nombre en base') as String,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Matrícula ${f['matricula']}'
                      '${((f['correo'] ?? '') as String).isNotEmpty ? ' · ${f['correo']}' : ''}',
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _accionMini(Icons.copy, 'Matrícula',
                            () => Helpers.copiarAlPortapapeles(
                                context, '${f['matricula']}', 'Matrícula')),
                        if (((f['correo'] ?? '') as String).isNotEmpty) ...[
                          _accionMini(Icons.copy, 'Correo',
                              () => Helpers.copiarAlPortapapeles(
                                  context, '${f['correo']}', 'Correo')),
                          _accionMini(Icons.email, 'Enviar correo',
                              () => Helpers.abrirCorreo(
                                    context: context,
                                    destinatario: '${f['correo']}',
                                    asunto: 'CESSUM',
                                    cuerpo: '',
                                  )),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _generandoKardex ? null : _descargarKardex,
                style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: BorderSide(color: cessumRed.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: _generandoKardex
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cessumRed))
                    : const Icon(Icons.picture_as_pdf),
                label: Text(_generandoKardex
                    ? 'Generando kardex...'
                    : 'Descargar kardex (PDF)'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MiPagosScreen(
                      matriculaForzada: '${f['matricula']}',
                      nombreAlumno: (f['nombre'] ?? '') as String,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cessumGold,
                  side: BorderSide(color: cessumGold.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Ver pagos y estado de cuenta'),
              ),
            ),
            const SizedBox(height: 12),
            _seccion(
              'Calificaciones',
              cals.length,
              cals
                  .map<Widget>((c) => _fila(
                        '${c['clave']} · ${c['materia']}\n${c['programa']} ${c['generacion']}',
                        '${c['calificacion']}',
                        chip: _chip((c['estatus'] ?? '') as String),
                      ))
                  .toList(),
            ),
            _seccion(
              'Trámites',
              tras.length,
              tras
                  .map<Widget>((t) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _fila('${t['tipo']}\n${t['fecha']}', '',
                              chip: _chip((t['estatus'] ?? '') as String)),
                          if (((t['documento'] ?? '') as String).isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => Helpers.abrirUrlExterna(
                                    (t['documento'] ?? '') as String,
                                    context),
                                icon: const Icon(Icons.picture_as_pdf,
                                    size: 16, color: cessumGold),
                                label: const Text('Documento generado',
                                    style: TextStyle(
                                        color: cessumGold, fontSize: 12)),
                              ),
                            ),
                        ],
                      ))
                  .toList(),
            ),
            _seccion(
              'Incidencias (Mesa de ayuda)',
              incs.length,
              incs
                  .map<Widget>((i) => _fila(
                        '${i['folio']} · ${i['categoria']}\n${i['fecha']}',
                        '',
                        chip: _chip((i['estatus'] ?? '') as String),
                      ))
                  .toList(),
            ),
            _seccion(
              'Justificaciones de faltas',
              justs.length,
              justs
                  .map<Widget>((j) => _fila(
                        '${j['materia']}\n${j['fecha']} · ${j['motivo']}',
                        '',
                        chip: _chip((j['estatus'] ?? '') as String),
                      ))
                  .toList(),
            ),
            if (riesgo != null)
              _seccion('Riesgo académico', 1, [
                _fila(
                  'Nivel: ${riesgo['nivel']} · ${riesgo['diasSinConexion']} días sin conexión'
                  '${(riesgo['reprobadas'] ?? 0) != 0 ? ' · ${riesgo['reprobadas']} reprobada(s)' : ''}',
                  '',
                  chip: _chip((riesgo['nivel'] ?? '') as String),
                ),
              ]),
            if (titu != null)
              _seccion('Titulación', 1, [
                _fila('Folio ${titu['folio']}\nOpción: ${titu['opcion']}',
                    '', chip: _chip((titu['etapa'] ?? '') as String)),
                if (((titu['resultado'] ?? '') as String).isNotEmpty)
                  _fila('Resultado: ${titu['resultado']}', ''),
              ]),
            _seccion(
              'Pagos pendientes',
              pagos.length,
              pagos
                  .map<Widget>((p) => _fila(
                        '${p['concepto']}'
                        '${(p['monto'] ?? '').toString().isNotEmpty ? ' · \$${p['monto']}' : ''}'
                        '\nVence: ${p['fechaLimite']}',
                        '',
                        chip: _chip((p['estatus'] ?? '') as String),
                      ))
                  .toList(),
            ),
            if (moodle != null && moodle['enMoodle'] == true)
              _seccion(
                'Aula Virtual (Moodle)',
                mInsc.length,
                [
                  _fila(
                    'Actividad: ${mAct?['eventos'] ?? 0} acciones en '
                    '${mAct?['dias'] ?? 30} días'
                    '${(mAct?['ultimoEvento'] ?? '').toString().isNotEmpty ? '\nÚltima: ${mAct?['ultimoEvento']}' : ''}',
                    '',
                  ),
                  ...mInsc.map<Widget>((c) => _fila(
                        '${c['curso']}'
                        '${(c['ultimoAcceso'] ?? '').toString().isNotEmpty ? '\nÚltimo acceso: ${c['ultimoAcceso']}${c['diasSinEntrar'] != null ? ' (hace ${c['diasSinEntrar']} días)' : ''}' : '\nNunca ha entrado a este curso'}'
                        '${c['progreso'] != null ? ' · Avance ${c['progreso']}%' : ''}',
                        '',
                        chip: c['calificacion'] != null
                            ? _chip('${c['calificacion']}')
                            : null,
                      )),
                  ...mTar
                      .where((t) => t['entregado'] != true)
                      .map<Widget>((t) => _fila(
                            'Tarea: ${t['tarea']} (${t['curso']})',
                            '',
                            chip: _chip(
                                t['vencida'] == true ? 'Vencida' : 'Pendiente'),
                          )),
                ],
              )
            else if (moodle != null && moodle['enMoodle'] == false)
              _seccion('Aula Virtual (Moodle)', 0, [
                _fila(
                    'Este alumno no se encontró en el Aula con su correo institucional.',
                    ''),
              ]),
            _seccion(
              'Últimos accesos a la app',
              accs.length,
              accs
                  .map<Widget>((a) => _fila(a.toString(), ''))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Diálogo para buscar un alumno por nombre o matrícula y elegirlo.
/// Devuelve la matrícula seleccionada vía Navigator.pop.
class _BuscadorNombreDialog extends StatefulWidget {
  const _BuscadorNombreDialog();

  @override
  State<_BuscadorNombreDialog> createState() => _BuscadorNombreDialogState();
}

class _BuscadorNombreDialogState extends State<_BuscadorNombreDialog> {
  final _ctrl = TextEditingController();
  bool _cargando = false;
  List<Map<String, dynamic>> _res = [];
  String? _msg;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) {
      setState(() => _msg = 'Escribe al menos 2 letras.');
      return;
    }
    setState(() {
      _cargando = true;
      _msg = null;
    });
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=buscar_alumno&q=${Uri.encodeComponent(q)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final res = ((data['resultados'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _res = res;
        _cargando = false;
        _msg = res.isEmpty ? 'Sin coincidencias.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _msg = 'No se pudo buscar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buscar por nombre', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onSubmitted: (_) => _buscar(),
                    decoration: const InputDecoration(
                      hintText: 'Nombre o matrícula',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _cargando ? null : _buscar,
                  icon: const Icon(Icons.search, color: cessumRed),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: cessumRed),
              ),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_msg!,
                    style: const TextStyle(color: Colors.black54)),
              ),
            if (_res.isNotEmpty)
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _res.length,
                  itemBuilder: (ctx, i) {
                    final a = _res[i];
                    final baja = a['baja'] == true;
                    return ListTile(
                      dense: true,
                      title: Text('${a['nombre']}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${a['matricula']} · ${a['programa']} ${a['generacion']}'
                        '${baja ? ' · BAJA' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: baja
                          ? const Icon(Icons.block,
                              size: 16, color: Colors.black38)
                          : null,
                      onTap: () => Navigator.pop(context, '${a['matricula']}'),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

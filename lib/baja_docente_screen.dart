import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

/// (9-oct-2026) POSIBLES BAJAS REPORTADAS POR EL PROFESOR.
///
/// Desde Calificaciones, el docente marca con una bandera a un reprobado que
/// no se conectó, dejó de entregar o avisó que se va. Aquí Vicerrectoría ve
/// todas esas alertas, con el contexto del alumno (estatus en el padrón,
/// reprobadas del ciclo, otras alertas), y registra qué hizo: seguimiento,
/// contacto, se regularizó, baja o descartar. La alerta NO da de baja: la baja
/// formal sigue su procedimiento de siempre.
///
/// Rutas: GET baja_docente_listar [&estado=abiertas|resueltas|todas]
///        POST baja_docente_atender {actor, folio, decision, notas}
class BajaDocenteScreen extends StatefulWidget {
  const BajaDocenteScreen({super.key});

  @override
  State<BajaDocenteScreen> createState() => _BajaDocenteScreenState();
}

class _BajaDocenteScreenState extends State<BajaDocenteScreen> {
  bool _cargando = true;
  String _error = '';
  String _estado = 'abiertas'; // abiertas · resueltas · todas
  String _programa = '';
  String _q = '';
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _porEstado = {};
  int _abiertas = 0;
  String _ayuda = '';
  String _nota = '';
  Map<String, dynamic> _estados = {};
  final Set<String> _abiertosHistorial = {};
  final TextEditingController _buscar = TextEditingController();
  String _actor = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      _actor = await SessionStore.validEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'baja_docente_listar',
        'estado': _estado,
        if (_programa.isNotEmpty) 'programa': _programa,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception('${data['error'] ?? 'Sin respuesta del Guardián.'}');
      }
      final lista = ((data['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = lista;
        _porEstado = Map<String, dynamic>.from((data['porEstado'] as Map?) ?? {});
        _abiertas = (data['abiertas'] as num?)?.toInt() ?? 0;
        _ayuda = '${data['ayuda'] ?? ''}';
        _nota = '${data['nota'] ?? ''}';
        _estados = Map<String, dynamic>.from((data['estados'] as Map?) ?? {});
        _cargando = false;
      });
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'El Guardián tardó demasiado. Vuelve a intentarlo.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  List<String> get _programas {
    final s = <String>{};
    for (final it in _items) {
      final p = '${it['programa'] ?? ''}'.trim();
      if (p.isNotEmpty) s.add(p);
    }
    final l = s.toList()..sort();
    return l;
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _q.trim().toLowerCase();
    return _items.where((it) {
      if (_programa.isNotEmpty && '${it['programa'] ?? ''}' != _programa) {
        return false;
      }
      if (q.isEmpty) return true;
      final texto = [
        it['alumno'], it['matricula'], it['materia'], it['docente'],
        it['folio'], it['programa'], it['grupo'], it['motivoTexto'],
      ].map((x) => '${x ?? ''}'.toLowerCase()).join(' ');
      return texto.contains(q);
    }).toList();
  }

  Color _colorNivel(String nivel) {
    switch (nivel) {
      case 'vencido':
        return cessumRed;
      case 'critico':
        return cessumGold;
      case 'alerta':
        return Colors.orange.shade700;
      default:
        return Colors.green.shade700;
    }
  }

  String _textoNivel(Map<String, dynamic> it) {
    final dias = (it['dias'] as num?)?.toInt();
    if (it['abierta'] != true) return 'Resuelta';
    if (dias == null) return 'Sin fecha';
    if (dias == 0) return 'Hoy';
    if (dias == 1) return 'Hace 1 día sin atender';
    return 'Hace $dias días sin atender';
  }

  Future<void> _ayudaDialogo() async {
    const fija =
        'El docente marca «posible baja» cuando el alumno reprobó (6) y además no se conectó '
        'a las sesiones o dejó de conectarse, no entregó evidencias, avisó que deja el programa '
        'o no responde a sus mensajes.\n\n'
        'Qué hacer aquí:\n'
        '1. Contactar al alumno (correo, llamada o WhatsApp) y registrar «Alumno contactado».\n'
        '2. Si regresa o regulariza, marcar «Se regularizó».\n'
        '3. Si procede la baja, marcar «Baja» con el motivo: esta alerta solo la documenta; '
        'la baja formal se tramita como siempre (Bajas / Posibles bajas por pago, Art. 40).\n'
        '4. Si la alerta no tenía fundamento, «Descartar» con el motivo.\n\n'
        'Una alerta sin atender más de 3 días se marca crítica; más de 7, vencida. '
        'Todas aparecen también en el Panel de pendientes.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.help_outline, color: cessumRed),
          SizedBox(width: 8),
          Expanded(child: Text('¿Cuándo se marca y qué hago?')),
        ]),
        content: SingleChildScrollView(
          child: Text(
            (_ayuda.isNotEmpty ? '$_ayuda\n\n' : '') + fija,
            style: const TextStyle(fontSize: 13.5, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _atender(Map<String, dynamic> it, String decision) async {
    const titulos = {
      'seguimiento': 'Poner en seguimiento',
      'contactado': 'Registrar que ya se contactó al alumno',
      'regularizado': 'Marcar como regularizado',
      'baja': 'Registrar decisión de baja',
      'descartar': 'Descartar la alerta',
      'reabrir': 'Reabrir la alerta',
    };
    final notasObligatorias = decision == 'baja' || decision == 'descartar';
    final notas = TextEditingController();
    bool enviando = false;
    String error = '';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(titulos[decision] ?? decision,
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${it['alumno'] ?? ''} · ${it['matricula'] ?? ''} · ${it['materia'] ?? ''}',
                    style: TextStyle(fontSize: 12.5, color: cessumMuted(ctx))),
                const SizedBox(height: 10),
                TextField(
                  controller: notas,
                  enabled: !enviando,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 900,
                  decoration: InputDecoration(
                    labelText: notasObligatorias
                        ? 'Motivo (obligatorio)'
                        : 'Notas (qué se hizo, qué dijo el alumno)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (decision == 'baja')
                  Text(
                    'Esto documenta la decisión. La baja formal se tramita por el procedimiento de siempre.',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(ctx)),
                  ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(error,
                      style: const TextStyle(color: cessumRed, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: decision == 'baja' ? cessumRed : cessumGold,
                  foregroundColor: Colors.white),
              onPressed: enviando
                  ? null
                  : () async {
                      if (notasObligatorias && notas.text.trim().length < 5) {
                        setD(() => error = 'Escribe el motivo.');
                        return;
                      }
                      setD(() {
                        enviando = true;
                        error = '';
                      });
                      try {
                        final resp = await http
                            .post(Uri.parse(guardianUrl),
                                headers: {
                                  'Content-Type': 'text/plain;charset=utf-8'
                                },
                                body: jsonEncode({
                                  'accion': 'baja_docente_atender',
                                  'actor': _actor,
                                  'folio': it['folio'],
                                  'decision': decision,
                                  'notas': notas.text.trim(),
                                }))
                            .timeout(const Duration(seconds: 60));
                        final data =
                            jsonDecode(resp.body) as Map<String, dynamic>;
                        if (data['ok'] != true) {
                          setD(() {
                            enviando = false;
                            error = '${data['error'] ?? 'No se pudo guardar.'}';
                          });
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('${data['nota'] ?? 'Listo.'}')));
                        }
                        _cargar();
                      } on TimeoutException {
                        setD(() {
                          enviando = false;
                          error = 'Tardó demasiado. Intenta de nuevo.';
                        });
                      } catch (e) {
                        setD(() {
                          enviando = false;
                          error = 'No se pudo guardar: $e';
                        });
                      }
                    },
              child: Text(enviando ? 'Guardando…' : 'Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color, {IconData? icono}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icono != null) ...[
          Icon(icono, size: 13, color: color),
          const SizedBox(width: 4),
        ],
        Text(texto,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _tarjeta(Map<String, dynamic> it) {
    final abierta = it['abierta'] == true;
    final nivel = '${it['nivel'] ?? 'ok'}';
    final color = abierta ? _colorNivel(nivel) : Colors.green.shade700;
    final folio = '${it['folio'] ?? ''}';
    final verHist = _abiertosHistorial.contains(folio);
    final reprobadas = (it['reprobadasCiclo'] as num?)?.toInt() ?? 0;
    final otras = (it['otrasAlertas'] as num?)?.toInt() ?? 0;
    final correoAl = '${it['correoAlumno'] ?? ''}';
    final detalle = '${it['detalle'] ?? ''}';
    final notas = '${it['notas'] ?? ''}';
    final estatus = '${it['estatusAlumno'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${it['alumno'] ?? ''}',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cessumInk(context))),
                    const SizedBox(height: 2),
                    Text(
                      '${it['matricula'] ?? ''}'
                      '${estatus.isNotEmpty ? ' · $estatus en el padrón' : ''}'
                      '${correoAl.isNotEmpty ? ' · $correoAl' : ''}',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              _chip('${it['estadoTexto'] ?? it['estado'] ?? ''}', color,
                  icono: abierta ? Icons.flag : Icons.check_circle_outline),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${it['programa'] ?? ''}'
            '${'${it['generacion'] ?? ''}'.isNotEmpty ? ' · Gen. ${it['generacion']}' : ''}'
            '${'${it['grupo'] ?? ''}'.isNotEmpty ? ' · Grupo ${it['grupo']}' : ''}',
            style: TextStyle(fontSize: 12.5, color: cessumInk(context)),
          ),
          Text(
            '${it['materia'] ?? ''}'
            '${'${it['calificacion'] ?? ''}'.isNotEmpty ? ' · calificación ${it['calificacion']}' : ''}'
            ' · reportó ${it['docente'] ?? ''}',
            style: TextStyle(fontSize: 12.5, color: cessumInk(context)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('${it['motivoTexto'] ?? it['motivo'] ?? ''}', cessumRed,
                  icono: Icons.report_gmailerrorred),
              if ('${it['desde'] ?? ''}'.isNotEmpty)
                _chip('Desde ${it['desde']}', cessumGold, icono: Icons.event),
              _chip(
                  '${it['contacto'] ?? 'No'}'.toLowerCase().startsWith('s')
                      ? 'El docente sí intentó contactarlo'
                      : 'El docente no lo contactó',
                  Colors.blueGrey,
                  icono: Icons.phone_outlined),
              if (reprobadas > 0)
                _chip(
                    '$reprobadas reprobada${reprobadas == 1 ? '' : 's'} en el ciclo',
                    cessumRed,
                    icono: Icons.trending_down),
              if (otras > 0)
                _chip('$otras alerta${otras == 1 ? '' : 's'} más de este alumno',
                    cessumGold,
                    icono: Icons.layers_outlined),
              _chip('${it['fecha'] ?? ''} · ${_textoNivel(it)}', color,
                  icono: Icons.schedule),
            ],
          ),
          if (detalle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(detalle,
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: cessumInk(context))),
          ],
          if ((it['reprobadasDetalle'] as List?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Reprobadas del ciclo: ${(it['reprobadasDetalle'] as List).join(', ')}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
              ),
            ),
          if (notas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Notas de atención: $notas',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: FontStyle.italic,
                      color: cessumInk(context))),
            ),
          if ('${it['historial'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() {
                if (verHist) {
                  _abiertosHistorial.remove(folio);
                } else {
                  _abiertosHistorial.add(folio);
                }
              }),
              child: Text(verHist ? 'Ocultar historial ▲' : 'Ver historial ▼',
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: cessumRed,
                      fontWeight: FontWeight.w700)),
            ),
            if (verHist)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${it['historial']}',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: cessumMuted(context))),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (correoAl.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      visualDensity: VisualDensity.compact),
                  onPressed: () => Helpers.abrirUrlExterna(
                      'mailto:$correoAl?subject=${Uri.encodeComponent('CESSUM · ${it['materia'] ?? ''}')}',
                      context),
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('Escribir al alumno',
                      style: TextStyle(fontSize: 12)),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cessumGold,
                    visualDensity: VisualDensity.compact),
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: '${it['alumno'] ?? ''} · ${it['matricula'] ?? ''} · '
                          '${it['programa'] ?? ''} · ${it['materia'] ?? ''} · '
                          '${it['motivoTexto'] ?? ''}${detalle.isNotEmpty ? ' · $detalle' : ''}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Datos copiados.')));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copiar datos', style: TextStyle(fontSize: 12)),
              ),
              if (abierta) ...[
                if ('${it['estado']}' == 'reportada')
                  _accion('En seguimiento', Icons.play_arrow_outlined, cessumGold,
                      () => _atender(it, 'seguimiento')),
                if ('${it['estado']}' != 'contactado')
                  _accion('Contactado', Icons.phone_in_talk_outlined, cessumGold,
                      () => _atender(it, 'contactado')),
                _accion('Se regularizó', Icons.check_circle_outline,
                    Colors.green.shade700, () => _atender(it, 'regularizado')),
                _accion('Baja', Icons.person_off_outlined, cessumRed,
                    () => _atender(it, 'baja')),
                _accion('Descartar', Icons.close, Colors.blueGrey,
                    () => _atender(it, 'descartar')),
              ] else
                _accion('Reabrir', Icons.replay, cessumGold,
                    () => _atender(it, 'reabrir')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accion(String texto, IconData icono, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          visualDensity: VisualDensity.compact,
          elevation: 0),
      onPressed: onTap,
      icon: Icon(icono, size: 16),
      label: Text(texto, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _resumen() {
    final total = _items.length;
    final vencidas = _items.where((x) => x['abierta'] == true && x['nivel'] == 'vencido').length;
    final criticas = _items.where((x) => x['abierta'] == true && x['nivel'] == 'critico').length;
    Widget n(String v, String etq, Color c) => Expanded(
          child: Column(children: [
            Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
            Text(etq, style: TextStyle(fontSize: 10.5, color: cessumMuted(context)), textAlign: TextAlign.center),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        n('$_abiertas', 'Abiertas', cessumRed),
        n('$vencidas', 'Más de 7 días', cessumRed),
        n('$criticas', '3 a 7 días', cessumGold),
        n('${(_porEstado['regularizado'] as num?)?.toInt() ?? 0}', 'Regularizados', Colors.green.shade700),
        n('${(_porEstado['baja'] as num?)?.toInt() ?? 0}', 'Bajas', Colors.blueGrey),
        n('$total', _estado == 'todas' ? 'Total' : 'En esta vista', cessumInk(context)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _visibles;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Posibles bajas · reportadas por docentes',
            style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: '¿Cuándo se marca y qué hago?',
            icon: const Icon(Icons.help_outline),
            onPressed: _ayudaDialogo,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : RefreshIndicator(
              color: cessumRed,
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                children: [
                  if (_error.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumRed.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: cessumRed.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline, color: cessumRed),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error, style: const TextStyle(fontSize: 13))),
                        TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                      ]),
                    ),
                  _resumen(),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<String>(
                          style: ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
                          ),
                          segments: const [
                            ButtonSegment(value: 'abiertas', label: Text('Abiertas')),
                            ButtonSegment(value: 'resueltas', label: Text('Resueltas')),
                            ButtonSegment(value: 'todas', label: Text('Todas')),
                          ],
                          selected: {_estado},
                          onSelectionChanged: (s) {
                            setState(() => _estado = s.first);
                            _cargar();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buscar,
                          onChanged: (v) => setState(() => _q = v),
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            hintText: 'Buscar alumno, matrícula, materia, docente o folio',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            suffixIcon: _q.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _buscar.clear();
                                      setState(() => _q = '');
                                    }),
                          ),
                        ),
                      ),
                      if (_programas.length > 1) ...[
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: _programa.isEmpty ? '' : _programa,
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('Todos los programas', style: TextStyle(fontSize: 12.5))),
                            ..._programas.map((p) => DropdownMenuItem(value: p, child: Text(p, style: const TextStyle(fontSize: 12.5)))),
                          ],
                          onChanged: (v) => setState(() => _programa = v ?? ''),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_nota.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(_nota, style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.4)),
                    ),
                  if (visibles.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(children: [
                        Icon(Icons.flag_outlined, size: 40, color: cessumMuted(context)),
                        const SizedBox(height: 8),
                        Text(
                          _estado == 'abiertas'
                              ? 'No hay alertas abiertas. Cuando un docente marque a un reprobado como posible baja, aparecerá aquí.'
                              : 'Nada que mostrar con estos filtros.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cessumMuted(context)),
                        ),
                      ]),
                    )
                  else
                    ...visibles.map(_tarjeta),
                ],
              ),
            ),
    );
  }
}

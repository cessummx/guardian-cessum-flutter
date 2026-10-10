// =====================================================================
//  recursamiento_autogestivo_admin.dart · CESSUM · (24-sep-2026)
//  RECURSAMIENTO AUTOGESTIVO · lado de Vicerrectoría
//
//  Se muestra dentro de Recursamientos (panel de administración), en el
//  filtro «Autogestivo». Solo un administrador lo habilita: el Guardián lo
//  vuelve a comprobar con la llave de la sesión.
//
//  FLUJO
//   1. «Asignar»: alumno (buscador) + materia pendiente de su plan +
//      enlace directo al curso + indicaciones + periodo (inicio y semanas).
//      Queda «Pendiente de pago»: el alumno ve el costo y los datos para
//      pagar, pero NO el enlace del curso.
//   1b. El alumno sube su comprobante; la IA lo lee (monto, cuenta de CESSUM,
//      fecha, archivo no repetido) y si corresponde se habilita solo. Si no,
//      queda «Pago por revisar» y aquí se valida o rechaza. Al validarse, el
//      Guardián lo MATRICULA en el curso del Aula (nadie lo matricula a mano).
//   2. El alumno trabaja el curso y toca «Avisar que terminé».
//   3. Aquí aparece «Por revisar» arriba de todo; además, cada día llega un
//      correo a vicerrectoria@cessum.mx mientras quede alguno pendiente.
//   4. Se revisa: Aprobar · Pedir ajustes (con comentario) · Cancelar.
//
//  Guardián: GET autogestivo_admin · GET avance_plan · POST autogestivo_habilitar
//            POST autogestivo_revisar · GET autogestivo_correo_diario
//  Nada de aquí captura calificaciones: la calificación oficial se registra
//  por la vía de siempre.
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'alumnos_service.dart';
import 'aula_curso_selector.dart';   // (5-oct-2026) curso del aula sugerido con IA
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// (24-sep) Una segunda materia autogestiva en el mismo programa es EXCEPCIÓN:
/// solo la autoriza un superadministrador, y debe confirmarla expresamente.
Future<bool> confirmarExcepcionAutog(BuildContext context, String mensaje) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Autorizar como excepción?', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mensaje, style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 10),
          const Text(
              'La regla es una materia autogestiva por programa. Si la autoriza, quedará registrada como excepción con su correo.',
              style: TextStyle(fontSize: 12.5, color: cessumRed, fontWeight: FontWeight.w600)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No autorizar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Autorizar como excepción'),
        ),
      ],
    ),
  );
  return ok == true;
}

class AutogestivoAdminVista extends StatefulWidget {
  /// Se llama cuando cambia el número de pendientes por revisar, para que el
  /// panel actualice el contador del filtro.
  final ValueChanged<int>? alCambiar;
  const AutogestivoAdminVista({super.key, this.alCambiar});

  @override
  State<AutogestivoAdminVista> createState() => _AutogestivoAdminVistaState();
}

class _AutogestivoAdminVistaState extends State<AutogestivoAdminVista> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _items = [];
  final Set<String> _ocupados = {};
  String _ver = 'abiertos'; // abiertos | todos

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'autogestivo_admin'}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar.');
      _items = ((d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      widget.alCambiar?.call((d['porRevisar'] as num?)?.toInt() ?? 0);
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  void _aviso(String t, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : const Color(0xFF1E7F52),
      duration: const Duration(seconds: 5),
      content: Text(t),
    ));
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ---------------- Revisar ----------------

  /// (24-sep) Pre-revisión con IA: lee las entregas del alumno en el Aula y
  /// propone calificación por tarea, dictamen y retroalimentación.
  Future<void> _prerevisarIa(Map<String, dynamic> x, {bool rehacer = false}) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'autogestivo_ia_prerevisar',
            'id': '${x['id']}',
            if (rehacer) 'rehacer': '1',
          }))
          .timeout(const Duration(seconds: 330));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      d = {'ok': false, 'error': 'No se pudo conectar o tardó demasiado. Intente de nuevo.'};
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (d['ok'] != true) {
      _aviso('${d['error'] ?? 'No se pudo pre-revisar.'}', error: true);
      return;
    }
    final tareas = ((d['tareas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final sug = '${d['sugerencia']}';
    final c = sug == 'Aprobado' ? const Color(0xFF1E7F52) : cessumGold;
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: cessumGold),
          const SizedBox(width: 8),
          Expanded(child: Text('IA sugiere: $sug', style: TextStyle(fontSize: 17, color: c, fontWeight: FontWeight.w800))),
        ]),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${x['nombre']} · ${x['materia']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Promedio sugerido ${d['promedio']} · ${d['entregadas']} de ${d['total']} tareas entregadas'
                  '${d['guardada'] == true ? ' · pre-revisión del ${d['fecha']}' : ''}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(ctx))),
              const SizedBox(height: 10),
              for (final t in tareas)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cessumMuted(ctx).withValues(alpha: 0.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${t['tarea']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                      Text(
                        t['sinEntrega'] == true
                            ? 'Sin entregar'
                            : t['evaluada'] == true
                                ? '${t['calificacion']}'
                                : (t['pendiente'] == true ? 'Sin revisar' : 'No legible'),
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: t['sinEntrega'] == true || t['cumple'] == false ? cessumRed : const Color(0xFF1E7F52)),
                      ),
                    ]),
                    for (final f in ((t['fortalezas'] as List?) ?? []))
                      Text('+ $f', style: const TextStyle(fontSize: 12, height: 1.35)),
                    for (final f in ((t['faltantes'] as List?) ?? []))
                      Text('– $f', style: const TextStyle(fontSize: 12, height: 1.35, color: cessumRed)),
                    if ('${t['error'] ?? ''}'.isNotEmpty)
                      Text('${t['error']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(ctx))),
                  ]),
                ),
              const SizedBox(height: 4),
              const Text('Retroalimentación sugerida para el alumno', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              Text('${d['retroSugerida'] ?? ''}', style: const TextStyle(fontSize: 13, height: 1.4)),
              const SizedBox(height: 8),
              Text('${d['aviso'] ?? ''}', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'rehacer'), child: const Text('Volver a revisar')),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: cessumGold),
            onPressed: () => Navigator.pop(ctx, 'Requiere ajustes'),
            child: const Text('Pedir ajustes con este texto'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E7F52)),
            onPressed: () => Navigator.pop(ctx, 'Aprobado'),
            child: const Text('Aprobar con este texto'),
          ),
        ],
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'rehacer') {
      await _prerevisarIa(x, rehacer: true);
      return;
    }
    await _revisar(x, accion, comentarioInicial: '${d['retroSugerida'] ?? ''}');
  }

  Future<void> _revisar(Map<String, dynamic> x, String resultado, {String comentarioInicial = ''}) async {
    final com = TextEditingController(text: comentarioInicial);
    final pideTexto = resultado != 'Aprobado' || comentarioInicial.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            resultado == 'Aprobado'
                ? '¿Aprobar las actividades?'
                : resultado == 'Requiere ajustes'
                    ? 'Pedir ajustes'
                    : '¿Cancelar este recursamiento?',
            style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['nombre']} · ${x['materia']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              resultado == 'Aprobado'
                  ? 'Al alumno le llega el aviso de que quedó aprobado. Recuerde capturar la calificación oficial por la vía de siempre.'
                  : resultado == 'Requiere ajustes'
                      ? 'Escriba qué debe corregir. Al alumno le llega este texto y podrá volver a avisar cuando lo tenga.'
                      : 'El alumno deja de ver este recursamiento. Puede escribirle el motivo.',
              style: TextStyle(fontSize: 13, height: 1.4, color: cessumMuted(ctx)),
            ),
            if (pideTexto) ...[
              const SizedBox(height: 10),
              TextField(
                controller: com,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  labelText: resultado == 'Requiere ajustes'
                      ? 'Qué debe ajustar (obligatorio)'
                      : resultado == 'Aprobado'
                          ? 'Comentario para el alumno (opcional)'
                          : 'Motivo (opcional)',
                ),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: resultado == 'Aprobado' ? const Color(0xFF1E7F52) : cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(resultado == 'Aprobado' ? 'Aprobar' : resultado == 'Requiere ajustes' ? 'Enviar ajustes' : 'Cancelar recursamiento'),
          ),
        ],
      ),
    );
    final texto = com.text.trim();
    com.dispose();
    if (ok != true || !mounted) return;
    final id = '${x['id']}';
    setState(() => _ocupados.add(id));
    try {
      final d = await _post({'accion': 'autogestivo_revisar', 'id': id, 'resultado': resultado, 'comentario': texto});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Listo: quedó «$resultado» y se le avisó al alumno.');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupados.remove(id));
  }

  /// Pago que la lectura automática no pudo validar: validar o rechazar.
  Future<void> _decidirPago(Map<String, dynamic> x, bool validar) async {
    final com = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(validar ? '¿Validar el pago?' : 'Rechazar comprobante', style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['nombre']} · ${x['materia']} · costo \$${x['costo']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Lectura automática: ${'${x['pago']}'.replaceFirst('Por revisar: ', '')}',
                style: TextStyle(fontSize: 12.5, color: cessumMuted(ctx))),
            const SizedBox(height: 8),
            Text(
              validar
                  ? 'Se le abre el curso al alumno y le llega el aviso.'
                  : 'El alumno vuelve a «Pendiente de pago» y le llega su comentario para subir otro comprobante.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: com,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                labelText: validar ? 'Nota (opcional)' : 'Qué está mal (obligatorio)',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: validar ? const Color(0xFF1E7F52) : cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(validar ? 'Validar y abrir el curso' : 'Rechazar'),
          ),
        ],
      ),
    );
    final texto = com.text.trim();
    com.dispose();
    if (ok != true || !mounted) return;
    final id = '${x['id']}';
    setState(() => _ocupados.add(id));
    try {
      final d = await _post({'accion': 'autogestivo_pago', 'id': id, 'decision': validar ? 'validar' : 'rechazar', 'comentario': texto});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso(validar ? 'Pago validado: se le abrió el curso al alumno.' : 'Comprobante rechazado; se le avisó al alumno.');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupados.remove(id));
  }

  /// (24-sep) Botón «Matricular en el Aula»: matricula al alumno en el curso
  /// del enlace en este momento. Si aún no paga, se advierte antes.
  Future<void> _matricularAula(Map<String, dynamic> x) async {
    final estado = '${x['estado']}';
    final sinPago = estado == 'Pendiente de pago' || estado == 'Pago por revisar';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Matricular en el Aula?', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['nombre']} · ${x['materia']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Curso: ${x['link']}', style: TextStyle(fontSize: 12, color: cessumMuted(ctx))),
            const SizedBox(height: 10),
            if (sinPago)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cessumRed.withValues(alpha: 0.4)),
                ),
                child: const Text(
                    'Aún no tiene el pago validado: al matricularla podrá entrar al curso sin haber pagado. '
                    'Si el pago ya se hizo, conviene usar «Validar pago», que además la matricula.',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumRed, fontWeight: FontWeight.w600)),
              )
            else
              const Text('Se matricula en el curso en este momento.', style: TextStyle(fontSize: 13)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: sinPago ? cessumRed : const Color(0xFF1E7F52)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(sinPago ? 'Matricular de todos modos' : 'Matricular'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final id = '${x['id']}';
    setState(() => _ocupados.add(id));
    try {
      final d = await _post({'accion': 'autogestivo_matricular', 'id': id});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo matricular.');
      _aviso('Matriculada en el Aula (curso ${d['curso']}).');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupados.remove(id));
  }

  /// (24-sep) Solicitud del alumno: aprobar (y asignar curso y periodo) o rechazar.
  Future<void> _resolverSolicitud(Map<String, dynamic> x, bool aprobar) async {
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _DialogoResolver(item: x, aprobar: aprobar),
    );
    if (r == null || !mounted) return;
    final id = '${x['id']}';
    setState(() => _ocupados.add(id));
    try {
      var d = await _post({'accion': 'autogestivo_resolver', 'id': id, ...r});
      if (d['requiereExcepcion'] == true && mounted) {
        if (!await confirmarExcepcionAutog(context, '${d['error']}')) {
          if (mounted) setState(() => _ocupados.remove(id));
          return;
        }
        d = await _post({'accion': 'autogestivo_resolver', 'id': id, 'excepcion': true, ...r});
      }
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso(aprobar
          ? 'Solicitud aprobada (${d['periodo']}). Al alumno le llegó el aviso.'
          : 'Solicitud rechazada; se le avisó al alumno.');
      await _cargar();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupados.remove(id));
  }

  Future<void> _enviarCorreoAhora() async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'autogestivo_correo_diario'}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo enviar.');
      _aviso(d['enviado'] == true
          ? 'Correo enviado a ${d['a']} con ${d['porRevisar']} pendiente(s).'
          : 'No hay nada por revisar: no se envió correo.');
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  // ---------------- Habilitar ----------------

  Future<void> _habilitar() async {
    final hecho = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DialogoHabilitar(),
    );
    if (hecho == true) {
      _aviso('Recursamiento autogestivo asignado. Al alumno le llegó el aviso en la app.');
      await _cargar();
    }
  }

  // ---------------- Vista ----------------

  Color _colorDe(String e) => switch (e) {
        'Solicitada' => const Color(0xFF7C3AED),
        'Rechazada' => Colors.grey,
        'Por revisar' || 'Pago por revisar' => cessumGold,
        'Pendiente de pago' => const Color(0xFF6B7280),
        'Aprobado' => const Color(0xFF1E7F52),
        'Requiere ajustes' => cessumRed,
        'Cancelado' => Colors.grey,
        _ => const Color(0xFF3B6EA8),
      };

  @override
  Widget build(BuildContext context) {
    final visibles = _ver == 'todos'
        ? _items
        : _items
            .where((x) => ['Solicitada', 'Pago por revisar', 'Por revisar', 'Requiere ajustes', 'Pendiente de pago', 'Habilitado']
                .contains('${x['estado']}'))
            .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
        ),
        child: Text(
          'Se asigna la materia con su periodo; el alumno paga y sube su comprobante, que se valida solo si '
          'corresponde (monto, cuenta de CESSUM y fecha). Entonces se le abre el curso, trabaja a su ritmo y al '
          'terminar toca la campanita. Los pagos que no se pudieron validar y las actividades por revisar aparecen '
          'aquí arriba y llegan cada día en un correo a vicerrectoria@cessum.mx hasta que se atiendan.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context)),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: _habilitar,
          icon: const Icon(Icons.add_task, size: 18),
          label: const Text('Asignar recursamiento autogestivo'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
          onPressed: _enviarCorreoAhora,
          icon: const Icon(Icons.mark_email_unread_outlined, size: 18),
          label: const Text('Enviarme el correo ahora'),
        ),
        ChoiceChip(
          label: const Text('Abiertos'),
          selected: _ver == 'abiertos',
          onSelected: (_) => setState(() => _ver = 'abiertos'),
        ),
        ChoiceChip(
          label: Text('Todos (${_items.length})'),
          selected: _ver == 'todos',
          onSelected: (_) => setState(() => _ver = 'todos'),
        ),
      ]),
      const SizedBox(height: 12),
      if (_cargando)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Center(child: CircularProgressIndicator(color: cessumRed)),
        )
      else if (_error.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(children: [
            Text(_error, textAlign: TextAlign.center),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        )
      else if (visibles.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(
            child: Text(
                _ver == 'abiertos' ? 'No hay recursamientos autogestivos abiertos.' : 'Todavía no se ha habilitado ninguno.',
                style: TextStyle(color: cessumMuted(context))),
          ),
        )
      else
        ...visibles.map(_tarjeta),
    ]);
  }

  Widget _tarjeta(Map<String, dynamic> x) {
    final estado = '${x['estado']}';
    final c = _colorDe(estado);
    final id = '${x['id']}';
    final ocupado = _ocupados.contains(id);
    final dias = (x['diasEsperando'] as num?)?.toInt();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: estado == 'Por revisar' ? 0.7 : 0.3), width: estado == 'Por revisar' ? 1.6 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${x['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(estado, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          ),
        ]),
        const SizedBox(height: 2),
        Text('${x['matricula']} · ${x['programa']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 6),
        Text('${x['materia']}${'${x['clave']}'.isNotEmpty ? ' (${x['clave']})' : ''}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if ('${x['inicio']}'.isNotEmpty)
          Text(
            'Periodo: ${x['inicio']} al ${x['fin']}'
            '${(x['costo'] as num? ?? 0) > 0 ? ' · Costo \$${x['costo']}' : ''}'
            '${x['vencido'] == true ? ' · PERIODO VENCIDO' : ''}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: x['vencido'] == true ? cessumRed : cessumInk(context)),
          ),
        if ('${x['pago']}'.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Pago: ${x['pago']}',
                style: TextStyle(
                    fontSize: 11.5,
                    color: '${x['estado']}' == 'Pago por revisar' ? cessumRed : cessumMuted(context))),
          ),
        const SizedBox(height: 2),
        Text(
          'Asignado el ${x['habilitado']}'
          '${'${x['termino']}'.isNotEmpty ? ' · Avisó que terminó el ${x['termino']}' : ''}'
          '${dias != null ? ' · ${dias == 0 ? 'hoy' : dias == 1 ? '1 día esperando' : '$dias días esperando'}' : ''}',
          style: TextStyle(fontSize: 11.5, color: dias != null && dias >= 3 ? cessumRed : cessumMuted(context)),
        ),
        if ('${x['nota']}'.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Nota del alumno: «${x['nota']}»', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
        ],
        if ('${x['comentario']}'.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Comentario de revisión: ${x['comentario']}', style: const TextStyle(fontSize: 12.5)),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if ('${x['link']}'.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
              onPressed: () => launchUrl(Uri.parse('${x['link']}'), webOnlyWindowName: '_blank'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Abrir curso'),
            ),
          if (estado == 'Solicitada') ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E7F52), visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _resolverSolicitud(x, true),
              icon: const Icon(Icons.task_alt, size: 16),
              label: const Text('Aprobar y asignar'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _resolverSolicitud(x, false),
              icon: const Icon(Icons.block, size: 16),
              label: const Text('Rechazar'),
            ),
          ],
          if ('${x['link']}'.contains('aula.cessum.mx') && !['Cancelado', 'Aprobado', 'Rechazada', 'Solicitada'].contains(estado))
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF3B6EA8), visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _matricularAula(x),
              icon: const Icon(Icons.how_to_reg, size: 16),
              label: const Text('Matricular en el Aula'),
            ),
          if ('${x['comprobante']}'.isNotEmpty)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumGold, visualDensity: VisualDensity.compact),
              onPressed: () => launchUrl(Uri.parse('${x['comprobante']}'), webOnlyWindowName: '_blank'),
              icon: const Icon(Icons.receipt_long, size: 16),
              label: const Text('Ver comprobante'),
            ),
          if (estado == 'Pago por revisar' || estado == 'Pendiente de pago') ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E7F52), visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _decidirPago(x, true),
              icon: const Icon(Icons.verified, size: 16),
              label: const Text('Validar pago'),
            ),
            if (estado == 'Pago por revisar')
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
                onPressed: ocupado ? null : () => _decidirPago(x, false),
                icon: const Icon(Icons.block, size: 16),
                label: const Text('Rechazar comprobante'),
              ),
          ],
          if (estado == 'Por revisar') ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumGold, visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _prerevisarIa(x),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Pre-revisión con IA'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E7F52), visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _revisar(x, 'Aprobado'),
              icon: const Icon(Icons.check_circle, size: 16),
              label: const Text('Aprobar'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumGold, visualDensity: VisualDensity.compact),
              onPressed: ocupado ? null : () => _revisar(x, 'Requiere ajustes'),
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('Pedir ajustes'),
            ),
          ],
          if (['Pendiente de pago', 'Pago por revisar', 'Habilitado', 'Por revisar', 'Requiere ajustes'].contains(estado) && estado != 'Solicitada')
            TextButton(
              onPressed: ocupado ? null : () => _revisar(x, 'Cancelado'),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
        ]),
      ]),
    );
  }
}

// =====================================================================
//  Diálogo «Asignar»: alumno → materia pendiente → curso → periodo → pago.
// =====================================================================
class _DialogoHabilitar extends StatefulWidget {
  const _DialogoHabilitar();
  @override
  State<_DialogoHabilitar> createState() => _DialogoHabilitarState();
}

class _DialogoHabilitarState extends State<_DialogoHabilitar> {
  final _busca = TextEditingController();
  final _link = TextEditingController();
  final _instr = TextEditingController();
  final _materiaLibre = TextEditingController();
  List<AlumnoInfo> _todos = [];
  bool _cargandoPadron = true;
  AlumnoInfo? _alumno;
  bool _cargandoPlan = false;
  String _errorPlan = '';
  List<Map<String, String>> _pendientes = [];
  Map<String, String>? _materia;
  bool _otra = false;
  bool _enviando = false;
  String _error = '';
  // (24-sep) Periodo y pago.
  late DateTime _inicio = _proximoLunes();
  int _semanas = 5;
  bool _requierePago = true;

  static DateTime _proximoLunes() {
    final h = DateTime.now();
    final hoy = DateTime(h.year, h.month, h.day);
    final dias = (DateTime.monday - hoy.weekday + 7) % 7;
    return hoy.add(Duration(days: dias == 0 ? 7 : dias));
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _dma(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  DateTime get _fin => _inicio.add(Duration(days: _semanas * 7 - 1));

  @override
  void initState() {
    super.initState();
    AlumnosService.listarAlumnos(incluirBajas: false).then((l) {
      if (mounted) setState(() {
        _todos = l;
        _cargandoPadron = false;
      });
    });
  }

  @override
  void dispose() {
    _busca.dispose();
    _link.dispose();
    _instr.dispose();
    _materiaLibre.dispose();
    super.dispose();
  }

  String _n(String s) {
    s = s.toLowerCase();
    const a = 'áàäâéèëêíìïîóòöôúùüûñ';
    const b = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  List<AlumnoInfo> get _coinciden {
    final q = _n(_busca.text);
    if (q.length < 2) return [];
    return _todos.where((a) => _n(a.nombre).contains(q) || a.matricula.contains(q)).take(8).toList();
  }

  Future<void> _elegirAlumno(AlumnoInfo a) async {
    setState(() {
      _alumno = a;
      _cargandoPlan = true;
      _errorPlan = '';
      _pendientes = [];
      _materia = null;
      _otra = false;
    });
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'avance_plan', 'matricula': a.matricula}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo leer su plan.');
      final l = <Map<String, String>>[];
      for (final c in (d['ciclos'] as List? ?? [])) {
        final ciclo = '${(c as Map)['ciclo'] ?? ''}';
        for (final m in (c['materias'] as List? ?? [])) {
          final mm = m as Map;
          if ('${mm['estado']}' != 'Aprobada') {
            l.add({'clave': '${mm['clave'] ?? ''}', 'materia': '${mm['materia'] ?? ''}', 'ciclo': ciclo});
          }
        }
      }
      _pendientes = l;
      if (l.isEmpty) _otra = true;
    } catch (e) {
      _errorPlan = '$e'.replaceFirst('Exception: ', '');
      _otra = true;
    }
    if (mounted) setState(() => _cargandoPlan = false);
  }

  Future<void> _guardar() async {
    final materia = _otra ? _materiaLibre.text.trim() : (_materia?['materia'] ?? '');
    final clave = _otra ? '' : (_materia?['clave'] ?? '');
    final link = _link.text.trim();
    if (_alumno == null) {
      setState(() => _error = 'Elija al alumno.');
      return;
    }
    if (materia.isEmpty) {
      setState(() => _error = 'Elija o escriba la materia.');
      return;
    }
    if (!RegExp(r'^https://\S+$').hasMatch(link)) {
      setState(() => _error = 'Pegue el enlace completo del curso, empezando con https://');
      return;
    }
    setState(() {
      _enviando = true;
      _error = '';
    });
    try {
      var excepcion = false;
      late Map<String, dynamic> d;
      while (true) {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'excepcion': excepcion,
                'accion': 'autogestivo_habilitar',
                'matricula': _alumno!.matricula,
                'clave': clave,
                'materia': materia,
                'link': link,
                'instrucciones': _instr.text.trim(),
                'inicio': _ymd(_inicio),
                'semanas': _semanas,
                'requierePago': _requierePago,
              }))
          .timeout(const Duration(seconds: 60));
      d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['requiereExcepcion'] == true && !excepcion && mounted) {
        if (await confirmarExcepcionAutog(context, '${d['error']}')) {
          excepcion = true;
          continue;
        }
        if (mounted) setState(() => _enviando = false);
        return;
      }
      break;
      }
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo asignar.');
      if (!mounted) return;
      // Si el alumno no está al corriente, se avisa antes de cerrar: puede
      // que no convenga que pague un recursamiento con adeudo pendiente.
      final aviso = '${d['aviso'] ?? ''}';
      if (aviso.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Asignado, con una observación'),
            content: Text(aviso),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Asignar recursamiento autogestivo', style: TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 1. Alumno
            const Text('1. Alumno', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
            const SizedBox(height: 6),
            if (_alumno == null) ...[
              TextField(
                controller: _busca,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  hintText: _cargandoPadron ? 'Cargando padrón…' : 'Nombre o matrícula',
                ),
              ),
              ..._coinciden.map((a) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.nombre, style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text('${a.matricula} · ${a.programa} · ${a.generacion}',
                        style: const TextStyle(fontSize: 11.5)),
                    onTap: () => _elegirAlumno(a),
                  )),
            ] else
              Row(children: [
                Expanded(
                  child: Text('${_alumno!.nombre}\n${_alumno!.matricula} · ${_alumno!.programa}',
                      style: const TextStyle(fontSize: 13.5, height: 1.35)),
                ),
                TextButton(
                  onPressed: _enviando ? null : () => setState(() => _alumno = null),
                  child: const Text('Cambiar'),
                ),
              ]),
            // 2. Materia
            if (_alumno != null) ...[
              const SizedBox(height: 14),
              const Text('2. Materia', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              const SizedBox(height: 4),
              if (_cargandoPlan)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Center(child: CircularProgressIndicator(color: cessumRed)),
                )
              else ...[
                if (_errorPlan.isNotEmpty)
                  Text('No se pudo leer su plan ($_errorPlan). Escriba la materia.',
                      style: const TextStyle(fontSize: 12, color: cessumRed)),
                if (_pendientes.isNotEmpty)
                  Text('Materias que tiene pendientes:', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                ..._pendientes.map((m) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: '${m['clave']}|${m['materia']}',
                      groupValue: _otra || _materia == null ? null : '${_materia!['clave']}|${_materia!['materia']}',
                      onChanged: (_) => setState(() {
                        _materia = m;
                        _otra = false;
                      }),
                      title: Text('${m['materia']}', style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${m['clave']} · ${m['ciclo']}', style: const TextStyle(fontSize: 11)),
                    )),
                if (_pendientes.isNotEmpty)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _otra,
                    onChanged: (v) => setState(() => _otra = v == true),
                    title: const Text('Otra materia (escribirla)', style: TextStyle(fontSize: 13)),
                  ),
                if (_otra)
                  TextField(
                    controller: _materiaLibre,
                    onChanged: (_) => setState(() {}),   // (5-oct-2026) el selector del curso busca con lo que se escribe
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder(), labelText: 'Nombre de la materia'),
                  ),
              ],
              // 3. Curso
              const SizedBox(height: 14),
              const Text('3. Curso del aula', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              const SizedBox(height: 6),
              // (5-oct-2026) Sugiere el curso más completo de la materia; se puede abrir antes de matricular.
              AulaCursoSelector(
                materia: _otra ? _materiaLibre.text.trim() : '${_materia?['materia'] ?? ''}',
                programa: _alumno?.programa ?? '',
                link: _link,
              ),
              TextField(
                controller: _link,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'https://aula.cessum.mx/course/view.php?id=…',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                  _requierePago
                      ? 'NO lo matricule a mano en el Aula: el Guardián lo matricula en este curso en cuanto se valide su pago. '
                          'Si ya está matriculado, quítele la matrícula para que no entre sin pagar.'
                      : 'El Guardián lo matricula en este curso al asignarlo.',
                  style: TextStyle(fontSize: 11.5, color: _requierePago ? cessumRed : cessumMuted(context))),
              // 4. Periodo
              const SizedBox(height: 14),
              const Text('4. Periodo', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              const SizedBox(height: 6),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final f = await showDatePicker(
                      context: context,
                      initialDate: _inicio,
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      helpText: 'Inicio del periodo',
                    );
                    if (f != null) setState(() => _inicio = f);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('Inicia ${_dma(_inicio)}'),
                ),
                DropdownButton<int>(
                  value: _semanas,
                  items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text('$i semana${i == 1 ? '' : 's'}'))],
                  onChanged: (v) => setState(() => _semanas = v ?? 5),
                ),
              ]),
              Text('Termina el ${_dma(_fin)}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeThumbColor: cessumRed,
                value: _requierePago,
                onChanged: (v) => setState(() => _requierePago = v),
                title: const Text('Requiere pago', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                    _requierePago
                        ? 'El curso se le abre cuando suba su comprobante y se valide.'
                        : 'Se le abre el curso de inmediato, sin cobro.',
                    style: const TextStyle(fontSize: 11.5)),
              ),
              // 5. Indicaciones
              const SizedBox(height: 14),
              const Text('5. Indicaciones para el alumno', style: TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
              const SizedBox(height: 6),
              TextField(
                controller: _instr,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Ej. Realiza las 4 actividades del curso y envíalas antes del 30 de octubre.',
                ),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_error, style: const TextStyle(color: cessumRed, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _enviando ? null : () => Navigator.pop(context, false), child: const Text('Cerrar')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: _enviando || _alumno == null ? null : _guardar,
          icon: _enviando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check, size: 18),
          label: const Text('Asignar y avisar al alumno'),
        ),
      ],
    );
  }
}

// =====================================================================
//  (24-sep) Resolver la solicitud autogestiva de un alumno.
// =====================================================================
class _DialogoResolver extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool aprobar;
  const _DialogoResolver({required this.item, required this.aprobar});
  @override
  State<_DialogoResolver> createState() => _DialogoResolverState();
}

class _DialogoResolverState extends State<_DialogoResolver> {
  final _link = TextEditingController();
  final _instr = TextEditingController();
  final _com = TextEditingController();
  late DateTime _inicio = _proximoLunes();
  int _semanas = 5;
  bool _requierePago = true;
  String _error = '';

  static DateTime _proximoLunes() {
    final h = DateTime.now();
    final hoy = DateTime(h.year, h.month, h.day);
    final dias = (DateTime.monday - hoy.weekday + 7) % 7;
    return hoy.add(Duration(days: dias == 0 ? 7 : dias));
  }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _dma(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void dispose() {
    _link.dispose();
    _instr.dispose();
    _com.dispose();
    super.dispose();
  }

  void _listo() {
    if (!widget.aprobar) {
      if (_com.text.trim().isEmpty) {
        setState(() => _error = 'Escriba el motivo del rechazo.');
        return;
      }
      Navigator.pop(context, {'decision': 'rechazar', 'comentario': _com.text.trim()});
      return;
    }
    if (!RegExp(r'^https://\S+$').hasMatch(_link.text.trim())) {
      setState(() => _error = 'Pegue el enlace completo del curso, empezando con https://');
      return;
    }
    Navigator.pop(context, {
      'decision': 'aprobar',
      'link': _link.text.trim(),
      'inicio': _ymd(_inicio),
      'semanas': _semanas,
      'requierePago': _requierePago,
      'instrucciones': _instr.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final x = widget.item;
    final fin = _inicio.add(Duration(days: _semanas * 7 - 1));
    return AlertDialog(
      title: Text(widget.aprobar ? 'Aprobar y asignar' : 'Rechazar solicitud', style: const TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['nombre']} · ${x['matricula']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${x['materia']}', style: const TextStyle(fontSize: 13)),
            if ('${x['nota']}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Motivo del alumno: «${x['nota']}»',
                    style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: cessumMuted(context))),
              ),
            const SizedBox(height: 12),
            if (!widget.aprobar)
              TextField(
                controller: _com,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'Motivo del rechazo'),
              )
            else ...[
              // (5-oct-2026) Sugiere el curso más completo de la materia; se puede abrir antes de matricular.
              AulaCursoSelector(materia: '${widget.item['materia'] ?? ''}', programa: '${widget.item['programa'] ?? ''}', link: _link),
              TextField(
                controller: _link,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(), isDense: true, labelText: 'Enlace del curso',
                    hintText: 'https://aula.cessum.mx/course/view.php?id=…'),
              ),
              const SizedBox(height: 4),
              const Text('NO lo matricule a mano: el Guardián lo matricula al validarse el pago.',
                  style: TextStyle(fontSize: 11.5, color: cessumRed)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final f = await showDatePicker(
                      context: context,
                      initialDate: _inicio,
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (f != null) setState(() => _inicio = f);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('Inicia ${_dma(_inicio)}'),
                ),
                DropdownButton<int>(
                  value: _semanas,
                  items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text('$i semana${i == 1 ? '' : 's'}'))],
                  onChanged: (v) => setState(() => _semanas = v ?? 5),
                ),
              ]),
              Text('Termina el ${_dma(fin)}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeThumbColor: cessumRed,
                value: _requierePago,
                onChanged: (v) => setState(() => _requierePago = v),
                title: const Text('Requiere pago', style: TextStyle(fontSize: 13)),
              ),
              TextField(
                controller: _instr,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'Indicaciones para el alumno'),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_error, style: const TextStyle(color: cessumRed, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: widget.aprobar ? const Color(0xFF1E7F52) : cessumRed),
          onPressed: _listo,
          child: Text(widget.aprobar ? 'Aprobar y avisar' : 'Rechazar y avisar'),
        ),
      ],
    );
  }
}

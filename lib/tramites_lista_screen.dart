import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;   // para incrustar el PDF en la página

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';

/// Apartado de TRÁMITES escolares para administración: ver solicitudes,
/// marcarlas como atendidas o rechazadas y dejar notas.
class TramitesListaScreen extends StatefulWidget {
  const TramitesListaScreen({super.key});

  @override
  State<TramitesListaScreen> createState() => _TramitesListaScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

class _Tramite {
  final int fila;
  final String fecha;
  String estatus;
  final String nombre;
  final String matricula;
  final String correo;
  final String programa;
  final String modalidad;
  final String generacion;
  final String tipoTramite;
  final String observaciones;
  final String comprobante;
  final String comprobantePago;
  final String resueltoPor;
  final String fechaResolucion;
  final String notas;
  final String documento;
  final int? limiteMs;

  _Tramite.fromMap(Map<String, dynamic> m)
      : fila = int.tryParse('${m['fila']}') ?? 0,
        fecha = (m['fecha'] ?? '').toString(),
        estatus = (m['estatus'] ?? '').toString(),
        nombre = (m['nombre'] ?? '').toString(),
        matricula = (m['matricula'] ?? '').toString(),
        correo = (m['correo'] ?? '').toString(),
        programa = (m['programa'] ?? '').toString(),
        modalidad = (m['modalidad'] ?? '').toString(),
        generacion = (m['generacion'] ?? '').toString(),
        tipoTramite = (m['tipoTramite'] ?? '').toString(),
        observaciones = (m['observaciones'] ?? '').toString(),
        comprobante = (m['comprobante'] ?? '').toString(),
        comprobantePago = (m['comprobantePago'] ?? '').toString(),
        resueltoPor = (m['resueltoPor'] ?? '').toString(),
        fechaResolucion = (m['fechaResolucion'] ?? '').toString(),
        notas = (m['notas'] ?? '').toString(),
        documento = (m['documento'] ?? '').toString(),
        limiteMs = (m['limiteMs'] is num) ? (m['limiteMs'] as num).toInt() : null;
}

class _TramitesListaScreenState extends State<TramitesListaScreen> {
  bool _cargando = true;
  String? _error;
  List<_Tramite> _items = [];
  final TextEditingController _busqueda = TextEditingController();
  String _filtro = '';

  /// (ago-20) FILTRO POR SITUACIÓN.
  ///
  /// La lista mezclaba todo —lo urgente, lo vencido, lo ya resuelto y lo que
  /// espera un pago— y había que leer tarjeta por tarjeta para saber qué
  /// tocaba. Con cien trámites eso no se hace: se atiende lo que quedó
  /// arriba, y lo vencido se hunde.
  ///
  /// «Fuera de tiempo» va primero a propósito: es lo único de esta pantalla
  /// donde alguien ya lleva esperando de más.
  String _situacion = 'todos';

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _cargar();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
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

  /// En qué situación está un trámite. Usa el mismo cálculo que el semáforo
  /// de la tarjeta, para que el filtro y la etiqueta nunca se contradigan.
  String _situacionDe(_Tramite t) {
    if (_esAtendido(t.estatus) || _esRechazo(t.estatus)) return 'atendido';
    // «En espera de requisitos» lo pone quien anota que falta algo —un pago,
    // un documento—. No es un retraso nuestro: es que no procede todavía.
    final est = _norm(t.estatus);
    if (est.contains('espera') || t.notas.contains('[NO PROCEDE AUN]')) {
      return 'espera';
    }
    if (t.limiteMs == null) return 'entiempo';
    return DateTime.now().millisecondsSinceEpoch >= t.limiteMs!
        ? 'fuera'
        : 'entiempo';
  }

  bool _coincide(_Tramite t) {
    if (_situacion != 'todos' && _situacionDe(t) != _situacion) return false;
    final q = _norm(_filtro);
    if (q.isEmpty) return true;
    final blob = _norm('${t.nombre} ${t.matricula} ${t.programa} '
        '${t.generacion} ${t.modalidad} ${t.tipoTramite} '
        '${t.observaciones} ${t.correo}');
    for (final palabra in q.split(RegExp(r'\s+'))) {
      if (palabra.isEmpty) continue;
      if (!blob.contains(palabra)) return false;
    }
    return true;
  }

  /// Las pestañas de situación, con su conteo. El número importa: si dice
  /// «Fuera de tiempo (0)» se puede pasar de largo con tranquilidad, y si
  /// dice 14 se sabe sin abrir nada.
  Widget _filtrosSituacion(List<_Tramite> todos) {
    final cuenta = <String, int>{
      'todos': todos.length,
      'entiempo': 0,
      'fuera': 0,
      'espera': 0,
      'atendido': 0,
    };
    for (final t in todos) {
      final s = _situacionDe(t);
      cuenta[s] = (cuenta[s] ?? 0) + 1;
    }

    final opciones = <List<dynamic>>[
      ['fuera', 'Fuera de tiempo', cessumRed],
      ['entiempo', 'Atender', const Color(0xFF1E7B34)],
      ['espera', 'En espera', const Color(0xFFB07D12)],
      ['atendido', 'Atendidos', cessumMuted(context)],
      ['todos', 'Todos', cessumMuted(context)],
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opciones.map((o) {
          final clave = o[0] as String;
          final texto = o[1] as String;
          final color = o[2] as Color;
          final n = cuenta[clave] ?? 0;
          final activo = _situacion == clave;
          return Padding(
            padding: const EdgeInsets.only(right: 7),
            child: InkWell(
              onTap: () => setState(() => _situacion = clave),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: activo ? color : color.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text('$texto ($n)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: activo ? Colors.white : color)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buscador() {
    return TextField(
      controller: _busqueda,
      onChanged: (v) => setState(() => _filtro = v),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Buscar por nombre, matrícula, programa, tipo…',
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

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          // (ago-29) Se manda el actor: la ruta ya exige rol de administrador.
          // Devuelve el padrón de trámites completo y no puede quedar abierta.
          .replace(queryParameters: {
        'accion': 'tramites_listar',
        'actor': await SessionStore.realEmail() ?? '',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final lista = (data['tramites'] as List<dynamic>? ?? [])
          .map((e) => _Tramite.fromMap(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _items = lista;
          _cargando = false;
        });
        // (2-sep) Con la lista en mano se piden TODOS los adeudos en una
        // sola llamada, en lugar de una petición por tarjeta.
        _pedirAdeudosLote();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar. Revisa tu conexión.';
        });
      }
    }
  }

  // 'Atendido'/'Atendida' = atendido. Rechazo robusto (variantes/acentos).
  bool _esAtendido(String e) => e.toLowerCase().startsWith('atend');
  bool _esRechazo(String e) {
    final s = e.toLowerCase();
    return s.contains('rechaz') ||
        s.contains('cancel') ||
        s.contains('negad') ||
        s.contains('denegad') ||
        s.contains('improceden');
  }

  // (1-oct-2026) ¿Este trámite es Informe financiero o Constancia de No
  // Adeudo? Esos dos ya no se generan directo al "Validar y enviar": pasan
  // primero por la pantalla de decisión, dato por dato.
  bool _requiereDecisionAdeudo(String tipoTramite) {
    final n = tipoTramite.toLowerCase();
    return n.contains('informe financiero') ||
        (n.contains('adeudo') && !n.contains('sin adeudo'));
  }

  // (1-oct-2026) PANTALLA DE DECISIÓN — dato por dato, antes de generar.
  // Trae el desglose completo (adeudoRealDeAlumno_ vía informe_financiero_
  // decision), lo muestra entero, y deja capturar un adeudo manual si el
  // cálculo no basta. Devuelve null si el admin cancela, o un Map con lo
  // que hay que mandar a tramite_validar para que SÍ genere el documento:
  // {'adeudoConfirmadoPor': correo, 'adeudoConfirmado': {...}} o
  // {'adeudoConfirmadoPor': correo, 'adeudoManual': monto, 'notaAdeudoManual': texto}.
  Future<Map<String, dynamic>?> _pantallaDecisionAdeudo(_Tramite t) async {
    Map<String, dynamic>? decision;
    String? error;
    final cerrarAvance = _mostrarAvance('Calculando el adeudo contra el plan');
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'informe_financiero_decision',
        'matricula': t.matricula,
        'actor': await SessionStore.realEmail() ?? '',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        decision = data;
      } else {
        error = (data['error'] ?? 'No se pudo calcular el adeudo.').toString();
      }
    } catch (e) {
      error = 'No se pudo consultar el cálculo: $e';
    }
    cerrarAvance();

    if (error != null) {
      _aviso(error);
      return null;
    }
    if (decision == null) return null;

    final ac = Map<String, dynamic>.from(decision['adeudoCalculado'] as Map);
    final alumno = Map<String, dynamic>.from(decision['alumno'] as Map);
    final pagos = ((ac['detallePagos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final materias = ((ac['detalleMaterias'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final anomalias = ((ac['anomalias'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final avisos = ((ac['avisos'] as List?) ?? []).map((e) => '$e').toList();
    final calculable = ac['calculable'] == true;
    final sync = Map<String, dynamic>.from((decision['sincronizacionPagos'] as Map?) ?? {});
    final syncVigente = sync['vigente'] == true;
    final avisoPagos = (sync['aviso'] ?? '').toString();
    final reporte = (decision['reporte'] ?? '').toString();

    final adeudoManualCtrl = TextEditingController();
    final notaManualCtrl = TextEditingController();
    // No permitir confirmar un saldo calculado con pagos no sincronizados.
    bool usarManual = !calculable || !syncVigente;

    final confirmado = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Revisión antes de generar — Informe financiero'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${alumno['nombre']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text('${alumno['matricula']} · ${alumno['programa']} · ${alumno['generacion']} · ${alumno['modalidad']}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  const Divider(height: 20),
                  if (!syncVigente) ...[
                     Container(
                       padding: const EdgeInsets.all(10),
                       decoration: BoxDecoration(
                         color: Colors.orange.withValues(alpha: 0.12),
                         borderRadius: BorderRadius.circular(8),
                         border: Border.all(color: Colors.orange),
                       ),
                       child: Text(
                         'ADVERTENCIA: $avisoPagos Actualiza los pagos y vuelve a abrir esta revisión. '
                         'Solo utiliza el importe manual si ya cotejaste los recibos por otro medio.',
                         style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                       ),
                     ),
                     const SizedBox(height: 10),
                   ],
                  if (!calculable) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('No se pudo calcular el adeudo automáticamente',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          for (final a in avisos)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('• $a', style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Text('Modo de pago: ${ac['modoPago']}', style: const TextStyle(fontSize: 13)),
                    Text('Costo por materia: \$${(ac['costoPorMateria'] ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    Text('Materias exigibles a la fecha: ${ac['materiasExigibles']}',
                        style: const TextStyle(fontSize: 13)),
                    Text('Materias cubiertas (pagadas, validadas): ${ac['materiasCubiertas']}',
                        style: const TextStyle(fontSize: 13)),
                    Text('Materias faltantes: ${ac['materiasFaltantes']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: cessumRed)),
                    Text('Adeudo calculado: \$${(ac['adeudoCalculado'] ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 10),
                  ],
                  if (anomalias.isNotEmpty) ...[
                    const Text('Anomalías detectadas en los pagos:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.red)),
                    for (final an in anomalias)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, left: 4),
                        child: Text('• ${an['fecha']} — ${an['detalle']}', style: const TextStyle(fontSize: 11.5)),
                      ),
                    const SizedBox(height: 10),
                  ],
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Materias exigibles (${materias.length})', style: const TextStyle(fontSize: 13)),
                    children: [
                      for (final m in materias)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text('• ${m['denominacion']} (${m['periodo']}) — ${m['estado']}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Pagos registrados (${pagos.length})', style: const TextStyle(fontSize: 13)),
                    children: [
                      for (final p in pagos)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                              '• ${p['fecha']} · ${p['tipo']} · \$${(p['monto'] ?? 0).toStringAsFixed(2)} · ${p['estatus']}',
                              style: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const Divider(height: 24),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: usarManual,
                      onChanged: (!calculable || !syncVigente)
                          ? null
                          : (v) => setD(() => usarManual = v ?? false),
                    title: const Text('Capturar adeudo manual (en vez del calculado)',
                        style: TextStyle(fontSize: 13)),
                  ),
                  if (usarManual) ...[
                    TextField(
                      controller: adeudoManualCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Adeudo manual (pesos, 0 si es sin adeudo)',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notaManualCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Nota (por qué se ajustó manualmente)',
                          isDense: true,
                          border: OutlineInputBorder()),
                      maxLines: 2,
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar reporte del caso (para revisión a fondo)',
                        style: TextStyle(fontSize: 12.5)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: reporte));
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Reporte copiado.')));
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Confirmar importe y continuar'),
              onPressed: () async {
                if (usarManual) {
                  final monto = double.tryParse(adeudoManualCtrl.text.trim().replaceAll(',', ''));
                  if (monto == null || !monto.isFinite || monto < 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Captura un importe válido no negativo (puede ser 0).')));
                    return;
                  }
                  if (notaManualCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Explica el ajuste manual, incluso cuando el adeudo sea 0.')));
                    return;
                  }
                  Navigator.pop(ctx, {
                    'adeudoManual': monto,
                    'notaAdeudoManual': notaManualCtrl.text.trim(),
                  });
                } else {
                  if (!calculable) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content: Text('No es calculable — marca "Capturar adeudo manual" para continuar.')));
                    return;
                  }
                  Navigator.pop(ctx, {'confirmaCalculado': true});
                }
              },
            ),
          ],
        ),
      ),
    );

    if (confirmado == null) return null;
    final correoAdmin = await SessionStore.realEmail() ?? 'Administración';
    if (confirmado['adeudoManual'] != null) {
      return {
        'adeudoConfirmadoPor': correoAdmin,
        'adeudoManual': confirmado['adeudoManual'],
        'notaAdeudoManual': confirmado['notaAdeudoManual'],
      };
    }
    return {'adeudoConfirmadoPor': correoAdmin};
  }

  Future<void> _resolver(_Tramite t, String estatus) async {
    final bool atender = estatus == 'Atendido';
    // (1-oct-2026) Informe financiero / No Adeudo: antes de mostrar el
    // diálogo normal de "Validar y enviar", pasa por la pantalla de
    // decisión. Si el admin cancela ahí, no se abre nada más.
    Map<String, dynamic>? decisionAdeudo;
    if (atender && _requiereDecisionAdeudo(t.tipoTramite)) {
      decisionAdeudo = await _pantallaDecisionAdeudo(t);
      if (decisionAdeudo == null) return;
    }
    final notas = TextEditingController(text: t.notas);
    // (ago-3) Constancia oficial: campos opcionales para fijar periodo y
    // fechas exactas (calendarios especiales, p. ej. becas). Vacíos = el
    // sistema los calcula solo de calificaciones y asignaciones.
    final tipoLc = t.tipoTramite.toLowerCase();
    final esOficial = atender &&
        tipoLc.contains('constancia') &&
        tipoLc.contains('oficial');
    final ovrPeriodo = TextEditingController();
    final ovrInicio = TextEditingController();
    final ovrTermino = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(atender ? 'Validar y enviar' : 'Rechazar trámite'),
        content: SingleChildScrollView(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t.tipoTramite}\n${t.nombre}',
                style: const TextStyle(height: 1.4)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (!atender
                        ? cessumRed
                        : (t.documento.startsWith('http') || !_esOtro(t)
                            ? _verdeOk
                            : const Color(0xFFB07D12)))
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              // (ago-22) EL AVISO PROMETÍA UN DOCUMENTO QUE NO SIEMPRE EXISTE.
              // Decía siempre «se generará el documento oficial y se enviará
              // con el PDF adjunto». Para los tipos con plantilla es cierto;
              // para «Otro» no hay plantilla, así que el alumno recibía el
              // correo de trámite atendido SIN nada — y el aviso le había
              // dicho a quien valida que sí iba adjunto. Ahora el texto
              // depende de lo que de verdad va a pasar.
              child: Text(
                !atender
                    ? 'El alumno recibirá un correo indicando que su trámite '
                        'fue rechazado. No se adjunta documento.'
                    : (t.documento.startsWith('http')
                        ? 'Se enviará por correo al alumno el documento que ya '
                            'está adjunto a este trámite, y quedará '
                            'descargable en "Mis trámites".'
                        : (_esOtro(t)
                            ? 'ATENCIÓN: este trámite es de tipo «Otro» y no '
                                'tiene plantilla, así que NO se genera ningún '
                                'documento. El alumno recibirá el aviso de '
                                'trámite atendido SIN documento. Si quieres '
                                'enviarle algo, cierra esto y usa «Generar '
                                'documento» y luego «Adjuntar constancia '
                                'generada».'
                            : 'Al validar se generará el documento oficial y '
                                'se enviará por correo al alumno con el PDF '
                                'adjunto. También quedará descargable en '
                                '"Mis trámites".')),
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: (atender &&
                            !t.documento.startsWith('http') &&
                            _esOtro(t))
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: (atender &&
                            !t.documento.startsWith('http') &&
                            _esOtro(t))
                        ? const Color(0xFF8A5A00)
                        : null),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notas,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Nota para el alumno (opcional)',
                  border: OutlineInputBorder()),
            ),
            if (esOficial) ...[
              const SizedBox(height: 12),
              const Text('DATOS DEL CICLO (TRIMESTRE/SEMESTRE) (opcional)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFA56B16),
                      letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(
                'Déjalos vacíos para que el sistema los calcule. Llénalos '
                'solo si el alumno pide fechas o periodo específicos.',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ovrPeriodo,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Número de periodo (ej. 3)',
                    isDense: true,
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: ovrInicio,
                    decoration: const InputDecoration(
                        labelText: 'Inicio (dd/mm/aaaa)',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: ovrTermino,
                    decoration: const InputDecoration(
                        labelText: 'Término (dd/mm/aaaa)',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                ),
              ]),
            ],
          ],
        )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: atender ? _verdeOk : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(atender ? Icons.send : Icons.cancel, size: 18),
            label: Text(atender ? 'Validar y enviar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // La misma barra de la vista previa: este paso tarda tanto o más, y sin
    // señal de vida uno pulsa otra vez — y aquí volver a pulsar significa
    // generar y ENVIAR el documento dos veces al alumno.
    final cerrarAvance = _mostrarAvance(
        atender ? 'Generando y enviando el documento' : 'Registrando el rechazo');
    setState(() => _cargando = true);
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http.post(
        Uri.parse(guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'accion': 'tramite_validar',
          'fila': t.fila,
          'matricula': t.matricula,
          'estatus': estatus,
          'notas': notas.text.trim(),
          'validadaPor': correo ?? 'Administración',
          if (esOficial && ovrPeriodo.text.trim().isNotEmpty)
            'periodo': ovrPeriodo.text.trim(),
          if (esOficial && ovrInicio.text.trim().isNotEmpty)
            'inicio': ovrInicio.text.trim(),
          if (esOficial && ovrTermino.text.trim().isNotEmpty)
            'termino': ovrTermino.text.trim(),
          if (decisionAdeudo != null) ...decisionAdeudo,
        }),
      // (ago-27) 150 s, no 90. «Validar y enviar» hace mucho más que la vista
      // previa: arma el documento, lo mueve a la carpeta, lo comparte con el
      // alumno, registra el folio y manda el correo. Con 90 la APP se rendía
      // antes que el servidor — el proxy da 120 y Apps Script sigue
      // trabajando — así que el documento a veces SÍ se generaba y se enviaba,
      // y aquí se veía como un error. Peor que lento: confuso.
      ).timeout(const Duration(seconds: 150));
      cerrarAvance();
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso(atender
          ? (data['yaAtendido'] == true
              ? 'El trámite ya estaba atendido: no se generó un duplicado.'
              : 'Trámite atendido y documento ligado para el alumno.')
          : 'Trámite rechazado. Se notificó al alumno.');
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
      cerrarAvance();
      _aviso('No se pudo guardar: $e');
    }
  }

  bool _esCambioModalidad(_Tramite t) =>
      t.tipoTramite.toLowerCase().contains('modalidad');

  String _modalidadDeseada(_Tramite t) {
    final m =
        RegExp(r'[Mm]odalidad deseada:\s*(.+)').firstMatch(t.observaciones);
    return m != null ? m.group(1)!.trim() : '';
  }

  Future<void> _aprobarYMover(_Tramite t) async {
    final modalidades = ['Virtual', 'Mixta', 'No Escolarizada'];
    String? modSel = _modalidadDeseada(t);
    if (!modalidades.contains(modSel)) modSel = null;
    final grupoCtrl = TextEditingController();
    final notasCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Aprobar y mover'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t.nombre} · ${t.matricula}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    'Modalidad actual: '
                    '${t.modalidad.isEmpty ? "Sin registrar" : t.modalidad}',
                    style: TextStyle(color: cessumMuted(context))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: modSel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Modalidad nueva *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: modalidades
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setLocal(() => modSel = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: grupoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Grupo destino *',
                    hintText: 'Ej. "No escolarizado" o "1 - mixto"',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notasCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Esto cambia su modalidad y grupo, marca el trámite como '
                  'atendido y le avisa por correo.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _verdeOk, foregroundColor: Colors.white),
              onPressed: () {
                if (modSel == null || modSel!.isEmpty) return;
                if (grupoCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.move_down, size: 18),
              label: const Text('Aprobar y mover'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _cargando = true);
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http.post(
        Uri.parse(guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'accion': 'tramite_modalidad_aprobar',
          'fila': t.fila,
          'matricula': t.matricula,
          'actor': correo ?? '',
          'validadaPor': correo ?? 'Administración',
          'nuevaModalidad': modSel,
          'nuevoGrupo': grupoCtrl.text.trim(),
          'notas': notasCtrl.text.trim(),
        }),
      ).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso('Modalidad cambiada y trámite atendido. Se avisó al alumno.');
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
      _aviso('No se pudo aprobar: $e'.replaceAll('Exception: ', ''));
    }
  }

  Future<void> _abrir(String url) async {
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el comprobante.');
    }
  }

  Future<void> _verDoc(String url) async {
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el documento.');
    }
  }

  // Adivina el tipo de documento para la vista previa a partir del
  // texto del trámite. Si no lo reconoce, devuelve null (se pregunta).
  String? _tipoPreview(String tipoTramite) {
    final n = tipoTramite
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
    // (14-sep) La ficha va primero: su nombre contiene «plan» y «estudio»,
    // y ninguna regla de abajo la reconocería. Mismo orden que
    // tipoDocDeTramite_ en el Guardián.
    if (n.contains('ficha de plan') ||
        n.contains('plan y programa') ||
        n.contains('plan de estudio') ||
        n.contains('rvoe')) {
      return 'plan_estudios';
    }
    // (5-oct-2026) Documentos para becas y crédito. Mismo orden que tipoDocDeTramite_ en el Guardián.
    if (n.contains('carta de costos') || n.contains('costos del programa')) return 'costos';
    if (n.contains('beca institucional') || n.contains('constancia de beca')) return 'beca';
    if (n.contains('kardex')) return 'kardex';
    if (n.contains('informe financiero')) return 'informe_financiero';
    if (n.contains('pasante')) return 'pasante';
    if (n.contains('terminaci')) return 'terminacion';
    if (n.contains('adeudo')) return 'noadeudo';
    if (n.contains('inscrip')) return 'inscripcion';
    if (n.contains('certificad')) return 'certificado';
    if (n.contains('constancia') && n.contains('oficial')) {
      return 'constancia_oficial'; // la de becas: periodo, fechas y promedios
    }
    if (n.contains('constancia')) return 'constancia';
    return null;
  }

  // (ago-24) ESTADO DE CUENTA DEL ALUMNO, EN LA MISMA TARJETA.
  //
  // Se emitían constancias y kardex sin saber si el alumno debía. Quien
  // atiende el trámite se enteraba después, o nunca. La etiqueta se consulta
  // al vuelo por matrícula y se recuerda mientras dure la pantalla, para no
  // pedir lo mismo cada vez que se redibuja la lista.
  final Map<String, Map<String, dynamic>> _adeudo = {};
  final Set<String> _adeudoPidiendo = {};
  // (2-sep) Mientras el lote de adeudos está en camino, las tarjetas NO
  // disparan peticiones individuales: esa ráfaga era la que congestionaba
  // la cola de Apps Script (489 llamadas de adeudo_estado en 7 días,
  // p95 17.7 s, medido en Tiempos). Cuando el lote ya pasó —bien o mal—
  // la petición por tarjeta queda solo como respaldo de lo que falte.
  bool _loteIntentado = false;

  // (2-sep) ADEUDOS EN LOTE: una sola llamada resuelve todas las
  // matrículas de la lista con UNA lectura de Vencimientos en el Guardián.
  Future<void> _pedirAdeudosLote() async {
    _loteIntentado = false;
    final mats = <String>{};
    for (final t in _items) {
      final m = t.matricula.trim();
      if (m.isNotEmpty && !_adeudo.containsKey(m)) mats.add(m);
    }
    if (mats.isEmpty) {
      _loteIntentado = true;
      if (mounted) setState(() {});
      return;
    }
    try {
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'adeudos_lote',
        'actor': await SessionStore.realEmail() ?? '',
        'matriculas': mats.join(','),
      });
      final r = await http.get(u).timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final ads = d['adeudos'];
      if (d['ok'] == true && ads is Map<String, dynamic>) {
        ads.forEach((mat, v) {
          if (v is Map<String, dynamic>) _adeudo[mat.trim()] = v;
        });
      }
    } catch (_) {
      // Si el lote no llegó, el respaldo por tarjeta sigue funcionando.
    } finally {
      _loteIntentado = true;
      if (mounted) setState(() {});
    }
  }

  Future<void> _pedirAdeudo(String matricula) async {
    final mat = matricula.trim();
    if (mat.isEmpty || _adeudo.containsKey(mat) || _adeudoPidiendo.contains(mat)) {
      return;
    }
    _adeudoPidiendo.add(mat);
    try {
      final u = Uri.parse(guardianUrl).replace(
          queryParameters: {'accion': 'adeudo_estado', 'matricula': mat});
      final r = await http.get(u).timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() => _adeudo[mat] = d);
      }
    } catch (_) {
      // Sin respuesta no se pinta etiqueta: mejor no decir nada que decir
      // "al día" de alguien que quizá deba.
    } finally {
      _adeudoPidiendo.remove(mat);
    }
  }

  /// Etiqueta AL DÍA / CON PAGOS PENDIENTES, tocable para ver el desglose.
  Widget _selloAdeudo(_Tramite t) {
    final d = _adeudo[t.matricula.trim()];
    if (d == null) {
      // (2-sep) Mientras el lote está en camino, aquí no se dispara nada:
      // la ráfaga individual era la que saturaba la cola. Si el lote ya
      // pasó y esta matrícula quedó sin dato, se pide sola (respaldo).
      if (_loteIntentado) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _pedirAdeudo(t.matricula));
      }
      return const SizedBox.shrink();
    }
    final alDia = d['alDia'] == true;
    final c = alDia ? _verdeOk : cessumRed;
    final porVencer = (d['porVencer'] ?? 0) is num ? (d['porVencer'] as num) : 0;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: InkWell(
        onTap: () => _verDesglose(t, d),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withValues(alpha: 0.45)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(alDia ? Icons.verified_outlined : Icons.error_outline,
                size: 15, color: c),
            const SizedBox(width: 6),
            Text('${d['etiqueta']}',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: c)),
            if (!alDia) ...[
              const SizedBox(width: 6),
              Text('\$${d['totalVencido']}',
                  style: TextStyle(fontSize: 11.5, color: c)),
            ] else if (porVencer > 0) ...[
              const SizedBox(width: 6),
              Text('· $porVencer por vencer',
                  style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ],
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 14, color: c),
          ]),
        ),
      ),
    );
  }

  Future<void> _verDesglose(_Tramite t, Map<String, dynamic> d) async {
    final des = Map<String, dynamic>.from(
        (d['desglose'] as Map?) ?? const <String, dynamic>{});
    final venc = ((des['vencidos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final pv = ((des['porVencer'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${d['etiqueta']}', style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t.nombre} · ${t.matricula}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${d['resumen']}',
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
                if (venc.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Vencidos (${venc.length})',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: cessumRed)),
                  const SizedBox(height: 4),
                  ...venc.map((p) => _renglonPago(p, cessumRed, t)),
                ],
                if (pv.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Por vencer (${pv.length})',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFB07D12))),
                  const SizedBox(height: 3),
                  Text('Aún en plazo: no cuentan como adeudo.',
                      style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                  const SizedBox(height: 4),
                  ...pv.map((p) => _renglonPago(p, const Color(0xFFB07D12), t)),
                ],
                if (venc.isEmpty && pv.isEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('No hay pagos registrados como pendientes.',
                      style: TextStyle(fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _agregarVencimientoDialog(t);
            },
            icon: const Icon(Icons.add, size: 17, color: cessumRed),
            label: const Text('Agregar vencimiento',
                style: TextStyle(color: cessumRed)),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  // (29-sep) Marca un vencimiento como pagado sin borrarlo (conserva el
  // historial). Refresca el sello de adeudo de esa matrícula al terminar,
  // para que la tarjeta refleje el cambio de inmediato.
  Future<void> _marcarVencimientoPagado(Map<String, dynamic> p, _Tramite t) async {
    final fila = p['fila'];
    if (fila == null) return;
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'vencimiento_marcar_pagado',
                'fila': fila,
                'actor': await SessionStore.realEmail() ?? '',
              }))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // cierra el diálogo de desglose
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('Marcado como pagado: ${p['concepto']}.'),
      ));
      _pedirAdeudo(t.matricula);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('No se pudo marcar como pagado: $e'),
      ));
    }
  }

  // (29-sep) Captura manual de un vencimiento/adeudo DESDE el trámite del
  // alumno — sin buscador, porque ya se sabe de quién es. Es la misma ruta
  // que usa la pantalla de "Recordatorios de pago", así que aparece ahí
  // también y el alumno la ve reflejada donde consulta sus pagos.
  Future<void> _agregarVencimientoDialog(_Tramite t) async {
    final concepto = TextEditingController(text: 'Reinscripción');
    final monto = TextEditingController();
    final fecha = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nuevo vencimiento · ${t.nombre}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Matrícula ${t.matricula}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 10),
              TextField(
                controller: concepto,
                decoration: const InputDecoration(
                  labelText: 'Concepto *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: monto,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fecha,
                decoration: const InputDecoration(
                  labelText: 'Fecha límite (dd/mm/aaaa) *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
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
            onPressed: () {
              if (concepto.text.trim().isEmpty || fecha.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Escribe el concepto y la fecha límite.'),
                ));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'vencimiento_guardar',
                'matricula': t.matricula,
                'nombre': t.nombre,
                'correo': t.correo,
                'programa': t.programa,
                'concepto': concepto.text.trim(),
                'monto': monto.text.trim(),
                'fechaLimite': fecha.text.trim(),
                'actor': await SessionStore.realEmail() ?? '',
              }))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.green,
        content: Text('Vencimiento registrado.'),
      ));
      _pedirAdeudo(t.matricula);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('No se pudo guardar: $e'),
      ));
    }
  }

  Widget _renglonPago(Map<String, dynamic> p, Color c, _Tramite t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['concepto']}',
                    style: const TextStyle(fontSize: 12.5)),
                Text('Vence ${p['fechaLimite']}',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black45)),
              ],
            ),
          ),
          Text('${p['monto']}',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, size: 19),
            color: _verdeOk,
            tooltip: 'Marcar como pagado',
            visualDensity: VisualDensity.compact,
            onPressed: () => _marcarVencimientoPagado(p, t),
          ),
        ],
      ),
    );
  }

  bool _esFactura(_Tramite t) =>
      t.tipoTramite.toLowerCase().contains('factura');

  // (ago-22) «Otro» es el único tipo sin plantilla: el alumno describe con
  // sus palabras lo que necesita. El tipo llega como «Otro: <lo que pidió>»,
  // así que basta con reconocer el prefijo.
  bool _esOtro(_Tramite t) {
    final s = t.tipoTramite.trim().toLowerCase();
    return s == 'otro' || s == 'otros' || s.startsWith('otro:') ||
        s.startsWith('otros:');
  }

  // Selecciona el/los archivo(s) de la factura (PDF/XML) y los envía.
  void _subirFactura(_Tramite t) {
    final input = html.FileUploadInputElement()
      ..accept = '.pdf,.xml,application/pdf,text/xml,application/xml'
      ..multiple = true;
    input.click();
    input.onChange.listen((_) async {
      final files = input.files;
      if (files == null || files.isEmpty) return;
      final archivos = <Map<String, String>>[];
      for (final f in files) {
        final reader = html.FileReader();
        reader.readAsDataUrl(f);
        await reader.onLoadEnd.first;
        final result = reader.result as String;
        final coma = result.indexOf(',');
        final b64 = coma >= 0 ? result.substring(coma + 1) : result;
        archivos.add({
          'nombre': f.name,
          'mime': f.type.isNotEmpty ? f.type : 'application/octet-stream',
          'base64': b64,
        });
      }
      if (archivos.isEmpty) return;
      await _enviarFactura(t, archivos);
    });
  }

  // Reenvía la notificación de la solicitud de factura a facturación (contadora).
  Future<void> _reenviarFactura(_Tramite t) async {
    _aviso('Reenviando notificación a facturación…');
    try {
      final actor = await SessionStore.realEmail() ?? 'Administración';
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'factura_reenviar',
              'fila': t.fila,
              'matricula': t.matricula,
              'actor': actor,
            }),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _aviso('Notificación reenviada a facturación.');
      } else {
        _aviso(data['error']?.toString() ?? 'No se pudo reenviar.');
      }
    } catch (e) {
      _aviso('Error de conexión: $e');
    }
  }

  Future<void> _enviarFactura(
      _Tramite t, List<Map<String, String>> archivos) async {
    _aviso('Enviando factura al alumno…');
    try {
      final actor = await SessionStore.realEmail() ?? 'Administración';
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'tramite_factura_enviar',
              'fila': t.fila,
              'matricula': t.matricula,
              'actor': actor,
              'archivos': archivos,
            }),
          )
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _aviso('Factura enviada al alumno por correo.');
        await _cargar();
      } else {
        _aviso(data['error']?.toString() ?? 'No se pudo enviar la factura.');
      }
    } catch (e) {
      _aviso('Error de conexión: $e');
    }
  }

  /// Genera una COPIA editable del documento y ofrece los dos caminos:
  /// editarla en Drive o descargarla en Word. Es copia a propósito: si el
  /// alumno ya recibió su PDF, ese documento es un hecho y no debe cambiar
  /// por editar otro archivo.
  /// Sube un documento hecho a mano y lo asocia al trámite.
  ///
  /// Se pregunta si enviarlo al alumno, porque a veces se adjunta solo para
  /// dejar constancia de algo que ya se entregó en físico, y mandar un correo
  /// en ese caso confunde a quien ya lo tiene.
  Future<void> _adjuntarDocumento(_Tramite t) async {
    try {
      final input = html.FileUploadInputElement()
        ..accept = 'application/pdf,.doc,.docx,image/*';
      input.click();
      await input.onChange.first;
      if (input.files == null || input.files!.isEmpty) return;
      final file = input.files!.first;

      if (!mounted) return;
      final enviar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Adjuntar documento',
              style: TextStyle(fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(file.name,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Para ${t.nombre}',
                  style: TextStyle(
                      fontSize: 12.5, color: cessumMuted(context))),
            ),
            const SizedBox(height: 12),
            const Text(
                'El archivo queda guardado con el trámite. ¿Se lo enviamos '
                'también por correo?',
                style: TextStyle(fontSize: 12.5, height: 1.4)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Solo guardar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar y enviar'),
            ),
          ],
        ),
      );
      if (enviar == null) return;

      final reader = html.FileReader();
      reader.readAsDataUrl(file);
      await reader.onLoad.first;
      final dataUrl = reader.result as String;
      final coma = dataUrl.indexOf(',');
      if (coma < 0) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subiendo documento…')));

      final actor = await SessionStore.realEmail() ?? '';
      final r = await http.post(
        Uri.parse(guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'accion': 'tramite_adjuntar',
          'fila': t.fila,
          'base64': dataUrl.substring(coma + 1),
          'mime': file.type.isNotEmpty ? file.type : 'application/pdf',
          'nombre': file.name,
          'enviar': enviar ? '1' : '0',
          'actor': actor,
        }),
      );
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor:
            d['ok'] == true ? const Color(0xFF1E7B34) : cessumRed,
        content: Text('${d['nota'] ?? d['error'] ?? ''}'),
      ));
      if (d['ok'] == true) _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
  }

  Future<void> _generarEditable(_Tramite t) async {
    final prog = await _elegirPrograma(t);
    if (prog == null) return; // canceló
    final cerrarAvance = _mostrarAvance('Generando el documento editable');
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'tramite_generar_editable',
              'fila': t.fila,
              'matricula': t.matricula,
              'programa': prog,
              'actor': correo ?? 'Administración',
            }),
          )
          .timeout(const Duration(seconds: 120));
      // La barra se cierra ANTES de abrir el diálogo del resultado: dos
      // ventanas encimadas dejan una imposible de cerrar.
      cerrarAvance();
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso(data['error']?.toString() ?? 'No se pudo generar el editable.');
        return;
      }
      if (!mounted) return;
      final docUrl = (data['docUrl'] ?? '').toString();
      final docxUrl = (data['docxUrl'] ?? '').toString();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Documento editable listo',
              style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${data['tipo'] ?? ''} · ${data['alumno'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text(
                  'Es una copia: el documento que ya se le envió al alumno no '
                  'cambia si editas ésta. Cuando termines, envíasela con el '
                  'botón de reenviar o por correo.',
                  style: TextStyle(fontSize: 12.5, height: 1.4)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
            if (docxUrl.startsWith('http'))
              OutlinedButton.icon(
                onPressed: () {
                  launchUrl(Uri.parse(docxUrl), webOnlyWindowName: '_blank');
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.download, size: 17),
                label: const Text('Descargar Word'),
              ),
            if (docUrl.startsWith('http'))
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () {
                  launchUrl(Uri.parse(docUrl), webOnlyWindowName: '_blank');
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.edit, size: 17),
                label: const Text('Editar en Drive'),
              ),
          ],
        ),
      );
    } catch (e) {
      // La barra se cierra tambien si falla, o quedaria en pantalla.
      cerrarAvance();
      _aviso('Error de conexión: $e');
    }
  }

  // (ago-22) DOCUMENTO SUGERIDO PARA LOS TRÁMITES «OTRO».
  //
  // «Otro» no tiene plantilla: el generador contestaba «Este trámite no
  // genera un documento automático» y la carta se redactaba a mano, fuera
  // del sistema. Aquí el Guardián propone un borrador con los datos que ya
  // tiene del alumno y con lo que él mismo pidió en su solicitud —si pidió
  // días y horario, se incluyen desde la Base de Asignaciones—, con el
  // mismo encabezado, sello y firma que las demás constancias.
  //
  // Es una PROPUESTA: no manda correo, no marca el trámite y no toca el
  // documento oficial. Por eso el diálogo dice qué se incluyó y qué quedó
  // pendiente de revisar, en vez de entregar un archivo mudo.
  /// Pide una propuesta al Guardián. [indicaciones] son las correcciones que
  /// escribe quien revisa; en la primera vuelta van vacías.
  Future<Map<String, dynamic>?> _pedirPropuesta(
      _Tramite t, String indicaciones) async {
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'tramite_generar_otro',
              'fila': t.fila,
              'matricula': t.matricula,
              'indicaciones': indicaciones,
              'actor': correo ?? 'Administración',
            }),
          )
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso(data['error']?.toString() ?? 'No se pudo generar la propuesta.');
        return null;
      }
      return data;
    } catch (e) {
      _aviso('Error de conexión: $e');
      return null;
    }
  }

  /// Adopta la propuesta ya revisada como el documento del trámite: la liga a
  /// la columna Documento y la baja a solo lectura. No envía nada — de eso se
  /// encarga «Validar y enviar».
  Future<bool> _usarPropuesta(_Tramite t, String docId) async {
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'tramite_otro_usar',
              'fila': t.fila,
              'matricula': t.matricula,
              'docId': docId,
              'actor': correo ?? 'Administración',
            }),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso(data['error']?.toString() ?? 'No se pudo adjuntar.');
        return false;
      }
      return true;
    } catch (e) {
      _aviso('Error de conexión: $e');
      return false;
    }
  }

  // (ago-22) DOCUMENTO SUGERIDO PARA LOS TRÁMITES «OTRO».
  //
  // «Otro» no tiene plantilla: el generador contestaba «Este trámite no
  // genera un documento automático» y la carta se redactaba a mano, fuera
  // del sistema. Aquí el Guardián propone un borrador con los datos que ya
  // tiene del alumno y con lo que él mismo pidió en su solicitud.
  //
  // (ago-22, segunda vuelta) LA PROPUESTA SE CORRIGE Y SE ADOPTA AQUÍ MISMO.
  // Antes el diálogo solo dejaba descargar: había que corregir el Word,
  // volver a subirlo por «Adjuntar documento» —que además escribe en las
  // notas y no en la columna Documento— y hasta entonces validar. Ahora el
  // diálogo tiene tres salidas: escribir indicaciones y volver a generar,
  // adoptar la propuesta como documento del trámite, o descargarla.
  Future<void> _generarOtro(_Tramite t) async {
    _aviso('Redactando propuesta con los datos del sistema…');
    final primera = await _pedirPropuesta(t, '');
    if (primera == null || !mounted) return;
    // No nula a partir de aquí: el diálogo la reemplaza al regenerar, así que
    // se guarda en una variable no anulable para no salpicar el árbol de «!».
    var data = primera;

    final indicaciones = TextEditingController();
    var ocupado = false;
    var adoptada = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setLocal) {
          final incluido =
              (data['incluido'] as List?)?.map((e) => e.toString()).toList() ??
                  <String>[];
          final avisos =
              (data['avisos'] as List?)?.map((e) => e.toString()).toList() ??
                  <String>[];
          final aplicadas = (data['indicacionesAplicadas'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              <String>[];
          final docUrl = (data['docUrl'] ?? '').toString();
          final docxUrl = (data['docxUrl'] ?? '').toString();
          final docId = (data['docId'] ?? '').toString();

          Future<void> regenerar() async {
            setLocal(() => ocupado = true);
            final nueva = await _pedirPropuesta(t, indicaciones.text.trim());
            if (nueva != null) data = nueva;
            setLocal(() => ocupado = false);
          }

          Future<void> adoptar() async {
            setLocal(() => ocupado = true);
            final ok = await _usarPropuesta(t, docId);
            setLocal(() => ocupado = false);
            if (ok) {
              adoptada = true;
              if (ctx2.mounted) Navigator.pop(ctx2);
            }
          }

          return AlertDialog(
            title: const Text('Propuesta lista para revisar',
                style: TextStyle(fontSize: 17)),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${data['titulo'] ?? ''} · ${data['alumno'] ?? ''}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    if ((data['asunto'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Pidió: ${data['asunto']}',
                          style: TextStyle(
                              fontSize: 12, color: cessumMuted(context))),
                    ],
                    if (incluido.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Lo que incluí',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _verdeOk)),
                      const SizedBox(height: 4),
                      ...incluido.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text('·  $s',
                                style: const TextStyle(
                                    fontSize: 12.5, height: 1.35)),
                          )),
                    ],
                    if (aplicadas.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Lo que cambié con tus indicaciones',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1565C0))),
                      const SizedBox(height: 4),
                      ...aplicadas.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text('·  $s',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: Color(0xFF1565C0))),
                          )),
                    ],
                    if (avisos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Revisa antes de entregar',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB07D12))),
                      const SizedBox(height: 4),
                      ...avisos.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text('·  $s',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    color: Color(0xFF8A5A00))),
                          )),
                    ],
                    const SizedBox(height: 14),
                    TextField(
                      controller: indicaciones,
                      maxLines: 3,
                      enabled: !ocupado,
                      decoration: const InputDecoration(
                        labelText: 'Qué le falta o qué sobra',
                        helperText:
                            'Entiendo «titulo: CARTA LABORAL», «sin horario», '
                            '«sin RVOE», «agrega el horario». Lo demás se '
                            'corrige a mano en el editable.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: ocupado ? null : regenerar,
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text('Volver a generar con mis '
                            'indicaciones'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cessumGold,
                          side: const BorderSide(color: cessumGold),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (docxUrl.startsWith('http'))
                          Expanded(
                            child: TextButton.icon(
                              onPressed: ocupado
                                  ? null
                                  : () => launchUrl(Uri.parse(docxUrl),
                                      webOnlyWindowName: '_blank'),
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('Word',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                        if (docUrl.startsWith('http'))
                          Expanded(
                            child: TextButton.icon(
                              onPressed: ocupado
                                  ? null
                                  : () => launchUrl(Uri.parse(docUrl),
                                      webOnlyWindowName: '_blank'),
                              icon: const Icon(Icons.edit, size: 16),
                              label: const Text('Editar en Drive',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                        'Al adjuntarla queda como documento del trámite y se '
                        'vuelve de solo lectura. No se envía nada todavía: '
                        'eso lo hace «Validar y enviar».',
                        style: TextStyle(fontSize: 11.5, height: 1.35)),
                    if (ocupado) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(minHeight: 3),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: ocupado ? null : () => Navigator.pop(ctx2),
                  child: const Text('Cerrar')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: (ocupado || docId.isEmpty) ? null : adoptar,
                icon: const Icon(Icons.attach_file, size: 17),
                label: const Text('Adjuntar constancia generada'),
              ),
            ],
          );
        },
      ),
    );
    indicaciones.dispose();
    if (adoptada) {
      _aviso('Queda como documento del trámite. Usa «Validar y enviar» '
          'para notificarle al alumno.');
      await _cargar();
    }
  }

  /// (ago-22) ¿A NOMBRE DE QUÉ PROGRAMA SE EMITE?
  ///
  /// Un kardex, un certificado o una carta de pasante son de UN programa. Hay
  /// alumnos que cursaron dos —maestría y luego doctorado— y el padrón solo
  /// guarda el vigente: emitir siempre por el padrón deja al egresado de
  /// maestría sin forma de pedir el suyo.
  ///
  /// Y hay un caso que NO es programa cursado: las materias de otro posgrado
  /// tomadas como formación continua en las primeras generaciones. Por eso no
  /// se elige solo: se enseña cuántas materias validadas tiene en cada uno y
  /// decide quien emite. Con un solo programa, no pregunta nada.
  ///
  /// Devuelve '' si se usa el del padrón, o null si el usuario canceló.
  Future<String?> _elegirPrograma(_Tramite t) async {
    const conPrograma = ['kardex', 'certificad', 'pasante', 'terminaci'];
    final tipo = t.tipoTramite.toLowerCase();
    if (!conPrograma.any(tipo.contains)) return '';
    List<Map<String, dynamic>> progs = [];
    String padron = '';
    try {
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alumno_programas_calif',
        'matricula': t.matricula,
      });
      final r = await http.get(u).timeout(const Duration(seconds: 25));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        progs = ((d['programas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        padron = (d['programaPadron'] ?? '').toString();
      }
    } catch (_) {
      return ''; // sin catálogo, se emite como siempre: por el padrón
    }
    if (progs.length < 2) return '';
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿De qué programa es este documento?',
            style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t.nombre} tiene calificaciones de ${progs.length} '
                'programas. El documento se emite a nombre de uno solo.',
                style: const TextStyle(fontSize: 12.5, height: 1.35)),
            const SizedBox(height: 4),
            Text(
                'Pocas materias suelen ser formación continua; muchas, un '
                'programa cursado.',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 12),
            ...progs.map((p) {
              final nom = (p['programa'] ?? '').toString();
              final val = (p['validadas'] ?? 0).toString();
              final tot = (p['materias'] ?? 0).toString();
              final esPadron = p['esDelPadron'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    foregroundColor: esPadron ? cessumRed : cessumInk(context),
                    side: BorderSide(
                        color: esPadron ? cessumRed : cessumFaint(context)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onPressed: () =>
                      Navigator.pop(ctx, esPadron && nom == padron ? '' : nom),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nom,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(
                          '$val validada(s) de $tot'
                          '${esPadron ? '  ·  el vigente en el padrón' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, color: cessumMuted(context))),
                    ],
                  ),
                ),
              );
            }),
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

  /// (ago-29) ACTUALIZAR EL DOCUMENTO Y ENVIAR.
  ///
  /// Cuando un documento sale con un dato mal —una fecha, un promedio, un
  /// nombre— había que pedirle al alumno que volviera a solicitar el
  /// trámite: se generaba un folio nuevo, se le cobraba otra vez en algunos
  /// casos, y el historial quedaba con dos trámites para una sola petición.
  ///
  /// Esto REGENERA el documento del MISMO trámite, con los datos como estén
  /// hoy, y se lo reenvía. El folio, la fecha de solicitud y el registro no
  /// se tocan: es el mismo trámite, corregido.
  ///
  /// Va aparte de "Reenviar al alumno" a propósito: aquel manda otra vez el
  /// PDF que ya existe; este lo VUELVE A CONSTRUIR. Si el dato se corrigió
  /// en la base después de generarlo, solo este lo recoge.
  /// (ago-29) Tres salidas, no una. Corregir un documento suele llevar dos o
  /// tres intentos, y antes cada uno le mandaba al alumno un correo idéntico
  /// diciéndole "atendimos tu observación".
  Future<void> _actualizarDoc(_Tramite t) async {
    // 0 cancelar · 1 solo ver · 2 actualizar sin avisar · 3 actualizar y enviar
    final modo = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Actualizar el documento'),
        content: Text(
          'Se vuelve a construir el documento de este mismo trámite con los '
          'datos como están ahora.\n\n'
          'Si el error venía de un dato de la base, corrígelo ANTES: el '
          'documento se arma con lo que haya en este momento.\n\n'
          'Mientras lo afinas usa «Solo ver»: regenera sin escribirle a '
          '${t.nombre}. Cuando quede bien, envíaselo.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actionsOverflowButtonSpacing: 6,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 1),
              child: const Text('Solo ver (no envía)')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 2),
              child: const Text('Actualizar sin avisar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, 3),
            child: const Text('Actualizar y enviar'),
          ),
        ],
      ),
    );
    if (modo == null || modo == 0) return;

    _aviso(modo == 1 ? 'Generando vista previa…' : 'Regenerando el documento…');
    try {
      final correo = await SessionStore.realEmail();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'tramite_doc_reenviar',
        'matricula': t.matricula,
        'fila': '${t.fila}',
        'actor': correo ?? 'Administración',
        if (modo == 1) 'previa': '1',
        if (modo == 2) 'avisar': '0',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso(data['error']?.toString() ?? 'No se pudo actualizar.');
        return;
      }
      // El backend distingue los tres casos y lo dice con precisión.
      _aviso(data['nota']?.toString() ?? 'Documento actualizado.');
      final url = (data['pdfUrl'] ?? '').toString();
      if (url.startsWith('http')) {
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
      }
      await _cargar();
    } catch (e) {
      _aviso('Error de conexión: $e');
    }
  }

  Future<void> _generarDoc(_Tramite t) async {
    final prog = await _elegirPrograma(t);
    if (prog == null) return; // canceló
    _aviso('Generando documento…');
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'tramite_generar_doc',
              'fila': t.fila,
              'matricula': t.matricula,
              'programa': prog,
              'actor': correo ?? 'Administración',
            }),
          )
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso(data['error']?.toString() ?? 'No se pudo generar el documento.');
        return;
      }
      _aviso('Documento generado y enviado al alumno.');
      final url = (data['pdfUrl'] ?? '').toString();
      if (url.startsWith('http')) {
        await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
      }
      await _cargar();
    } catch (e) {
      _aviso('Error de conexión: $e');
    }
  }

  // (ago-3) Reclasificar el trámite a otro tipo del tabulador (p. ej. a la
  // constancia oficial con periodo y promedios) sin abrir la hoja de cálculo.
  /// Anota algo en el trámite sin resolverlo.
  ///
  /// Con la casilla de bloqueo, además lo marca como «En espera de
  /// requisitos» y la nota sale en rojo. Eso es lo que faltaba en el caso del
  /// kárdex: quien fue a aprobarlo no tenía cómo saber que había un pago
  /// pendiente, porque el dato estaba en WhatsApp.
  Future<void> _agregarNota(_Tramite t) async {
    final ctrl = TextEditingController();
    bool bloquea = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Nota · ${t.nombre}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Lo que quien vea este trámite necesita saber antes de '
                    'resolverlo. Las notas se acumulan con fecha y autor.',
                    style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nota',
                  hintText: 'Ej. No ha pagado. Se le avisó por WhatsApp el 21.',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: bloquea,
                onChanged: (v) => setLocal(() => bloquea = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('No resolver todavía',
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: const Text(
                    'Lo marca en rojo y pasa a «En espera de requisitos», '
                    'para que nadie lo apruebe sin leer esto.',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB07D12)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;

    try {
      final actor = await SessionStore.realEmail() ?? '';
      final r = await http.get(
        Uri.parse(guardianUrl).replace(queryParameters: {
          'accion': 'tramite_nota',
          'fila': '${t.fila}',
          'nota': ctrl.text.trim(),
          'actor': actor,
          if (bloquea) 'bloquea': '1',
        }),
      );
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor:
            d['ok'] == true ? const Color(0xFF1E7B34) : cessumRed,
        content: Text('${d['nota'] ?? d['error'] ?? ''}'),
      ));
      if (d['ok'] == true) _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
  }

  Future<void> _reclasificar(_Tramite t) async {
    /* (3-sep) FALTABAN TIPOS QUE EL SISTEMA SÍ SABE EMITIR.
       Un alumno pidió su carta de pasante por «Otro», y al ir a
       reclasificarla no estaba en la lista: había que dejarla como «Otro» y
       emitirla por fuera. El Guardián genera siete tipos —incluidos pasante y
       certificado parcial— y esta lista solo ofrecía nueve etiquetas sin
       ellos. Se agregan los que faltaban. */
    const tipos = <String>[
      'Constancia de inscripción',
      'Constancia de estudios digital o físico',
      'Constancia de estudios oficial (periodo, fechas y promedios)',
      'Boleta física',
      'Boleta Digital',
      'Kardex digital o físico',
      'Certificado parcial de estudios',
      'Carta de pasante',
      'Constancia de terminación de estudios',
      'Ficha de plan y programa de estudio con RVOE',
      'Carta de costos del programa',
      'Constancia de beca institucional',
      'Informe financiero',
      'Constancia de no adeudo',
    ];
    final elegido = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Reclasificar trámite',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('Actual: ${t.tipoTramite}',
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          ...tipos.map((tp) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, tp),
                child: Text(tp, style: const TextStyle(fontSize: 13.5)),
              )),
        ],
      ),
    );
    if (elegido == null || !mounted) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'tramite_retipar',
        'actor': await SessionStore.realEmail() ?? '',
        'matricula': t.matricula,
        'fila': '${t.fila}',
        'tipo': elegido.toLowerCase(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reclasificado a: ${data['tipoNuevo']}'),
          backgroundColor: Colors.green.shade700));
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo reclasificar: $e'),
          backgroundColor: cessumRed));
    }
  }

  /// (ago-27) BARRA DE AVANCE PARA LA GENERACIÓN DE DOCUMENTOS.
  ///
  /// Antes solo salía un aviso que desaparecía en tres segundos y luego nada
  /// durante hasta minuto y medio. Sin señal de vida uno pulsa otra vez, y
  /// cada nueva pulsación lanza OTRA generación que compite con la primera y
  /// la hace más lenta todavía.
  ///
  /// HONESTIDAD DE LA BARRA: el servidor no informa su avance, así que un
  /// porcentaje exacto sería inventado. Lo que se muestra es el TIEMPO
  /// TRANSCURRIDO contra lo que suele tardar, y el paso en el que va según
  /// ese tiempo. Se detiene en 95 % y ahí espera: llegar a 100 % antes de que
  /// el documento exista sería mentir.
  ///
  /// Devuelve una función para cerrarlo.
  void Function() _mostrarAvance(String titulo) {
    final inicio = DateTime.now();
    bool cerrado = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: StatefulBuilder(
            builder: (ctx2, setLocal) {
              // Se repinta cada medio segundo mientras el diálogo viva.
              Future.delayed(const Duration(milliseconds: 500), () {
                if (!cerrado) {
                  try {
                    setLocal(() {});
                  } catch (_) {}
                }
              });
              final seg = DateTime.now().difference(inicio).inMilliseconds / 1000;
              // 60 s es lo que tarda un documento normal; los pesados llegan
              // a 90. La barra se acerca al 95 % y ahí se queda.
              final avance = (seg / 60).clamp(0.0, 0.95);
              String paso;
              if (seg < 4) {
                paso = 'Buscando al alumno…';
              } else if (seg < 12) {
                paso = 'Reuniendo sus calificaciones…';
              } else if (seg < 25) {
                paso = 'Calculando promedios y fechas del periodo…';
              } else if (seg < 45) {
                paso = 'Armando el documento…';
              } else if (seg < 70) {
                paso = 'Convirtiéndolo a PDF…';
              } else {
                paso = 'Tarda más de lo normal. Suele pasar con alumnos de '
                    'muchas materias: sigue trabajando.';
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: avance,
                      minHeight: 9,
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(cessumRed),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(paso,
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                  const SizedBox(height: 6),
                  Text('${seg.toStringAsFixed(0)} segundos',
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Text(
                    'No cierres esta ventana ni vuelvas a pulsar: cada intento '
                    'nuevo compite con este y lo hace más lento.',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: Colors.grey.shade600),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    return () {
      if (cerrado) return;
      cerrado = true;
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    };
  }

  /// Muestra el PDF DENTRO de la pantalla, a pantalla casi completa.
  ///
  /// Drive sirve una vista previa por /preview a partir del id del archivo.
  /// El enlace que devuelve el Guardián es de exportación (/export?format=pdf),
  /// así que se le saca el id y se arma el de vista previa: el de exportación
  /// descarga en vez de mostrar.
  void _verPdfAqui(String url, _Tramite t) {
    // (3-sep) El botón «Periodos» solo tiene sentido en el kárdex: es el
    // único documento que imprime el ciclo escolar de cada asignatura.
    final esKardex = t.tipoTramite.toLowerCase().contains('kardex') ||
        t.tipoTramite.toLowerCase().contains('kárdex');
    final matriculaDoc = t.matricula;
    final programaDoc = t.programa;
    final m = RegExp(r'[-\w]{25,}').firstMatch(url);
    final visor = m != null
        ? 'https://drive.google.com/file/d/${m.group(0)}/preview'
        : url;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: const BoxDecoration(
              color: cessumRed,
              borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.nombre,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    Text('Vista previa · no es el documento oficial',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11.5)),
                  ],
                ),
              ),
              // (3-sep) Atajo a los periodos, solo en el kárdex. Se pone aquí
              // porque es viendo el documento cuando uno nota que a una materia
              // le falta el ciclo: se corrige y se vuelve a generar sin salir.
              if (esKardex)
                TextButton.icon(
                  onPressed: () async {
                    final cambio = await showDialog<bool>(
                      context: ctx,
                      builder: (_) => PeriodosKardexDialog(
                          matricula: matriculaDoc, programa: programaDoc),
                    );
                    if (cambio == true && ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.event_note,
                      size: 16, color: Colors.white),
                  label: const Text('Periodos',
                      style: TextStyle(color: Colors.white, fontSize: 12.5)),
                ),
              // Se conserva la opción de abrirlo aparte: para un documento
              // largo a veces conviene la pantalla completa del navegador.
              TextButton.icon(
                onPressed: () =>
                    launchUrl(Uri.parse(url), webOnlyWindowName: '_blank'),
                icon: const Icon(Icons.open_in_new,
                    size: 16, color: Colors.white),
                label: const Text('Abrir aparte',
                    style: TextStyle(color: Colors.white, fontSize: 12.5)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ]),
          ),
          Expanded(
            child: SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.92,
              child: _IframePdf(src: visor),
            ),
          ),
        ]),
      ),
    );
  }

  // (ago-27) Un documento a la vez. Cada pulsación lanzaba OTRA generación que
  // competía con la anterior: por eso pulsar de nuevo, que es lo natural
  // cuando no hay señal de vida, hacía la espera todavía más larga.
  bool _generando = false;

  Future<void> _vistaPrevia(_Tramite t) async {
    if (_generando) {
      _aviso('Ya se está generando un documento. Espera a que termine: '
          'lanzar otro lo hace más lento.');
      return;
    }
    if (t.matricula.isEmpty) {
      _aviso('Este trámite no tiene matrícula para previsualizar.');
      return;
    }
    var tipo = _tipoPreview(t.tipoTramite);
    if (tipo == null) {
      final opciones = <List<String>>[
        ['Constancia de estudios', 'constancia'],
        ['Certificado parcial', 'certificado'],
        ['Constancia de inscripción', 'inscripcion'],
        ['Constancia de no adeudo', 'noadeudo'],
        ['Carta de pasante', 'pasante'],
        ['Carta de terminación', 'terminacion'],
        ['Kardex', 'kardex'],
        ['Ficha de plan y programa de estudio (RVOE)', 'plan_estudios'],
        ['Carta de costos del programa', 'costos'],
        ['Constancia de beca institucional', 'beca'],
        ['Informe financiero', 'informe_financiero'],
      ];
      tipo = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('¿Qué documento quieres previsualizar?'),
          children: opciones
              .map((op) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, op[1]),
                    child: Text(op[0]),
                  ))
              .toList(),
        ),
      );
      if (tipo == null) return;
    }
    // La barra sustituye al aviso: se queda a la vista todo el rato que dure.
    final cerrarAvance = _mostrarAvance('Generando la vista previa');
    setState(() => _generando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'documento_preview_pdf',
        'tipo': tipo,
        'matricula': t.matricula,
      });
      // (ago-27) 150 s, igual que «Validar y enviar». Con 90 la APP se rendía
      // antes que el servidor: por URL directa la constancia responde bien,
      // pero el navegador y el puente suman sus tiempos y se pasaban del
      // límite. El proxy da 120 y Apps Script sigue trabajando, así que el
      // documento a veces SÍ estaba listo cuando aquí ya decía que falló.
      final resp = await http.get(uri).timeout(const Duration(seconds: 150));
      cerrarAvance();
      // (ago-25) DECIR QUÉ FALLÓ, no «no se pudo».
      // El catch anterior se tragaba el error real y mostraba un mensaje
      // genérico: imposible saber si faltaba un dato del alumno, si el
      // servidor tardó, o si la respuesta no era JSON. Sin eso, cada reporte
      // obligaba a reproducir el caso a ciegas.
      Map<String, dynamic> data;
      try {
        data = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        final crudo = resp.body.trim();
        _aviso('El sistema respondió algo inesperado (${resp.statusCode}): '
            '${crudo.substring(0, crudo.length > 140 ? 140 : crudo.length)}');
        return;
      }
      final url = (data['pdfUrl'] ?? '').toString();
      if (data['ok'] == true && url.isNotEmpty) {
        // (ago-27) Se abre AQUÍ MISMO, no en otra pestaña. Cambiar de ventana
        // para revisar un documento y volver buscando el trámite es lo que
        // hace que se revisen a medias.
        _verPdfAqui(url, t);
      } else if (data['ok'] == true && url.isEmpty) {
        _aviso('El documento se generó pero no llegó su enlace. '
            'Avísale a sistemas: el trámite sí quedó registrado.');
      } else {
        _aviso(data['error']?.toString() ??
            'No se pudo generar la vista previa (sin razón declarada).');
      }
    } on TimeoutException {
      cerrarAvance();
      _aviso('La vista previa tardó más de 150 segundos. Suele pasar cuando el '
          'alumno tiene muchas materias: vuelve a intentarlo.');
    } catch (e) {
      cerrarAvance();
      _aviso('No se pudo abrir la vista previa: $e');
    } finally {
      // Se suelta SIEMPRE, pase lo que pase: si el candado quedara puesto,
      // no se podría generar ningún otro documento en toda la sesión.
      cerrarAvance();
      if (mounted) setState(() => _generando = false);
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // (25-sep) Las pestañas no filtraban con el buscador vacío: esta línea
    // devolvía TODOS los trámites cuando no había texto, y la pestaña elegida
    // se ignoraba (solo «funcionaba» al escribir algo). _coincide ya revisa la
    // pestaña y, si hay texto, también el buscador: se aplica siempre.
    final base = _items.where(_coincide).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Trámites escolares'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error != null
              ? _vistaError()
              : _items.isEmpty
                  ? _vistaVacia()
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        children: [
                          _buscador(),
                          const SizedBox(height: 10),
                          _filtrosSituacion(_items),
                          const SizedBox(height: 12),
                          if (base.isEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 30),
                              child: Center(
                                child: Text(
                                  _busqueda.text.trim().isNotEmpty
                                      ? 'Sin resultados para "${_busqueda.text.trim()}".'
                                      : _situacion == 'fuera'
                                          ? 'Ninguno fuera de tiempo. Todo al corriente.'
                                          : _situacion == 'espera'
                                              ? 'Ninguno en espera de requisitos.'
                                              : _situacion == 'entiempo'
                                                  ? 'Nada pendiente por atender.'
                                                  : 'Sin trámites en esta vista.',
                                  textAlign: TextAlign.center,
                                  style:
                                      const TextStyle(color: Colors.black54),
                                ),
                              ),
                            )
                          else
                            ...base.map(_tarjeta),
                        ],
                      ),
                    ),
    );
  }

  // Milisegundos HÁBILES entre dos instantes (excluye sábado y domingo).
  // Durante el fin de semana el conteo no avanza (temporizador en pausa).
  int _habilRestanteMs(int fromMs, int toMs) {
    if (toMs <= fromMs) return 0;
    int total = 0;
    DateTime cursor = DateTime.fromMillisecondsSinceEpoch(fromMs);
    final to = DateTime.fromMillisecondsSinceEpoch(toMs);
    while (cursor.isBefore(to)) {
      final nextMid = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final segEnd = nextMid.isBefore(to) ? nextMid : to;
      final dow = cursor.weekday; // 1=Lun .. 6=Sab, 7=Dom
      if (dow != 6 && dow != 7) {
        total += segEnd.difference(cursor).inMilliseconds;
      }
      cursor = segEnd;
    }
    return total;
  }

  // Semáforo + regresiva de 72 h hábiles para atender el trámite.
  Widget _semaforoEntrega(_Tramite t) {
    final pendiente = !_esAtendido(t.estatus) && !_esRechazo(t.estatus);
    if (!pendiente || t.limiteMs == null) return const SizedBox.shrink();
    final limite = t.limiteMs!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final vencido = now >= limite;
    final restante = _habilRestanteMs(now, limite);
    final finde = () {
      final w = DateTime.now().weekday;
      return w == 6 || w == 7;
    }();
    Color color;
    String texto;
    if (vencido) {
      color = cessumRed;
      texto = 'Plazo vencido';
    } else {
      final h = restante ~/ 3600000;
      color = h < 6 ? cessumRed : (h < 24 ? cessumGold : _verdeOk);
      final d = restante ~/ 86400000;
      final hh = (restante % 86400000) ~/ 3600000;
      final mm = (restante % 3600000) ~/ 60000;
      texto = 'Atender en '
          '${d > 0 ? '${d}d ' : ''}${hh}h ${mm}m hábiles'
          '${finde ? ' (en pausa · fin de semana)' : ''}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(texto,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjeta(_Tramite t) {
    final pendiente = !_esAtendido(t.estatus) && !_esRechazo(t.estatus);
    final atendido = _esAtendido(t.estatus);
    final tieneDoc = t.documento.startsWith('http');
    final c = pendiente ? cessumGold : (atendido ? _verdeOk : cessumRed);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: c.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                    pendiente
                        ? Icons.hourglass_top
                        : (atendido ? Icons.verified : Icons.cancel),
                    size: 16,
                    color: c),
                const SizedBox(width: 6),
                Text(t.estatus.isEmpty ? 'Pendiente' : t.estatus,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: c, fontSize: 13)),
                const Spacer(),
                Text(t.fecha,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black45)),
              ],
            ),
          ),
          _semaforoEntrega(t),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.tipoTramite,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cessumRed)),
                const SizedBox(height: 4),
                Text(t.nombre,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CC.ink)),
                Text('Matrícula: ${t.matricula}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
                _selloAdeudo(t),
                const SizedBox(height: 8),
                _linea('Programa', t.programa),
                _linea('Modalidad', t.modalidad),
                _linea('Generación', t.generacion),
                _linea('Observaciones', t.observaciones),
                if (t.correo.isNotEmpty) _linea('Correo', t.correo),
                if (!pendiente && t.resueltoPor.isNotEmpty)
                  _linea('Resuelto por',
                      '${t.resueltoPor} · ${t.fechaResolucion}'),
                // (ago-20) LAS NOTAS VAN DESTACADAS, NO COMO UN RENGLÓN MÁS.
                //
                // Se aprobó un kárdex que no debía porque el motivo —«no ha
                // pagado»— estaba en WhatsApp y no aquí. Una nota que se lee
                // igual que la modalidad o la generación no detiene a nadie:
                // la que dice NO PROCEDE AÚN tiene que verse antes de que la
                // mano llegue al botón de aprobar.
                if (t.notas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: t.notas.contains('[NO PROCEDE AUN]')
                          ? cessumRed.withValues(alpha: 0.09)
                          : cessumGold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: (t.notas.contains('[NO PROCEDE AUN]')
                                  ? cessumRed
                                  : cessumGold)
                              .withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                              t.notas.contains('[NO PROCEDE AUN]')
                                  ? Icons.block
                                  : Icons.sticky_note_2_outlined,
                              size: 15,
                              color: t.notas.contains('[NO PROCEDE AUN]')
                                  ? cessumRed
                                  : cessumGold),
                          const SizedBox(width: 6),
                          Text(
                              t.notas.contains('[NO PROCEDE AUN]')
                                  ? 'NO RESOLVER TODAVÍA'
                                  : 'NOTAS INTERNAS',
                              style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: .9,
                                  fontWeight: FontWeight.w800,
                                  color: t.notas.contains('[NO PROCEDE AUN]')
                                      ? cessumRed
                                      : cessumGold)),
                        ]),
                        const SizedBox(height: 5),
                        Text(t.notas,
                            style: const TextStyle(
                                fontSize: 12.5, height: 1.5)),
                      ],
                    ),
                  ),
                ],
                if (t.comprobante.isNotEmpty &&
                    t.comprobante.startsWith('http'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => _abrir(t.comprobante),
                      icon: const Icon(Icons.receipt_long,
                          size: 16, color: cessumRed),
                      label: Text(
                          _esFactura(t)
                              ? 'Ver constancia de situación fiscal'
                              : 'Ver comprobante',
                          style: const TextStyle(color: cessumRed, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumRed),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                if (t.comprobantePago.isNotEmpty &&
                    t.comprobantePago.startsWith('http'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => _abrir(t.comprobantePago),
                      icon: const Icon(Icons.payments,
                          size: 16, color: cessumRed),
                      label: const Text('Ver comprobante de pago',
                          style: TextStyle(color: cessumRed, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumRed),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                // (ago-20) Anotar SIN resolver. Antes solo se podía escribir
                // una nota al validar o rechazar —o sea al final, cuando ya
                // no evita nada—. Este botón sirve mientras el trámite sigue
                // pendiente, que es cuando la información vale.
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => _agregarNota(t),
                    icon: const Icon(Icons.edit_note,
                        size: 16, color: Color(0xFFB07D12)),
                    label: const Text('Agregar nota',
                        style: TextStyle(
                            color: Color(0xFFB07D12), fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFB07D12)),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                if (!_esFactura(t))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => _reclasificar(t),
                      icon: Icon(Icons.swap_horiz,
                          size: 16, color: cessumMuted(context)),
                      label: Text('Reclasificar tipo',
                          style: TextStyle(
                              color: cessumMuted(context), fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: cessumFaint(context)),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                if (!_esFactura(t))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => _vistaPrevia(t),
                      icon: const Icon(Icons.visibility,
                          size: 16, color: cessumGold),
                      label: const Text('Vista previa',
                          style: TextStyle(color: cessumGold, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumGold),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                if (_esFactura(t)) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _subirFactura(t),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: Text(
                          t.documento.startsWith('http')
                              ? 'Subir otra factura y reenviar'
                              : 'Subir factura (PDF/XML) y enviar',
                          style: const TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                        'Puedes subir el PDF y el XML juntos. Se enviarán al '
                        'alumno por correo y quedarán en Mis trámites.',
                        style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _reenviarFactura(t),
                      icon: const Icon(Icons.forward_to_inbox,
                          size: 16, color: cessumGold),
                      label: const Text(
                          'Reenviar notificación a facturación',
                          style: TextStyle(color: cessumGold, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumGold),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
                if (tieneDoc && !_esRechazo(t.estatus)) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _verDoc(t.documento),
                      icon: const Icon(Icons.picture_as_pdf,
                          size: 16, color: _verdeOk),
                      label: const Text('Ver documento generado (PDF)',
                          style: TextStyle(color: _verdeOk, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _verdeOk),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
                // (ago-9) GENERAR EDITABLE. El generador siempre produce un
                // Google Doc y de ahí saca el PDF, pero solo se entregaba el
                // PDF: para cambiar una línea —un acento, una fecha, una
                // redacción particular— había que rehacer el documento a
                // mano. Va tanto en solicitudes como en aprobados, porque la
                // corrección suele hacerse ANTES de enviar.
                // (ago-22) SOLO EN «OTRO». Los demás tipos tienen plantilla y
                // deben seguir usando «Generar editable»: dos caminos para el
                // mismo trámite producirían dos documentos distintos.
                if (_esOtro(t) && !_esFactura(t)) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _generarOtro(t),
                      icon: const Icon(Icons.auto_awesome, size: 17),
                      label: const Text(
                          'Generar documento (partiendo de la solicitud)',
                          style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cessumGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                        'Propuesta con los datos del sistema y lo que pidió el '
                        'alumno. No se envía nada: la revisas y la descargas.',
                        style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                  ),
                ],
                if (!_esFactura(t)) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _generarEditable(t),
                      icon: const Icon(Icons.edit_document,
                          size: 16, color: cessumGold),
                      label: const Text('Generar editable (Word o Drive)',
                          style: TextStyle(color: cessumGold, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumGold),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  // (ago-21) ADJUNTAR UN DOCUMENTO HECHO A MANO.
                  //
                  // Cuando el alumno pide «Otros» no hay plantilla que
                  // generar: el documento se redacta aparte. Antes eso se
                  // mandaba por WhatsApp y el trámite quedaba «atendido» sin
                  // nada adjunto — meses después nadie podía comprobar qué se
                  // entregó, ni que se entregó.
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _adjuntarDocumento(t),
                      icon: const Icon(Icons.attach_file,
                          size: 16, color: Color(0xFF1565C0)),
                      label: const Text('Adjuntar documento',
                          style: TextStyle(
                              color: Color(0xFF1565C0), fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF1565C0)),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
                if (atendido && !_esFactura(t)) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _generarDoc(t),
                      icon: const Icon(Icons.forward_to_inbox,
                          size: 16, color: cessumRed),
                      label: Text(
                          tieneDoc
                              ? 'Reenviar al alumno (PDF)'
                              : 'Generar y enviar documento (PDF)',
                          style: const TextStyle(
                              color: cessumRed, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumRed),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  // (ago-29) Solo tiene sentido si YA hay documento: es para
                  // corregir uno que salió mal, no para generar el primero.
                  if (tieneDoc) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _actualizarDoc(t),
                        icon: const Icon(Icons.autorenew, size: 16),
                        label: const Text(
                            'Actualizar el documento y enviar',
                            style: TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cessumGold,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Lo vuelve a construir con los datos de hoy, sin abrir '
                        'un trámite nuevo. Puedes verlo antes de enviarlo, o '
                        'actualizarlo sin avisarle al alumno.',
                        style: TextStyle(fontSize: 11, color: cessumFaint(context)),
                      ),
                    ),
                  ],
                ],
                if (pendiente) ...[
                  const Divider(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => _resolver(t, 'Rechazado'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: cessumRed),
                          foregroundColor: cessumRed,
                        ),
                        child: const Text('Rechazar'),
                      ),
                      const SizedBox(width: 8),
                      if (_esCambioModalidad(t))
                        ElevatedButton.icon(
                          onPressed: () => _aprobarYMover(t),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _verdeOk,
                              foregroundColor: Colors.white),
                          icon: const Icon(Icons.move_down, size: 18),
                          label: const Text('Aprobar y mover'),
                        )
                      else if (!_esFactura(t))
                        ElevatedButton.icon(
                          onPressed: () => _resolver(t, 'Atendido'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: _verdeOk,
                              foregroundColor: Colors.white),
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Validar y enviar'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linea(String etq, String valor) {
    if (valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text('$etq:',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          ),
          Expanded(
            child: Text(valor,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cessumInk(context))),
          ),
        ],
      ),
    );
  }

  Widget _vistaVacia() {
    return const CessumEmptyState(
      icon: Icons.inbox_rounded,
      title: 'Sin solicitudes por ahora',
      subtitle:
          'Cuando un alumno envíe un trámite, aparecerá aquí para que lo revises.',
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
                style: TextStyle(color: cessumMuted(context), height: 1.4)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
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

/// (ago-27) Muestra un PDF de Drive DENTRO de la app.
///
/// Flutter web no dibuja PDFs por sí mismo: se incrusta un iframe con la vista
/// previa de Drive. Hay que registrar la vista una sola vez por dirección —
/// registrarla dos veces con el mismo nombre truena en tiempo de ejecución, y
/// esta pantalla puede abrir varios documentos en una misma sesión.
class _IframePdf extends StatefulWidget {
  final String src;
  const _IframePdf({required this.src});

  @override
  State<_IframePdf> createState() => _IframePdfState();
}

class _IframePdfState extends State<_IframePdf> {
  static final Set<String> _registradas = {};
  late final String _vista;

  @override
  void initState() {
    super.initState();
    // Un nombre por dirección: así el mismo documento reusa su vista y uno
    // distinto crea la suya.
    _vista = 'pdf-${widget.src.hashCode}';
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

// ===========================================================================
// (3-sep) PERIODOS DEL KÁRDEX
// ---------------------------------------------------------------------------
// El kárdex ahora imprime el ciclo escolar en que se cursó cada materia. El
// Guardián lo deduce de la generación (24-2 en adelante), pero para las
// generaciones anteriores la correspondencia no cuadra —lo advirtió
// Vicerrectoría— y se deja en blanco a propósito.
//
// Esta hoja es donde se llena ese blanco. Se abre desde el visor del kárdex,
// que es justo donde uno se da cuenta de que falta: se ve el documento, se
// corrige, se vuelve a generar.
//
// Lo capturado a mano SIEMPRE gana sobre lo deducido. La regla no sabe que
// alguien recursó en otro ciclo o se reincorporó; quien lo atendió, sí.
// ===========================================================================

class _PeriodoFila {
  final String clave;
  final String materia;
  final String ciclo;
  final String deducido;
  final String calificacion;
  String manual;
  final TextEditingController ctrl;

  _PeriodoFila({
    required this.clave,
    required this.materia,
    required this.ciclo,
    required this.deducido,
    required this.calificacion,
    required String manual,
  })  : manual = manual,
        ctrl = TextEditingController(text: manual);

  /// Lo que se imprimirá en el kárdex.
  String get efectivo => ctrl.text.trim().isNotEmpty ? ctrl.text.trim() : deducido;
  bool get sinDato => efectivo.isEmpty;
  bool get esManual => ctrl.text.trim().isNotEmpty;
}

class PeriodosKardexDialog extends StatefulWidget {
  final String matricula;
  final String programa;
  const PeriodosKardexDialog({
    super.key,
    required this.matricula,
    this.programa = '',
  });

  @override
  State<PeriodosKardexDialog> createState() => _PeriodosKardexDialogState();
}

class _PeriodosKardexDialogState extends State<PeriodosKardexDialog> {
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  String _nombre = '';
  String _programa = '';
  String _generacion = '';
  String _modalidad = '';
  String _tipoPeriodo = '';
  int _porAnio = 0;
  List<_PeriodoFila> _filas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = await SessionStore.realEmail();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'kardex_periodos',
        'matricula': widget.matricula,
        if (widget.programa.isNotEmpty) 'programa': widget.programa,
        'actor': correo ?? '',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      if (!mounted) return;
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) {
        setState(() {
          _error = '${j['error'] ?? 'No se pudo leer la información.'}';
          _cargando = false;
        });
        return;
      }
      for (final f in _filas) {
        f.ctrl.dispose();
      }
      final lista = (j['materias'] as List? ?? []);
      setState(() {
        _nombre = '${j['nombre'] ?? ''}';
        _programa = '${j['programa'] ?? ''}';
        _generacion = '${j['generacion'] ?? ''}';
        _modalidad = '${j['modalidad'] ?? ''}';
        _tipoPeriodo = '${j['tipoPeriodo'] ?? ''}';
        _porAnio = (j['periodosPorAnio'] is num)
            ? (j['periodosPorAnio'] as num).toInt()
            : 0;
        _filas = lista
            .map((e) => _PeriodoFila(
                  clave: '${e['clave'] ?? ''}',
                  materia: '${e['materia'] ?? ''}',
                  ciclo: '${e['ciclo'] ?? ''}',
                  deducido: '${e['deducido'] ?? ''}',
                  calificacion: '${e['calificacion'] ?? ''}',
                  manual: '${e['manual'] ?? ''}',
                ))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo conectar: $e';
        _cargando = false;
      });
    }
  }

  /// Solo viaja lo que el usuario escribió o borró: no se manda de vuelta al
  /// servidor lo que la regla ya deduce sola.
  Future<void> _guardar() async {
    final cambios = _filas
        .where((f) => f.ctrl.text.trim() != f.manual)
        .map((f) => {
              'clave': f.clave,
              'materia': f.materia,
              'periodo': f.ctrl.text.trim(),
            })
        .toList();
    if (cambios.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cambios que guardar.')),
      );
      return;
    }
    final malos = _filas
        .where((f) =>
            f.ctrl.text.trim().isNotEmpty &&
            !RegExp(r'^\d{4}-\d{1,2}$').hasMatch(f.ctrl.text.trim()))
        .toList();
    if (malos.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: CC.redAlt,
        content: Text(
            'Revise el formato: "${malos.first.ctrl.text.trim()}" no es un periodo. '
            'Se escribe año-número, por ejemplo 2025-1.'),
      ));
      return;
    }
    setState(() => _guardando = true);
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'kardex_periodos_lote',
              'matricula': widget.matricula,
              'programa': _programa,
              'filas': cambios,
              'actor': correo ?? '',
            }),
          )
          .timeout(const Duration(seconds: 90));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _guardando = false);
      if (j['ok'] == true) {
        for (final f in _filas) {
          f.manual = f.ctrl.text.trim();
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _verdeOk,
          content: Text('${j['nota'] ?? 'Guardado.'} '
              'Vuelva a generar el kárdex para verlo.'),
        ));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: CC.redAlt,
          content: Text('${j['error'] ?? 'No se pudo guardar.'}'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: CC.redAlt,
        content: Text('No se pudo guardar: $e'),
      ));
    }
  }

  /// Copia el periodo deducido al campo editable, para las filas que sí lo
  /// tienen: sirve cuando se quiere fijar el valor aunque cambie la regla.
  void _fijarDeducidos() {
    setState(() {
      for (final f in _filas) {
        if (f.ctrl.text.trim().isEmpty && f.deducido.isNotEmpty) {
          f.ctrl.text = f.deducido;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sinDato = _filas.where((f) => f.sinDato).length;
    final ancho = MediaQuery.of(context).size.width;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: ancho > 900 ? 860 : ancho * 0.96,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _encabezado(sinDato),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Leyendo las asignaturas…'),
              ]),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                const Icon(Icons.error_outline, color: CC.redAlt, size: 32),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _cargar,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reintentar'),
                ),
              ]),
            )
          else ...[
            _fichaAlumno(),
            Flexible(child: _tabla()),
            _pie(sinDato),
          ],
        ]),
      ),
    );
  }

  Widget _encabezado(int sinDato) => Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        decoration: const BoxDecoration(
          color: CC.red,
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Row(children: [
          const Icon(Icons.event_note, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Periodos del kárdex',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Text(
                      _cargando
                          ? widget.matricula
                          : '$_nombre · ${widget.matricula}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12)),
                ]),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Cerrar',
          ),
        ]),
      );

  Widget _fichaAlumno() => Container(
        width: double.infinity,
        color: CC.goldSoft,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 14, runSpacing: 4, children: [
            _dato('Programa', _programa),
            _dato('Generación', _generacion),
            if (_modalidad.isNotEmpty) _dato('Modalidad', _modalidad),
            if (_tipoPeriodo.isNotEmpty)
              _dato('Periodo', '$_tipoPeriodo ($_porAnio al año)'),
          ]),
          const SizedBox(height: 6),
          Text(
              'El sistema deduce el periodo a partir de la generación, de la 24-2 '
              'en adelante. Lo que escriba aquí manda sobre lo deducido; deje el '
              'campo vacío para volver a la regla.',
              style: TextStyle(fontSize: 11.5, color: CC.ink.withValues(alpha: 0.75))),
        ]),
      );

  Widget _dato(String k, String v) => RichText(
        text: TextSpan(style: const TextStyle(fontSize: 12, color: CC.ink), children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: CC.muted)),
          TextSpan(text: v.isEmpty ? '—' : v,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _tabla() {
    if (_filas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Text('Este alumno no tiene asignaturas validadas.'),
      );
    }
    String cicloPrevio = '';
    final hijos = <Widget>[];
    for (final f in _filas) {
      if (f.ciclo != cicloPrevio) {
        cicloPrevio = f.ciclo;
        hijos.add(Container(
          width: double.infinity,
          color: CC.goldCard,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          child: Text(f.ciclo.isEmpty ? 'Sin ciclo en el plan' : f.ciclo,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: CC.goldDark)),
        ));
      }
      hijos.add(_fila(f));
    }
    return SingleChildScrollView(child: Column(children: hijos));
  }

  Widget _fila(_PeriodoFila f) {
    final estrecho = MediaQuery.of(context).size.width < 700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: CC.muted.withValues(alpha: 0.18))),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(f.materia,
                    style: const TextStyle(fontSize: 13, color: CC.ink)),
                Text(
                    [
                      if (f.clave.isNotEmpty) f.clave,
                      if (f.calificacion.isNotEmpty) 'calif. ${f.calificacion}',
                      if (f.deducido.isNotEmpty)
                        'la regla dice ${f.deducido}'
                      else
                        'la regla no la deduce',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11, color: CC.muted)),
              ]),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: estrecho ? 96 : 118,
          child: TextField(
            controller: f.ctrl,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: f.deducido.isEmpty ? 'AAAA-N' : f.deducido,
              hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: f.deducido.isEmpty ? CC.redAlt : CC.muted),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: const OutlineInputBorder(),
              suffixIcon: f.ctrl.text.trim().isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.backspace_outlined, size: 15),
                      tooltip: 'Quitar lo capturado y volver a la regla',
                      onPressed: () => setState(() => f.ctrl.clear()),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 74, child: _sello(f)),
      ]),
    );
  }

  Widget _sello(_PeriodoFila f) {
    if (f.sinDato) {
      return const _Etiqueta(
          texto: 'falta', color: CC.redAlt, fondo: CC.redSoft);
    }
    if (f.esManual) {
      return const _Etiqueta(
          texto: 'a mano', color: CC.goldDark, fondo: CC.goldSoft);
    }
    return _Etiqueta(
        texto: 'regla',
        color: _verdeOk,
        fondo: _verdeOk.withValues(alpha: 0.10));
  }

  Widget _pie(int sinDato) => Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        decoration: BoxDecoration(
          color: CC.hueso,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
          border: Border(top: BorderSide(color: CC.muted.withValues(alpha: 0.25))),
        ),
        child: Row(children: [
          Expanded(
            child: Text(
                sinDato == 0
                    ? 'Todas las asignaturas tienen periodo.'
                    : '$sinDato asignatura(s) saldrán sin periodo en el kárdex.',
                style: TextStyle(
                    fontSize: 12,
                    color: sinDato == 0 ? _verdeOk : CC.redAlt,
                    fontWeight: FontWeight.w600)),
          ),
          TextButton.icon(
            onPressed: _guardando ? null : _fijarDeducidos,
            icon: const Icon(Icons.push_pin_outlined, size: 16),
            label: const Text('Fijar los deducidos', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: CC.red),
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 16),
            label: Text(_guardando ? 'Guardando…' : 'Guardar'),
          ),
        ]),
      );
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color color;
  final Color fondo;
  const _Etiqueta(
      {required this.texto, required this.color, required this.fondo});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: fondo, borderRadius: BorderRadius.circular(20)),
        child: Text(texto,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 10.5, color: color, fontWeight: FontWeight.w700)),
      );
}

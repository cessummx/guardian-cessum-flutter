import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'mesa_ayuda_pagos_screen.dart';

/// Alumno: "Mis pagos". Muestra cuánto le toca pagar al mes (con beca si la
/// tiene, o el monto normal de su generación) y su historial de pagos.
class MiPagoScreen extends StatefulWidget {
  const MiPagoScreen({super.key, this.embebido = false});
  /// (4-oct-2026) Dentro de «Pagos» (pestañas) va sin barra propia: la pone el contenedor.
  final bool embebido;


  @override
  State<MiPagoScreen> createState() => _MiPagoScreenState();
}

class _MiPagoScreenState extends State<MiPagoScreen> {
  bool _cargando = true;
  String? _error;
  StudentProfile? _perfil;

  // monto
  bool _esBeca = false;
  num _porcentaje = 0;
  num _montoMensual = 0;
  num _bonoRecomienda = 0;
  num _montoConBono = 0;
  int _bonoReferidos = 0;
  String _bonoNota = '';
  String _modoPago = 'mensual';
  int _numPagos = 0;
  String _fechaLimitePago = '';
  String _materiaLimite = '';

  // Mixta: el pago es POR PERIODO académico (7 pagos en total), sin
  // mensualidades ni recargos por día 15.
  bool get _esPeriodo => _modoPago == 'periodo';

  // Formatea 'yyyy-MM-dd' como 'lunes 27 de julio de 2026'. Si no parsea,
  // devuelve el texto original.
  String _fmtFechaLarga(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const dias = [
      'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'
    ];
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
      'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    return '${dias[d.weekday - 1]} ${d.day} de ${meses[d.month - 1]} de ${d.year}';
  }
  num _montoNormal = 0;
  String _linkPago = '';
  bool _desconocido = false;

  // historial
  bool _emitiendo = false;
  List<Map<String, dynamic>> _pagos = [];
  num _sumaMateria = 0;
  num _sumaReins = 0;
  int _porValidar = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final p = await StudentProfile.load();
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _cargando = false;
          _error = 'Completa tu perfil para ver tus pagos.';
        });
        return;
      }
      _perfil = p;

      // (sep-2026) Las tres consultas van EN PARALELO (antes eran en serie y
      // el estado de cuenta se pedía aparte, después de pintar). Además el
      // estado de cuenta se vuelve a pedir en cada actualización: antes, al
      // deslizar para refrescar, se quedaba con el dato viejo.
      Future<Map<String, dynamic>?> pedir(
          Map<String, String> q, int segundos) async {
        try {
          final u = Uri.parse(guardianUrl).replace(queryParameters: q);
          final r = await http.get(u).timeout(Duration(seconds: segundos));
          final d = jsonDecode(r.body);
          return d is Map ? Map<String, dynamic>.from(d) : null;
        } catch (_) {
          return null;
        }
      }

      final res = await Future.wait([
        pedir({
          'accion': 'mi_pago_mensual',
          'matricula': p.matricula,
          'programa': p.programa,
          'generacion': p.generacion,
        }, 40),
        pedir({
          'accion': 'pagos_seguimiento_alumno',
          'matricula': p.matricula,
        }, 40),
        pedir({
          'accion': 'adeudo_estado',
          'matricula': p.matricula,
        }, 30),
      ]);
      final dMonto = res[0];
      final dHist = res[1];
      final dAdeudo = res[2];
      if (dMonto == null && dHist == null) {
        throw Exception('Sin respuesta del servidor');
      }

      if (dMonto != null && dMonto['ok'] == true) {
        _esBeca = dMonto['esBeca'] == true;
        _porcentaje = montoCessum(dMonto['porcentaje']);
        _montoMensual = montoCessum(dMonto['montoMensual']);
        _bonoRecomienda = montoCessum(dMonto['bonoRecomienda']);
        _montoConBono = montoCessum(dMonto['montoConBono']);
        _bonoReferidos = montoCessum(dMonto['bonoReferidos']).toInt();
        _bonoNota = (dMonto['bonoNota'] ?? '').toString();
        _modoPago = (dMonto['modoPago'] ?? 'mensual').toString();
        _numPagos = montoCessum(dMonto['numPagos']).toInt();
        _fechaLimitePago = (dMonto['fechaLimitePago'] ?? '').toString();
        _materiaLimite = (dMonto['materiaLimite'] ?? '').toString();
        _montoNormal = montoCessum(dMonto['montoNormalGrupo']);
        _linkPago = (dMonto['linkPago'] ?? '').toString();
        _desconocido = dMonto['desconocido'] == true;
      }

      if (dHist != null && dHist['ok'] == true) {
        _pagos = listaMapasCessum(dHist['pagos']);
        _sumaMateria = montoCessum(dHist['sumaMateria']);
        _sumaReins = montoCessum(dHist['sumaReinscripcion']);
        _porValidar = montoCessum(dHist['porValidar']).toInt();
      }

      // Sin respuesta del estado de cuenta no se pinta el veredicto: decirle
      // "al día" a alguien que quizá deba sería peor que no decir nada.
      _adeudo =
          (dAdeudo != null && dAdeudo['ok'] == true) ? dAdeudo : null;
    } catch (e) {
      _error = 'No se pudieron cargar tus pagos. Intenta de nuevo.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  // (ago-24) ¿ESTOY AL DÍA? Es la primera pregunta del alumno y la pantalla
  // no la respondía: mostraba cuánto le toca pagar y su historial, pero no
  // el veredicto. Aquí va arriba de todo, con el desglose de lo vencido y lo
  // que aún está en plazo — que no es lo mismo y no debe asustar igual.
  Map<String, dynamic>? _adeudo;

  // Texto del aviso que se mostró al alumno; viaja en el reporte de la mesa
  // de ayuda para que Atención a Estudiantes vea exactamente lo mismo.
  String _ultimoAviso = '';

  Widget _estadoCuenta() {
    final d = _adeudo;
    if (d == null) return const SizedBox.shrink();
    final alDia = d['alDia'] == true;
    final c = alDia ? const Color(0xFF1E8E3E) : cessumRed;
    final des = Map<String, dynamic>.from(
        (d['desglose'] as Map?) ?? const <String, dynamic>{});
    final venc = ((des['vencidos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final pv = ((des['porVencer'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(alDia ? Icons.verified : Icons.error_outline, size: 22, color: c),
            const SizedBox(width: 9),
            Expanded(
              child: Text('${d['etiqueta']}',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, color: c)),
            ),
            if (!alDia)
              Text('\$${d['totalVencido']}',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: c)),
          ]),
          const SizedBox(height: 6),
          Text('${d['resumen']}',
              style: const TextStyle(fontSize: 12.5, height: 1.4)),
          if (venc.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('VENCIDOS',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w800,
                    color: c)),
            const SizedBox(height: 4),
            ...venc.map((p) => _renglonAdeudo(p, c)),
          ],
          if (pv.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('POR VENCER · AÚN EN PLAZO',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFB07D12))),
            const SizedBox(height: 4),
            ...pv.map((p) => _renglonAdeudo(p, const Color(0xFFB07D12))),
          ],
        ],
      ),
    );
  }

  Widget _renglonAdeudo(Map<String, dynamic> p, Color c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: widget.embebido ? null : AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis pagos'),
        actions: [
          IconButton(
              tooltip: 'Mesa de ayuda',
              onPressed: () => _abrirAyuda(),
              icon: const Icon(Icons.support_agent)),
          IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => _abrirAyuda(),
                        icon: const Icon(Icons.support_agent, size: 18),
                        label: const Text('Abrir mesa de ayuda'),
                      ),
                    ],
                  ),
                ))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _estadoCuenta(),
                      _cardMonto(),
                      const SizedBox(height: 14),
                      _bonoCard(),
                      _recordatorioPago(),
                      _botonPago(),
                      const SizedBox(height: 18),
                      _analisis(),
                      const SizedBox(height: 18),
                      _resumen(),
                      const SizedBox(height: 18),
                      // (4-oct-2026) En pestañas, el historial completo vive en «Mis pagos»: aquí solo un acceso.
                      if (widget.embebido)
                        OutlinedButton.icon(
                          onPressed: () => DefaultTabController.maybeOf(context)?.animateTo(1),
                          icon: const Icon(Icons.receipt_long, size: 18),
                          label: Text(_pagos.isEmpty ? 'Ver mis pagos' : 'Ver mis ${_pagos.length} pago(s) registrados'),
                        )
                      else ...[
                      const Text('Historial de pagos',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      if (_pagos.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('Aún no hay pagos registrados.',
                              style: TextStyle(color: cessumMuted(context))),
                        ),
                      ..._pagos.map(_itemPago),
                      ],
                      const SizedBox(height: 18),
                      _tarjetaAyuda(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
    );
  }

  Widget _cardMonto() {
    if (_desconocido) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _esPeriodo
              ? 'Aún no podemos calcular tu cuota por periodo automáticamente. '
                  'Consulta el monto con administración.'
              : 'Aún no podemos calcular tu colegiatura mensual automáticamente. '
                  'Consulta el monto con administración.',
          style: const TextStyle(fontSize: 13.5),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [cessumRed, Color(0xFF8E1622)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
              _esPeriodo
                  ? 'Cuota por periodo académico'
                  : 'Tu colegiatura mensual',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Text(_money(_montoMensual),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900)),
          if (_esPeriodo)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _numPagos > 0
                    ? '$_numPagos pagos en total (uno por periodo)'
                    : '7 pagos en total (uno por periodo)',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 8),
          if (_esBeca)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Beca $_porcentaje% aplicada'
                '${_montoNormal > 0 ? '  ·  antes ${_money(_montoNormal)}' : ''}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5),
              ),
            )
          else
            const Text('Monto regular de tu generación',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _bonoCard() {
    if (_bonoRecomienda <= 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E8E3E).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard,
                  color: Color(0xFF1E8E3E), size: 22),
              const SizedBox(width: 8),
              Text('Descuento por recomendación: -${_money(_bonoRecomienda)}',
                  style: const TextStyle(
                      color: Color(0xFF1E7D32),
                      fontWeight: FontWeight.w800,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _bonoNota.isNotEmpty
                ? _bonoNota
                : 'Por recomendar a $_bonoReferidos persona(s) ganaste ${_money(_bonoRecomienda)}. Este mes pagas ${_money(_montoConBono)}.',
            style: TextStyle(color: cessumInk(context), fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Text('Este mes pagas: ${_money(_montoConBono)}',
              style: const TextStyle(
                  color: Color(0xFF1E7D32),
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          Text('Aplica solo para el pago de este mes.',
              style: TextStyle(color: cessumMuted(context), fontSize: 11.5)),
        ],
      ),
    );
  }

  /// ¿Ya hay un pago de colegiatura (Materia) registrado en el mes en curso?
  /// El aviso de fecha límite / recargo miraba SOLO el calendario, así que a
  /// quien ya pagó puntual igual le salía "aplica recargo del 5%".
  /// Devuelve: 0 = no hay pago del mes · 1 = pagado y validado · 2 = subido,
  /// en revisión.
  int get _estadoPagoDelMes {
    final now = DateTime.now();
    int estado = 0;
    for (final p in _pagos) {
      if ((p['tipo'] ?? '').toString() != 'Materia') continue;
      final f = (p['fecha'] ?? '').toString();
      final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(f);
      if (m == null) continue;
      final mes = int.tryParse(m.group(2) ?? '');
      final anio = int.tryParse(m.group(3) ?? '');
      if (mes != now.month || anio != now.year) continue;
      final validado = (p['estatus'] ?? '').toString() == 'Validado';
      if (validado) return 1;
      estado = 2;
    }
    return estado;
  }

  Widget _alCorriente(bool enRevision) {
    final color = enRevision ? const Color(0xFFA56B16) : const Color(0xFF1E7B34);
    final fondo = enRevision ? const Color(0xFFE0A800).withValues(alpha: 0.13) : const Color(0xFF1E8E3E).withValues(alpha: 0.10);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(enRevision ? Icons.hourglass_top : Icons.check_circle,
              color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enRevision
                      ? 'Ya subiste tu pago de este mes.'
                      : 'Estás al corriente este mes.',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  enRevision
                      ? 'Está en revisión; en cuanto se valide aparecerá en tu historial. No aplica recargo.'
                      : 'Tu colegiatura de este mes ya está registrada. No aplica recargo.',
                  style: TextStyle(color: cessumMuted(context), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordatorioPago() {
    final now = DateTime.now();
    final monto = _bonoRecomienda > 0 ? _montoConBono : _montoMensual;
    // MODO POR PERIODO (Mixta): no hay mensualidades, día 15 ni recargos. Se
    // muestra solo una nota informativa del pago por periodo.
    if (_esPeriodo) {
      _ultimoAviso = 'Pago por periodo académico'
          '${_fechaLimitePago.isNotEmpty ? ' · fecha límite $_fechaLimitePago' : ''}';
      return Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFFA56B16), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pago por periodo académico',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13.5)),
                  const SizedBox(height: 2),
                  Text(
                    'En la modalidad mixta el pago se realiza por periodo académico, '
                    '${_numPagos > 0 ? '$_numPagos' : '7'} pagos en total (uno por periodo).',
                    style: TextStyle(color: cessumMuted(context), fontSize: 12),
                  ),
                  if (_fechaLimitePago.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Fecha límite de este periodo: '
                      '${_fmtFechaLarga(_fechaLimitePago)} '
                      '(último día de clases del periodo).',
                      style: TextStyle(
                          color: cessumInk(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Si el pago se realiza después del último día de clases del '
                      'periodo, aplica un recargo del 5% sobre la cuota.',
                      style: TextStyle(color: cessumMuted(context), fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    // MODO POR MATERIA: la fecha límite es el término (domingo 5ª semana) de la materia.
    if (_modoPago == 'materia' && _fechaLimitePago.isNotEmpty) {
      final lim = DateTime.tryParse(_fechaLimitePago);
      if (lim != null) {
        final hoy = DateTime(now.year, now.month, now.day);
        final flim = DateTime(lim.year, lim.month, lim.day);
        final dias = flim.difference(hoy).inDays;
        final fechaTxt =
            '${flim.day.toString().padLeft(2, '0')}/${flim.month.toString().padLeft(2, '0')}/${flim.year}';
        if (dias >= 0) {
          _ultimoAviso = 'Fecha límite de pago por materia: $fechaTxt';
          final urgente = dias <= 3;
          final color = urgente ? cessumRed : const Color(0xFFA56B16);
          final fondo =
              urgente ? cessumRed.withValues(alpha: 0.09) : const Color(0xFFE0A800).withValues(alpha: 0.13);
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: fondo,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(urgente ? Icons.alarm : Icons.event_available,
                    color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          dias == 0
                              ? 'Hoy vence tu pago de la materia ($fechaTxt).'
                              : 'Faltan $dias día${dias == 1 ? '' : 's'} para tu fecha límite de pago: $fechaTxt.',
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                          _materiaLimite.isNotEmpty
                              ? 'Corresponde al cierre de: $_materiaLimite. El pago es por materia.'
                              : 'El pago es por materia (vence el domingo de la última semana).',
                          style: TextStyle(
                              color: cessumMuted(context), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          _ultimoAviso = 'Recargo por pago de materia vencido ($fechaTxt)';
          final conInteres = (monto * 1.05).roundToDouble();
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumRed.withValues(alpha: 0.55)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: cessumRed, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Venció el pago de la materia ($fechaTxt): recargo del 5%.',
                          style: const TextStyle(
                              color: cessumRed,
                              fontWeight: FontWeight.w800,
                              fontSize: 14)),
                      const SizedBox(height: 3),
                      Text('Monto con recargo: ${_money(conInteres)}.',
                          style: TextStyle(
                              color: cessumInk(context), fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
      }
    }
    // Si la colegiatura del mes ya está pagada, no hay nada que recordar ni
    // recargo que advertir.
    final estadoMes = _estadoPagoDelMes;
    if (estadoMes > 0) {
      _ultimoAviso = estadoMes == 2
          ? 'Pago del mes subido, en revisión'
          : 'Al corriente este mes';
      return _alCorriente(estadoMes == 2);
    }
    return _recordatorioMensual(now, monto);
  }

  // (sep-2026) EL RECARGO YA NO SE DECIDE SOLO CON EL CALENDARIO.
  // Antes: pasado el día 15 y sin pago de «Materia» en el mes, salía «Ya pasó
  // el día 15: aplica recargo del 5%», aunque al alumno no le tocara pagar ese
  // mes. Caso real: Gen 26-4, primera mensualidad en octubre, veía el recargo
  // el 28 de septiembre justo debajo de «Estás al día». Ahora manda el estado
  // de cuenta oficial (adeudo_estado): el recargo en rojo aparece SOLO si hay
  // pagos vencidos; si no, se muestra el próximo vencimiento real.
  Widget _recordatorioMensual(DateTime now, num monto) {
    final hoy = DateTime(now.year, now.month, now.day);
    final d = _adeudo;
    if (d == null) {
      _ultimoAviso = 'Recordatorio general (estado de cuenta no disponible)';
      return _banner(
        color: const Color(0xFFA56B16),
        icono: Icons.event_available,
        titulo: 'El pago oportuno de la colegiatura es del 1 al 15 de cada mes.',
        detalle: 'No pudimos consultar tu estado de cuenta en este momento. '
            'Desliza hacia abajo para actualizar.',
      );
    }
    final des = Map<String, dynamic>.from(
        (d['desglose'] as Map?) ?? const <String, dynamic>{});
    final venc = listaMapasCessum(des['vencidos']);
    final pv = listaMapasCessum(des['porVencer']);

    // 1) Hay pagos vencidos: aquí sí aplica el recargo.
    if (venc.isNotEmpty) {
      final n = venc.length;
      _ultimoAviso = 'Recargo por $n pago(s) vencido(s)';
      return _banner(
        color: cessumRed,
        icono: Icons.warning_amber_rounded,
        titulo: n == 1
            ? 'Tienes 1 pago vencido: aplica recargo del 5%.'
            : 'Tienes $n pagos vencidos: aplica recargo del 5%.',
        detalle: 'El detalle está en tu estado de cuenta, arriba. Si ya '
            'pagaste y no aparece, repórtalo.',
        motivo: 'adeudo',
        textoAyuda: 'Ya pagué: reportarlo',
      );
    }

    // 2) Próximo vencimiento real, según el estado de cuenta.
    final prox = proximoVencimientoCessum(pv, hoy);
    if (prox != null) {
      final f = fechaCessum(prox['fechaLimite'])!;
      final dias = f.difference(hoy).inDays;
      final concepto = (prox['concepto'] ?? '').toString();
      final llevaRecargo = !concepto.toLowerCase().contains('reinscrip');
      final urgente = dias <= 3;
      _ultimoAviso =
          'Próximo vencimiento: $concepto (${fechaLargaCessum(f)})';
      return _banner(
        color: urgente ? cessumRed : const Color(0xFFA56B16),
        icono: urgente ? Icons.alarm : Icons.event_available,
        titulo: dias == 0
            ? 'Hoy vence tu pago.'
            : dias <= 20
                ? 'Faltan $dias día${dias == 1 ? '' : 's'} para tu fecha límite de pago.'
                : 'Tu próximo pago vence el ${fechaLargaCessum(f)}.',
        detalle: '${concepto.isNotEmpty ? '$concepto · ' : ''}'
            'fecha límite: ${fechaLargaCessum(f)}.'
            '${llevaRecargo ? ' Después de esa fecha aplica un recargo del 5%.' : ''}',
      );
    }

    // 3) Nuevo ingreso: todavía no hay colegiaturas en su historial ni nada
    //    por vencer. No hay recargo que advertir.
    final tieneColegiaturas =
        _pagos.any((p) => (p['tipo'] ?? '').toString() == 'Materia');
    if (!tieneColegiaturas) {
      _ultimoAviso = 'Sin mensualidades por pagar todavía';
      return _banner(
        color: const Color(0xFF1E8E3E),
        icono: Icons.check_circle,
        titulo: 'No tienes mensualidades por pagar en este momento.',
        detalle: 'Cada colegiatura se cubre del 1 al 15 del mes que '
            'corresponde. Cuando se acerque tu fecha límite, aparecerá aquí.',
      );
    }

    // 4) Alumno en curso, sin adeudo vencido, pero sin el pago de este mes
    //    en su historial. Del 1 al 15: cuenta regresiva. Después del 15: aviso
    //    ÁMBAR (no rojo), porque el estado de cuenta no marca adeudo.
    if (now.day <= 15) {
      final faltan = 15 - now.day;
      final urgente = faltan <= 3;
      _ultimoAviso = 'Cuenta regresiva al día 15 ($faltan días)';
      return _banner(
        color: urgente ? cessumRed : const Color(0xFFA56B16),
        icono: urgente ? Icons.alarm : Icons.event_available,
        titulo: faltan == 0
            ? 'Hoy es tu fecha límite de pago (día 15).'
            : 'Faltan $faltan día${faltan == 1 ? '' : 's'} para tu fecha límite de pago (día 15).',
        detalle: 'El pago oportuno es del 1 al 15 de cada mes.',
      );
    }
    final conInteres = (monto * 1.05).roundToDouble();
    _ultimoAviso = 'Colegiatura del mes no registrada (después del día 15)';
    return _banner(
      color: const Color(0xFFA56B16),
      icono: Icons.info_outline,
      titulo: 'Tu colegiatura de este mes no aparece registrada.',
      detalle: 'Tu estado de cuenta no marca adeudo vencido. Si te corresponde '
          'pagar este mes, después del día 15 el monto con recargo del 5% es '
          '${_money(conInteres)}. Si ya pagaste, sube tu comprobante o '
          'repórtalo.',
      motivo: 'no_aparece',
      textoAyuda: 'Ya pagué: reportarlo',
    );
  }

  Widget _banner({
    required Color color,
    required IconData icono,
    required String titulo,
    required String detalle,
    String? motivo,
    String textoAyuda = '¿No te corresponde? Repórtalo',
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(detalle,
                    style: TextStyle(
                        color: cessumInk(context),
                        fontSize: 12.5,
                        height: 1.35)),
                if (motivo != null)
                  TextButton.icon(
                    onPressed: () =>
                        _abrirAyuda(motivo: motivo, detalle: titulo),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        foregroundColor: color),
                    icon: const Icon(Icons.support_agent, size: 16),
                    label:
                        Text(textoAyuda, style: const TextStyle(fontSize: 12)),
                  )
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Análisis automático y mesa de ayuda ─────────────────────────────────

  Widget _analisis() {
    final hs = analizarPagos(
      pagos: _pagos,
      montoMensual: _montoMensual,
      montoConBono: _bonoRecomienda > 0 ? _montoConBono : 0,
      modoPago: _modoPago,
      esBeca: _esBeca,
      porcentajeBeca: _porcentaje,
      montoDesconocido: _desconocido,
      adeudo: _adeudo,
    );
    return AnalisisPagosCard(
      hallazgos: hs,
      onReportar: (x) => _abrirAyuda(
          motivo: x.motivoAyuda, detalle: '${x.titulo}. ${x.detalle}'),
    );
  }

  Widget _tarjetaAyuda() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _abrirAyuda(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cessumRed.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const Icon(Icons.support_agent, color: cessumRed, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('¿Algo no está bien?',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(
                      'Abre la mesa de ayuda: tu reporte llega a Atención a '
                      'Estudiantes con tus datos y con lo que ves en esta '
                      'pantalla.',
                      style: TextStyle(
                          fontSize: 12, height: 1.35, color: cessumMuted(context))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: cessumRed),
          ],
        ),
      ),
    );
  }

  void _abrirAyuda({String? motivo, String? detalle}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MesaAyudaPagosScreen(
        motivoInicial: motivo,
        detalleInicial: detalle,
        contexto: _contextoAyuda(),
      ),
    ));
  }

  String _contextoAyuda() {
    final d = _adeudo;
    final des = Map<String, dynamic>.from(
        (d?['desglose'] as Map?) ?? const <String, dynamic>{});
    final b = StringBuffer()
      ..writeln('Pantalla: Mis pagos')
      ..writeln('Esquema de pago: $_modoPago')
      ..writeln('Monto mostrado: '
          '${_desconocido ? 'no calculado' : _money(_montoMensual)}'
          '${_esBeca ? ' (beca $_porcentaje%)' : ''}')
      ..writeln('Estado de cuenta: '
          '${d == null ? 'no disponible' : '${d['etiqueta'] ?? ''}'}')
      ..writeln('Vencidos: ${listaMapasCessum(des['vencidos']).length} · '
          'Por vencer: ${listaMapasCessum(des['porVencer']).length}')
      ..writeln('Pagos registrados: ${_pagos.length} '
          '(por validar: $_porValidar)');
    if (_ultimoAviso.isNotEmpty) b.writeln('Aviso en pantalla: $_ultimoAviso');
    return b.toString().trim();
  }

  Widget _botonPago() {
    if (_linkPago.trim().isEmpty) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Ir al formulario de pago',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        onPressed: () async {
          final uri = Uri.parse(_linkPago.trim());
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('No se pudo abrir el formulario de pago.')));
          }
        },
      ),
    );
  }

  Widget _resumen() {
    Widget chip(String label, String valor, IconData ic) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: Column(
              children: [
                Icon(ic, color: cessumGold, size: 20),
                const SizedBox(height: 4),
                Text(valor,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text(label,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        chip('Colegiaturas\npagadas', _money(_sumaMateria), Icons.payments),
        chip('Reinscripciones', _money(_sumaReins), Icons.event_repeat),
        if (_porValidar > 0)
          chip('Por validar', '$_porValidar', Icons.hourglass_bottom),
      ],
    );
  }

  /// Pide el COMPROBANTE OFICIAL de un pago ya validado: PDF con encabezado
  /// de CESSUM, folio verificable y firma de la Dirección de Administración y
  /// Finanzas.
  ///
  /// La ruta es 'comprobante_pago_alumno' y NO 'comprobante_pago': esta
  /// pantalla lista los pagos de la hoja PagosConsolidado (la que arman los
  /// formularios de registro), mientras que la ruta del administrador lee la
  /// hoja Pagos. Son bases distintas y sus números de fila no se corresponden.
  Future<void> _comprobante(Map<String, dynamic> p) async {
    final mat = _perfil?.matricula.trim() ?? '';
    if (mat.isEmpty) {
      _aviso('No encontramos tu matrícula en este dispositivo.');
      return;
    }
    setState(() => _emitiendo = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'comprobante_pago_alumno',
        'matricula': mat,
        'fila': '${p['fila']}',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      final pdf = (d['pdfUrl'] ?? '').toString();
      final folio = (d['folio'] ?? '').toString();
      // Un ok:true SIN pdfUrl no es un comprobante: es el Guardián
      // respondiendo a una acción que no reconoce, casi siempre porque el
      // Code.gs se guardó pero no se publicó.
      if (pdf.isEmpty) {
        throw Exception('El servidor respondió sin comprobante. Falta '
            'publicar la versión nueva del Guardián en Apps Script.');
      }
      if (!mounted) return;
      // El PDF se abre desde un botón del diálogo y no solo: si se llama a
      // launchUrl después de esperar la respuesta, el navegador lo trata como
      // ventana emergente y lo bloquea sin avisar.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Comprobante listo',
              style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Tu comprobante quedó emitido con la firma de la Dirección '
                  'de Administración y Finanzas.',
                  style: TextStyle(fontSize: 13, height: 1.35)),
              if (folio.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Folio: $folio',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 10),
              Text(
                  'Este documento acredita el pago ante la institución. No es '
                  'una factura (CFDI): si la necesitas, pídela a la Dirección '
                  'de Administración y Finanzas antes del cierre del mes.',
                  style: TextStyle(
                      fontSize: 11.5, height: 1.35, color: cessumMuted(context))),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                Navigator.pop(ctx);
                _abrirPdf(pdf);
              },
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Descargar PDF'),
            ),
          ],
        ),
      );
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''));
    }
    if (mounted) setState(() => _emitiendo = false);
  }

  Future<void> _abrirPdf(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    try {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el PDF.');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  Widget _itemPago(Map<String, dynamic> p) {
    final estatus = (p['estatus'] ?? '').toString();
    final porValidar = estatus.toLowerCase() == 'por validar';
    final tipo = (p['tipo'] ?? '').toString();
    final monto = (p['monto'] ?? '').toString();
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
      ListTile(
        leading: Icon(
          tipo == 'Reinscripción' ? Icons.event_repeat : Icons.payments,
          color: cessumRed,
        ),
        title: Text(
          (p['concepto'] ?? tipo).toString().isEmpty
              ? tipo
              : (p['concepto'] ?? tipo).toString(),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${p['fecha'] ?? ''}'
          '${tipo.isNotEmpty ? ' · $tipo' : ''}',
          style: const TextStyle(fontSize: 11.5),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (monto.isNotEmpty)
              Text(_money(num.tryParse(monto.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13.5)),
            if (porValidar)
              const Text('Por validar',
                  style: TextStyle(fontSize: 10.5, color: cessumGold))
            else
              const Text('Validado',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF1E8E3E))),
          ],
        ),
      ),
          // COMPROBANTE INSTITUCIONAL. Solo para pagos ya validados: uno "Por
          // validar" todavía no está asentado en los registros, y el documento
          // afirma que la institución recibió el pago.
          if (!porValidar)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: TextButton.icon(
                  onPressed: _emitiendo ? null : () => _comprobante(p),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF1E8E3E)),
                  icon: const Icon(Icons.workspace_premium, size: 16),
                  label: const Text('Comprobante oficial',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

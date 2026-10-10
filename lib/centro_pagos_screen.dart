// =====================================================================
//  CENTRO DE PAGOS (4-oct-2026)
//  Entrada única de administración para todo lo de pagos. Arriba, lo que
//  espera una decisión, con cuántos son, su antigüedad y si ya pasó el
//  plazo; abajo, las herramientas. Cada tarjeta abre la pantalla de
//  siempre: aquí no se valida ni se decide nada, solo se ve y se entra.
//  Lee la ruta pagos_centro del Guardián (caché de 10 minutos;
//  «Actualizar» la ignora).
// =====================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'seguimiento_pagos_admin_screen.dart';
import 'pagos_por_aclarar_screen.dart';
import 'pagos_auditoria_ia_screen.dart';
import 'bajas_pago_screen.dart';
import 'convenios_admin_screen.dart';
import 'pagos_docentes_screen.dart';
import 'pagos_screen.dart';
import 'convenio_pago_screen.dart';
import 'ajuste_pagos_admin_screen.dart';
import 'pagos_administrativos_screen.dart';
import 'admin_pagos_screen.dart';
import 'conciliacion_pagos_screen.dart';

const Color _verde = Color(0xFF1E7B34);
const Color _ambar = Color(0xFFB7791F);

class CentroPagosScreen extends StatefulWidget {
  const CentroPagosScreen({super.key});
  @override
  State<CentroPagosScreen> createState() => _CentroPagosScreenState();
}

class _CentroPagosScreenState extends State<CentroPagosScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar({bool fresco = false}) async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final actor = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pagos_centro', 'actor': actor, if (fresco) 'fresco': '1'});
      final r = await http.get(uri).timeout(const Duration(seconds: 170));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() { _cargando = false; _d = d; if (d['ok'] != true) _error = '${d['error'] ?? 'No se pudo cargar.'}'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'No se pudo cargar el resumen (conexión o tiempo). Las pantallas de abajo funcionan igual.'; });
    }
  }

  Map<String, dynamic> _t(String k) => Map<String, dynamic>.from(((_d['tarjetas'] as Map?) ?? {})[k] as Map? ?? {});
  int? _n(dynamic v) => v == null ? null : int.tryParse('$v'.split('.').first);

  Future<void> _abrir(Widget w) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    if (mounted) _cargar(fresco: true);   // al volver, los contadores reflejan lo que se hizo
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Centro de pagos'),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : () => _cargar(fresco: true), icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        color: cessumRed,
        onRefresh: () => _cargar(fresco: true),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 30), children: [
          _encabezado(),
          const SizedBox(height: 16),
          _titulo('Espera una decisión'),
          _decisiones(),
          const SizedBox(height: 20),
          _titulo('Herramientas'),
          _herramientas(),
        ]),
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: cessumGold, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: cessumRed)),
        ]),
      );

  Widget _encabezado() {
    final pv = _t('porValidar');
    final urg = _n(_d['urgentes']) ?? 0;
    String linea;
    if (_cargando) {
      linea = 'Revisando todas las bandejas… puede tardar hasta un minuto.';
    } else if (_error.isNotEmpty) {
      linea = _error;
    } else {
      final total = ['porValidar', 'porAclarar', 'auditoriaIa', 'bajas', 'conveniosSolicitudes', 'docentes']
          .map((k) => k == 'porValidar' ? (_n(pv['recientes']) ?? 0) : (_n(_t(k)['total']) ?? 0))
          .fold<int>(0, (a, b) => a + b);
      linea = total == 0 ? 'Todo al día.' : '$total asunto(s) esperan una decisión${urg > 0 ? ' · $urg con plazo vencido' : ''}.';
    }
    return Container(
      decoration: BoxDecoration(color: cessumRed, borderRadius: BorderRadius.circular(16), border: const Border(bottom: BorderSide(color: cessumGold, width: 4))),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 30),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('PAGOS · ADMINISTRACIÓN', style: TextStyle(color: Color(0xFFF6EBD3), fontSize: 10.5, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(linea, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.35)),
          if ('${_d['generado'] ?? ''}'.isNotEmpty && !_cargando)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Corte: ${_d['generado']}${_d['deCache'] == true ? ' · desliza hacia abajo para actualizar' : ''}',
                style: const TextStyle(color: Color(0xFFF7DCDC), fontSize: 11.5))),
        ])),
        if (_cargando) const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
      ]),
    );
  }

  Widget _decisiones() {
    final pv = _t('porValidar'), pa = _t('porAclarar'), ia = _t('auditoriaIa'), bj = _t('bajas'), cs = _t('conveniosSolicitudes'), dc = _t('docentes');
    final items = <Widget>[
      _tarjeta(
        icono: Icons.fact_check_outlined, titulo: 'Pagos por validar',
        numero: _n(pv['recientes']),
        detalle: pv.isEmpty ? '' : (_n(pv['recientes']) == 0 ? 'Nada reciente por validar' : 'El más antiguo lleva ${pv['diasMasViejoReciente']} día(s) · plazo 3 días hábiles'),
        nota: (_n(pv['antiguos']) ?? 0) > 0 ? '+ ${pv['antiguos']} con más de 90 días (rezago histórico)' : '',
        vencido: pv['vencido'] == true,
        destino: const SeguimientoPagosAdminScreen(),
        accion: ((_n(pv['antiguos']) ?? 0) > 0 || (_n(pv['cerradosHistoricos']) ?? 0) > 0)
            ? Wrap(spacing: 6, runSpacing: 4, children: [
                if ((_n(pv['antiguos']) ?? 0) > 0)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: const BorderSide(color: cessumRed), visualDensity: VisualDensity.compact),
                    onPressed: _cerrarRezago,
                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                    label: const Text('Cerrar rezago', style: TextStyle(fontSize: 12))),
                if ((_n(pv['cerradosHistoricos']) ?? 0) > 0)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _reabrirTodos,
                    child: Text('${pv['cerradosHistoricos']} cerrados · reabrir', style: const TextStyle(fontSize: 12))),
              ])
            : null),
      _tarjeta(icono: Icons.report_gmailerrorred_outlined, titulo: 'Pagos por aclarar', numero: _n(pa['total']),
        detalle: 'Comprobantes que no cuadran con un alumno', destino: const PagosPorAclararScreen(), error: '${pa['error'] ?? ''}'),
      _tarjeta(icono: Icons.auto_awesome, titulo: 'Auditoría con IA', numero: _n(ia['total']),
        detalle: ia.isEmpty ? '' : '${ia['duplicados'] ?? 0} duplicado(s) · ${ia['revisar'] ?? 0} por revisar · ${ia['noLegibles'] ?? 0} no legible(s)',
        destino: const PagosAuditoriaIaScreen(), error: '${ia['error'] ?? ''}'),
      _tarjeta(icono: Icons.person_off_outlined, titulo: 'Bajas por pago', numero: _n(bj['total']),
        detalle: 'Alumnos que cumplen la regla de baja y esperan tu decisión', destino: const BajasPagoScreen(), error: '${bj['error'] ?? ''}'),
      _tarjeta(icono: Icons.handshake_outlined, titulo: 'Solicitudes de convenio', numero: _n(cs['total']),
        detalle: (_n(cs['total']) ?? 0) == 0 ? 'Sin solicitudes por responder' : 'La más antigua lleva ${cs['diasMasViejo'] ?? 0} día(s)',
        vencido: cs['vencido'] == true, destino: const ConveniosAdminScreen(), error: '${cs['error'] ?? ''}'),
      _tarjeta(icono: Icons.school_outlined, titulo: 'Docentes por pagar', numero: _n(dc['total']),
        detalle: (_n(dc['montoEstimado']) ?? 0) > 0 ? 'Estimado: \$${_miles(_n(dc['montoEstimado'])!)}' : 'Materias terminadas sin pago registrado',
        destino: const PagosDocentesScreen(), error: '${dc['error'] ?? ''}'),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth > 760 ? 3 : (c.maxWidth > 480 ? 2 : 1);
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (final w in items) SizedBox(width: (c.maxWidth - 12 * (cols - 1)) / cols, child: w),
      ]);
    });
  }

  // ── (4-oct-2026) Rezago histórico: cerrar y reabrir ──
  Future<Map<String, dynamic>> _llamar(Map<String, String> q) async {
    final actor = (await SessionStore.validEmail()) ?? '';
    final uri = Uri.parse(guardianUrl).replace(queryParameters: {...q, 'actor': actor});
    final r = await http.get(uri).timeout(const Duration(seconds: 120));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cerrarRezago() async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)));
    Map<String, dynamic> d;
    try { d = await _llamar({'accion': 'pagos_historicos', 'dias': '90'}); } catch (e) { d = {'ok': false, 'error': '$e'}; }
    if (!mounted) return;
    Navigator.of(context).pop();
    if (d['ok'] != true) { _snack('${d['error'] ?? 'No se pudo revisar el rezago.'}'); return; }
    final lista = ((d['lista'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (lista.isEmpty) { _snack('No hay pagos por validar con más de 90 días.'); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar el rezago histórico'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['candidatos']} pago(s) por validar con más de 90 días · ${d['alumnos']} alumno(s) · \$${_miles(_n(d['montoTotal']) ?? 0)} · el más viejo lleva ${d['masViejo']} días.',
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Text('Cerrarlos solo los quita de los contadores de pendientes (este Centro, el correo diario y la barra). '
                  'No cambian adeudos, bajas ni estados de cuenta, no se avisa a nadie y se pueden reabrir.',
                  style: TextStyle(fontSize: 12.5, height: 1.45)),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final x in lista.take(60))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('${x['fecha']} · ${x['nombre']} (${x['matricula']}) · \$${x['monto']} · ${x['dias']} días',
                        style: const TextStyle(fontSize: 12)),
                  ),
                if (lista.length > 60) Text('… y ${lista.length - 60} más.', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true),
              child: Text('Cerrar ${d['candidatos']} pago(s)')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await _llamar({'accion': 'pagos_historicos', 'dias': '90', 'confirmar': '1'});
      if (!mounted) return;
      _snack(r['ok'] == true ? 'Listo: ${r['cerrados'] ?? 0} pago(s) cerrados como históricos.' : '${r['error'] ?? 'No se pudo cerrar.'}');
    } catch (e) {
      _snack('No se pudo cerrar: $e');
    }
    if (mounted) _cargar(fresco: true);
  }

  Future<void> _reabrirTodos() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reabrir los pagos históricos'),
        content: const Text('Vuelven a contar como «por validar» en los pendientes. No cambia nada más.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reabrir todos')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final r = await _llamar({'accion': 'pagos_historicos_reabrir', 'todos': '1'});
      if (!mounted) return;
      _snack(r['ok'] == true ? '${r['reabiertos'] ?? 0} pago(s) reabiertos.' : '${r['error'] ?? 'No se pudo reabrir.'}');
    } catch (e) {
      _snack('No se pudo reabrir: $e');
    }
    if (mounted) _cargar(fresco: true);
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  String _miles(int v) => '$v'.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  Widget _tarjeta({required IconData icono, required String titulo, required int? numero, required String detalle,
      required Widget destino, String nota = '', bool vencido = false, String error = '', Widget? accion}) {
    final hay = (numero ?? 0) > 0;
    final color = vencido ? cessumRed : (hay ? _ambar : _verde);
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _abrir(destino),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: _cargando ? cessumMuted(context).withValues(alpha: 0.3) : color, width: 5)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icono, color: cessumRed, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(error.isNotEmpty ? 'No se pudo contar; ábrelo para revisar.' : detalle,
                  style: TextStyle(fontSize: 12, height: 1.35, color: error.isNotEmpty ? cessumRed : cessumMuted(context))),
              if (nota.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(nota, style: TextStyle(fontSize: 11.5, color: cessumMuted(context), fontStyle: FontStyle.italic))),
              if (vencido) const Padding(padding: EdgeInsets.only(top: 4), child: Text('PLAZO VENCIDO', style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: cessumRed))),
              if (accion != null && !_cargando) Padding(padding: const EdgeInsets.only(top: 6), child: accion),
            ])),
            const SizedBox(width: 8),
            _cargando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(numero == null ? '—' : '$numero', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: color, height: 1)),
          ]),
        ),
      ),
    );
  }

  Widget _herramientas() {
    final h = <(IconData, String, String, Widget)>[
      (Icons.account_balance, 'Conciliación bancaria', 'Cruza los pagos por validar con los depósitos del banco y valida los que ya están', const ConciliacionPagosScreen()),
      (Icons.edit_note, 'Registro de pagos', 'Registrar, consultar y corregir pagos (inscripciones, colegiaturas, trámites)', const PagosScreen()),
      (Icons.request_quote_outlined, 'Nuevo convenio de pago', 'Armar un plan de pagos para un alumno, con IA si quieres', const ConvenioPagoScreen()),
      (Icons.tune, 'Ajustes de cuota', 'Montos especiales por alumno o por grupo (becas, descuentos, excepciones)', const AjustePagosAdminScreen()),
      (Icons.badge_outlined, 'Nómina administrativa', 'Pagos al personal administrativo', const PagosAdministrativosScreen()),
      (Icons.description_outlined, 'Contratos y pagos del personal', 'Contratos en PDF, firmas y registro de pagos del staff', const AdminPagosScreen()),
    ];
    return Column(children: [
      for (final x in h)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Icon(x.$1, color: cessumGold),
            title: Text(x.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            subtitle: Text(x.$3, style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _abrir(x.$4),
          ),
        ),
    ]);
  }
}

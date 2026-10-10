import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'foto_web_picker.dart';
import 'csv_export.dart';   // (24-sep) exportar la nómina con el estado del mes

// =====================================================================
// PAGOS Y CONTRATOS ADMINISTRATIVOS (panel admin) — separado de docentes
//   GET  admin_staff_listar ?actor
//   POST admin_staff_guardar   { actor, id, nombre, rfc, rol, monto, correo }
//   POST admin_staff_eliminar  { actor, id }
//   POST admin_contrato_pdf    { actor, id } -> { url }   (honorarios 6 meses)
//   POST admin_pago_registrar  { actor, nombre, correo, periodo, monto,
//                                base64, mime } -> { comprobante }
// =====================================================================

class AdminPagosScreen extends StatefulWidget {
  const AdminPagosScreen({super.key});

  @override
  State<AdminPagosScreen> createState() => _AdminPagosScreenState();
}

class _AdminPagosScreenState extends State<AdminPagosScreen> {
  bool _cargando = true;
  String _error = '';
  String _actor = '';
  List<Map<String, dynamic>> _lista = [];
  final Set<String> _ocupado = {};
  // (24-sep) Historial de pagos (admin_pagos_listar) y buscador.
  List<Map<String, dynamic>> _pagos = [];
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];

  /// ¿Este pago corresponde al mes en curso? Por el periodo escrito
  /// («Septiembre 2026») o, si no lo dice, por la fecha en que se registró.
  bool _esDelMes(Map<String, dynamic> pg) {
    final n = DateTime.now();
    final per = '${pg['periodo'] ?? ''}'.toLowerCase();
    if (per.contains(_meses[n.month - 1]) && per.contains('${n.year}')) return true;
    final f = '${pg['fecha'] ?? ''}'; // dd/MM/yyyy
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(f);
    if (per.trim().isEmpty && m != null) {
      return int.parse(m.group(2)!) == n.month && int.parse(m.group(3)!) == n.year;
    }
    return false;
  }

  bool _esDe(Map<String, dynamic> pg, Map<String, dynamic> p) {
    final c1 = '${pg['correo'] ?? ''}'.trim().toLowerCase(), c2 = '${p['correo'] ?? ''}'.trim().toLowerCase();
    if (c1.isNotEmpty && c2.isNotEmpty) return c1 == c2;
    return '${pg['nombre'] ?? ''}'.trim().toLowerCase() == '${p['nombre'] ?? ''}'.trim().toLowerCase();
  }

  List<Map<String, dynamic>> _pagosDe(Map<String, dynamic> p) => _pagos.where((pg) => _esDe(pg, p)).toList();
  bool _pagadoEsteMes(Map<String, dynamic> p) => _pagosDe(p).any(_esDelMes);
  bool _activo(Map<String, dynamic> p) => '${p['estatus'] ?? 'Activo'}'.toLowerCase() != 'baja';
  num _monto(dynamic v) => v is num ? v : (num.tryParse('$v'.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0);
  String _pesos(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  void _exportar() {
    descargarCsv(
        'nomina_administrativa.csv',
        construirCsv(['Nombre', 'RFC', 'Correo', 'Rol', 'Estatus', 'Monto mensual', 'Pagado este mes', 'Último pago'], [
          for (final p in _lista)
            () {
              final pg = _pagosDe(p);
              final u = pg.isEmpty ? null : pg.last;
              return [
                p['nombre'], p['rfc'], p['correo'], p['rol'], p['estatus'] ?? 'Activo', _monto(p['monto']),
                _pagadoEsteMes(p) ? 'Sí' : 'No',
                u == null ? '' : '${u['fecha']} · ${u['periodo']} · ${_monto(u['monto'])}',
              ];
            }(),
        ]));
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    // (24-sep) Correo REAL: en «Ver como profesor» validEmail() devuelve el del
    // profesor, y el Guardián rechazaría la acción por no ser administrador.
    _actor = (await SessionStore.realEmail()) ?? '';
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=admin_staff_listar&actor=${Uri.encodeComponent(_actor)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      // (24-sep) El historial de pagos, para saber a quién le falta el del mes.
      var pagos = <Map<String, dynamic>>[];
      // (4-oct-2026) Si el historial falla, NO se dice que a todos les falta el pago del mes: se avisa.
      var fallaPagos = false;
      try {
        final r2 = await http
            .get(Uri.parse('$guardianUrl?accion=admin_pagos_listar&actor=${Uri.encodeComponent(_actor)}'))
            .timeout(const Duration(seconds: 30));
        final d2 = jsonDecode(r2.body) as Map<String, dynamic>;
        if (d2['ok'] == true) {
          pagos = (d2['pagos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } else {
          fallaPagos = true;
        }
      } catch (_) {
        fallaPagos = true;
      }
      if (!mounted) return;
      if (fallaPagos) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(seconds: 6),
            content: Text('No se pudo cargar el historial de pagos del personal: lo de «falta el pago del mes» puede no ser exacto. Actualiza en un momento.')));
      }
      setState(() {
        _lista = (data['administrativos'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _pagos = pagos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        // (24-sep) El motivo real (p. ej. «cierre sesión y vuelva a entrar»).
        _error = (m.contains('TimeoutException') || m.startsWith('FormatException'))
            ? 'No se pudo cargar. Intente de nuevo en un momento.'
            : m;
      });
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    payload['actor'] = _actor;
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 90));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  void _snack(String t, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t), backgroundColor: err ? cessumRed : CC.goldDark));
  }

  Future<void> _editar([Map<String, dynamic>? p]) async {
    final nombre = TextEditingController(text: (p?['nombre'] ?? '').toString());
    final rfc = TextEditingController(text: (p?['rfc'] ?? '').toString());
    final correo = TextEditingController(text: (p?['correo'] ?? '').toString());
    final monto = TextEditingController(
        text: p != null ? (p['monto'] ?? '').toString() : '3000');
    String rol = (p?['rol'] ?? 'Honorarios').toString();
    if (rol != 'Honorarios' && rol != 'Directivo') rol = 'Honorarios';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(p == null ? 'Agregar persona' : 'Editar'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: nombre,
                  decoration: const InputDecoration(labelText: 'Nombre completo')),
              TextField(
                  controller: rfc,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'RFC (opcional)')),
              TextField(
                  controller: correo,
                  keyboardType: TextInputType.emailAddress,
                  decoration:
                      const InputDecoration(labelText: 'Correo (opcional)')),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Rol: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: rol,
                  items: const [
                    DropdownMenuItem(
                        value: 'Honorarios', child: Text('Honorarios')),
                    DropdownMenuItem(
                        value: 'Directivo', child: Text('Directivo')),
                  ],
                  onChanged: (v) => setD(() {
                    rol = v ?? 'Honorarios';
                    if (monto.text.isEmpty ||
                        monto.text == '3000' ||
                        monto.text == '7000') {
                      monto.text = rol == 'Directivo' ? '7000' : '3000';
                    }
                  }),
                ),
              ]),
              TextField(
                  controller: monto,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  decoration: const InputDecoration(
                      labelText: 'Monto mensual (\$)', prefixText: '\$ ')),
            ]),
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
      ),
    );
    if (ok != true) return;
    if (nombre.text.trim().isEmpty) {
      _snack('El nombre es obligatorio.', err: true);
      return;
    }
    final data = await _post({
      'accion': 'admin_staff_guardar',
      'id': p?['id'] ?? nombre.text.trim(),
      'nombre': nombre.text.trim(),
      'rfc': rfc.text.trim(),
      'rol': rol,
      'monto': monto.text.trim(),
      'correo': correo.text.trim(),
    });
    if (data['ok'] == true) {
      _snack('Guardado.');
      _cargar();
    } else {
      _snack('${data['error'] ?? 'No se pudo guardar.'}', err: true);
    }
  }

  Future<void> _contrato(Map<String, dynamic> p) async {
    if ((p['rfc'] ?? '').toString().trim().isEmpty) {
      _snack('Captura primero el RFC de esta persona para el contrato.',
          err: true);
      _editar(p);
      return;
    }
    final id = (p['id'] ?? '').toString();
    setState(() => _ocupado.add('c$id'));
    _snack('Generando contrato…');
    try {
      final data =
          await _post({'accion': 'admin_contrato_pdf', 'id': id});
      if (data['ok'] == true && (data['url'] ?? '').toString().isNotEmpty) {
        await launchUrl(Uri.parse(data['url'].toString()),
            mode: LaunchMode.externalApplication);
      } else {
        _snack('${data['error'] ?? 'No se pudo generar.'}', err: true);
      }
    } catch (_) {
      _snack('Error de conexión.', err: true);
    }
    if (mounted) setState(() => _ocupado.remove('c$id'));
  }

  Future<void> _firma(Map<String, dynamic> p) async {
    final correo = (p['correo'] ?? '').toString().trim().toLowerCase();
    if (correo.isEmpty || !correo.contains('@')) {
      _snack('Primero captura el correo de esta persona (Editar).', err: true);
      _editar(p);
      return;
    }
    final foto = await seleccionarFoto();
    if (foto == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Subir firma'),
        content: Text(
            'Registrar esta firma para:\n${p['nombre']}\n$correo\n\n'
            'Requisito: debe ser PNG con fondo transparente (sin fondo).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar firma'),
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
                'accion': 'firma_docente_guardar',
                'correo': correo,
                'solicitante': _actor,
                'imagenBase64': base64Encode(foto.bytes),
              }))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _snack('Firma guardada. Ya saldrá en su contrato.');
      } else {
        _snack('${data['error'] ?? 'No se pudo guardar la firma.'}',
            err: true);
      }
    } catch (_) {
      _snack('Error de conexión.', err: true);
    }
  }

  Future<void> _registrarPago(Map<String, dynamic> p) async {
    final periodo = TextEditingController(
        text: _mesActual());
    final monto =
        TextEditingController(text: (p['monto'] ?? '').toString());
    List<int>? compBytes;
    String compMime = '';
    String compNombre = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text('Registrar pago · ${(p['nombre'] ?? '').toString()}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: periodo,
                decoration:
                    const InputDecoration(labelText: 'Periodo (ej. Julio 2026)')),
            TextField(
                controller: monto,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: const InputDecoration(
                    labelText: 'Monto', prefixText: '\$ ')),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed)),
              icon: const Icon(Icons.attach_file, size: 18),
              label: Text(compBytes == null
                  ? 'Subir comprobante'
                  : 'Comprobante: $compNombre'),
              onPressed: () async {
                final doc = await seleccionarDocumento();
                if (doc != null) {
                  setD(() {
                    compBytes = doc.bytes;
                    compMime = doc.mime;
                    compNombre = doc.nombre;
                  });
                }
              },
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final payload = <String, dynamic>{
      'accion': 'admin_pago_registrar',
      'nombre': p['nombre'] ?? '',
      'correo': p['correo'] ?? '',
      'periodo': periodo.text.trim(),
      'monto': monto.text.trim(),
    };
    if (compBytes != null) {
      payload['base64'] = base64Encode(compBytes!);
      payload['mime'] = compMime;
    }
    final data = await _post(payload);
    if (data['ok'] == true) {
      _snack('Pago registrado.');
      await _cargar(); // (24-sep) se refleja al instante en «pagado este mes»
    } else {
      _snack('${data['error'] ?? 'No se pudo registrar.'}', err: true);
    }
  }

  String _mesActual() {
    const m = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
      'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];
    final n = DateTime.now();
    return '${m[n.month - 1]} ${n.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Pagos y contratos · Administrativos'),
        actions: [
          IconButton(
              tooltip: 'Exportar la nómina a CSV',
              onPressed: _cargando || _lista.isEmpty ? null : _exportar,
              icon: const Icon(Icons.download)),
          IconButton(
              tooltip: 'Agregar persona',
              onPressed: () => _editar(),
              icon: const Icon(Icons.person_add_alt_1)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : RefreshIndicator(
              color: cessumRed,
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error.isNotEmpty)
                    Text(_error, style: const TextStyle(color: cessumRed))
                  else if (_lista.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 30),
                      child: Center(
                          child: Text('Sin personal. Usa + para agregar.',
                              style: TextStyle(color: CC.muted))),
                    )
                  else ...[
                    _resumen(),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _q,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Buscar por nombre, RFC, correo o rol',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._lista.where((p) {
                      final q = _q.text.trim().toLowerCase();
                      return q.isEmpty ||
                          '${p['nombre']} ${p['rfc']} ${p['correo']} ${p['rol']}'.toLowerCase().contains(q);
                    }).map(_tarjeta),
                  ],
                ],
              ),
            ),
    );
  }

  /// (24-sep) Resumen del mes: nómina, pagado y a quién le falta.
  Widget _resumen() {
    final activos = _lista.where(_activo).toList();
    final nomina = activos.fold<num>(0, (s, p) => s + _monto(p['monto']));
    final pagadoMes = _pagos.where(_esDelMes).fold<num>(0, (s, pg) => s + _monto(pg['monto']));
    final faltan = activos.where((p) => !_pagadoEsteMes(p)).toList();
    Widget kpi(String v, String t, {Color? c}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CC.gold.withValues(alpha: 0.35)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v, style: TextStyle(color: c ?? CC.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              Text(t, style: const TextStyle(color: CC.muted, fontSize: 10.5)),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        kpi('${activos.length}', 'personas activas'),
        const SizedBox(width: 8),
        kpi(_pesos(nomina), 'nómina mensual'),
        const SizedBox(width: 8),
        kpi(_pesos(pagadoMes), 'pagado en ${_mesActual()}', c: CC.goldDark),
      ]),
      const SizedBox(height: 8),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: (faltan.isEmpty ? const Color(0xFF1E8E3E) : cessumRed).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          faltan.isEmpty
              ? 'Todos tienen registrado su pago de ${_mesActual()}.'
              : 'Sin pago registrado en ${_mesActual()}: ${faltan.map((p) => p['nombre']).join(', ')}.',
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: faltan.isEmpty ? const Color(0xFF1E8E3E) : cessumRed),
        ),
      ),
    ]);
  }

  Widget _tarjeta(Map<String, dynamic> p) {
    final rol = (p['rol'] ?? 'Honorarios').toString();
    final esDir = rol.toLowerCase().contains('directiv');
    final color = esDir ? CC.goldDark : cessumRed;
    final id = (p['id'] ?? '').toString();
    final gen = _ocupado.contains('c$id');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CC.gold.withValues(alpha: 0.35)),
      ),
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
                    Text((p['nombre'] ?? '').toString(),
                        style: const TextStyle(
                            color: CC.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text([
                      if ((p['rfc'] ?? '').toString().isNotEmpty)
                        (p['rfc']).toString(),
                      if ((p['correo'] ?? '').toString().isNotEmpty)
                        (p['correo']).toString(),
                    ].join(' · '),
                        style: const TextStyle(color: CC.muted, fontSize: 11)),
                    if ((p['rfc'] ?? '').toString().trim().isEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: cessumRed.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('RFC pendiente',
                            style: TextStyle(
                                color: cessumRed,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(rol,
                        style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 4),
                  Text('\$${(p['monto'] ?? 0).toString()}',
                      style: const TextStyle(
                          color: CC.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const Text('mensual',
                      style: TextStyle(color: CC.muted, fontSize: 9)),
                ],
              ),
            ],
          ),
          () {
            // (24-sep) Estado del mes y último pago.
            final pg = _pagosDe(p);
            final u = pg.isEmpty ? null : pg.last;
            final pagado = _pagadoEsteMes(p);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Icon(pagado ? Icons.check_circle : Icons.schedule,
                    size: 16, color: pagado ? const Color(0xFF1E8E3E) : cessumRed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${pagado ? 'Pagado en ${_mesActual()}' : 'Sin pago en ${_mesActual()}'}'
                    '${u == null ? ' · aún no tiene pagos registrados' : ' · último: ${u['fecha']} · ${u['periodo']} · ${_pesos(_monto(u['monto']))}'}',
                    style: TextStyle(
                        fontSize: 11.5, color: pagado ? const Color(0xFF1E8E3E) : CC.muted, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            );
          }(),
          const SizedBox(height: 10),
          Row(
            children: [
              _btn(Icons.edit_outlined, 'Editar', () => _editar(p),
                  outline: true),
              const SizedBox(width: 8),
              _btn(Icons.draw_outlined, 'Firma', () => _firma(p),
                  outline: true),
              const SizedBox(width: 8),
              _btn(
                  Icons.description_outlined,
                  gen ? 'Generando…' : 'Contrato',
                  gen ? null : () => _contrato(p)),
              const SizedBox(width: 8),
              _btn(Icons.receipt_long_outlined, 'Pago',
                  () => _registrarPago(p),
                  outline: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _btn(IconData ic, String label, VoidCallback? onTap,
      {bool outline = false}) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ic, size: 16),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
    return Expanded(
      child: outline
          ? OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed),
                  padding: const EdgeInsets.symmetric(vertical: 8)),
              onPressed: onTap,
              child: child)
          : ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8)),
              onPressed: onTap,
              child: child),
    );
  }
}

// ADMIN: Nómina de administrativos (jul-2026). Personal con pago Quincenal
// o Mensual: pendientes del periodo actual, marcar pagado (con referencia y
// comprobante por correo), padrón editable e historial.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';

class PagosAdministrativosScreen extends StatefulWidget {
  const PagosAdministrativosScreen({super.key});

  @override
  State<PagosAdministrativosScreen> createState() =>
      _PagosAdministrativosScreenState();
}

class _PagosAdministrativosScreenState
    extends State<PagosAdministrativosScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _actor = '';
  bool _cargando = true;
  String _error = '';
  String _hoy = '';
  List<Map<String, dynamic>> _personal = [];
  List<Map<String, dynamic>> _historial = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    SessionStore.realEmail().then((c) {
      if (mounted) setState(() => _actor = (c ?? '').toString());
    });
    _cargar();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r1 = await http
          .get(Uri.parse('$guardianUrl?accion=nomina_admin_listar'))
          .timeout(const Duration(seconds: 45));
      final d1 = jsonDecode(r1.body) as Map<String, dynamic>;
      if (d1['ok'] != true) throw Exception(d1['error'] ?? 'Error');
      final r2 = await http
          .get(Uri.parse('$guardianUrl?accion=nomina_admin_historial'))
          .timeout(const Duration(seconds: 45));
      final d2 = jsonDecode(r2.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _hoy = (d1['hoy'] ?? '').toString();
        _personal = ((d1['personal'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _historial = ((d2['pagos'] as List?) ?? [])
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

  Future<Map<String, dynamic>> _get(String qs) async {
    final r = await http
        .get(Uri.parse('$guardianUrl?$qs'))
        .timeout(const Duration(seconds: 45));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _aviso(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? const Color(0xFF1E8E3E) : Colors.red,
      content: Text(msg),
    ));
  }

  Future<void> _marcarPagado(Map<String, dynamic> p) async {
    final refCtrl = TextEditingController();
    final montoCtrl =
        TextEditingController(text: (p['monto'] ?? 0).toString());
    final okDlg = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pagar a ${p['nombre']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Periodo: ${p['periodoActual']} · CLABE: ${p['clabe']}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: montoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Monto', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                  labelText: 'Referencia de la transferencia',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar pago')),
        ],
      ),
    );
    if (okDlg != true) return;
    final res = await _get('accion=nomina_admin_pagar'
        '&correo=${Uri.encodeComponent((p['correo'] ?? '').toString())}'
        '&monto=${Uri.encodeComponent(montoCtrl.text.trim())}'
        '&referencia=${Uri.encodeComponent(refCtrl.text.trim())}'
        '&actor=${Uri.encodeComponent(_actor)}');
    if (res['ok'] == true) {
      _aviso('Pago del periodo ${res['periodo']} registrado; '
          'se envió el comprobante por correo.');
      _cargar();
    } else {
      _aviso('${res['error']}', ok: false);
    }
  }

  Future<void> _editarPersona([Map<String, dynamic>? p]) async {
    final correo = TextEditingController(text: (p?['correo'] ?? '').toString());
    final nombre = TextEditingController(text: (p?['nombre'] ?? '').toString());
    final puesto = TextEditingController(text: (p?['puesto'] ?? '').toString());
    final clabe = TextEditingController(text: (p?['clabe'] ?? '').toString());
    final banco = TextEditingController(text: (p?['banco'] ?? '').toString());
    final monto =
        TextEditingController(text: p == null ? '' : (p['monto'] ?? 0).toString());
    var periodicidad = (p?['periodicidad'] ?? 'Quincenal').toString();
    final okDlg = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(p == null ? 'Alta de administrativo' : 'Editar datos'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: correo,
                    enabled: p == null,
                    decoration: const InputDecoration(
                        labelText: 'Correo', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: nombre,
                    decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: puesto,
                    decoration: const InputDecoration(
                        labelText: 'Puesto', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: clabe,
                    decoration: const InputDecoration(
                        labelText: 'CLABE interbancaria',
                        border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: banco,
                    decoration: const InputDecoration(
                        labelText: 'Banco', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: monto,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Monto por periodo',
                        border: OutlineInputBorder())),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: periodicidad,
                  items: const [
                    DropdownMenuItem(
                        value: 'Quincenal', child: Text('Quincenal')),
                    DropdownMenuItem(value: 'Mensual', child: Text('Mensual')),
                  ],
                  onChanged: (v) =>
                      setLocal(() => periodicidad = v ?? 'Quincenal'),
                  decoration: const InputDecoration(
                      labelText: 'Periodicidad', border: OutlineInputBorder()),
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
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (okDlg != true) return;
    final res = await _get('accion=nomina_admin_alta'
        '&correo=${Uri.encodeComponent(correo.text.trim())}'
        '&nombre=${Uri.encodeComponent(nombre.text.trim())}'
        '&puesto=${Uri.encodeComponent(puesto.text.trim())}'
        '&clabe=${Uri.encodeComponent(clabe.text.trim())}'
        '&banco=${Uri.encodeComponent(banco.text.trim())}'
        '&monto=${Uri.encodeComponent(monto.text.trim())}'
        '&periodicidad=${Uri.encodeComponent(periodicidad)}'
        '&actor=${Uri.encodeComponent(_actor)}');
    if (res['ok'] == true) {
      _aviso(p == null ? 'Administrativo dado de alta.' : 'Datos actualizados.');
      _cargar();
    } else {
      _aviso('${res['error']}', ok: false);
    }
  }

  Future<void> _baja(Map<String, dynamic> p) async {
    final okDlg = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Baja de la nómina'),
        content: Text('¿Dar de baja a ${p['nombre']}? Dejará de aparecer '
            'en pendientes (su historial se conserva).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Dar de baja')),
        ],
      ),
    );
    if (okDlg != true) return;
    final res = await _get('accion=nomina_admin_baja'
        '&correo=${Uri.encodeComponent((p['correo'] ?? '').toString())}'
        '&actor=${Uri.encodeComponent(_actor)}');
    if (res['ok'] == true) {
      _aviso('Baja registrada.');
      _cargar();
    } else {
      _aviso('${res['error']}', ok: false);
    }
  }

  Future<void> _misDatos() async {
    final correo = await SessionStore.realEmail();
    if (correo == null || correo.isEmpty) return;
    Map<String, dynamic> d = {};
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'nomina_admin_mis_datos',
            'correo': correo,
          }))
          .timeout(const Duration(seconds: 45));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      d = {'ok': false, 'error': 'error de conexión'};
    }
    if (!mounted) return;
    // (4-oct-2026) Antes, si la consulta fallaba se abría el formulario VACÍO y, al guardar, se podían borrar el banco y la
    // CLABE registrados. Ahora, si no se pudieron leer tus datos, no se abre.
    if (d['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed,
          content: Text('No se pudieron cargar tus datos (${d['error'] ?? 'intenta de nuevo'}). No se abrió el formulario para no perder lo registrado.')));
      return;
    }
    if (d['ok'] == true &&
        d['existe'] != true &&
        d['puedeCrear'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed,
          content: Text('${d['nota'] ?? 'Sin acceso al autoservicio.'}')));
      return;
    }
    final nombre =
        TextEditingController(text: (d['nombre'] ?? '').toString());
    final puesto =
        TextEditingController(text: (d['puesto'] ?? '').toString());
    final banco =
        TextEditingController(text: (d['banco'] ?? '').toString());
    final clabe =
        TextEditingController(text: (d['clabe'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mis datos de nómina'),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(correo,
                style: TextStyle(
                    fontSize: 12, color: cessumMuted(context))),
            const SizedBox(height: 10),
            TextField(
                controller: nombre,
                decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 8),
            TextField(
                controller: puesto,
                decoration: const InputDecoration(
                    labelText: 'Puesto',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 8),
            TextField(
                controller: banco,
                decoration: const InputDecoration(
                    labelText: 'Banco',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 8),
            TextField(
                controller: clabe,
                keyboardType: TextInputType.number,
                maxLength: 18,
                decoration: const InputDecoration(
                    labelText: 'CLABE interbancaria (18 dígitos)',
                    counterText: '',
                    border: OutlineInputBorder(),
                    isDense: true)),
            const SizedBox(height: 6),
            Text(
                'El monto y la periodicidad los define Dirección; aquí '
                'solo capturas tus datos personales y bancarios.',
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
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
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'nomina_admin_mis_datos_guardar',
                'correo': correo,
                'nombre': nombre.text.trim(),
                'puesto': puesto.text.trim(),
                'banco': banco.text.trim(),
                'clabe': clabe.text.trim(),
              }))
          .timeout(const Duration(seconds: 60));
      final res = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: res['ok'] == true
              ? const Color(0xFF1E8E3E)
              : cessumRed,
          content: Text(res['ok'] == true
              ? 'Tus datos quedaron guardados.'
              : '${res['error']}')));
      if (res['ok'] == true) _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes =
        _personal.where((p) => p['pendiente'] == true).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Pagos a administrativos',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: _misDatos,
            icon: const Icon(Icons.badge, size: 18),
            label: const Text('Mis datos'),
          ),
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Pendientes (${pendientes.length})'),
            Tab(text: 'Personal (${_personal.length})'),
            const Tab(text: 'Historial'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: () => _editarPersona(),
        icon: const Icon(Icons.person_add),
        label: const Text('Alta'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Text('Error: $_error'))
              : TabBarView(
                  controller: _tab,
                  children: [
                    _listaPendientes(pendientes),
                    _listaPersonal(),
                    _listaHistorial(),
                  ],
                ),
    );
  }

  Widget _listaPendientes(List<Map<String, dynamic>> pendientes) {
    if (pendientes.isEmpty) {
      return Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Sin pagos pendientes en el periodo actual. 🎉',
            style: TextStyle(color: cessumMuted(context))),
      ));
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('Hoy: $_hoy · el periodo se calcula solo '
            '(quincenal: Q1 días 1-15, Q2 del 16 al fin de mes).',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 10),
        for (final p in pendientes) _tarjetaPersona(p, pendiente: true),
      ],
    );
  }

  Widget _listaPersonal() {
    if (_personal.isEmpty) {
      return Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Aún no hay personal registrado. Usa el botón Alta.',
            style: TextStyle(color: cessumMuted(context))),
      ));
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [for (final p in _personal) _tarjetaPersona(p)],
    );
  }

  Widget _tarjetaPersona(Map<String, dynamic> p, {bool pendiente = false}) {
    final activo = p['activo'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: pendiente
                ? cessumGold.withValues(alpha: 0.6)
                : cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${p['nombre']}${activo ? '' : ' · BAJA'}',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: activo ? cessumInk(context) : cessumFaint(context)),
                ),
              ),
              Text('\$${(p['monto'] ?? 0)} · ${p['periodicidad']}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
          Text('${p['puesto']} · ${p['correo']}',
              style:
                  const TextStyle(fontSize: 11.5, color: Colors.black54)),
          Row(
            children: [
              Expanded(
                child: Text(
                    'CLABE: ${p['clabe']}'
                    '${(p['banco'] ?? '').toString().isNotEmpty ? ' · ${p['banco']}' : ''}',
                    style: TextStyle(
                        fontSize: 11.5, color: cessumInk(context))),
              ),
              IconButton(
                tooltip: 'Copiar CLABE',
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: (p['clabe'] ?? '').toString()));
                  _aviso('CLABE copiada.');
                },
              ),
            ],
          ),
          Text(
            'Periodo ${p['periodoActual']}: '
            '${p['pagadoPeriodo'] == true ? 'PAGADO' : 'pendiente'}',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: p['pagadoPeriodo'] == true
                    ? const Color(0xFF1E8E3E)
                    : cessumGold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (pendiente || (activo && p['pagadoPeriodo'] != true))
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8E3E),
                        foregroundColor: Colors.white),
                    onPressed: () => _marcarPagado(p),
                    icon: const Icon(Icons.payments, size: 18),
                    label: const Text('Marcar pagado'),
                  ),
                ),
              if (pendiente || (activo && p['pagadoPeriodo'] != true))
                const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _editarPersona(p),
                child: const Text('Editar'),
              ),
              const SizedBox(width: 8),
              if (activo)
                IconButton(
                  tooltip: 'Dar de baja',
                  icon: const Icon(Icons.person_off,
                      color: cessumRed, size: 20),
                  onPressed: () => _baja(p),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listaHistorial() {
    if (_historial.isEmpty) {
      return Center(
          child: Text('Aún no hay pagos registrados.',
              style: TextStyle(color: cessumMuted(context))));
    }
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        for (final h in _historial)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${h['nombre']} · ${h['periodo']}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(
                          '${h['fecha']}'
                          '${(h['referencia'] ?? '').toString().isNotEmpty ? ' · Ref: ${h['referencia']}' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, color: cessumMuted(context))),
                    ],
                  ),
                ),
                Text('\$${h['monto']}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

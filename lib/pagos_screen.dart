import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'foto_web_picker.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Registro de PAGOS (base central): registrar, consultar, filtrar por tipo
/// (incluye reinscripciones), verificar y corregir. Escribe en la hoja "Pagos".
class PagosScreen extends StatefulWidget {
  const PagosScreen({super.key});

  @override
  State<PagosScreen> createState() => _PagosScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);
const List<String> _tiposPago = [
  'Inscripción',
  'Reinscripción',
  'Colegiatura',
  'Trámite',
  'Otro',
];
const List<String> _metodos = [
  'Depósito BBVA',
  'Transferencia',
  'Efectivo',
  'Otro',
];

class _Pago {
  final int fila;
  final String fecha;
  String nombre;
  String matricula;
  String correo;
  String programa;
  String generacion;
  String tipoPago;
  String concepto;
  String monto;
  String metodo;
  String referencia;
  String comprobante;
  String estatus;
  String registradoPor;
  String notas;

  _Pago.fromMap(Map<String, dynamic> m)
      : fila = int.tryParse('${m['fila']}') ?? 0,
        fecha = (m['fecha'] ?? '').toString(),
        nombre = (m['nombre'] ?? '').toString(),
        matricula = (m['matricula'] ?? '').toString(),
        correo = (m['correo'] ?? '').toString(),
        programa = (m['programa'] ?? '').toString(),
        generacion = (m['generacion'] ?? '').toString(),
        tipoPago = (m['tipoPago'] ?? '').toString(),
        concepto = (m['concepto'] ?? '').toString(),
        monto = (m['monto'] ?? '').toString(),
        metodo = (m['metodo'] ?? '').toString(),
        referencia = (m['referencia'] ?? '').toString(),
        comprobante = (m['comprobante'] ?? '').toString(),
        estatus = (m['estatus'] ?? '').toString(),
        registradoPor = (m['registradoPor'] ?? '').toString(),
        notas = (m['notas'] ?? '').toString();
}

class _PagosScreenState extends State<PagosScreen> {
  final TextEditingController _busqueda = TextEditingController();
  bool _cargando = true;
  bool _ocupado = false;
  String? _error;
  List<_Pago> _items = [];
  String _tipoFiltro = 'Todos';

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

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final params = {'accion': 'pagos_listar'};
      final q = _busqueda.text.trim();
      if (q.isNotEmpty) params['q'] = q;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final lista = (data['pagos'] as List<dynamic>? ?? [])
          .map((e) => _Pago.fromMap(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _items = lista;
          _cargando = false;
        });
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

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final resp = await http
        .post(
          Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 90));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true || data.containsKey('guardadas')) {
      throw Exception(data['error'] ??
          'El Guardián todavía no tiene las funciones de pagos. Sube el '
              'Code.gs y publica una versión nueva.');
    }
    return data;
  }

  List<_Pago> get _filtrados {
    if (_tipoFiltro == 'Todos') return _items;
    return _items.where((p) => p.tipoPago == _tipoFiltro).toList();
  }

  double get _suma {
    double t = 0;
    for (final p in _filtrados) {
      final n = double.tryParse(
          p.monto.replaceAll(RegExp(r'[^0-9.]'), '').trim());
      if (n != null) t += n;
    }
    return t;
  }

  Future<void> _registrar({_Pago? base}) async {
    final nombre = TextEditingController(text: base?.nombre ?? '');
    final matricula = TextEditingController(text: base?.matricula ?? '');
    final correo = TextEditingController(text: base?.correo ?? '');
    final programa = TextEditingController(text: base?.programa ?? '');
    final generacion = TextEditingController(text: base?.generacion ?? '');
    final concepto = TextEditingController(text: base?.concepto ?? '');
    final monto = TextEditingController(text: base?.monto ?? '');
    final referencia = TextEditingController(text: base?.referencia ?? '');
    final notas = TextEditingController(text: base?.notas ?? '');
    String tipo = _tiposPago.contains(base?.tipoPago)
        ? base!.tipoPago
        : _tiposPago.first;
    String metodo =
        _metodos.contains(base?.metodo) ? base!.metodo : _metodos.first;
    String estatus = base?.estatus.isNotEmpty == true ? base!.estatus : 'Registrado';
    FotoElegida? comprobante;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget campo(TextEditingController c, String etq,
              {TextInputType? tipoT}) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: c,
                keyboardType: tipoT,
                decoration: InputDecoration(
                    labelText: etq,
                    border: const OutlineInputBorder(),
                    isDense: true),
              ),
            );
          }

          return AlertDialog(
            title: Text(base == null ? 'Registrar pago' : 'Editar pago'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  campo(nombre, 'Nombre'),
                  campo(matricula, 'Matrícula', tipoT: TextInputType.number),
                  campo(correo, 'Correo'),
                  campo(programa, 'Programa'),
                  campo(generacion, 'Generación'),
                  DropdownButtonFormField<String>(
                    value: tipo,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Tipo de pago', isDense: true),
                    items: _tiposPago
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setLocal(() => tipo = v ?? tipo),
                  ),
                  const SizedBox(height: 8),
                  campo(concepto, 'Concepto / detalle'),
                  campo(monto, 'Monto (MXN)',
                      tipoT: TextInputType.number),
                  DropdownButtonFormField<String>(
                    value: metodo,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Método', isDense: true),
                    items: _metodos
                        .map((t) =>
                            DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setLocal(() => metodo = v ?? metodo),
                  ),
                  const SizedBox(height: 8),
                  campo(referencia, 'Referencia / folio'),
                  DropdownButtonFormField<String>(
                    value: estatus,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Estatus', isDense: true),
                    items: const [
                      DropdownMenuItem(
                          value: 'Registrado', child: Text('Registrado')),
                      DropdownMenuItem(
                          value: 'Verificado', child: Text('Verificado')),
                    ],
                    onChanged: (v) => setLocal(() => estatus = v ?? estatus),
                  ),
                  const SizedBox(height: 8),
                  campo(notas, 'Notas'),
                  if (base == null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            comprobante != null
                                ? 'Comprobante adjuntado'
                                : 'Comprobante (opcional)',
                            style: TextStyle(
                                fontSize: 12, color: cessumMuted(context)),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final f = await seleccionarFoto();
                            if (f != null) setLocal(() => comprobante = f);
                          },
                          child: Text(comprobante != null
                              ? 'Cambiar'
                              : 'Adjuntar'),
                        ),
                      ],
                    ),
                  ],
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
                  if (matricula.text.trim().isEmpty ||
                      monto.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                        content:
                            Text('La matrícula y el monto son obligatorios.')));
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(base == null ? 'Registrar' : 'Guardar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    try {
      final quien = await SessionStore.realEmail();
      if (base == null) {
        final payload = <String, dynamic>{
          'accion': 'pago_registrar',
          'nombre': nombre.text.trim(),
          'matricula': matricula.text.trim(),
          'correo': correo.text.trim(),
          'programa': programa.text.trim(),
          'generacion': generacion.text.trim(),
          'tipoPago': tipo,
          'concepto': concepto.text.trim(),
          'monto': monto.text.trim(),
          'metodo': metodo,
          'referencia': referencia.text.trim(),
          'estatus': estatus,
          'notas': notas.text.trim(),
          'registradoPor': quien ?? 'Administración',
        };
        if (comprobante != null) {
          payload['comprobanteBase64'] = base64Encode(comprobante!.bytes);
          payload['comprobanteMime'] = comprobante!.mime;
        }
        await _post(payload);
        _aviso('Pago registrado.');
      } else {
        await _post({
          'accion': 'pago_actualizar',
          'fila': base.fila,
          'tipoPago': tipo,
          'concepto': concepto.text.trim(),
          'monto': monto.text.trim(),
          'metodo': metodo,
          'referencia': referencia.text.trim(),
          'estatus': estatus,
          'notas': notas.text.trim(),
        });
        _aviso('Pago actualizado.');
      }
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _ocupado = false);
      _aviso('No se pudo guardar: $e');
      return;
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _borrar(_Pago p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar pago'),
        content: Text('¿Borrar el pago de ${p.nombre} (${p.monto})?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    try {
      await _post({'accion': 'pago_actualizar', 'fila': p.fila, 'borrar': true});
      _aviso('Pago borrado.');
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _ocupado = false);
      _aviso('No se pudo borrar: $e');
    }
  }

  Future<void> _abrir(String url) async {
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el comprobante.');
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
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Registro de pagos'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _ocupado ? null : _cargar),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _ocupado ? null : () => _registrar(),
        icon: const Icon(Icons.add),
        label: const Text('Registrar pago'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _busqueda,
                    onSubmitted: (_) => _cargar(),
                    decoration: InputDecoration(
                      hintText: 'Buscar por matrícula o nombre',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _cargando ? null : _cargar,
                    child: const Text('Buscar'),
                  ),
                ),
              ],
            ),
          ),
          _chips(),
          if (_ocupado) const LinearProgressIndicator(color: cessumRed),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? _vistaError()
                    : _filtrados.isEmpty
                        ? _vistaVacia()
                        : RefreshIndicator(
                            color: cessumRed,
                            onRefresh: _cargar,
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 90),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 8, left: 2),
                                  child: Text(
                                    '${_filtrados.length} pago(s) · Total: \$${_suma.toStringAsFixed(2)} MXN',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: cessumMuted(context)),
                                  ),
                                ),
                                ..._filtrados.map(_tarjeta),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    final tipos = ['Todos', ..._tiposPago];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        children: tipos.map((t) {
          final sel = _tipoFiltro == t;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(t),
              selected: sel,
              selectedColor: cessumRed,
              labelStyle: TextStyle(
                  color: sel ? Colors.white : cessumInk(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              onSelected: (_) => setState(() => _tipoFiltro = t),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _tarjeta(_Pago p) {
    final verificado = p.estatus == 'Verificado';
    final esReins = p.tipoPago.toLowerCase().contains('reinscrip');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.nombre.isEmpty ? '(sin nombre)' : p.nombre,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              Text('\$${p.monto}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: cessumRed)),
            ],
          ),
          Text('Matrícula: ${p.matricula}  ·  ${p.fecha}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _chip(p.tipoPago,
                  esReins ? const Color(0xFF6A1B9A) : cessumGold),
              _chip(p.estatus.isEmpty ? 'Registrado' : p.estatus,
                  verificado ? _verdeOk : cessumFaint(context)),
              if (p.metodo.isNotEmpty)
                Text(p.metodo,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
          if (p.concepto.isNotEmpty) _linea('Concepto', p.concepto),
          if (p.referencia.isNotEmpty) _linea('Referencia', p.referencia),
          if (p.programa.isNotEmpty) _linea('Programa', p.programa),
          if (p.notas.isNotEmpty) _linea('Notas', p.notas),
          const Divider(height: 18),
          Row(
            children: [
              if (p.comprobante.isNotEmpty && p.comprobante.startsWith('http'))
                TextButton.icon(
                  onPressed: () => _abrir(p.comprobante),
                  icon: const Icon(Icons.receipt_long,
                      size: 16, color: cessumRed),
                  label: const Text('Comprobante',
                      style: TextStyle(color: cessumRed, fontSize: 12)),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit, size: 19, color: cessumGold),
                tooltip: 'Editar',
                onPressed: () => _registrar(base: p),
              ),
              IconButton(
                icon:
                    const Icon(Icons.delete_outline, size: 19, color: cessumRed),
                tooltip: 'Borrar',
                onPressed: () => _borrar(p),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String txt, Color c) {
    if (txt.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Widget _linea(String etq, String valor) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.payments_outlined, color: cessumFaint(context), size: 52),
            SizedBox(height: 12),
            Text('No hay pagos registrados con este filtro.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
          ],
        ),
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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: triage de aspirantes leídos de los Forms de inscripción.
/// Semáforo: sin_matricula (rojo) > codigo_sin_validar (naranja) >
/// pago_sin_verificar (amarillo) > listo (verde). Permite marcar la revisión
/// (pago / cuenta / código) de cada aspirante.
class AspirantesPendientesScreen extends StatefulWidget {
  const AspirantesPendientesScreen({super.key});

  @override
  State<AspirantesPendientesScreen> createState() =>
      _AspirantesPendientesScreenState();
}

class _AspirantesPendientesScreenState
    extends State<AspirantesPendientesScreen> {
  static const Color _cOrange = Color(0xFFE08600);
  static const Color _cAmber = Color(0xFFC79A00);
  static const Color _cGreen = Color(0xFF1E8E3E);

  final _busca = TextEditingController();

  bool _cargando = true;
  String? _accionClave; // clave en proceso de marcado
  String? _filtroEstado; // null = todos
  List<Map<String, dynamic>> _lista = [];
  Map<String, dynamic> _conteos = {};
  List<Map<String, dynamic>> _forms = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : null));
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'aspirantes_pendientes',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _lista = ((data['aspirantes'] as List<dynamic>? ?? []))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _conteos = Map<String, dynamic>.from(data['conteos'] as Map? ?? {});
        _forms = ((data['forms'] as List<dynamic>? ?? []))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _aviso('${data['error'] ?? 'No se pudo cargar.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _marcar(
      Map<String, dynamic> a, String campo, bool valor) async {
    final clave = (a['clave'] ?? '').toString();
    setState(() => _accionClave = clave);
    try {
      final actor = await _actor();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'aspirante_revisar',
                'actor': actor,
                'clave': clave,
                'correo': a['correo'] ?? '',
                'nombre': a['nombre'] ?? '',
                'programa': a['programa'] ?? '',
                campo: valor,
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        await _cargar();
      } else {
        _aviso('${data['error'] ?? 'No se pudo guardar.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    } finally {
      if (mounted) setState(() => _accionClave = null);
    }
  }

  Future<void> _abrirComprobante(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el enlace.', error: true);
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'sin_matricula':
        return cessumRed;
      case 'codigo_sin_validar':
        return _cOrange;
      case 'pago_sin_verificar':
        return _cAmber;
      case 'listo':
        return _cGreen;
      default:
        return cessumFaint(context);
    }
  }

  String _labelEstado(String estado) {
    switch (estado) {
      case 'sin_matricula':
        return 'Sin matrícula';
      case 'codigo_sin_validar':
        return 'Código sin validar';
      case 'pago_sin_verificar':
        return 'Pago sin verificar';
      case 'listo':
        return 'Listo';
      default:
        return estado;
    }
  }

  int _cont(String k) => (_conteos[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final q = _busca.text.trim().toLowerCase();
    final visibles = _lista.where((a) {
      if (_filtroEstado != null && '${a['estado']}' != _filtroEstado) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = '${a['nombre']} ${a['correo']} ${a['matricula']}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();

    final formsConError =
        _forms.where((f) => (f['error'] ?? '').toString().isNotEmpty).toList();

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Aspirantes'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          // Tablero de semáforo
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Todos', _cont('total'), cessumMuted(context), null),
                _chip('Sin matrícula', _cont('sin_matricula'), cessumRed,
                    'sin_matricula'),
                _chip('Código', _cont('codigo_sin_validar'), _cOrange,
                    'codigo_sin_validar'),
                _chip('Pago', _cont('pago_sin_verificar'), _cAmber,
                    'pago_sin_verificar'),
                _chip('Listos', _cont('listo'), _cGreen, 'listo'),
              ],
            ),
          ),
          // Buscador
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _busca,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, correo o matrícula',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: _busca.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _busca.clear()),
                      ),
              ),
            ),
          ),
          if (formsConError.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
              ),
              child: Text(
                'No se pudo leer: '
                '${formsConError.map((f) => f['etiqueta'] ?? f['id']).join(', ')}. '
                'Revisa que la cuenta del Guardián tenga acceso a esas hojas.',
                style: const TextStyle(fontSize: 12, color: cessumRed),
              ),
            ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator(color: cessumRed))
                : visibles.isEmpty
                    ? Center(
                        child: Text('Sin aspirantes para este filtro.',
                            style: TextStyle(color: cessumMuted(context))))
                    : RefreshIndicator(
                        onRefresh: _cargar,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: visibles.length,
                          itemBuilder: (_, i) => _item(visibles[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int n, Color color, String? estado) {
    final sel = _filtroEstado == estado;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _filtroEstado = sel ? null : estado),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text('$label · $n',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : color)),
      ),
    );
  }

  Widget _item(Map<String, dynamic> a) {
    final estado = (a['estado'] ?? '').toString();
    final color = _colorEstado(estado);
    final clave = (a['clave'] ?? '').toString();
    final enProceso = _accionClave == clave;
    final codigoPresente = a['codigoPresente'] == true;
    final codigoValidado = a['codigoValidado'] == true;
    final codigoInfo = (a['codigoInfo'] ?? '').toString();
    final comprobante = (a['comprobante'] ?? '').toString();
    final matricula = (a['matricula'] ?? '').toString();
    final programa = (a['programa'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 4)),
        boxShadow: const [
          BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    (a['nombre'] ?? '').toString().isNotEmpty
                        ? (a['nombre']).toString()
                        : (a['correo'] ?? '(sin nombre)').toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_labelEstado(estado),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if ((a['correo'] ?? '').toString().isNotEmpty)
            Text((a['correo']).toString(),
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          Text(
              [
                if (programa.isNotEmpty) programa,
                'Gen. ${a['generacion']}',
                if ((a['fecha'] ?? '').toString().isNotEmpty) '${a['fecha']}',
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (matricula.isNotEmpty)
            Text('Matrícula: $matricula',
                style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (codigoPresente)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(codigoValidado ? Icons.check_circle : Icons.error,
                      size: 14,
                      color: codigoValidado ? _cGreen : _cOrange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        'Código: ${a['codigo']}'
                        '${codigoValidado ? ' (válido)' : ' (sin validar)'}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: codigoValidado ? _cGreen : _cOrange,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          if (codigoInfo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 18),
              child: Text(codigoInfo,
                  style: TextStyle(
                      fontSize: 11,
                      color: codigoValidado ? _cGreen : cessumMuted(context),
                      fontStyle: FontStyle.italic)),
            ),
          const SizedBox(height: 8),
          // Acciones de revisión
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (comprobante.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _abrirComprobante(comprobante),
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text('Comprobante'),
                ),
              _toggle('Pago', a['revPago'] == true,
                  enProceso, () => _marcar(a, 'pagoVerificado', !(a['revPago'] == true))),
              _toggle('Cuenta', a['revCuenta'] == true,
                  enProceso, () => _marcar(a, 'cuentaCreada', !(a['revCuenta'] == true))),
              if (codigoPresente)
                _toggle('Código', a['revCodigo'] == true,
                    enProceso, () => _marcar(a, 'codigoValidado', !(a['revCodigo'] == true))),
              if (enProceso)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cessumRed)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool on, bool disabled, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? _cGreen.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: on ? _cGreen : cessumFaint(context), width: on ? 1.2 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14, color: on ? _cGreen : cessumFaint(context)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: on ? _cGreen : cessumMuted(context))),
          ],
        ),
      ),
    );
  }
}

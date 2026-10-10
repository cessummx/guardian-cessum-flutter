import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'foto_web_picker.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

const Color _verdeOk = Color(0xFF1E8E3E);

class PagosDocentesScreen extends StatefulWidget {
  const PagosDocentesScreen({super.key});

  @override
  State<PagosDocentesScreen> createState() => _PagosDocentesScreenState();
}

class _PagosDocentesScreenState extends State<PagosDocentesScreen> {
  bool _cargandoPend = false;
  bool _cargandoHist = false;
  List<Map<String, dynamic>> _pendientes = [];
  List<Map<String, dynamic>> _historial = [];
  // Vacío = TODOS los programas. Si el usuario escribe un programa y busca,
  // se filtra solo por ese.
  String _programa = '';
  String _actor = '';

  // Controlador persistente del campo "Programa" para que el botón Buscar
  // lea siempre lo que está escrito.
  final TextEditingController _progCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    SessionStore.realEmail().then((c) => _actor = c ?? '');
    _cargarPendientes();
  }

  @override
  void dispose() {
    _progCtrl.dispose();
    super.dispose();
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t),
      backgroundColor: error ? cessumRed : _verdeOk,
    ));
  }

  // Descartar un pendiente basura: no se pagará y deja de aparecer.
  Future<void> _descartarPendiente(Map p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar pendiente'),
        content: Text(
          '¿Descartar este pago pendiente?\n\n'
          '${p['materia']}\n${p['docente']} · ${p['generacion']} · ${p['grupo']}\n\n'
          'Dejará de aparecer en la lista y NO se pagará. '
          'Queda registrado en la bitácora quién lo descartó.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _cargandoPend = true);
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'pago_prof_descartar',
              'clave': p['clave'],
              'docente': p['docente'],
              'materia': p['materia'],
              'grupo': p['grupo'],
              'actor': _actor.isNotEmpty ? _actor : 'Administración',
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo descartar.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF1E8E3E),
          content: Text('Pendiente descartado.'),
        ));
      }
      await _cargarPendientes();
    } catch (e) {
      if (mounted) {
        setState(() => _cargandoPend = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('No se pudo descartar: $e'),
        ));
      }
    }
  }

  Future<void> _cargarPendientes() async {
    setState(() => _cargandoPend = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pagos_prof_pendientes',
        if (_programa.isNotEmpty) 'programa': _programa,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _pendientes = ((data['pendientes'] ?? []) as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
      } else {
        _aviso(data['error']?.toString() ?? 'No se pudo cargar.', error: true);
      }
    } catch (e) {
      _aviso('Error de conexión: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargandoPend = false);
    }
  }

  Future<void> _cargarHistorial() async {
    setState(() => _cargandoHist = true);
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'pagos_prof_historial'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _historial = ((data['historial'] ?? []) as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
      } else {
        _aviso(data['error']?.toString() ?? 'No se pudo cargar.', error: true);
      }
    } catch (e) {
      _aviso('Error de conexión: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargandoHist = false);
    }
  }

  Future<void> _registrarPago(Map<String, dynamic> p) async {
    final montoCtrl = TextEditingController(
        text: (p['montoSugerido'] ?? '').toString());
    final etiquetaParte = (p['etiquetaParte'] ?? '').toString();
    final conceptoCtrl = TextEditingController(text: 'Pago de asignatura');
    DocElegido? comprobante;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Registrar pago'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['materia']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: cessumRed)),
                Text('${p['docente']} · ${p['correoDocente']}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
                // (jul-2026) Contrato de la materia + datos bancarios del
                // docente (CLABE que él mismo capturó), jalados del módulo
                // de contratos para pagar sin brincar de pantalla.
                if (((p['contrato']?['estatus']) ?? '').toString() !=
                    'Validado') ...[
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: cessumRed.withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'AÚN NO PROCEDE EL PAGO: falta que el docente firme su '
                      'contrato (lo hace en app.cessum.mx → Mi contrato, donde '
                      'también captura su CLABE).',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cessumRed),
                    ),
                  ),
                ],
                if (p['contrato'] != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(
                      (p['contrato']?['estatus'] ?? '') == 'Validado'
                          ? Icons.verified
                          : Icons.hourglass_bottom,
                      size: 15,
                      color: (p['contrato']?['estatus'] ?? '') == 'Validado'
                          ? const Color(0xFF1E8E3E)
                          : cessumGold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Contrato: ${(p['contrato']?['estatus'] ?? '').toString().isEmpty ? 'Pendiente' : p['contrato']?['estatus']}',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    if (((p['contrato']?['pdfUrl']) ?? '')
                        .toString()
                        .isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 26)),
                        onPressed: () => Helpers.abrirUrlExterna(
                            p['contrato']!['pdfUrl'].toString(), context),
                        child: const Text('Ver contrato',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                  ]),
                ] else ...[
                  const SizedBox(height: 4),
                  const Text('Contrato: sin registro para esta materia',
                      style:
                          TextStyle(fontSize: 11.5, color: cessumGold)),
                ],
                if (p['banco'] != null &&
                    ((p['banco']?['clabe']) ?? '')
                        .toString()
                        .isNotEmpty) ...[
                  Row(children: [
                    Expanded(
                      child: Text(
                        'CLABE: ${p['banco']?['clabe']}'
                        '${((p['banco']?['banco']) ?? '').toString().isNotEmpty ? ' · ${p['banco']?['banco']}' : ''}'
                        '${((p['banco']?['titular']) ?? '').toString().isNotEmpty ? ' · ${p['banco']?['titular']}' : ''}',
                        style: TextStyle(
                            fontSize: 11.5, color: cessumInk(context)),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copiar CLABE',
                      icon: const Icon(Icons.copy, size: 15),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: p['banco']!['clabe'].toString()));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('CLABE copiada.')));
                      },
                    ),
                  ]),
                ] else ...[
                  const Text(
                      'Sin CLABE registrada (el docente la captura en Mi contrato).',
                      style:
                          TextStyle(fontSize: 11.5, color: cessumGold)),
                ],
                if (etiquetaParte.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(etiquetaParte,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cessumGold)),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: montoCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Monto (MXN)',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: conceptoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Concepto (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d =
                              await seleccionarDocumento(tipo: 'imagen');
                          if (d != null) setLocal(() => comprobante = d);
                        },
                        icon: const Icon(Icons.photo_library, size: 18),
                        label: const Text('Foto'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cessumGold,
                          side: const BorderSide(color: cessumGold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await seleccionarDocumento(tipo: 'pdf');
                          if (d != null) setLocal(() => comprobante = d);
                        },
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        label: const Text('PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cessumGold,
                          side: const BorderSide(color: cessumGold),
                        ),
                      ),
                    ),
                  ],
                ),
                if (comprobante != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: _verdeOk),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Adjuntado: ${comprobante!.nombre}',
                            style: const TextStyle(
                                fontSize: 12, color: _verdeOk),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Se enviará un correo al profesor avisándole del pago, con el '
                  'comprobante y un mensaje de agradecimiento.',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            // (jul-2026) REGLA institucional: procede el pago solo con acta
            // validada Y contrato firmado (Validado). Sin contrato, el botón
            // se apaga y el diálogo lo dice claro.
            Builder(builder: (ctx2) {
              final contratoOk =
                  ((p['contrato']?['estatus']) ?? '').toString() == 'Validado';
              return ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _verdeOk,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    disabledForegroundColor: Colors.white70),
                onPressed: !contratoOk
                    ? null
                    : () {
                        final m = double.tryParse(montoCtrl.text.trim());
                        if (m == null || m <= 0) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                  content: Text('Indica un monto válido.'),
                                  backgroundColor: cessumRed));
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                icon: Icon(contratoOk ? Icons.verified : Icons.lock,
                    size: 18),
                label: Text(contratoOk
                    ? 'Confirmar pago'
                    : 'Falta el contrato firmado'),
              );
            }),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final monto = double.tryParse(montoCtrl.text.trim()) ?? 0;
    if (monto <= 0) return;

    if (comprobante == null) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sin comprobante'),
          content: const Text(
              'No adjuntaste el comprobante de depósito. ¿Registrar el pago de todas formas?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Registrar')),
          ],
        ),
      );
      if (seguir != true) return;
    }

    setState(() => _cargandoPend = true);
    try {
      final payload = <String, dynamic>{
        'accion': 'pagar_profesor',
        'correoDocente': p['correoDocente'],
        'docente': p['docente'],
        'programa': p['programa'],
        'generacion': p['generacion'],
        'grupo': p['grupo'],
        'materia': p['materia'],
        'claveMateria': p['claveMateria'],
        'ciclo': p['ciclo'],
        'terminoLegible': p['terminoLegible'] ?? p['termino'],
        'monto': monto,
        'parte': p['parte'] ?? '',
        'concepto': conceptoCtrl.text.trim(),
        'actor': _actor.isNotEmpty ? _actor : 'Administración',
      };
      if (comprobante != null) {
        payload['depositoBase64'] = base64Encode(comprobante!.bytes);
        payload['depositoMime'] = comprobante!.mime;
      }
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso(data['error']?.toString() ?? 'No se pudo registrar el pago.',
            error: true);
        return;
      }
      _pendientes.remove(p);
      _aviso(
          'Pago registrado (folio ${data['folio']}, ${data['montoFmt'] ?? ''}). Se avisó al profesor.');
      final pdf = (data['comprobantePagoUrl'] ?? '').toString();
      if (pdf.startsWith('http') && mounted) {
        await Helpers.abrirUrlExterna(pdf, context);
      }
    } catch (e) {
      _aviso('Error de conexión: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargandoPend = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Pagos a docentes'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Histórico'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tabPendientes(),
            _tabHistorial(),
          ],
        ),
      ),
    );
  }

  Widget _tabPendientes() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _progCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Programa (opcional)',
                    hintText: 'Vacío = todos los programas',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    _programa = v.trim();
                    _cargarPendientes();
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () {
                  _programa = _progCtrl.text.trim();
                  _cargarPendientes();
                },
                child: const Text('Buscar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cargandoPend
              ? const Center(child: CircularProgressIndicator())
              : _pendientes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No hay asignaturas pendientes de pago con esos criterios.\n'
                          'Aparecen aquí cuando su acta queda validada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cessumMuted(context)),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargarPendientes,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: _pendientes.length,
                        itemBuilder: (_, i) => _cardPend(_pendientes[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _cardPend(Map<String, dynamic> p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${p['materia']}',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cessumRed)),
              ),
              Builder(builder: (_) {
                final actaOk = p['actaValidada'] == true;
                final color = actaOk ? _verdeOk : cessumGold;
                final texto = actaOk ? 'acta validada' : 'semana 5';
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(texto,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: color)),
                );
              }),
              IconButton(
                tooltip: 'Descartar (no se pagará)',
                icon: const Icon(Icons.close, size: 18, color: cessumRed),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _descartarPendiente(p),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _linea('Docente', '${p['docente']} · ${p['correoDocente']}'),
          _linea('Programa', '${p['programa']}'),
          _linea('Generación / Grupo', '${p['generacion']} · ${p['grupo']}'),
          _linea('Clave', '${p['claveMateria'] ?? '—'}'),
          if ((p['etiquetaParte'] ?? '').toString().isNotEmpty &&
              (p['etiquetaParte']).toString() != 'Pago único (al validar acta)')
            _linea('Parte', '${p['etiquetaParte']}'),
          _linea('Monto sugerido', '\$${p['montoSugerido'] ?? '—'}'),
          _linea(
            p['actaValidada'] == true ? 'Terminó' : 'Semana 5',
            p['actaValidada'] == true
                ? '${p['terminoLegible'] ?? p['termino']} (hace ${p['diasDesde']} días)'
                : '${p['fechaReferencia'] ?? ''} (hace ${p['diasDesde']} días)',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumGold, foregroundColor: Colors.white),
              onPressed: () => _registrarPago(p),
              icon: const Icon(Icons.payments, size: 18),
              label: const Text('Registrar pago'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabHistorial() {
    if (_historial.isEmpty && !_cargandoHist) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _historial.isEmpty) _cargarHistorial();
      });
    }
    return _cargandoHist
        ? const Center(child: CircularProgressIndicator())
        : _historial.isEmpty
            ? Center(
                child: Text('Aún no hay pagos registrados.',
                    style: TextStyle(color: cessumMuted(context))))
            : RefreshIndicator(
                onRefresh: _cargarHistorial,
                child: ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _historial.length,
                  itemBuilder: (_, i) => _cardHist(_historial[i]),
                ),
              );
  }

  Future<void> _eliminarPago(Map<String, dynamic> r) async {
    final folio = (r['folio'] ?? '').toString();
    if (folio.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar pago'),
        content: Text(
            '¿Eliminar el pago de "${r['materia']}" (folio $folio)?\n\n'
            'Saldrá del histórico. Si era el único pago de esa materia, '
            'volverá a aparecer en Pendientes.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: cessumRed))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _cargandoHist = true);
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'eliminar_pago_profesor',
              'folio': folio,
              'actor': _actor.isNotEmpty ? _actor : 'Administración',
            }),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso(data['error']?.toString() ?? 'No se pudo eliminar el pago.',
            error: true);
        return;
      }
      _historial.remove(r);
      _aviso('Pago eliminado (folio $folio).');
      _cargarHistorial();
      _cargarPendientes();
    } catch (e) {
      _aviso('Error de conexión: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargandoHist = false);
    }
  }

  /// (4-oct-2026) Adjuntar el comprobante de depósito a un pago que se registró sin él. Venía solo en la pantalla
  /// duplicada «Pagos a profesores»; al unificarlas, se trae aquí para no perderlo.
  Future<void> _adjuntarDeposito(String folio) async {
    if (folio.isEmpty) return;
    final doc = await seleccionarDocumento();
    if (doc == null || !mounted) return;
    setState(() => _cargandoHist = true);
    try {
      final email = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'pago_prof_comprobante',
                'actor': email,
                'folio': folio,
                'depositoBase64': base64Encode(doc.bytes),
                'depositoMime': doc.mime,
              }))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _aviso('Depósito adjuntado al folio $folio.');
        await _cargarHistorial();
      } else {
        _aviso('${data['error'] ?? 'No se pudo adjuntar.'}', error: true);
      }
    } catch (e) {
      _aviso('Error de conexión: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargandoHist = false);
    }
  }

  Widget _cardHist(Map<String, dynamic> r) {
    final pago = (r['comprobantePagoUrl'] ?? '').toString();
    final dep = (r['comprobanteDepositoUrl'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${r['materia']}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cessumRed)),
              ),
              Text('${r['montoFmt'] ?? ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: _verdeOk)),
            ],
          ),
          const SizedBox(height: 2),
          Text('${r['docente']} · ${r['correoDocente']}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          Text('${r['programa']} · Gen ${r['generacion']} · Grupo ${r['grupo']}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          Text('${r['fecha']} · Folio ${r['folio']}',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (pago.startsWith('http') || dep.startsWith('http') || '${r['folio'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (!dep.startsWith('http') && '${r['folio'] ?? ''}'.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _cargandoHist ? null : () => _adjuntarDeposito('${r['folio']}'),
                    icon: const Icon(Icons.upload_file, size: 15, color: cessumGold),
                    label: const Text('Adjuntar depósito', style: TextStyle(color: cessumGold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cessumGold),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (pago.startsWith('http'))
                  OutlinedButton.icon(
                    onPressed: () => Helpers.abrirUrlExterna(pago, context),
                    icon: const Icon(Icons.picture_as_pdf,
                        size: 15, color: cessumRed),
                    label: const Text('Comprobante de pago',
                        style: TextStyle(color: cessumRed, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cessumRed),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (dep.startsWith('http'))
                  OutlinedButton.icon(
                    onPressed: () => Helpers.abrirUrlExterna(dep, context),
                    icon: const Icon(Icons.receipt_long,
                        size: 15, color: cessumGold),
                    label: const Text('Depósito',
                        style: TextStyle(color: cessumGold, fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: cessumGold),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _eliminarPago(r),
              icon: const Icon(Icons.delete_outline,
                  size: 16, color: cessumRed),
              label: const Text('Eliminar pago',
                  style: TextStyle(color: cessumRed, fontSize: 12)),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linea(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
          children: [
            TextSpan(
                text: '$k: ',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: cessumGold)),
            TextSpan(text: v, style: TextStyle(color: cessumInk(context))),
          ],
        ),
      ),
    );
  }
}

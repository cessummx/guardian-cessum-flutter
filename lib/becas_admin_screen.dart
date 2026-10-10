import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'becas_deteccion_screen.dart';

/// Admin: apartado de BECADOS. Permite buscar y seleccionar al alumno,
/// capturar el porcentaje de beca y los montos (ordinario y con beca), y
/// generar el Convenio de Beca en PDF (con folio y QR) para firma.
class BecasAdminScreen extends StatefulWidget {
  const BecasAdminScreen({super.key});

  @override
  State<BecasAdminScreen> createState() => _BecasAdminScreenState();
}

class _BecasAdminScreenState extends State<BecasAdminScreen> {
  final _buscar = TextEditingController();
  final _porc = TextEditingController();
  final _ordi = TextEditingController();
  final _beca = TextEditingController();
  final _notas = TextEditingController();

  // alumno seleccionado
  String _mat = '';
  String _nombre = '';
  String _programa = '';
  String _generacion = '';
  String _correo = '';

  List<Map<String, dynamic>> _resultados = [];
  List<Map<String, dynamic>> _becas = [];
  /// Registros que suben los ALUMNOS con su resolución (hoja BecasRegistros).
  /// Es otra base distinta de 'Becas': aquélla es el sistema financiero que
  /// aplica el descuento; ésta son las solicitudes por dictaminar. Hasta hoy
  /// solo se podían dictaminar desde los botones del correo.
  List<Map<String, dynamic>> _registros = [];
  int _pendientes = 0;
  String? _dictaminando;
  bool _buscando = false;
  bool _guardando = false;
  bool _cargandoLista = true;
  String? _generandoMat;

  @override
  void initState() {
    super.initState();
    _cargarLista();
  }

  @override
  void dispose() {
    _buscar.dispose();
    _porc.dispose();
    _ordi.dispose();
    _beca.dispose();
    _notas.dispose();
    super.dispose();
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : Colors.green));
  }

  double _n(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  void _recalcBeca() {
    final o = _n(_ordi.text);
    final p = _n(_porc.text);
    if (o > 0 && p > 0) {
      _beca.text = (o * (100 - p) / 100).round().toString();
      setState(() {});
    }
  }

  Future<void> _cargarLista() async {
    setState(() => _cargandoLista = true);
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'becas_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _becas = ((data['becas'] as List<dynamic>? ?? []))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    await _cargarRegistros();
    if (mounted) setState(() => _cargandoLista = false);
  }

  Future<void> _cargarRegistros() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'becas_registros_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && mounted) {
        setState(() {
          _registros = ((data['registros'] as List<dynamic>? ?? []))
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _pendientes = (data['pendientes'] ?? 0) as int;
        });
      }
    } catch (_) {
      // si falla, la pantalla sigue sirviendo para el registro manual
    }
  }

  /// Dictamina un registro del alumno. Valida con porcentaje (que se aplica
  /// al sistema financiero y baja la mensualidad al instante) o rechaza con
  /// motivo. En ambos casos el Guardián le manda un correo al alumno.
  Future<void> _dictaminar(Map<String, dynamic> r, bool validar) async {
    final porc = TextEditingController(text: validar ? '50' : '');
    final ordi = TextEditingController();
    final notas = TextEditingController();
    final alumno = (r['nombre'] ?? 'el alumno').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(validar ? 'Validar beca' : 'Rechazar beca',
            style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF4F2ED),
                      borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(alumno,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13.5)),
                      Text(
                          '${r['matricula']} · ${r['programa']} ${r['generacion']}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black54)),
                      const SizedBox(height: 6),
                      Text('${r['tipoBeca']}'
                          '${(r['otorgante'] ?? '').toString().isNotEmpty ? ' · ${r['otorgante']}' : ''}',
                          style: const TextStyle(fontSize: 12)),
                      if ((r['condicion'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Condición: ${r['condicion']}',
                            style: const TextStyle(
                                fontSize: 11.5, height: 1.3)),
                      ],
                    ],
                  ),
                ),
                if (validar) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: porc,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '% de descuento *',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [25, 50, 75, 100]
                        .map((v) => ActionChip(
                              label: Text('$v%'),
                              onPressed: () => porc.text = '$v',
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ordi,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Colegiatura ordinaria (opcional)',
                        helperText:
                            'Si la dejas vacía se toma la de su generación.',
                        isDense: true,
                        prefixText: '\$ ',
                        border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: notas,
                  maxLines: 3,
                  decoration: InputDecoration(
                      labelText:
                          validar ? 'Notas (opcional)' : 'Motivo del rechazo *',
                      isDense: true,
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFBF6EE),
                      border: Border.all(color: CC.goldBorder),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(
                      validar
                          ? '📧 Se le envía UN correo a $alumno avisándole que su '
                              'beca quedó validada, y el descuento se aplica al '
                              'instante en su mensualidad.'
                          : '📧 Se le envía UN correo a $alumno con el motivo '
                              'que escribas aquí.',
                      style: const TextStyle(fontSize: 11.5, height: 1.3)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    validar ? const Color(0xFF1E8E3E) : cessumRed,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(validar ? 'Validar y avisar' : 'Rechazar y avisar'),
          ),
        ],
      ),
    );
    final txtPorc = porc.text.trim();
    final txtOrdi = ordi.text.trim();
    final txtNotas = notas.text.trim();
    porc.dispose();
    ordi.dispose();
    notas.dispose();
    if (ok != true) return;
    if (validar && (_n(txtPorc) <= 0 || _n(txtPorc) > 100)) {
      _aviso('El porcentaje debe estar entre 1 y 100.', error: true);
      return;
    }
    if (!validar && txtNotas.isEmpty) {
      _aviso('Escribe el motivo del rechazo.', error: true);
      return;
    }
    setState(() => _dictaminando = '${r['fila']}');
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final params = <String, String>{
        'accion': 'beca_registro_dictaminar',
        'fila': '${r['fila']}',
        'decision': validar ? 'Validada' : 'Rechazada',
        'actor': actor,
        'notas': txtNotas,
      };
      if (validar) {
        params['porcentaje'] = txtPorc;
        if (txtOrdi.isNotEmpty) params['montoOrdinario'] = txtOrdi;
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso(validar ? 'Beca validada y aplicada.' : 'Registro rechazado.');
      await _cargarLista();
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _dictaminando = null);
  }

  Future<void> _buscarAlumnos() async {
    final q = _buscar.text.trim();
    if (q.length < 2) {
      _aviso('Escribe al menos 2 letras o números.', error: true);
      return;
    }
    setState(() => _buscando = true);
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'becas_alumno_buscar', 'q': q});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _resultados = ((data['alumnos'] as List<dynamic>? ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (_resultados.isEmpty) _aviso('Sin coincidencias.', error: true);
    } catch (e) {
      _aviso('Error al buscar.', error: true);
    }
    if (mounted) setState(() => _buscando = false);
  }

  void _seleccionar(Map<String, dynamic> a) {
    setState(() {
      _mat = (a['matricula'] ?? '').toString();
      _nombre = (a['nombre'] ?? '').toString();
      _programa = (a['programa'] ?? '').toString();
      _generacion = (a['generacion'] ?? '').toString();
      _correo = (a['correo'] ?? '').toString();
      _resultados = [];
      _buscar.text = _nombre;
    });
    // precargar si ya tiene beca
    final prev = _becas.firstWhere(
      (b) => (b['matricula'] ?? '').toString() == _mat,
      orElse: () => {},
    );
    if (prev.isNotEmpty) {
      _porc.text = '${prev['porcentaje'] ?? ''}';
      _ordi.text = '${prev['montoOrdinario'] ?? ''}';
      _beca.text = '${prev['montoBeca'] ?? ''}';
      _notas.text = '${prev['notas'] ?? ''}';
    }
  }

  Future<void> _guardar() async {
    if (_mat.isEmpty) {
      _aviso('Primero selecciona un alumno.', error: true);
      return;
    }
    if (_n(_porc.text) <= 0) {
      _aviso('Escribe el porcentaje de la beca.', error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'beca_guardar',
                'actor': actor,
                'matricula': _mat,
                'nombre': _nombre,
                'programa': _programa,
                'generacion': _generacion,
                'correo': _correo,
                'porcentaje': _n(_porc.text),
                'montoOrdinario': _n(_ordi.text),
                'montoBeca': _n(_beca.text),
                'notas': _notas.text.trim(),
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso('Beca guardada.');
      _limpiar();
      await _cargarLista();
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _guardando = false);
  }

  void _limpiar() {
    _mat = '';
    _nombre = '';
    _programa = '';
    _generacion = '';
    _correo = '';
    _buscar.clear();
    _porc.clear();
    _ordi.clear();
    _beca.clear();
    _notas.clear();
    setState(() {});
  }

  Future<void> _convenio(String mat) async {
    setState(() => _generandoMat = mat);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'beca_convenio',
                'actor': actor,
                'matricula': mat,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final url = (data['pdfUrl'] ?? '').toString();
      if (url.isNotEmpty && mounted) {
        await Helpers.abrirUrlExterna(url, context);
      }
      _aviso('Convenio generado (folio ${data['folio']}).');
      await _cargarLista();
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _generandoMat = null);
  }

  Future<void> _cambiarEstatus(String mat, String estatus) async {
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'beca_estatus',
                'actor': actor,
                'matricula': mat,
                'estatus': estatus,
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso(estatus == 'Activa' ? 'Beca reactivada.' : 'Beca cancelada.');
      await _cargarLista();
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Becados'),
        actions: [
          IconButton(
            tooltip: 'Detectar becas por pagos',
            icon: const Icon(Icons.insights),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const BecasDeteccionScreen(),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarLista,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _seccionSolicitudes(),
            _seccionRegistro(),
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text('Alumnos becados',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (_cargandoLista)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 8),
            if (_becas.isEmpty && !_cargandoLista)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Aún no hay becas registradas.',
                    style: TextStyle(color: Colors.black54)),
              ),
            ..._becas.map(_tarjetaBeca),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  /// Solicitudes que subieron los alumnos con su resolución. Antes solo se
  /// podían dictaminar desde los botones del correo que llega a vicerrectoría;
  /// si ese correo se perdía, el registro se quedaba en el limbo.
  Widget _seccionSolicitudes() {
    final pendientes =
        _registros.where((r) => (r['estatus'] ?? '') == 'En revisión').toList();
    final resueltos =
        _registros.where((r) => (r['estatus'] ?? '') != 'En revisión').toList();
    if (_registros.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inbox, color: cessumGold, size: 20),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Solicitudes de los alumnos',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: cessumGold)),
              ),
              if (_pendientes > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: cessumRed, borderRadius: BorderRadius.circular(20)),
                  child: Text('$_pendientes por dictaminar',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
              'Becas que el alumno registró desde la app con su resolución. '
              'Al validarlas, el descuento se aplica solo a su mensualidad.',
              style: TextStyle(fontSize: 11.5, height: 1.3)),
          const SizedBox(height: 10),
          if (pendientes.isEmpty)
            const Text('Sin solicitudes pendientes.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54))
          else
            ...pendientes.map(_tarjetaRegistro),
          if (resueltos.isNotEmpty) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Ya dictaminadas (${resueltos.length})',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                children: resueltos.map(_tarjetaRegistro).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaRegistro(Map<String, dynamic> r) {
    final estatus = (r['estatus'] ?? 'En revisión').toString();
    final pendiente = estatus == 'En revisión';
    final validada = estatus == 'Validada';
    final url = (r['resolucionUrl'] ?? '').toString();
    final ocupado = _dictaminando == '${r['fila']}';
    final color = pendiente
        ? cessumGold
        : (validada ? const Color(0xFF1E8E3E) : cessumRed);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((r['nombre'] ?? '').toString(),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(estatus,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ),
            ],
          ),
          Text('${r['matricula']} · ${r['programa']} ${r['generacion']}',
              style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 5),
          Text(
              '${r['tipoBeca']}'
              '${(r['otorgante'] ?? '').toString().isNotEmpty ? ' · ${r['otorgante']}' : ''}',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600)),
          if ((r['condicion'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('Condición: ${r['condicion']}',
                style: const TextStyle(fontSize: 11.5, height: 1.3)),
          ],
          Text('Solicitó el ${r['fecha']}',
              style: const TextStyle(fontSize: 10.5, color: Colors.black45)),
          if (!pendiente && (r['notas'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Nota: ${r['notas']}',
                  style: const TextStyle(
                      fontSize: 11.5, color: Colors.black54)),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (url.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: () => Helpers.abrirUrlExterna(url, context),
                  icon: const Icon(Icons.attachment, size: 16),
                  label: const Text('Ver resolución',
                      style: TextStyle(fontSize: 12)),
                )
              else
                const Text('Sin resolución adjunta',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFC62828))),
              if (pendiente) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E8E3E),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact),
                  onPressed: ocupado ? null : () => _dictaminar(r, true),
                  icon: ocupado
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.verified, size: 16),
                  label: const Text('Validar', style: TextStyle(fontSize: 12)),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      visualDensity: VisualDensity.compact),
                  onPressed: ocupado ? null : () => _dictaminar(r, false),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Rechazar', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _seccionRegistro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Registrar / editar beca',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: cessumRed)),
          const SizedBox(height: 10),
          TextField(
            controller: _buscar,
            decoration: InputDecoration(
              labelText: 'Buscar alumno (matrícula o nombre)',
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: _buscando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search, color: cessumRed),
                onPressed: _buscando ? null : _buscarAlumnos,
              ),
            ),
            onSubmitted: (_) => _buscarAlumnos(),
          ),
          ..._resultados.map((a) => ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline, color: cessumGold),
                title: Text((a['nombre'] ?? '').toString()),
                subtitle: Text(
                    '${a['matricula']} · ${a['programa']} · ${a['generacion']}',
                    style: const TextStyle(fontSize: 11.5)),
                onTap: () => _seleccionar(a),
              )),
          if (_mat.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_nombre,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('$_mat · $_programa · Gen. $_generacion',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _porc,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _recalcBeca(),
                    decoration: const InputDecoration(
                        labelText: '% de beca',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _ordi,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _recalcBeca(),
                    decoration: const InputDecoration(
                        labelText: 'Colegiatura ordinaria',
                        isDense: true,
                        prefixText: '\$ ',
                        border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _beca,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Colegiatura mensual con beca (lo que paga)',
                  isDense: true,
                  prefixText: '\$ ',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notas,
              decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white),
                    icon: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: const Text('Guardar beca'),
                    onPressed: _guardando ? null : _guardar,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _limpiar,
                  child: const Text('Limpiar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaBeca(Map<String, dynamic> b) {
    final mat = (b['matricula'] ?? '').toString();
    final estatus = (b['estatus'] ?? 'Activa').toString();
    final activa = estatus.toLowerCase() == 'activa';
    final porc = (b['porcentaje'] ?? '').toString();
    final beca = (b['montoBeca'] ?? '').toString();
    final generando = _generandoMat == mat;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((b['nombre'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: activa
                        ? const Color(0xFF1E8E3E).withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(estatus,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: activa
                              ? const Color(0xFF1E8E3E)
                              : Colors.black54)),
                ),
              ],
            ),
            Text(
                '$mat · ${b['programa']} · Gen. ${b['generacion']}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Text('Beca $porc%  ·  paga \$$beca al mes',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            if ((b['folioConvenio'] ?? '').toString().isNotEmpty)
              Text('Convenio: ${b['folioConvenio']}',
                  style: const TextStyle(fontSize: 11, color: Colors.black45)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                TextButton.icon(
                  icon: generando
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Convenio PDF'),
                  onPressed: generando ? null : () => _convenio(mat),
                ),
                if (activa)
                  TextButton.icon(
                    icon: const Icon(Icons.cancel_outlined,
                        size: 18, color: Colors.redAccent),
                    label: const Text('Cancelar beca',
                        style: TextStyle(color: Colors.redAccent)),
                    onPressed: () => _confirmarCancelar(mat),
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reactivar'),
                    onPressed: () => _cambiarEstatus(mat, 'Activa'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarCancelar(String mat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar beca'),
        content: const Text(
            'El alumno volverá al monto ordinario de su generación. '
            '¿Confirmas la cancelación?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sí, cancelar',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true) _cambiarEstatus(mat, 'Cancelada');
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: motor general de **Becas por tipo**.
/// Tipos: USICAMM (cód. USICAMM26..30), Indígena, Discapacidad y Asignación
/// directa (cód. DIRECTA, editable). Registra la solicitud aunque el aspirante
/// aún no tenga matrícula; al vincularla, el % se aplica en la hoja 'Becas'
/// (de ahí sale el convenio). 'Referencia' vive en el módulo Recomienda.
class BecasTiposAdminScreen extends StatefulWidget {
  const BecasTiposAdminScreen({super.key});

  @override
  State<BecasTiposAdminScreen> createState() => _BecasTiposAdminScreenState();
}

class _BecasTiposAdminScreenState extends State<BecasTiposAdminScreen> {
  final _aspirante = TextEditingController();
  final _correo = TextEditingController();
  final _programa = TextEditingController();
  final _generacion = TextEditingController();
  final _matricula = TextEditingController();
  final _soporte = TextEditingController();
  final _inscripcion = TextEditingController();
  final _porcentaje = TextEditingController();
  String _inscManual = '';
  String _porcManual = '';
  final _cBuscaBeca = TextEditingController();
  List<Map<String, dynamic>> _resBeca = [];
  bool _buscandoBeca = false;

  List<Map<String, dynamic>> _tipos = [];
  String? _tipoSel;

  bool _cargando = true;
  bool _registrando = false;
  String? _accionId; // id en proceso (vincular/editar)
  int _pendientes = 0;
  int _vinculadas = 0;
  List<Map<String, dynamic>> _lista = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _buscarBeca() async {
    final q = _cBuscaBeca.text.trim();
    if (q.isEmpty) return;
    setState(() => _buscandoBeca = true);
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'grupos_admin_buscar', 'q': q});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final lista = (data['grupos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final vistos = <String>{};
      final unicos = <Map<String, dynamic>>[];
      for (final g in lista) {
        final m = (g['matricula'] ?? '').toString().trim();
        final key = m.isEmpty ? (g['correo'] ?? '').toString() : m;
        if (vistos.add(key)) unicos.add(g);
      }
      setState(() {
        _resBeca = unicos;
        _buscandoBeca = false;
      });
    } catch (_) {
      setState(() => _buscandoBeca = false);
    }
  }

  @override
  void dispose() {
    _aspirante.dispose();
    _correo.dispose();
    _programa.dispose();
    _generacion.dispose();
    _matricula.dispose();
    _soporte.dispose();
    _cBuscaBeca.dispose();
    _inscripcion.dispose();
    _porcentaje.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : null));
  }

  Map<String, dynamic>? get _cfg {
    for (final t in _tipos) {
      if ('${t['tipo']}' == _tipoSel) return t;
    }
    return null;
  }

  bool get _editable => (_cfg?['editable'] == true);
  bool get _requiereSoporte => (_cfg?['soporte'] == true);

  Future<void> _init() async {
    setState(() => _cargando = true);
    await _cargarTipos();
    await _cargarLista();
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarTipos() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'beca_tipos'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _tipos = ((data['tipos'] as List<dynamic>? ?? []))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (_tipos.isNotEmpty) {
          _tipoSel ??= '${_tipos.first['tipo']}';
          _aplicarDefaults();
        }
      }
    } catch (_) {}
  }

  Future<void> _cargarLista() async {
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'beca_sol_listar',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _lista = ((data['solicitudes'] as List<dynamic>? ?? []))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _pendientes = (data['pendientes'] as num?)?.toInt() ?? 0;
        _vinculadas = (data['vinculadas'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  Future<void> _recargar() async {
    setState(() => _cargando = true);
    await _cargarLista();
    if (mounted) setState(() => _cargando = false);
  }

  // Al cambiar de tipo, precarga inscripción y % por defecto.
  void _aplicarDefaults() {
    final c = _cfg;
    if (c == null) return;
    if (_editable) {
      // Editables (Asignación directa): arrancan VACÍOS para que el usuario escriba su valor.
      _inscripcion.text = '';
      _porcentaje.text = '';
      _inscManual = '';
      _porcManual = '';
    } else {
      _inscripcion.text = '${c['inscripcion'] ?? ''}';
      _porcentaje.text = '${c['porcentaje'] ?? ''}';
      _inscManual = _inscripcion.text;
      _porcManual = _porcentaje.text;
    }
  }

  String _condicionTexto() {
    final c = _cfg;
    if (c == null) return '';
    return 'Inscripción \$${c['inscripcion']} · Beca ${c['porcentaje']}%'
        '${_editable ? ' (editable)' : ''}';
  }

  Future<void> _registrar() async {
    if (_tipoSel == null) {
      _aviso('Selecciona un tipo de beca.', error: true);
      return;
    }
    if (_aspirante.text.trim().isEmpty && _correo.text.trim().isEmpty) {
      _aviso('Escribe al menos el nombre o el correo del aspirante.',
          error: true);
      return;
    }
    setState(() => _registrando = true);
    try {
      final actor = await _actor();
      final params = <String, String>{
        'accion': 'beca_sol_reg_get',
        'actor': actor,
        'tipo': '$_tipoSel',
        'aspirante': _aspirante.text.trim(),
        'correo': _correo.text.trim(),
        'programa': _programa.text.trim(),
        'generacion': _generacion.text.trim(),
        'matricula': _matricula.text.trim(),
        'soporte': _soporte.text.trim(),
      };
      if (_editable) {
        params['inscripcion'] =
            _inscManual.trim().isNotEmpty ? _inscManual.trim() : _inscripcion.text.trim();
        params['porcentaje'] =
            _porcManual.trim().isNotEmpty ? _porcManual.trim() : _porcentaje.text.trim();
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      final _insMsg = _editable ? (_inscManual.trim().isNotEmpty ? _inscManual.trim() : _inscripcion.text.trim()) : '${data['inscripcion']}';
      final _porMsg = _editable ? (_porcManual.trim().isNotEmpty ? _porcManual.trim() : _porcentaje.text.trim()) : '${data['porcentaje']}';
      _aviso(data['yaExistia'] == true
          ? 'Ya estaba registrado (${data['estatus']}). Inscripción \$$_insMsg + beca $_porMsg%.'
          : 'Registrado. Inscripción \$$_insMsg + beca $_porMsg%.');
      _aspirante.clear();
      _correo.clear();
      _programa.clear();
      _generacion.clear();
      _matricula.clear();
      _soporte.clear();
      _aplicarDefaults();
      await _recargar();
    } catch (e) {
      _aviso('No se pudo: $e'.replaceAll('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  Future<void> _vincular(Map<String, dynamic> r) async {
    final id = (r['id'] ?? '').toString();
    final ctrl =
        TextEditingController(text: (r['matricula'] ?? '').toString());
    final mat = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vincular matrícula'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r['aspirante'] ?? r['correo'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
                'Al vincular, la beca del ${r['porcentaje']}% se registra en la '
                'hoja Becas y queda lista para el convenio.',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Matrícula',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
    if (mat == null || mat.isEmpty) return;
    setState(() => _accionId = id);
    try {
      final actor = await _actor();
      final params = <String, String>{
        'accion': 'beca_sol_reg_get',
        'actor': actor,
        'tipo': '${r['tipo'] ?? ''}',
        'aspirante': '${r['aspirante'] ?? ''}',
        'correo': '${r['correo'] ?? ''}',
        'programa': '${r['programa'] ?? ''}',
        'generacion': '${r['generacion'] ?? ''}',
        'matricula': mat,
        'inscripcion': '${r['inscripcion'] ?? ''}',
        'porcentaje': '${r['porcentaje'] ?? ''}',
      };
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _aviso('Vinculada a $mat. Beca ${data['porcentaje']}% aplicada.');
        await _recargar();
      } else {
        _aviso('${data['error'] ?? 'No se pudo vincular.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    } finally {
      if (mounted) setState(() => _accionId = null);
    }
  }

  Future<void> _editar(Map<String, dynamic> r) async {
    final id = (r['id'] ?? '').toString();
    final insc =
        TextEditingController(text: (r['inscripcion'] ?? '').toString());
    final porc =
        TextEditingController(text: (r['porcentaje'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar beca'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r['aspirante'] ?? r['correo'] ?? ''}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: insc,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Inscripción (\$)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: porc,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Porcentaje de beca (%)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Text(
                (r['matricula'] ?? '').toString().isNotEmpty
                    ? 'Tiene matrícula: al guardar, se vuelve a aplicar en Becas.'
                    : 'Sin matrícula aún: se aplicará al vincular.',
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          ],
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
    );
    if (ok != true) return;
    setState(() => _accionId = id);
    try {
      final actor = await _actor();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'beca_sol_editar',
                'actor': actor,
                'id': id,
                'inscripcion': insc.text.trim(),
                'porcentaje': porc.text.trim(),
              }))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        _aviso('Actualizado: \$${data['inscripcion']} · ${data['porcentaje']}%.');
        await _recargar();
      } else {
        _aviso('${data['error'] ?? 'No se pudo editar.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    } finally {
      if (mounted) setState(() => _accionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _lista
        .where((r) => '${r['estatus']}'.toLowerCase() == 'pendiente')
        .toList();
    final vinculadas = _lista
        .where((r) => '${r['estatus']}'.toLowerCase() != 'pendiente')
        .toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Becas por tipo'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _recargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Formulario de registro
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Registrar beca',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: cessumRed)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _tipoSel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de beca',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _tipos
                      .map((t) => DropdownMenuItem<String>(
                            value: '${t['tipo']}',
                            child: Text('${t['label']}'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _tipoSel = v;
                      _aplicarDefaults();
                    });
                  },
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_condicionTexto(),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7A5A14))),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _cBuscaBeca,
                  decoration: InputDecoration(
                    labelText: 'Buscar alumno (nombre o matrícula)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _buscandoBeca
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)))
                        : IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _buscarBeca),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _buscarBeca(),
                ),
                if (_resBeca.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: _resBeca
                          .map((g) => ListTile(
                                dense: true,
                                title: Text((g['nombre'] ?? '').toString()),
                                subtitle: Text(
                                    '${g['matricula']} · ${g['programa']}'),
                                onTap: () => setState(() {
                                  _aspirante.text =
                                      (g['nombre'] ?? '').toString();
                                  _correo.text = (g['correo'] ?? '').toString();
                                  _programa.text =
                                      (g['programa'] ?? '').toString();
                                  _generacion.text =
                                      (g['generacion'] ?? '').toString();
                                  _matricula.text =
                                      (g['matricula'] ?? '').toString();
                                  _resBeca = [];
                                  _cBuscaBeca.clear();
                                }),
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('o captura manual',
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 6),
                TextField(
                  controller: _aspirante,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del aspirante',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _correo,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo del aspirante',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _programa,
                  decoration: const InputDecoration(
                    labelText: 'Programa (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _generacion,
                        decoration: const InputDecoration(
                          labelText: 'Generación (opcional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _matricula,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Matrícula (si ya tiene)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_editable) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inscripcion,
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _inscManual = v,
                          decoration: const InputDecoration(
                            labelText: 'Inscripción (\$)',
                            hintText: 'Escribe el monto',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _porcentaje,
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _porcManual = v,
                          decoration: const InputDecoration(
                            labelText: 'Beca (%)',
                            hintText: 'Escribe el %',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_requiereSoporte) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _soporte,
                    decoration: const InputDecoration(
                      labelText: 'Soporte / evidencia (enlace o nota)',
                      hintText: 'Constancia, autoadscripción, certificado…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white),
                    onPressed: _registrando ? null : _registrar,
                    icon: _registrando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.school),
                    label: const Text('Registrar beca'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          Text('Pendientes de matrícula ($_pendientes)',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 8),
          if (_cargando)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: cessumRed),
            ))
          else if (pendientes.isEmpty)
            const Text('Sin pendientes.',
                style: TextStyle(color: Colors.black54))
          else
            ...pendientes.map((r) => _item(r, true)),

          const SizedBox(height: 18),
          Text('Vinculadas ($_vinculadas)',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E8E3E))),
          const SizedBox(height: 8),
          if (vinculadas.isEmpty)
            const Text('Aún ninguna.', style: TextStyle(color: Colors.black54))
          else
            ...vinculadas.map((r) => _item(r, false)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _borrar(Map<String, dynamic> r) async {
    final id = (r['id'] ?? '').toString();
    if (id.isEmpty) return;
    final quien =
        (r['aspirante'] ?? '').toString().isNotEmpty
            ? (r['aspirante']).toString()
            : (r['correo'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar registro'),
        content: Text(
            '¿Borrar la beca de "$quien"? La quita de esta lista. '
            'No afecta las becas ya aplicadas en la hoja Becas.'),
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
    setState(() => _accionId = id);
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'beca_sol_borrar',
        'actor': actor,
        'id': id,
        'aplicar': '1',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      final borradas = (data['borradas'] ?? 0) as num;
      if (data['ok'] == true && borradas > 0) {
        _aviso('Registro borrado.');
        await _recargar();
      } else {
        _aviso(
            '${data['error'] ?? data['nota'] ?? 'No se pudo borrar.'}',
            error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    } finally {
      if (mounted) setState(() => _accionId = null);
    }
  }

  Widget _item(Map<String, dynamic> r, bool pendiente) {
    final id = (r['id'] ?? '').toString();
    final correo = (r['correo'] ?? '').toString();
    final programa = (r['programa'] ?? '').toString();
    final matricula = (r['matricula'] ?? '').toString();
    final label = (r['label'] ?? r['tipo'] ?? '').toString();
    final esDirecta = '${r['tipo']}'.toLowerCase() == 'directa';
    final enProceso = _accionId == id;
    final borrable = id.isNotEmpty && !id.startsWith('BX');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    (r['aspirante'] ?? '').toString().isNotEmpty
                        ? (r['aspirante']).toString()
                        : (correo.isNotEmpty ? correo : '(sin nombre)'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7A5A14))),
              ),
            ],
          ),
          if (correo.isNotEmpty && (r['aspirante'] ?? '').toString().isNotEmpty)
            Text(correo,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (programa.isNotEmpty)
            Text(programa,
                style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          Text(
              'Inscripción \$${r['inscripcion'] ?? 0} · Beca ${r['porcentaje'] ?? 0}%'
              '${(r['fecha'] ?? '').toString().trim().isNotEmpty ? ' · ${r['fecha']}' : ''}',
              style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
          if (matricula.isNotEmpty)
            Text('Matrícula: $matricula',
                style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (borrable && !enProceso) ...[
                OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(foregroundColor: cessumRed),
                  onPressed: () => _borrar(r),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Borrar'),
                ),
                const SizedBox(width: 8),
              ],
              if (esDirecta && !enProceso)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                  onPressed: () => _editar(r),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Editar'),
                ),
              if (esDirecta && pendiente) const SizedBox(width: 8),
              if (enProceso)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cessumRed)),
                )
              else if (pendiente)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E8E3E),
                      foregroundColor: Colors.white),
                  onPressed: () => _vincular(r),
                  icon: const Icon(Icons.link, size: 18),
                  label: const Text('Vincular matrícula'),
                )
              else
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified, size: 16, color: Color(0xFF1E8E3E)),
                    SizedBox(width: 4),
                    Text('Aplicada en Becas',
                        style: TextStyle(
                            color: Color(0xFF1E8E3E),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

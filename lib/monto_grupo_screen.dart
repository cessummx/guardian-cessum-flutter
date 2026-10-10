// ADMIN: fija manualmente el monto (mensualidad) de un grupo. Gana sobre la
// inferencia automática del backend, que adivinaba mal la modalidad (tomaba
// No-escolarizada en doctorados/maestrías mixtas). Las becas individuales
// siguen aplicando aparte: esto fija el monto SIN beca del grupo.
//
// Programa/generación/grupo se ELIGEN de selectores cargados del catálogo real
// (catalogo_grupos), no se teclean: así el override empata exacto con el grupo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class MontoGrupoScreen extends StatefulWidget {
  const MontoGrupoScreen({super.key});

  @override
  State<MontoGrupoScreen> createState() => _MontoGrupoScreenState();
}

class _MontoGrupoScreenState extends State<MontoGrupoScreen> {
  // Catálogo real: [{programa, generaciones:[{generacion, grupos:[...]}]}]
  List<Map<String, dynamic>> _catalogo = [];
  String? _programa;
  String? _generacion;
  String? _grupo; // null = toda la generación
  final _monto = TextEditingController();

  List<Map<String, dynamic>> _lista = [];
  bool _cargandoCatalogo = true;
  bool _cargandoLista = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarCatalogo();
    _cargarLista();
  }

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    setState(() => _cargandoCatalogo = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=catalogo_grupos'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _catalogo = ((data['catalogo'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoCatalogo = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoCatalogo = false);
    }
  }

  Future<void> _cargarLista() async {
    setState(() => _cargandoLista = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=monto_grupo_listar'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _lista = ((data['montos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoLista = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoLista = false);
    }
  }

  List<String> get _generacionesDelPrograma {
    final p = _catalogo.firstWhere(
      (e) => e['programa'] == _programa,
      orElse: () => {},
    );
    final gens = (p['generaciones'] as List?) ?? [];
    return gens.map((g) => (g['generacion'] ?? '').toString()).toList();
  }

  List<String> get _gruposDeLaGeneracion {
    final p = _catalogo.firstWhere(
      (e) => e['programa'] == _programa,
      orElse: () => {},
    );
    final gens = (p['generaciones'] as List?) ?? [];
    final g = gens.firstWhere(
      (x) => (x['generacion'] ?? '').toString() == _generacion,
      orElse: () => {},
    );
    return ((g['grupos'] as List?) ?? []).map((x) => x.toString()).toList();
  }

  Future<void> _guardar() async {
    final monto = double.tryParse(_monto.text.trim()) ?? 0;
    if (_programa == null || _generacion == null || monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.orange,
        content: Text('Elige programa, generación y un monto mayor a 0.'),
      ));
      return;
    }
    setState(() => _guardando = true);
    try {
      final actor = await SessionStore.validEmail() ?? '';
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=monto_grupo_guardar'
              '&programa=${Uri.encodeComponent(_programa!)}'
              '&generacion=${Uri.encodeComponent(_generacion!)}'
              '&grupo=${Uri.encodeComponent(_grupo ?? '')}'
              '&mensualidad=$monto'
              '&actor=${Uri.encodeComponent(actor)}'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF1E8E3E),
          content: Text('Monto del grupo guardado.'),
        ));
        setState(() {
          _monto.clear();
          _grupo = null;
        });
        _cargarLista();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(data['error']?.toString() ?? 'No se pudo guardar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar monto'),
        content: Text(
            '¿Quitar el monto fijo de ${m['programa']} ${m['generacion']}'
            '${(m['grupo'] ?? '').toString().isNotEmpty ? ' · ${m['grupo']}' : ''}?'
            '\n\nEl grupo volverá al cálculo automático.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final actor = await SessionStore.validEmail() ?? '';
      await http
          .get(Uri.parse('$guardianUrl?accion=monto_grupo_eliminar'
              '&fila=${m['fila']}'
              '&actor=${Uri.encodeComponent(actor)}'))
          .timeout(const Duration(seconds: 30));
      _cargarLista();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Monto de pago por grupo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _cargarCatalogo();
              _cargarLista();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumRed.withValues(alpha: 0.2)),
            ),
            child: Text(
              'Fija el monto mensual (sin beca) de un grupo. Gana sobre el '
              'cálculo automático, para casos donde el sistema toma la modalidad '
              'equivocada (mixtos que salían con precio de no escolarizada). Las '
              'becas de cada alumno se siguen aplicando aparte.',
              style: TextStyle(
                  fontSize: 12.5, color: cessumMuted(context), height: 1.4),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Fijar monto de un grupo',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 12),
          if (_cargandoCatalogo)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: cessumRed)),
            )
          else ...[
            _dropdown<String>(
              label: 'Programa',
              value: _programa,
              items: _catalogo
                  .map((e) => (e['programa'] ?? '').toString())
                  .toList(),
              onChanged: (v) => setState(() {
                _programa = v;
                _generacion = null;
                _grupo = null;
              }),
            ),
            const SizedBox(height: 12),
            _dropdown<String>(
              label: 'Generación',
              value: _generacion,
              enabled: _programa != null,
              items: _generacionesDelPrograma,
              onChanged: (v) => setState(() {
                _generacion = v;
                _grupo = null;
              }),
            ),
            const SizedBox(height: 12),
            _dropdown<String?>(
              label: 'Grupo (opcional — vacío = toda la generación)',
              value: _grupo,
              enabled: _generacion != null,
              items: <String?>[null, ..._gruposDeLaGeneracion],
              display: (v) => v == null ? 'Toda la generación' : v,
              onChanged: (v) => setState(() => _grupo = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _monto,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Monto mensual (ej. 3450)',
                prefixText: '\$ ',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: cessumRed, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(
                    _guardando ? 'Guardando…' : 'Guardar monto del grupo'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Montos fijados',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 8),
          if (_cargandoLista)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: cessumRed),
            ))
          else if (_lista.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Aún no has fijado montos manuales.',
                  style: TextStyle(fontSize: 13, color: cessumMuted(context))),
            )
          else
            ..._lista.map(_tarjeta),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    bool enabled = true,
    String Function(T)? display,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: enabled
                  ? cessumRed.withValues(alpha: 0.4)
                  : Colors.grey.withValues(alpha: 0.3)),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(enabled ? 'Selecciona…' : 'Elige primero el anterior',
              style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          items: enabled
              ? items
                  .map((it) => DropdownMenuItem<T>(
                        value: it,
                        child: Text(
                          display != null ? display(it) : it.toString(),
                          style: const TextStyle(fontSize: 13.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList()
              : const [],
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> m) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '${m['programa']} · ${m['generacion']}'
          '${(m['grupo'] ?? '').toString().isNotEmpty ? ' · ${m['grupo']}' : ' · (toda la generación)'}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '\$${m['mensualidad']} mensual',
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1E8E3E),
              fontWeight: FontWeight.w700),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _eliminar(m),
        ),
      ),
    );
  }
}

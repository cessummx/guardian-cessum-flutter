import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Admin: detector de anomalías de alta.
/// 1) Verificar antes de dar de alta: dice si la persona ya existe (por correo,
///    CURP, nombre o matrícula) para no generar matrícula de más.
/// 2) Escaneo de duplicados del padrón + curps.json (matrículas, correos, CURPs
///    y homónimos con matrícula distinta).
class AltasAnomaliasScreen extends StatefulWidget {
  const AltasAnomaliasScreen({super.key});

  @override
  State<AltasAnomaliasScreen> createState() => _AltasAnomaliasScreenState();
}

class _AltasAnomaliasScreenState extends State<AltasAnomaliasScreen> {
  static const Color _cGreen = Color(0xFF1E8E3E);

  // --- Verificar ---
  final _valor = TextEditingController();
  String _campo = 'correo';
  bool _verificando = false;
  List<Map<String, dynamic>>? _coincidencias;
  String _avisoVerif = '';

  // --- Escaneo ---
  bool _escaneando = true;
  Map<String, dynamic> _conteos = {};
  Map<String, List<Map<String, dynamic>>> _grupos = {
    'matriculasDup': [],
    'correosDup': [],
    'curpsDup': [],
    'nombresDup': [],
  };
  String _abierto = '';

  @override
  void initState() {
    super.initState();
    _escanear();
  }

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m), backgroundColor: error ? cessumRed : null));
  }

  List<Map<String, dynamic>> _listaDe(dynamic v) =>
      ((v as List<dynamic>? ?? []))
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<void> _escanear() async {
    setState(() => _escaneando = true);
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'altas_anomalias',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _conteos = Map<String, dynamic>.from(data['conteos'] as Map? ?? {});
        _grupos = {
          'matriculasDup': _listaDe(data['matriculasDup']),
          'correosDup': _listaDe(data['correosDup']),
          'curpsDup': _listaDe(data['curpsDup']),
          'nombresDup': _listaDe(data['nombresDup']),
        };
      } else {
        _aviso('${data['error'] ?? 'No se pudo escanear.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    }
    if (mounted) setState(() => _escaneando = false);
  }

  /// (24-sep) Marca un grupo de homónimos como PERSONAS DISTINTAS (revisado):
  /// deja de aparecer. No toca el padrón.
  Future<void> _marcarDistintas(Map<String, dynamic> g) async {
    final clave = '${g['clave'] ?? ''}';
    if (clave.isEmpty) return;
    final nombres = _listaDe(g['alumnos']).map((a) => '${a['nombre']} · ${a['matricula']}').join('\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Son personas distintas?', style: TextStyle(fontSize: 16)),
        content: Text(
            'Confirme que estos registros son de personas DIFERENTES que se llaman igual:\n\n$nombres\n\n'
            'El grupo dejará de aparecer. No se modifica el padrón. Si en el futuro aparece otra '
            'matrícula con el mismo nombre, volverá a salir para revisarse.',
            style: const TextStyle(fontSize: 13.5, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, son distintas'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final actor = await _actor();
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'altas_homonimo_ok', 'actor': actor, 'clave': clave}))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Marcado como personas distintas.');
      await _escanear();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _verificar() async {
    final v = _valor.text.trim();
    if (v.isEmpty) {
      _aviso('Escribe un dato para verificar.', error: true);
      return;
    }
    setState(() {
      _verificando = true;
      _coincidencias = null;
      _avisoVerif = '';
    });
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alta_verificar',
        'actor': actor,
        _campo: v,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _coincidencias = _listaDe(data['coincidencias']);
        _avisoVerif = (data['aviso'] ?? '').toString();
      } else {
        _aviso('${data['error'] ?? 'No se pudo verificar.'}', error: true);
      }
    } catch (_) {
      _aviso('No me pude conectar.', error: true);
    }
    if (mounted) setState(() => _verificando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Anomalías de alta'),
        actions: [
          IconButton(
              onPressed: _escaneando ? null : _escanear,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _seccionVerificar(),
          const SizedBox(height: 20),
          _seccionEscaneo(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _seccionVerificar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Ya existe? (verificar antes de dar de alta)',
              style:
                  TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 4),
          Text(
              'Busca a la persona en el padrón para no generarle una matrícula '
              'de más.',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  value: _campo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'correo', child: Text('Correo')),
                    DropdownMenuItem(value: 'curp', child: Text('CURP')),
                    DropdownMenuItem(value: 'nombre', child: Text('Nombre')),
                    DropdownMenuItem(
                        value: 'matricula', child: Text('Matrícula')),
                  ],
                  onChanged: (v) => setState(() => _campo = v ?? 'correo'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _valor,
                  onSubmitted: (_) => _verificar(),
                  decoration: const InputDecoration(
                    hintText: 'Dato a buscar',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _verificando ? null : _verificar,
              icon: _verificando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search),
              label: const Text('Verificar'),
            ),
          ),
          if (_avisoVerif.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE08600).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_avisoVerif,
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFF8A5300))),
            ),
          ],
          if (_coincidencias != null) ...[
            const SizedBox(height: 10),
            if (_coincidencias!.isEmpty)
              Row(
                children: const [
                  Icon(Icons.check_circle, color: _cGreen, size: 18),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('No existe en el padrón. Puedes darlo de alta.',
                        style: TextStyle(
                            color: _cGreen, fontWeight: FontWeight.w600)),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: cessumRed, size: 18),
                  const SizedBox(width: 6),
                  Text('Ya existe (${_coincidencias!.length})',
                      style: const TextStyle(
                          color: cessumRed, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 6),
              ..._coincidencias!.map(_alumnoTile),
            ],
          ],
        ],
      ),
    );
  }

  Widget _seccionEscaneo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Duplicados en el padrón',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed)),
        const SizedBox(height: 8),
        if (_escaneando)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(color: cessumRed),
          ))
        else ...[
          _filaDup('Matrículas duplicadas', 'matriculasDup'),
          _filaDup('Correos duplicados', 'correosDup'),
          _filaDup('CURPs duplicadas', 'curpsDup'),
          _filaDup('Homónimos (matrícula distinta)', 'nombresDup'),
        ],
      ],
    );
  }

  Widget _filaDup(String titulo, String clave) {
    final n = (_conteos[clave] as num?)?.toInt() ?? 0;
    final abierto = _abierto == clave;
    final grupos = _grupos[clave] ?? [];
    final color = n > 0 ? cessumRed : _cGreen;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: n == 0
                ? null
                : () => setState(() => _abierto = abierto ? '' : clave),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(n > 0 ? Icons.error : Icons.check_circle,
                      color: color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(titulo,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600))),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$n',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w800)),
                  ),
                  if (n > 0)
                    Icon(abierto ? Icons.expand_less : Icons.expand_more,
                        color: cessumFaint(context)),
                ],
              ),
            ),
          ),
          if (abierto)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                children: grupos.map((g) => _grupoTile(g, clave)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grupoTile(Map<String, dynamic> g, String clave) {
    final valor = (g['valor'] ?? g['curp'] ?? g['nombre'] ?? '').toString();
    final alumnos = _listaDe(g['alumnos']);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 2),
          ...alumnos.map((a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                    '• ${a['nombre'] ?? ''} · ${a['matricula'] ?? ''}'
                    '${(a['correo'] ?? '').toString().isNotEmpty ? ' · ${a['correo']}' : ''}'
                    '${(a['programa'] ?? '').toString().isNotEmpty ? ' · ${a['programa']}' : ''}',
                    style: TextStyle(
                        fontSize: 11.5, color: cessumMuted(context))),
              )),
          // (24-sep) Qué hacer con cada tipo de hallazgo.
          if (clave == 'nombresDup' && '${g['clave'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
                onPressed: () => _marcarDistintas(g),
                icon: const Icon(Icons.people_alt_outlined, size: 16),
                label: const Text('Son personas distintas'),
              ),
            )
          else if (clave != 'nombresDup')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  'Es un duplicado real: corríjalo en el expediente del alumno (Centro de datos), '
                  'dejando un solo registro en las dos bases.',
                  style: TextStyle(fontSize: 11, color: cessumMuted(context), fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  Widget _alumnoTile(Map<String, dynamic> a) {
    final razones = (a['coincidePor'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cessumRed.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${a['nombre'] ?? ''}  ·  ${a['matricula'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if ((a['correo'] ?? '').toString().isNotEmpty)
            Text((a['correo']).toString(),
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          Text(
              [
                if ((a['programa'] ?? '').toString().isNotEmpty) '${a['programa']}',
                if ((a['generacion'] ?? '').toString().isNotEmpty) 'Gen. ${a['generacion']}',
                if ((a['estatus'] ?? '').toString().isNotEmpty) '${a['estatus']}',
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
          if (razones.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Coincide por: $razones',
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: cessumRed,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

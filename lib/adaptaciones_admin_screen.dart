// ADMIN: Adaptaciones de modalidad (ago-2026). Panel del sistema vigilado:
// registrar una adaptación aprobada (alumno + materia con buscadores),
// ver Esperando/Matriculadas, cancelar, y forzar la búsqueda de oferta.
// El vigilante horario matricula solo cuando la materia está en línea.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class AdaptacionesAdminScreen extends StatefulWidget {
  const AdaptacionesAdminScreen({super.key});

  @override
  State<AdaptacionesAdminScreen> createState() =>
      _AdaptacionesAdminScreenState();
}

class _AdaptacionesAdminScreenState extends State<AdaptacionesAdminScreen> {
  bool _cargando = true;
  bool _escaneando = false;
  String _error = '';
  List<Map<String, dynamic>> _adaptaciones = [];
  List<Map<String, dynamic>> _alumnos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(String qs, {int seg = 60}) async {
    final r = await http
        .get(Uri.parse('$guardianUrl?$qs'))
        .timeout(Duration(seconds: seg));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _get('accion=adaptacion_listar');
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _adaptaciones = ((d['adaptaciones'] as List?) ?? [])
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

  void _aviso(String m, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: ok ? const Color(0xFF1E8E3E) : cessumRed,
        content: Text(m)));
  }

  Future<void> _escanearAhora() async {
    setState(() => _escaneando = true);
    try {
      final d = await _get('accion=adaptacion_scan', seg: 120);
      if (d['ok'] == true) {
        final mats = ((d['matriculadas'] as List?) ?? []).length;
        final sin = ((d['sinOferta'] as List?) ?? []).length;
        _aviso('Búsqueda hecha: $mats matriculada(s), $sin sin oferta aún.');
        _cargar();
      } else {
        _aviso('${d['error']}', ok: false);
      }
    } catch (e) {
      _aviso('$e', ok: false);
    } finally {
      if (mounted) setState(() => _escaneando = false);
    }
  }

  Future<void> _cargarAlumnos() async {
    if (_alumnos.isNotEmpty) return;
    final d = await _get('accion=clasificacion_alumnos', seg: 90);
    final lista = (d['alumnos'] as List?) ?? (d['lista'] as List?) ?? [];
    _alumnos = lista
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((a) =>
            (a['tipo'] ?? '') != 'Baja' &&
            (a['matricula'] ?? '').toString().isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>?> _elegirAlumno() async {
    try {
      await _cargarAlumnos();
    } catch (e) {
      _aviso('No pude cargar alumnos: $e', ok: false);
      return null;
    }
    if (!mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        var filtro = '';
        return StatefulBuilder(builder: (ctx, setLocal) {
          final vis = _alumnos.where((a) {
            if (filtro.isEmpty) return false; // exige teclear para no listar 400
            final t = '${a['nombre']} ${a['matricula']}'.toLowerCase();
            return t.contains(filtro.toLowerCase());
          }).take(30).toList();
          return AlertDialog(
            title: const Text('¿De qué alumno es la adaptación?'),
            content: SizedBox(
              width: 480,
              height: 400,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Nombre o matrícula…',
                      isDense: true,
                      border: OutlineInputBorder()),
                  onChanged: (v) => setLocal(() => filtro = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: filtro.isEmpty
                      ? Center(
                          child: Text('Escribe para buscar…',
                              style: TextStyle(
                                  fontSize: 12, color: cessumFaint(context))))
                      : ListView(children: [
                          for (final a in vis)
                            ListTile(
                              dense: true,
                              title: Text('${a['nombre']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '${a['matricula']} · ${a['programa']} ${a['generacion']} · ${a['grupo']}',
                                  style: const TextStyle(fontSize: 11.5)),
                              onTap: () => Navigator.pop(ctx, a),
                            ),
                        ]),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
            ],
          );
        });
      },
    );
  }

  Future<String?> _elegirMateria(String matricula) async {
    List<Map<String, dynamic>> materias = [];
    try {
      final d = await _get(
          'accion=alumno_materias_panorama&matricula=${Uri.encodeComponent(matricula)}');
      for (final k in ['enCurso', 'futuras']) {
        for (final m in ((d[k] as List?) ?? [])) {
          materias.add(Map<String, dynamic>.from(m as Map));
        }
      }
    } catch (_) {}
    if (!mounted) return null;
    final manualCtrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        var filtro = '';
        return StatefulBuilder(builder: (ctx, setLocal) {
          final vis = materias
              .where((m) =>
                  filtro.isEmpty ||
                  '${m['materia']}'
                      .toLowerCase()
                      .contains(filtro.toLowerCase()))
              .toList();
          return AlertDialog(
            title: const Text('¿Qué materia se adapta?'),
            content: SizedBox(
              width: 480,
              height: 430,
              child: Column(children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Buscar en sus materias…',
                      isDense: true,
                      border: OutlineInputBorder()),
                  onChanged: (v) => setLocal(() => filtro = v),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: materias.isEmpty
                      ? Center(
                          child: Text(
                              'Sin materias próximas registradas.\nEscríbela abajo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: cessumMuted(context))))
                      : ListView(children: [
                          for (final m in vis)
                            ListTile(
                              dense: true,
                              title: Text('${m['materia']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  'Del ${m['inicio']} al ${m['termino']}',
                                  style: const TextStyle(fontSize: 11.5)),
                              onTap: () => Navigator.pop(
                                  ctx, (m['materia'] ?? '').toString()),
                            ),
                        ]),
                ),
                const Divider(),
                TextField(
                  controller: manualCtrl,
                  decoration: const InputDecoration(
                      labelText: 'U otra materia (a mano)',
                      isDense: true,
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      final t = manualCtrl.text.trim();
                      if (t.isNotEmpty) Navigator.pop(ctx, t);
                    },
                    child: const Text('Usar la escrita a mano'),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
            ],
          );
        });
      },
    );
  }

  Future<void> _registrar() async {
    final al = await _elegirAlumno();
    if (al == null) return;
    final materia =
        await _elegirMateria((al['matricula'] ?? '').toString());
    if (materia == null || materia.isEmpty) return;
    final notasCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar adaptación'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${al['nombre']} (${al['matricula']})\n→ $materia',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: notasCtrl,
            decoration: const InputDecoration(
                labelText: 'Notas (motivo, acuerdo del Consejo…)',
                border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          Text(
              'Quedará "Esperando": el vigilante la matriculará solo '
              'cuando la materia esté en línea con aula creada, avisándole '
              'por correo al alumno y al docente destino.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true) return;
    final quien = await SessionStore.realEmail();
    final d = await _get('accion=adaptacion_registrar'
        '&matricula=${Uri.encodeComponent((al['matricula'] ?? '').toString())}'
        '&materia=${Uri.encodeComponent(materia)}'
        '&notas=${Uri.encodeComponent(notasCtrl.text.trim())}'
        '&actor=${Uri.encodeComponent(quien ?? '')}');
    if (d['ok'] == true) {
      _aviso('Registrada. El alumno ya recibió el aviso de que quedó '
          'en espera con matrícula automática.');
      _cargar();
    } else {
      _aviso('${d['error']}', ok: false);
    }
  }

  Future<void> _cancelar(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar adaptación'),
        content: Text(
            '¿Cancelar la adaptación de ${a['alumno']} para "${a['materia']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (ok != true) return;
    final d = await _get('accion=adaptacion_cancelar'
        '&matricula=${Uri.encodeComponent((a['matricula'] ?? '').toString())}'
        '&materia=${Uri.encodeComponent((a['materia'] ?? '').toString())}');
    if (d['ok'] == true) {
      _aviso('Cancelada.');
      _cargar();
    } else {
      _aviso('${d['error']}', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esperando =
        _adaptaciones.where((a) => a['estado'] == 'Esperando').toList();
    final resto =
        _adaptaciones.where((a) => a['estado'] != 'Esperando').toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Adaptaciones de modalidad',
            style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Buscar oferta ahora',
              onPressed: _escaneando ? null : _escanearAhora,
              icon: _escaneando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.radar)),
          IconButton(
              tooltip: 'Recargar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _registrar,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Registrar adaptación'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(child: Text('Error: $_error'))
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text(
                        'El vigilante corre cada hora: cuando la materia '
                        'esperada aparece en línea (otro grupo, con aula '
                        'creada), matricula al alumno y avisa por correo a '
                        'él y al docente. El radar de arriba fuerza una '
                        'búsqueda inmediata.',
                        style: TextStyle(
                            fontSize: 11.5, color: cessumMuted(context)),
                      ),
                      const SizedBox(height: 12),
                      Text('EN ESPERA (${esperando.length})',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: cessumGold)),
                      if (esperando.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Nadie en espera.',
                              style: TextStyle(
                                  fontSize: 12, color: cessumFaint(context))),
                        ),
                      for (final a in esperando) _tarjeta(a),
                      const SizedBox(height: 16),
                      Text('HISTORIAL (${resto.length})',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: cessumFaint(context))),
                      for (final a in resto) _tarjeta(a),
                    ],
                  ),
                ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final estado = (a['estado'] ?? '').toString();
    final c = estado == 'Esperando'
        ? cessumGold
        : estado == 'Matriculada'
            ? const Color(0xFF1E8E3E)
            : cessumFaint(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${a['alumno']} (${a['matricula']})',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(20)),
            child: Text(estado,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: c)),
          ),
        ]),
        Text('${a['materia']}',
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w600)),
        Text(
          '${a['programa']} · viene de ${a['grupoOrigen']}'
          '${(a['grupoDestino'] ?? '').toString().isNotEmpty ? '  →  ${a['grupoDestino']}' : ''}',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        Text(
          'Registrada: ${a['fecha']}'
          '${(a['matriculadaEn'] ?? '').toString().isNotEmpty ? ' · Matriculada: ${a['matriculadaEn']}' : ''}',
          style: TextStyle(fontSize: 11, color: cessumFaint(context)),
        ),
        if (estado == 'Esperando')
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: cessumRed),
              onPressed: () => _cancelar(a),
              icon: const Icon(Icons.cancel_outlined, size: 16),
              label:
                  const Text('Cancelar', style: TextStyle(fontSize: 12)),
            ),
          ),
      ]),
    );
  }
}

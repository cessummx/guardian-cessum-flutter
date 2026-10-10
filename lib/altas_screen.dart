// ALTAS DE INSCRIPCIÓN · VERIFICACIÓN (22-sep-2026)
//
// La alta la hace Sistemas. Esta pantalla no ejecuta nada: comprueba, contra
// los datos reales, en qué paso va cada solicitud de inscripción —revisión,
// cuenta, matrícula, padrón, base de Grupos, aula y bienvenida— y qué le
// falta. Los huecos que hoy se descubren por queja salen aquí solos.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class AltasScreen extends StatefulWidget {
  const AltasScreen({super.key});
  @override
  State<AltasScreen> createState() => _AltasScreenState();
}

class _AltasScreenState extends State<AltasScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  String _filtro = 'detenida';
  final _cBuscar = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cBuscar.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool refrescar = false}) async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      // (24-sep) Correo REAL: en «Ver como profesor» validEmail() devuelve el del profesor.
      final actor = ((await SessionStore.realEmail()) ?? '').trim().toLowerCase();
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'insc_pipeline',
            'actor': actor,
            if (refrescar) 'refrescar': '1',
          }))
          .timeout(const Duration(seconds: 180));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo consultar');
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Color _color(String sit) => sit == 'detenida'
      ? cessumRed
      : sit == 'en revisión'
          ? const Color(0xFFB8860B)
          : sit == 'completa'
              ? const Color(0xFF1E7F52)
              : Colors.grey;

  @override
  Widget build(BuildContext context) {
    final res = Map<String, dynamic>.from((_d['resumen'] as Map?) ?? {});
    final todas = ((_d['solicitudes'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    final q = _cBuscar.text.trim().toLowerCase();
    final lista = todas.where((s) {
      if (_filtro.isNotEmpty && s['situacion'] != _filtro) return false;
      if (q.isEmpty) return true;
      return '${s['nombre']} ${s['matricula']} ${s['programa']} ${s['correoInstitucional']}'
          .toLowerCase()
          .contains(q);
    }).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Altas de inscripción'),
        actions: [
          IconButton(
            tooltip: 'Volver a verificar (consulta Moodle)',
            onPressed: _cargando ? null : () => _cargar(refrescar: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: cessumRed),
                  SizedBox(height: 14),
                  Text('Comprobando solicitudes, padrón, grupos y aulas…',
                      textAlign: TextAlign.center),
                ]),
              ),
            )
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 42, color: cessumGold),
                      const SizedBox(height: 12),
                      Text(_error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: cessumRed),
                        onPressed: () => _cargar(),
                        child: const Text('Reintentar'),
                      ),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 30), children: [
                  Text(
                    'Solicitudes de los últimos ${_d['dias'] ?? 120} días · '
                    'verificado el ${_d['generado'] ?? ''}'
                    '${_d['moodleVerificado'] == true ? ' · aulas comprobadas en Moodle' : ''}'
                    '${_d['deCache'] == true ? ' · guardado; el botón de arriba lo rehace' : ''}',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    _cifra('Detenidas', res['detenidas'], cessumRed, 'detenida'),
                    _cifra('En revisión', res['pendientesRevision'], const Color(0xFFB8860B), 'en revisión'),
                    _cifra('Completas', res['completas'], const Color(0xFF1E7F52), 'completa'),
                    _cifra('Todas', res['total'], Colors.grey, ''),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cBuscar,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Buscar por nombre, matrícula, programa o correo',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  if (lista.isEmpty)
                    _tarjeta(const Text('Nada con ese filtro.'), Colors.grey)
                  else
                    ...lista.map(_solicitud),
                ]),
    );
  }

  Widget _cifra(String t, dynamic n, Color color, String filtro) => Expanded(
        child: InkWell(
          onTap: () => setState(() => _filtro = filtro),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: _filtro == filtro ? 0.18 : 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: _filtro == filtro ? 0.8 : 0.3)),
            ),
            child: Column(children: [
              Text('${n ?? 0}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              Text(t, style: TextStyle(fontSize: 10.5, color: color)),
            ]),
          ),
        ),
      );

  Widget _tarjeta(Widget hijo, Color borde) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borde.withValues(alpha: 0.35)),
        ),
        child: hijo,
      );

  Widget _solicitud(Map<String, dynamic> s) {
    final sit = (s['situacion'] ?? '').toString();
    final color = _color(sit);
    final pasos = ((s['pasos'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
    final falta = ((s['falta'] as List?) ?? []).map((f) => '$f').toList();
    return _tarjeta(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
            child: Text(sit.toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${s['nombre']}'.isEmpty ? '(sin nombre)' : '${s['nombre']}',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          Text('${s['fecha']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ]),
        Text(
          '${s['programa']}${(s['modalidad'] ?? '').toString().isNotEmpty ? ' · ${s['modalidad']}' : ''}'
          '${(s['matricula'] ?? '').toString().isNotEmpty ? ' · ${s['matricula']}' : ''}',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: pasos.map((p) {
            final ok = p['ok'];
            final c = ok == true
                ? const Color(0xFF1E7F52)
                : ok == false
                    ? cessumRed
                    : Colors.grey;
            return Tooltip(
              message: '${p['detalle']}',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.withValues(alpha: 0.35))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(ok == true ? Icons.check : (ok == false ? Icons.close : Icons.help_outline),
                      size: 12, color: c),
                  const SizedBox(width: 4),
                  Text('${p['paso']}', style: TextStyle(fontSize: 11, color: c)),
                ]),
              ),
            );
          }).toList(),
        ),
        if (falta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Falta: ${falta.join(' · ')}',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed)),
          ),
        if ((s['correoInstitucional'] ?? '').toString().isNotEmpty)
          Text('${s['correoInstitucional']}',
              style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ]),
      color,
    );
  }
}

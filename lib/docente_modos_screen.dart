import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'modos_aprendizaje.dart';

/// Vista del DOCENTE: agrega las respuestas de sus grupos asignados y sugiere
/// cómo diseñar la clase según el perfil del grupo.
class DocenteModosScreen extends StatefulWidget {
  const DocenteModosScreen({super.key});

  @override
  State<DocenteModosScreen> createState() => _DocenteModosScreenState();
}

class _DocenteModosScreenState extends State<DocenteModosScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _grupos = [];
  Map<String, int> _totales = {};
  int _nAlumnos = 0;
  int _conTest = 0;
  int _directivos = 0;
  List<String> _sugerencias = [];
  List<Map<String, dynamic>> _alumnos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      if (correo.isEmpty) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo identificar tu sesión de docente.';
        });
        return;
      }
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'modos_grupo', 'correo': correo});
      final r = await http.get(uri).timeout(const Duration(seconds: 50));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() {
          _cargando = false;
          _error = '${data['error'] ?? 'No se pudo cargar.'}';
        });
        return;
      }
      final t = (data['totales'] as Map?) ?? {};
      setState(() {
        _grupos = ((data['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _totales = {
          for (final k in kModos)
            k: (t[k] is int ? t[k] as int : int.tryParse('${t[k]}') ?? 0)
        };
        _nAlumnos = data['nAlumnos'] is int ? data['nAlumnos'] as int : 0;
        _conTest = data['conTest'] is int ? data['conTest'] as int : 0;
        _directivos = data['directivos'] is int ? data['directivos'] as int : 0;
        _sugerencias = ((data['sugerencias'] as List?) ?? [])
            .map((e) => '$e')
            .toList();
        _alumnos = ((data['alumnos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la información del grupo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Perfil de aprendizaje · mis grupos'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cessumRed),
                        onPressed: _cargar,
                        child: const Text('Reintentar',
                            style: TextStyle(color: Colors.white))),
                  ]),
                ))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: _contenido(),
                  ),
                ),
    );
  }

  List<Widget> _contenido() {
    final w = <Widget>[];
    // Grupos
    if (_grupos.isEmpty) {
      w.add(const Card(
        color: Colors.white,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
              // (ago-25) El mensaje anterior decía «verifica con Vicerrectoría tus
        // asignaciones», que a un alumno que llegó aquí por el buscador le
        // suena a que algo está mal con su inscripción. No lo estaba: esta
        // pantalla simplemente no es para él.
        'Esta pantalla es del docente: reúne cómo aprenden los alumnos de '
        'sus grupos. Si eres docente y no ves tus grupos, avísale a '
        'Vicerrectoría.'),
        ),
      ));
      return w;
    }
    w.add(Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _grupos
          .map((g) => Chip(
                backgroundColor: cessumGold.withValues(alpha: 0.15),
                label: Text('${g['programa']} · ${g['generacion']}',
                    style: const TextStyle(fontSize: 11.5)),
              ))
          .toList(),
    ));
    w.add(const SizedBox(height: 10));
    w.add(Row(
      children: [
        _kpi('Alumnos', '$_nAlumnos'),
        const SizedBox(width: 10),
        _kpi('Con test', '$_conTest'),
        const SizedBox(width: 10),
        _kpi('Directivos', '$_directivos'),
      ],
    ));
    w.add(const SizedBox(height: 14));

    // Gráfica agregada
    w.add(const Text('Modos de interacción del grupo',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)));
    w.add(const SizedBox(height: 8));
    if (_conTest == 0) {
      w.add(const Text('Aún no hay alumnos que hayan respondido el test.',
          style: TextStyle(color: Colors.black54)));
    } else {
      w.add(Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: BarrasModos(conteo: _totales),
        ),
      ));
    }

    // Sugerencias
    if (_sugerencias.isNotEmpty) {
      w.add(const SizedBox(height: 14));
      w.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.lightbulb, color: cessumGold),
              SizedBox(width: 8),
              Text('Sugerencias para diseñar tu clase',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            ..._sugerencias.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• $s', style: const TextStyle(fontSize: 13)),
                )),
          ],
        ),
      ));
    }

    // Alumnos
    w.add(const SizedBox(height: 16));
    w.add(const Text('Alumnos del grupo',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)));
    w.add(const SizedBox(height: 6));
    if (_alumnos.isEmpty) {
      w.add(const Text('Sin alumnos con perfil aún.',
          style: TextStyle(color: Colors.black54)));
    } else {
      for (final a in _alumnos) {
        w.add(_alumnoTile(a));
      }
    }
    return w;
  }

  Widget _kpi(String label, String valor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Text(valor,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: cessumRed)),
            Text(label,
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _alumnoTile(Map<String, dynamic> a) {
    final dom = '${a['dominante'] ?? ''}'
        .split(',')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final t = (a['test'] as Map?) ?? {};
    final conteo = {
      for (final k in kModos)
        k: (t[k] is int ? t[k] as int : int.tryParse('${t[k]}') ?? 0)
    };
    final hecho = a['hecho'] == true;
    final datos = [
      if ('${a['puesto'] ?? ''}'.isNotEmpty) '${a['puesto']}',
      if ('${a['institucion'] ?? ''}'.isNotEmpty) '${a['institucion']}',
      if ('${a['anios'] ?? ''}'.isNotEmpty) '${a['anios']} años exp.',
    ].join(' · ');
    return Card(
      color: Colors.white,
      child: ExpansionTile(
        title: Text('${a['nombre']}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          datos.isEmpty ? 'Sin datos de perfil' : datos,
          style: const TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          if ('${a['biografia'] ?? ''}'.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('"${a['biografia']}"',
                    style: const TextStyle(
                        fontStyle: FontStyle.italic, fontSize: 12.5)),
              ),
            ),
          if (!hecho)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Aún no ha respondido el test.',
                  style: TextStyle(color: Colors.black54, fontSize: 12.5)),
            )
          else ...[
            if (dom.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: dom
                      .map((k) => Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                (kModoColor[k] ?? cessumRed).withValues(alpha: 0.15),
                            label: Text(kModoNombre[k] ?? k,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: kModoColor[k] ?? cessumRed,
                                    fontWeight: FontWeight.bold)),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            BarrasModos(conteo: conteo),
          ],
        ],
      ),
    );
  }
}

// SEÑALES ACADÉMICAS (22-sep-2026)
//
// Dos vistas sobre las mismas señales —minutos en Meet, calificaciones y
// chat—: a quién se le está apagando la participación (alumnos) y qué
// materias hunden la permanencia y la aprobación en todas las generaciones
// (materias). Cada alumno trae su puntaje y las razones; el conjunto se
// contrasta con las bajas reales para decir qué tanto acierta.
// Estima y ordena; la decisión la toma una persona.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class SenalesScreen extends StatefulWidget {
  const SenalesScreen({super.key});
  @override
  State<SenalesScreen> createState() => _SenalesScreenState();
}

class _SenalesScreenState extends State<SenalesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  final _cBuscar = TextEditingController();
  String _nivel = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _cBuscar.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool refrescar = false}) async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final actor = ((await SessionStore.validEmail()) ?? '').trim().toLowerCase();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'senales_academicas',
        'actor': actor,
        if (refrescar) 'refrescar': '1',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 150));
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

  Color _colorNivel(String n) => n == 'alto'
      ? cessumRed
      : n == 'medio'
          ? const Color(0xFFB8860B)
          : const Color(0xFF1E7F52);

  @override
  Widget build(BuildContext context) {
    final res = Map<String, dynamic>.from((_d['resumen'] as Map?) ?? {});
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Señales académicas'),
        actions: [
          IconButton(
            tooltip: 'Volver a calcular',
            onPressed: _cargando ? null : () => _cargar(refrescar: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Alumnos${res['alto'] != null ? ' · ${res['alto']} en alto' : ''}'),
            const Tab(text: 'Materias'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: cessumRed),
                  SizedBox(height: 14),
                  Text('Leyendo asistencia, calificaciones y chat…',
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
              : TabBarView(
                  controller: _tabs,
                  children: [_vistaAlumnos(), _vistaMaterias()],
                ),
    );
  }

  Widget _tarjeta(Widget hijo, {Color? borde}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (borde ?? cessumGold).withValues(alpha: 0.30)),
        ),
        child: hijo,
      );

  Widget _contraste() {
    final c = Map<String, dynamic>.from((_d['contraste'] as Map?) ?? {});
    final bajas = (c['bajas'] as num?)?.toInt() ?? 0;
    final bAlto = (c['bajasAlto'] as num?)?.toInt() ?? 0;
    final bMedio = (c['bajasMedio'] as num?)?.toInt() ?? 0;
    final activos = (c['activos'] as num?)?.toInt() ?? 0;
    final aAlto = (c['activosAlto'] as num?)?.toInt() ?? 0;
    String pct(int a, int b) => b == 0 ? '—' : '${(a * 100 / b).round()}%';
    return _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('¿Qué tanto acierta?',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(
        'De $bajas alumnos que sí se dieron de baja, ${pct(bAlto + bMedio, bajas)} '
        'habrían salido en alto o medio con estas mismas señales '
        '(${pct(bAlto, bajas)} en alto). Entre los $activos activos, '
        '${pct(aAlto, activos)} están hoy en alto. Si el primer porcentaje es '
        'mucho mayor que el segundo, las señales separan bien; si son parecidos, '
        'todavía no distinguen y hay que tomarlas solo como orientación.',
        style: const TextStyle(fontSize: 12, height: 1.4),
      ),
    ]));
  }

  Widget _vistaAlumnos() {
    final todos = ((_d['alumnos'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    final q = _cBuscar.text.trim().toLowerCase();
    final lista = todos.where((a) {
      if (_nivel.isNotEmpty && a['nivel'] != _nivel) return false;
      if (q.isEmpty) return true;
      return '${a['nombre']} ${a['matricula']} ${a['programa']} ${a['generacion']}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final res = Map<String, dynamic>.from((_d['resumen'] as Map?) ?? {});
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 30), children: [
      Text(
        'Últimos ${_d['ventanaDias'] ?? 60} días · ${res['activos'] ?? 0} alumnos activos · '
        'medido el ${_d['generado'] ?? ''}'
        '${_d['deCache'] == true ? ' (guardado; el botón de arriba lo rehace)' : ''}',
        style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
      ),
      const SizedBox(height: 10),
      _contraste(),
      TextField(
        controller: _cBuscar,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: 'Buscar por nombre, matrícula, programa o generación',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Row(children: [
        for (final t in const [['', 'Todos'], ['alto', 'Alto'], ['medio', 'Medio'], ['bajo', 'Bajo']])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(t[1]),
              selected: _nivel == t[0],
              onSelected: (_) => setState(() => _nivel = t[0]),
            ),
          ),
        const Spacer(),
        Text('${lista.length}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
      ]),
      const SizedBox(height: 8),
      if (lista.isEmpty)
        _tarjeta(const Text('Nadie con ese filtro.'))
      else
        ...lista.map((a) {
          final nivel = (a['nivel'] ?? 'bajo').toString();
          final color = _colorNivel(nivel);
          final razones = ((a['razones'] as List?) ?? []).map((r) => '$r').toList();
          return _tarjeta(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(nivel.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w800, color: color)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${a['nombre']}',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                Text('${a['matricula']}',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              ]),
              Text('${a['programa']} ${a['generacion']} · ${a['grupo']}',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              const SizedBox(height: 4),
              if (a['sinDatos'] == true)
                const Text('Sin sesiones ni calificaciones registradas: no se puede juzgar.',
                    style: TextStyle(fontSize: 12))
              else if (razones.isEmpty)
                const Text('Sin señales de alarma.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E7F52)))
              else
                ...razones.map((r) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('• $r', style: const TextStyle(fontSize: 12.5, height: 1.3)),
                    )),
              if (a['sinDatos'] != true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Asistencia ${a['asistencia'] ?? '—'}${a['asistencia'] != null ? '%' : ''} '
                    '(${a['asistidas']} de ${a['sesiones']}) · '
                    '${a['minutos']} min por sesión · promedio ${a['promedio'] ?? '—'}',
                    style: TextStyle(fontSize: 11, color: cessumMuted(context)),
                  ),
                ),
            ]),
            borde: color,
          );
        }),
    ]);
  }

  Widget _vistaMaterias() {
    final lista = ((_d['materias'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 30), children: [
      Text(
        'Solo materias con 8 o más calificaciones. Permanencia promedio general: '
        '${_d['permanenciaPromedio'] ?? '—'} min por sesión. Primero las que más hunden.',
        style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
      ),
      const SizedBox(height: 10),
      if (lista.isEmpty)
        _tarjeta(const Text('Todavía no hay materias con datos suficientes.'))
      else
        ...lista.map((m) {
          final senales = ((m['senales'] as List?) ?? []).map((s) => '$s').toList();
          final grave = senales.isNotEmpty;
          return _tarjeta(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m['materia']}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              Text('${m['programa']} · ${m['alumnos']} calificaciones en ${m['generaciones']} generación(es)',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              const SizedBox(height: 4),
              Text(
                'Promedio ${m['promedio']} · ${m['reprobados']}% reprobados'
                '${m['permanencia'] != null ? ' · permanencia ${m['permanencia']} min' : ''}',
                style: const TextStyle(fontSize: 12.5),
              ),
              if (grave)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(senales.join(' · '),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700, color: cessumRed)),
                ),
            ]),
            borde: grave ? cessumRed : const Color(0xFF1E7F52),
          );
        }),
    ]);
  }
}

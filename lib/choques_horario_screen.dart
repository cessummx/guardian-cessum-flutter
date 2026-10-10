import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Detector de choques de horario en la programación académica.
///
/// Muestra cuando un mismo maestro está en dos clases el mismo día con horas
/// que se solapan, o cuando un grupo tiene dos materias encimadas.
class ChoquesHorarioScreen extends StatefulWidget {
  const ChoquesHorarioScreen({super.key});

  @override
  State<ChoquesHorarioScreen> createState() => _ChoquesHorarioScreenState();
}

class _ChoquesHorarioScreenState extends State<ChoquesHorarioScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  List<Map<String, dynamic>> _choques = [];
  List<Map<String, dynamic>> _huecos = [];
  bool _cargando = true;
  String? _error;

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
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'asignacion_choques'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final lista = (data['choques'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final huecos = (data['huecos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _choques = lista;
        _huecos = huecos;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo revisar la programación. Revisa tu conexión.';
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
        title: const Text('Choques de horario'),
        actions: [
          IconButton(
            tooltip: 'Volver a revisar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        color: cessumRed,
        child: _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonCard(),
          SizedBox(height: 12),
          SkeletonCard(),
          SizedBox(height: 12),
          SkeletonCard(),
        ],
      );
    }
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        CessumEmptyState(
          title: 'No se pudo revisar',
          subtitle: _error,
          icon: Icons.wifi_off_rounded,
          action: FilledButton.icon(
            onPressed: _cargar,
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ]);
    }
    if (_choques.isEmpty && _huecos.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        CessumEmptyState(
          title: 'Todo en orden',
          subtitle:
              'No se encontraron choques ni huecos en la programación activa.',
          icon: Icons.check_circle_outline,
        ),
      ]);
    }

    final items = <Widget>[_resumen(), const SizedBox(height: 12)];
    for (final c in _choques) {
      items.add(_tarjeta(c));
      items.add(const SizedBox(height: 12));
    }
    if (_huecos.isNotEmpty) {
      items.add(_encabezadoHuecos());
      items.add(const SizedBox(height: 12));
      for (final h in _huecos) {
        items.add(_tarjetaHueco(h));
        items.add(const SizedBox(height: 12));
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: items,
    );
  }

  Widget _encabezadoHuecos() {
    return Row(
      children: [
        Icon(Icons.report_gmailerrorred_outlined, size: 20, color: cessumGold),
        const SizedBox(width: 8),
        Text('Huecos en la programación (${_huecos.length})',
            style: CessumType.heading(15, color: cessumInk(context))),
      ],
    );
  }

  Widget _tarjetaHueco(Map<String, dynamic> h) {
    final isDark = cessumIsDark(context);
    final motivo = (h['motivo'] ?? '').toString();
    final materia = (h['materia'] ?? '(sin materia)').toString();
    final grupo = (h['grupo'] ?? '').toString();
    final prog = (h['programa'] ?? '').toString();
    final gen = (h['generacion'] ?? '').toString();
    final dia = (h['dia'] ?? '').toString();
    final hora = (h['hora'] ?? '').toString();
    final horario = [dia, hora].where((s) => s.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cessumGold.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(materia,
                    style: CessumType.heading(14, color: cessumInk(context))),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(motivo,
                    style: CessumType.label(11, color: cessumGold)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (prog.isNotEmpty) prog,
              if (grupo.isNotEmpty) 'Grupo $grupo',
              if (gen.isNotEmpty) 'Gen. $gen',
            ].join(' · '),
            style: CessumType.body(12, color: cessumMuted(context)),
          ),
          if (horario.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(horario,
                style: CessumType.body(11, color: cessumFaint(context))),
          ],
        ],
      ),
    );
  }

  Widget _resumen() {
    final maestros = _choques.where((c) => c['tipo'] == 'maestro').length;
    final grupos = _choques.where((c) => c['tipo'] == 'grupo').length;
    final hayChoques = _choques.isNotEmpty;
    final color = hayChoques ? cessumRed : cessumGold;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    hayChoques
                        ? '${_choques.length} choque(s) detectado(s)'
                        : 'Sin choques de horario',
                    style: CessumType.heading(16, color: cessumInk(context))),
                const SizedBox(height: 2),
                Text(
                    hayChoques
                        ? '$maestros de maestro · $grupos de grupo · ${_huecos.length} hueco(s)'
                        : '${_huecos.length} hueco(s) por completar',
                    style: CessumType.body(13, color: cessumMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> c) {
    final isDark = cessumIsDark(context);
    final tipo = (c['tipo'] ?? '').toString();
    final dia = (c['dia'] ?? '').toString();
    final a = Map<String, dynamic>.from(c['a'] as Map? ?? const {});
    final b = Map<String, dynamic>.from(c['b'] as Map? ?? const {});
    final esMaestro = tipo == 'maestro';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(esMaestro ? Icons.person : Icons.groups_2,
                  size: 18, color: cessumRed),
              const SizedBox(width: 6),
              Text(
                esMaestro ? 'Maestro encimado' : 'Grupo encimado',
                style: CessumType.heading(14, color: cessumInk(context)),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(dia,
                    style: CessumType.label(11, color: cessumGold)),
              ),
            ],
          ),
          if (esMaestro && (a['docente'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text((a['docente'] ?? '').toString(),
                style: CessumType.body(13, color: cessumMuted(context))),
          ],
          const SizedBox(height: 10),
          _fila(a),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('se encima con',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          ),
          _fila(b),
        ],
      ),
    );
  }

  Widget _fila(Map<String, dynamic> x) {
    final materia = (x['materia'] ?? '(sin materia)').toString();
    final hora = (x['hora'] ?? '').toString();
    final grupo = (x['grupo'] ?? '').toString();
    final prog = (x['programa'] ?? '').toString();
    final gen = (x['generacion'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumRed.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(materia,
                    style: CessumType.heading(13, color: cessumInk(context))),
              ),
              Text(hora,
                  style: CessumType.label(12, color: _verde)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (prog.isNotEmpty) prog,
              if (grupo.isNotEmpty) 'Grupo $grupo',
              if (gen.isNotEmpty) 'Gen. $gen',
            ].join(' · '),
            style: CessumType.body(11, color: cessumMuted(context)),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Ranking de juegos: Top 10 de estudiantes por mayor puntaje, por juego.
class RankingJuegosScreen extends StatefulWidget {
  final StudentProfile perfil;
  const RankingJuegosScreen({super.key, required this.perfil});

  @override
  State<RankingJuegosScreen> createState() => _RankingJuegosScreenState();
}

class _RankingJuegosScreenState extends State<RankingJuegosScreen> {
  // Las claves deben coincidir EXACTO con las que mandan los juegos.
  static const List<String> _juegos = [
    'MAASO Salta',
    'Memorama del Mayo',
    'Atrapa al MAASO',
    'El Camino del MAASO',
  ];

  String _juego = _juegos.first;
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _top = [];

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
      final uri = Uri.parse('$guardianUrl?accion=ranking_top'
          '&juego=${Uri.encodeComponent(_juego)}&limite=10');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _top = ((data['top'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el ranking. Intenta de nuevo.';
      });
    }
  }

  String _medalla(int pos) {
    if (pos == 1) return '🥇';
    if (pos == 2) return '🥈';
    if (pos == 3) return '🥉';
    return '$pos';
  }

  @override
  Widget build(BuildContext context) {
    final miMat = widget.perfil.matricula.trim();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Ranking · Top 10'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: Column(
        children: [
          // Selector de juego.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(
              spacing: 8,
              children: _juegos.map((j) {
                final sel = j == _juego;
                return ChoiceChip(
                  label: Text(j),
                  selected: sel,
                  selectedColor: cessumGold.withValues(alpha: 0.25),
                  onSelected: (_) {
                    if (j == _juego) return;
                    setState(() => _juego = j);
                    _cargar();
                  },
                );
              }).toList(),
            ),
          ),
          Expanded(child: _cuerpo(miMat)),
        ],
      ),
    );
  }

  Widget _cuerpo(String miMat) {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    if (_top.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '¡Aún no hay puntajes en "$_juego"!\nSé el primero en aparecer.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumMuted(context)),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: _top.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _top[i];
        final pos = (r['pos'] is int)
            ? r['pos'] as int
            : int.tryParse('${r['pos']}') ?? (i + 1);
        final nombre = (r['nombre'] ?? '').toString();
        final pts = (r['puntaje'] ?? 0).toString();
        final esYo = miMat.isNotEmpty && '${r['matricula']}'.trim() == miMat;
        return Container(
          decoration: BoxDecoration(
            color: esYo
                ? cessumGold.withValues(alpha: 0.16)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: esYo ? Border.all(color: cessumGold, width: 1.4) : null,
          ),
          child: ListTile(
            leading: SizedBox(
              width: 36,
              child: Center(
                child: Text(
                  _medalla(pos),
                  style: TextStyle(
                    fontSize: pos <= 3 ? 24 : 16,
                    fontWeight: FontWeight.w700,
                    color: cessumMuted(context),
                  ),
                ),
              ),
            ),
            title: Text(
              nombre.isEmpty ? 'Estudiante' : nombre,
              style: TextStyle(
                fontWeight: esYo ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            subtitle: esYo ? const Text('¡Tú!') : null,
            trailing: Text(
              pts,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: cessumRed,
              ),
            ),
          ),
        );
      },
    );
  }
}

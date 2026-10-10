import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';

/// Diagnóstico de calificaciones (pantalla nativa). Corre diag_calif, muestra
/// duplicados, notas inválidas, materias fuera del plan y matrículas huérfanas,
/// y permite limpiar (borrar filas NO validadas) por materia con vista previa.
class DiagCalifScreen extends StatefulWidget {
  const DiagCalifScreen({super.key});

  @override
  State<DiagCalifScreen> createState() => _DiagCalifScreenState();
}

class _DiagCalifScreenState extends State<DiagCalifScreen> {
  static const String _guardianUrl = 'https://app.cessum.mx/guardian.php';
  static const Color _hueso = Color(0xFFF5F1E8);

  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _duplicados = [];
  List<Map<String, dynamic>> _invalidas = [];
  List<Map<String, dynamic>> _noEnPlan = [];
  List<Map<String, dynamic>> _huerfanas = [];

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
      final uri = Uri.parse(_guardianUrl)
          .replace(queryParameters: {'accion': 'diag_calif'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) {
        throw Exception(j['error']?.toString() ?? 'Respuesta inválida');
      }
      List<Map<String, dynamic>> lst(String k) => (j[k] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _resumen = Map<String, dynamic>.from(j['resumen'] as Map? ?? {});
        _duplicados = lst('duplicados');
        _invalidas = lst('invalidas');
        _noEnPlan = lst('materiaNoEnPlan');
        _huerfanas = lst('matriculaHuerfana');
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  // Agrupa por programa|generacion|grupo|materia|clave y regresa una lista de
  // {reg base, n}.
  List<Map<String, dynamic>> _agrupar(List<Map<String, dynamic>> filas) {
    final mapa = <String, Map<String, dynamic>>{};
    for (final f in filas) {
      final k = [f['programa'], f['generacion'], f['grupo'], f['materia'], f['clave']]
          .map((e) => (e ?? '').toString())
          .join('|');
      if (mapa[k] == null) {
        mapa[k] = {...f, 'n': 0};
      }
      mapa[k]!['n'] = (mapa[k]!['n'] as int) + 1;
    }
    final l = mapa.values.toList();
    l.sort((a, b) => (b['n'] as int).compareTo(a['n'] as int));
    return l;
  }

  Future<void> _limpiar(Map<String, dynamic> g) async {
    final programa = (g['programa'] ?? '').toString();
    final generacion = (g['generacion'] ?? '').toString();
    final grupo = (g['grupo'] ?? '').toString();
    final clave = (g['clave'] ?? '').toString();
    final materia = (g['materia'] ?? '').toString();

    Map<String, dynamic> params(bool aplicar) => {
          'accion': 'limpiar_acta',
          'programa': programa,
          'generacion': generacion,
          'grupo': grupo,
          if (clave.isNotEmpty) 'clave': clave else 'materia': materia,
          if (aplicar) 'aplicar': '1',
        };

    // Vista previa
    int? candidatas;
    int validadas = 0;
    try {
      final uri =
          Uri.parse(_guardianUrl).replace(queryParameters: params(false));
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso('No se pudo previsualizar: ${data['error'] ?? ''}');
        return;
      }
      candidatas = (data['totalCandidatas'] ?? 0) as int;
      validadas = (data['validadasIntactas'] ?? 0) as int;
    } catch (e) {
      _aviso('Error: $e');
      return;
    }
    if (!mounted) return;
    if (candidatas == 0) {
      _aviso('No hay filas NO validadas para borrar en esta materia.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar materia'),
        content: Text(
          'Se borrarán $candidatas fila(s) NO validadas de:\n\n'
          '"$materia"\n$programa · Gen. $generacion · Grupo $grupo\n\n'
          '${validadas > 0 ? 'Se respetan $validadas validada(s).\n\n' : ''}'
          'Esta acción no se puede deshacer. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
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
    try {
      final uri =
          Uri.parse(_guardianUrl).replace(queryParameters: params(true));
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _aviso('Borradas ${data['borradas'] ?? 0} fila(s). Refrescando…');
        _cargar();
      } else {
        _aviso('No se pudo: ${data['error'] ?? ''}');
      }
    } catch (e) {
      _aviso('Error: $e');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Diagnóstico de calificaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _vistaError() : _vista()),
    );
  }

  Widget _vistaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.black38),
              const SizedBox(height: 12),
              Text('No se pudo cargar el diagnóstico.\n${_error ?? ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: _cargar,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );

  Widget _chip(Color c, String txt) => Container(
        margin: const EdgeInsets.only(right: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14)),
        child: Text(txt,
            style:
                TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
      );

  Widget _vista() {
    final filas = (_resumen['filas'] ?? 0);
    final dupG = _agrupar(_duplicados);
    final planG = _agrupar(_noEnPlan);
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Text('Revisadas $filas fila(s) de calificaciones.',
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 8),
        Wrap(children: [
          _chip(cessumRed, 'Duplicados ${_resumen['duplicados'] ?? 0}'),
          _chip(cessumGold, 'Inválidas ${_resumen['invalidas'] ?? 0}'),
          _chip(cessumRed, 'Fuera de plan ${_resumen['materiaNoEnPlan'] ?? 0}'),
          _chip(cessumGold,
              'Matrícula huérfana ${_resumen['matriculaHuerfana'] ?? 0}'),
        ]),
        const SizedBox(height: 10),
        _seccionLimpiable('Duplicados (mismo alumno y materia)', dupG),
        _seccionLimpiable('Materia con calificación FUERA del plan', planG),
        _seccionInfo('Notas inválidas (no numéricas o fuera de 6–10)',
            _invalidas),
        _seccionInfo('Matrículas que no están en el padrón', _huerfanas),
      ],
    );
  }

  Widget _seccionLimpiable(String titulo, List<Map<String, dynamic>> grupos) {
    if (grupos.isEmpty) {
      return _tarjetaVacia(titulo);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(titulo,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${grupos.length} materia(s) afectada(s)'),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: grupos.map((g) {
          return ListTile(
            dense: true,
            title: Text((g['materia'] ?? '').toString(),
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              '${g['programa']} · Gen. ${g['generacion']} · Grupo ${g['grupo']} · ${g['n']} fila(s)',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: TextButton.icon(
              onPressed: () => _limpiar(g),
              style: TextButton.styleFrom(foregroundColor: cessumRed),
              icon: const Icon(Icons.cleaning_services, size: 18),
              label: const Text('Limpiar'),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _seccionInfo(String titulo, List<Map<String, dynamic>> filas) {
    if (filas.isEmpty) {
      return _tarjetaVacia(titulo);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(titulo,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('${filas.length} registro(s) · revisar a mano'),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: filas.map((f) {
          return ListTile(
            dense: true,
            title: Text(
                '${f['nombre'] ?? ''} (${f['matricula'] ?? ''})',
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              '${f['materia'] ?? ''} · nota: ${f['calif'] ?? ''} · fila ${f['fila'] ?? ''}',
              style: const TextStyle(fontSize: 12),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _tarjetaVacia(String titulo) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading:
              const Icon(Icons.check_circle, color: Color(0xFF1E8E3E)),
          title: Text(titulo,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: const Text('Sin problemas ✔'),
        ),
      );
}

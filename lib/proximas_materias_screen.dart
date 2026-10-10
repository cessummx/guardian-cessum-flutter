import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Portal del alumno: PRÓXIMAS MATERIAS. Muestra las materias del siguiente
/// periodo/materia que ya están programadas a futuro para su grupo, con el
/// docente confirmado (si ya aceptó la invitación) o "por confirmar". Le da al
/// estudiante una prospectiva de lo que sigue en su plan.
class ProximasMateriasScreen extends StatefulWidget {
  final String matricula;

  const ProximasMateriasScreen({super.key, required this.matricula});

  @override
  State<ProximasMateriasScreen> createState() => _ProximasMateriasScreenState();
}

const Color _morado = Color(0xFF6A1B9A);
const Color _verdeOk = Color(0xFF1E8E3E);

class _ProximasMateriasScreenState extends State<ProximasMateriasScreen> {
  List<Map<String, dynamic>> _materias = [];
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
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'proximas_materias',
        'matricula': widget.matricula,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() => _error = (data['error'] ?? 'Error').toString());
      } else {
        setState(() {
          _materias = ((data['materias'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo cargar.');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _fecha(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct',
      'nov', 'dic'
    ];
    return '${d.day} ${meses[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _morado,
        foregroundColor: Colors.white,
        title: const Text('Próximas materias'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _materias.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_note,
                                size: 56, color: cessumFaint(context)),
                            const SizedBox(height: 12),
                            Text(
                              'Aún no hay materias programadas para tu próximo '
                              'periodo. Cuando la coordinación las programe, '
                              'aparecerán aquí.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cessumMuted(context)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: _morado.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  color: _morado, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Estas son las materias que siguen en tu plan, '
                                  'ya programadas por la coordinación.',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: cessumMuted(context)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._materias.map(_tarjeta),
                      ],
                    ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> m) {
    final confirmado = m['docenteConfirmado'] == true;
    final inicio = (m['inicio'] ?? '').toString();
    final termino = (m['termino'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m['materia']}',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person,
                    size: 16, color: confirmado ? _verdeOk : cessumGold),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (m['docente'] ?? '').toString().isEmpty
                        ? 'Docente por asignar'
                        : '${m['docente']}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (confirmado ? _verdeOk : cessumGold)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    confirmado ? 'Docente confirmado' : 'Por confirmar',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: confirmado ? _verdeOk : cessumGold),
                  ),
                ),
              ],
            ),
            if (inicio.isNotEmpty || termino.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 14, color: cessumFaint(context)),
                  const SizedBox(width: 6),
                  Text(
                    inicio.isNotEmpty && termino.isNotEmpty
                        ? '${_fecha(inicio)} al ${_fecha(termino)}'
                        : (inicio.isNotEmpty
                            ? 'Desde ${_fecha(inicio)}'
                            : 'Hasta ${_fecha(termino)}'),
                    style:
                        TextStyle(fontSize: 12, color: cessumMuted(context)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

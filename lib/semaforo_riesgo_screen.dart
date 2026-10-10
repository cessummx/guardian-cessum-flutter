import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Semáforo de riesgo de deserción (panel de administración).
/// Consume la acción 'riesgo_desercion' del Guardián y permite enviar
/// el correo de acompañamiento a los alumnos de riesgo alto.
class SemaforoRiesgoScreen extends StatefulWidget {
  const SemaforoRiesgoScreen({super.key});

  @override
  State<SemaforoRiesgoScreen> createState() => _SemaforoRiesgoScreenState();
}

class _SemaforoRiesgoScreenState extends State<SemaforoRiesgoScreen> {
  static const Color verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _lista = [];
  int _alto = 0, _medio = 0, _bajo = 0;
  String _filtro = 'Alto'; // Todos | Alto | Medio | Bajo
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final actor = await SessionStore.validEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'riesgo_desercion',
        'actor': actor,
      });
      final resp =
          await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo cargar');
      }
      final lista = (data['lista'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final conteo = Map<String, dynamic>.from(data['conteo'] as Map? ?? {});
      if (!mounted) return;
      setState(() {
        _lista = lista;
        _alto = (conteo['alto'] ?? 0) as int;
        _medio = (conteo['medio'] ?? 0) as int;
        _bajo = (conteo['bajo'] ?? 0) as int;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el semáforo de riesgo.';
      });
    }
  }

  Future<void> _enviarAcompanamiento() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar acompañamiento'),
        content: Text(
            'Se enviará un correo cálido de apoyo a los alumnos en riesgo ALTO '
            '($_alto). El mensaje no es alarmante. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _enviando = true);
    try {
      final actor = await SessionStore.validEmail() ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'acompanamiento_enviar',
                'confirmar': 'ENVIAR', // (22-sep) ya se confirmó en el diálogo
                'actor': actor,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _enviando = false);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: verde,
          content: Text(
              'Acompañamiento enviado a ${data['enviados'] ?? 0} alumno(s).'),
        ));
      } else {
        throw Exception(data['error'] ?? 'No se pudo');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: cessumRed,
        content: Text('No se pudo enviar el acompañamiento.'),
      ));
    }
  }

  Color _colorNivel(String n) {
    switch (n) {
      case 'Alto':
        return cessumRed;
      case 'Medio':
        return cessumGold;
      default:
        return verde;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrada = _filtro == 'Todos'
        ? _lista
        : _lista.where((a) => (a['nivel'] ?? '') == _filtro).toList();

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Semáforo de riesgo'),
        actions: [
          IconButton(
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54)),
                  ),
                )
              : Column(
                  children: [
                    _resumen(),
                    _filtros(),
                    Expanded(
                      child: filtrada.isEmpty
                          ? const Center(
                              child: Text('Sin alumnos en este nivel.',
                                  style: TextStyle(color: Colors.black45)))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                              itemCount: filtrada.length,
                              itemBuilder: (_, i) => _tarjeta(filtrada[i]),
                            ),
                    ),
                  ],
                ),
      floatingActionButton: (_cargando || _error.isNotEmpty || _alto == 0)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              onPressed: _enviando ? null : _enviarAcompanamiento,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.favorite),
              label: Text(_enviando
                  ? 'Enviando...'
                  : 'Acompañar a $_alto en riesgo alto'),
            ),
    );
  }

  Widget _resumen() {
    Widget card(String et, int n, Color c) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(6),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text('$n',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
                Text(et,
                    style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
      child: Row(
        children: [
          card('Riesgo alto', _alto, cessumRed),
          card('Riesgo medio', _medio, cessumGold),
          card('Riesgo bajo', _bajo, verde),
        ],
      ),
    );
  }

  Widget _filtros() {
    final opciones = ['Alto', 'Medio', 'Bajo', 'Todos'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: opciones.map((o) {
          final sel = _filtro == o;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(o),
              selected: sel,
              selectedColor: cessumRed,
              labelStyle: TextStyle(
                  color: sel ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => _filtro = o),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final nivel = (a['nivel'] ?? '').toString();
    final c = _colorNivel(nivel);
    final dias = (a['diasSinConexion'] ?? '').toString();
    final rep = (a['reprobadas'] ?? 0);
    final sin = (a['sinCalificar'] ?? 0);
    final diasTxt = dias == 'nunca'
        ? 'Nunca ha entrado'
        : 'Sin conexión: $dias día(s)';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 5, right: 10),
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((a['nombre'] ?? '').toString(),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    '${a['matricula'] ?? ''} · ${a['programa'] ?? ''}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _mini(Icons.wifi_off, diasTxt),
                      if ((rep as num) > 0)
                        _mini(Icons.cancel_outlined, 'Reprobadas: $rep'),
                      if ((sin as num) > 0)
                        _mini(Icons.hourglass_empty, 'Sin calificar: $sin'),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(nivel,
                  style: TextStyle(
                      color: c, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(IconData ic, String t) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ic, size: 13, color: Colors.black45),
        const SizedBox(width: 3),
        Text(t, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

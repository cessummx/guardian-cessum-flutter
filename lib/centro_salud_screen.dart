import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'diag_calif_screen.dart';

/// Centro de Salud de Datos: un solo tablero que corre el diagnóstico
/// consolidado (salud_academica) y ofrece los arreglos seguros (con vista
/// previa) desde un mismo lugar.
class CentroSaludScreen extends StatefulWidget {
  const CentroSaludScreen({super.key});

  @override
  State<CentroSaludScreen> createState() => _CentroSaludScreenState();
}

class _CentroSaludScreenState extends State<CentroSaludScreen> {
  static const String _guardianUrl = 'https://app.cessum.mx/guardian.php';
  static const Color _hueso = Color(0xFFF5F1E8);
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _data = {};

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
          .replace(queryParameters: {'accion': 'salud_academica'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) {
        throw Exception(j['error']?.toString() ?? 'Respuesta inválida');
      }
      setState(() {
        _data = j;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  int _n(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  Map<String, dynamic> _obj(String k) =>
      _data[k] is Map ? Map<String, dynamic>.from(_data[k] as Map) : {};

  // Corre una acción con vista previa -> confirmación -> aplicar. Usa el campo
  // 'nota' que devuelven las herramientas para describir el cambio.
  Future<void> _correr(String accion, String titulo,
      {Map<String, String> params = const {}}) async {
    // Vista previa
    Map<String, dynamic> prev;
    try {
      final uri = Uri.parse(_guardianUrl)
          .replace(queryParameters: {'accion': accion, ...params});
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      prev = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      _aviso('Error: $e');
      return;
    }
    if (prev['ok'] != true) {
      _aviso('No se pudo: ${prev['error'] ?? ''}');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text('${prev['nota'] ?? 'Se aplicará el arreglo.'}\n\n'
            '¿Aplicar los cambios?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final uri = Uri.parse(_guardianUrl).replace(
          queryParameters: {'accion': accion, ...params, 'aplicar': '1'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _aviso(data['ok'] == true
          ? (data['nota']?.toString() ?? 'Listo.')
          : 'No se pudo: ${data['error'] ?? ''}');
      _cargar();
    } catch (e) {
      _aviso('Error: $e');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Centro de Salud'),
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

  Widget _metric(String label, int valor) {
    final c = valor > 0 ? cessumRed : _verde;
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14)),
      child: Text('$label: $valor',
          style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _tarjeta(String titulo, IconData icono, List<Widget> metrics,
      {Widget? accion}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icono, color: cessumRed, size: 20),
              const SizedBox(width: 8),
              Text(titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ]),
            const SizedBox(height: 8),
            Wrap(children: metrics),
            if (accion != null) ...[
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: accion),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vista() {
    final cal = _obj('calificaciones');
    final asig = _obj('asignaciones');
    final pad = _obj('padron');
    final aulas = _obj('aulas');
    final choques = _n(_data['choques']);

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        const Text('Radiografía de las bases (toca una tarjeta para arreglar).',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 10),

        _tarjeta('Calificaciones', Icons.grading, [
          _metric('Duplicados', _n(cal['duplicados'])),
          _metric('Inválidas', _n(cal['invalidas'])),
          _metric('Fuera de plan', _n(cal['materiaNoEnPlan'])),
          _metric('Huérfanas', _n(cal['matriculaHuerfana'])),
        ],
            accion: TextButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DiagCalifScreen())),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Abrir y limpiar'),
            )),

        _tarjeta('Asignaciones', Icons.event_note, [
          _metric('Sin clave', _n(asig['sinClave'])),
          _metric('Docente sin correo', _n(asig['docenteSinCorreo'])),
          _metric('Sin vigencia', _n(asig['sinVigencia'])),
          _metric('Sin día/hora', _n(asig['sinDiaHora'])),
        ],
            accion: _n(asig['docenteSinCorreo']) > 0
                ? TextButton.icon(
                    onPressed: () => _correr('arreglar_docente_correo',
                        'Autocompletar correos de docentes'),
                    style: TextButton.styleFrom(foregroundColor: cessumRed),
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text('Autocompletar correos'),
                  )
                : null),

        _tarjeta('Padrón', Icons.groups, [
          _metric('Sin correo', _n(pad['sinCorreo'])),
          _metric('Matrícula duplicada', _n(pad['matriculaDuplicada'])),
          _metric('Grupos pelones', _n(pad['grupoPelon'])),
          _metric('Gen. rara', _n(pad['generacionRara'])),
        ],
            accion: TextButton.icon(
              onPressed: () =>
                  _correr('limpiar_padron', 'Normalizar generaciones y grupos'),
              style: TextButton.styleFrom(foregroundColor: cessumRed),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Normalizar'),
            )),

        _tarjeta('Programación', Icons.calendar_month, [
          _metric('Choques', choques),
        ]),

        _tarjeta('Aulas (Moodle)', Icons.school, [
          _metric('Sin Aula', _n(aulas['sinAula'])),
          _metric('Sin Meet', _n(aulas['sinMeet'])),
        ]),

        const SizedBox(height: 6),
        const Text('Limpiezas seguras (vista previa antes de aplicar):',
            style: TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.cleaning_services, color: cessumRed),
              title: const Text('Deduplicar calificaciones',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Conserva la mejor por alumno/materia y borra las sobrantes.',
                  style: TextStyle(fontSize: 12)),
              onTap: () => _correr('dedup_calif', 'Deduplicar calificaciones'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.auto_fix_high, color: cessumRed),
              title: const Text('Autocompletar correos de docentes',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Rellena el correo faltante buscando por nombre en el padrón.',
                  style: TextStyle(fontSize: 12)),
              onTap: () => _correr(
                  'arreglar_docente_correo', 'Autocompletar correos de docentes'),
            ),
          ]),
        ),
      ],
    );
  }
}

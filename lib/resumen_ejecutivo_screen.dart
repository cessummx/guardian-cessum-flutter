import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'salud_datos_screen.dart';
import 'moodle_admin_screen.dart';
import 'avance_captura_screen.dart';

/// Resumen ejecutivo: tablero de focos de atención para administración.
/// Carga en paralelo la salud de datos y los reportes del Aula, y permite
/// entrar al detalle de cada indicador con un toque.
class ResumenEjecutivoScreen extends StatefulWidget {
  const ResumenEjecutivoScreen({super.key});

  @override
  State<ResumenEjecutivoScreen> createState() => _ResumenEjecutivoScreenState();
}

class _ResumenEjecutivoScreenState extends State<ResumenEjecutivoScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  // Salud de datos
  bool _saludCargando = true;
  bool _saludError = false;
  int _problemas = 0;

  // Inactivos en el Aula (21 días)
  bool _inactCargando = true;
  bool _inactError = false;
  int _inactivos = 0;

  // Conciliación padrón <-> Aula
  bool _concCargando = true;
  bool _concError = false;
  int _faltan = 0;
  int _bajas = 0;

  // Captura de calificaciones pendiente
  bool _capturaCargando = true;
  bool _capturaError = false;
  int _capturaPendiente = 0;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  void _cargarTodo() {
    // Lanzadas en paralelo: cada tarjeta se actualiza cuando llega su dato.
    _cargarSalud();
    _cargarInactivos();
    _cargarConciliacion();
    _cargarCaptura();
  }

  Future<void> _cargarSalud() async {
    setState(() {
      _saludCargando = true;
      _saludError = false;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=salud_datos'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      final resumen = (data['resumen'] as Map?) ?? {};
      if (!mounted) return;
      setState(() {
        _problemas = (resumen['problemas'] ?? 0) as int;
        _saludCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saludCargando = false;
        _saludError = true;
      });
    }
  }

  Future<void> _cargarInactivos() async {
    setState(() {
      _inactCargando = true;
      _inactError = false;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=moodle_inactivos&dias=21'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      if (!mounted) return;
      setState(() {
        _inactivos = (data['total'] ?? 0) as int;
        _inactCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inactCargando = false;
        _inactError = true;
      });
    }
  }

  Future<void> _cargarConciliacion() async {
    setState(() {
      _concCargando = true;
      _concError = false;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=moodle_conciliacion'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      final resumen = (data['resumen'] as Map?) ?? {};
      if (!mounted) return;
      setState(() {
        _faltan = (resumen['faltanEnAula'] ?? 0) as int;
        _bajas = (resumen['bajasActivasEnAula'] ?? 0) as int;
        _concCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _concCargando = false;
        _concError = true;
      });
    }
  }

  Future<void> _cargarCaptura() async {
    setState(() {
      _capturaCargando = true;
      _capturaError = false;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=avance_captura'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      final resumen = (data['resumen'] as Map?) ?? {};
      final parciales = (resumen['parciales'] ?? 0) as int;
      final sinIniciar = (resumen['sinIniciar'] ?? 0) as int;
      if (!mounted) return;
      setState(() {
        _capturaPendiente = parciales + sinIniciar;
        _capturaCargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capturaCargando = false;
        _capturaError = true;
      });
    }
  }

  void _irCaptura() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AvanceCapturaScreen()));
  }

  void _irSalud() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const SaludDatosScreen()));
  }

  void _irMoodle() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const MoodleAdminScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Resumen ejecutivo',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargarTodo, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        color: cessumRed,
        onRefresh: () async => _cargarTodo(),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Padding(
              padding: EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                'Focos de atención de hoy. Toca una tarjeta para ver el detalle.',
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
              ),
            ),
            _tarjeta(
              titulo: 'Problemas de datos',
              descripcion: 'Duplicados, grupos sin docente, generaciones, etc.',
              cargando: _saludCargando,
              error: _saludError,
              valor: _problemas,
              colorBueno: _problemas == 0,
              icono: Icons.health_and_safety,
              onTap: _irSalud,
            ),
            _tarjeta(
              titulo: 'Captura de calificaciones pendiente',
              descripcion: 'Grupos parciales o sin iniciar por los docentes.',
              cargando: _capturaCargando,
              error: _capturaError,
              valor: _capturaPendiente,
              colorBueno: _capturaPendiente == 0,
              icono: Icons.pending_actions,
              onTap: _irCaptura,
            ),
            _tarjeta(
              titulo: 'Alumnos inactivos en el Aula',
              descripcion: 'Sin entrar a Moodle hace 21 días o más.',
              cargando: _inactCargando,
              error: _inactError,
              valor: _inactivos,
              colorBueno: _inactivos == 0,
              icono: Icons.timer_off,
              onTap: _irMoodle,
            ),
            _tarjeta(
              titulo: 'Faltan inscribir en el Aula',
              descripcion: 'Alumnos vigentes sin cuenta en Moodle.',
              cargando: _concCargando,
              error: _concError,
              valor: _faltan,
              colorBueno: _faltan == 0,
              icono: Icons.person_add_disabled,
              onTap: _irMoodle,
            ),
            _tarjeta(
              titulo: 'Bajas activas en el Aula',
              descripcion: 'Dados de baja que siguen activos en Moodle.',
              cargando: _concCargando,
              error: _concError,
              valor: _bajas,
              colorBueno: _bajas == 0,
              icono: Icons.no_accounts,
              onTap: _irMoodle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta({
    required String titulo,
    required String descripcion,
    required bool cargando,
    required bool error,
    required int valor,
    required bool colorBueno,
    required IconData icono,
    required VoidCallback onTap,
  }) {
    final color = error
        ? cessumFaint(context)
        : (colorBueno ? _verde : cessumRed);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(descripcion,
                        style: TextStyle(
                            fontSize: 11.5, color: cessumMuted(context))),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 56,
                child: Center(
                  child: cargando
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: cessumRed))
                      : error
                          ? Icon(Icons.cloud_off,
                              color: cessumFaint(context), size: 24)
                          : Text(
                              '$valor',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: color),
                            ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}

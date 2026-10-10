import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'mi_captura_screen.dart';
import 'mis_clases_screen.dart';
import 'mis_materias_screen.dart';
import 'banners_semanales_screen.dart';
import 'mis_pendientes_card.dart';
import 'mi_horario_docente_screen.dart';
import 'avisos_docente_screen.dart';
import 'tareas_docente_screen.dart';
import 'tutorias_docente_screen.dart';
import 'recursos_docente_screen.dart';
import 'riesgo_docente_screen.dart';
import 'tablero_docente_screen.dart';
import 'mis_invitaciones_docente_screen.dart';
import 'mis_alumnos_docente_screen.dart';
import 'mis_actas_docente_screen.dart';

/// Mi panel (docente): centro de mando con el resumen de captura y accesos
/// rápidos a TODO lo del docente — clases, materias, horario, tablero,
/// alumnos en riesgo, tareas, tutorías, avisos y recursos. Conecta las
/// pantallas que ya existen en la app; no duplica funcionalidad.
class MiPanelDocenteScreen extends StatefulWidget {
  const MiPanelDocenteScreen({super.key});

  @override
  State<MiPanelDocenteScreen> createState() => _MiPanelDocenteScreenState();
}

class _MiPanelDocenteScreenState extends State<MiPanelDocenteScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  bool _error = false;
  int _grupos = 0;
  int _completas = 0;
  int _pendientes = 0;
  String _correo = '';
  DateTime? _ultimaCarga;

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : Colors.black87;
  Color get _textoSuave => cessumMuted(context);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      _correo = correo;
      if (correo.isEmpty) {
        setState(() {
          _cargando = false;
          _error = true;
        });
        return;
      }
      final uri = Uri.parse('$guardianUrl?accion=panel_docente'
          '&correo=${Uri.encodeComponent(correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      if (!mounted) return;
      setState(() {
        _grupos = (data['grupos'] ?? 0) as int;
        _completas = (data['capturaCompletas'] ?? 0) as int;
        _pendientes = (data['capturaPendientes'] ?? 0) as int;
        _cargando = false;
        _ultimaCarga = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
      });
    }
  }

  void _abrir(Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
  }

  Future<void> _enviarResumen() async {
    if (_correo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo identificar tu correo.'),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Enviando tu resumen…'),
    ));
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(
                  {'accion': 'mi_resumen_enviar', 'correo': _correo}))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data['ok'] == true
            ? 'Te enviamos tu resumen a $_correo.'
            : (data['error'] ?? 'No se pudo enviar el resumen.').toString()),
        backgroundColor:
            data['ok'] == true ? const Color(0xFF1E8E3E) : cessumRed,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al enviar: $e'),
        backgroundColor: cessumRed,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi panel',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        color: cessumRed,
        onRefresh: () async {
          await _cargar();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          children: [
            _encabezado(),
            if (_ultimaCarga != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 2),
                child: Text(
                  Helpers.haceTexto(_ultimaCarga),
                  style: TextStyle(fontSize: 11.5, color: _textoSuave),
                ),
              ),
            const SizedBox(height: 16),
            if (_error) _bannerError(),
            _seccionTitulo('Mi captura de calificaciones'),
            Row(
              children: [
                _kpi('Grupos', '$_grupos', Icons.groups, cessumRed),
                const SizedBox(width: 10),
                _kpi('Completas', '$_completas', Icons.task_alt, _verde),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _kpi('Pendientes', '$_pendientes', Icons.pending_actions,
                    _pendientes > 0 ? cessumRed : _verde),
                const SizedBox(width: 10),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 20),
            const MisPendientesCard(),
            _seccionTitulo('Calificaciones'),
            _acceso('Capturar calificaciones', Icons.edit_note, cessumRed,
                () => _abrir(const CapturaCalificacionesScreen())),
            _acceso('Ver mi avance de captura', Icons.fact_check, cessumGold,
                () => _abrir(const MiCapturaScreen())),
            _acceso('Estado de mis actas', Icons.assignment_turned_in, cessumRed,
                () => _abrir(const MisActasDocenteScreen())),
            const SizedBox(height: 12),
            _seccionTitulo('Mis grupos y materias'),
            _acceso('Mis clases', Icons.class_outlined, cessumRed,
                () => _abrir(MisClasesScreen())),
            _acceso('Mis materias', Icons.menu_book_outlined, cessumGold,
                () => _abrir(MisMateriasScreen())),
            _acceso('Banners semanales', Icons.image_outlined, cessumRed,
                () => _abrir(const BannersSemanalesScreen())),
            _acceso('Mi horario', Icons.schedule, cessumRed,
                () => _abrir(MiHorarioDocenteScreen())),
            _acceso('Mi tablero', Icons.dashboard_outlined, cessumGold,
                () => _abrir(TableroDocenteScreen(correo: _correo))),
            _acceso('Mis invitaciones de materia', Icons.mark_email_read,
                cessumRed, () => _abrir(const MisInvitacionesDocenteScreen())),
            const SizedBox(height: 12),
            _seccionTitulo('Seguimiento de alumnos'),
            _acceso('Alumnos en riesgo', Icons.warning_amber_rounded, cessumRed,
                () => _abrir(RiesgoDocenteScreen(correo: _correo))),
            _acceso('Mis alumnos', Icons.groups_2_outlined, cessumGold,
                () => _abrir(const MisAlumnosDocenteScreen())),
            _acceso('Tareas y entregas', Icons.assignment_outlined, cessumGold,
                () => _abrir(TareasDocenteScreen())),
            _acceso('Tutorías', Icons.support_agent, cessumRed,
                () => _abrir(TutoriasDocenteScreen())),
            const SizedBox(height: 12),
            _seccionTitulo('Comunicación y recursos'),
            _acceso('Avisos a mis grupos', Icons.campaign_outlined, cessumGold,
                () => _abrir(AvisosDocenteScreen())),
            _acceso('Recursos y materiales', Icons.folder_open_outlined,
                cessumRed, () => _abrir(RecursosDocenteScreen())),
            _acceso('Enviar mi resumen por correo', Icons.outgoing_mail,
                cessumGold, _enviarResumen),
          ],
        ),
      ),
    );
  }

  Widget _bannerError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: cessumRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No se pudo cargar tu información. Revisa tu conexión.',
              style: TextStyle(fontSize: 13, color: _textoFuerte),
            ),
          ),
          TextButton(
            onPressed: _cargando ? null : _cargar,
            style: TextButton.styleFrom(foregroundColor: cessumRed),
            child: const Text('Reintentar',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _encabezado() {
    final msg = _cargando
        ? 'Cargando tu resumen...'
        : (_error
            ? 'No se pudo cargar tu resumen.'
            : (_pendientes == 0
                ? '¡Vas al día con tu captura!'
                : 'Tienes $_pendientes grupo(s) por capturar.'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cessumRed, cessumRed.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Panel del docente',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(msg,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _seccionTitulo(String t) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700, color: cessumRed)),
    );
  }

  Widget _kpi(String etiqueta, String valor, IconData icono, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _superficie,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color, size: 22),
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: _cargando
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumRed)),
                    )
                  : Text(_error ? '—' : valor,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: color)),
            ),
            Text(etiqueta,
                style: TextStyle(fontSize: 11.5, color: _textoSuave)),
          ],
        ),
      ),
    );
  }

  Widget _acceso(String texto, IconData icono, Color color, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icono, color: color, size: 22),
        ),
        title: Text(texto,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        trailing: Icon(Icons.chevron_right, color: cessumMuted(context)),
      ),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'foto_web_picker.dart';
import 'helpers.dart';
import 'student_profile.dart';
import 'mi_progreso_screen.dart';
import 'mi_aula_screen.dart';
import 'mi_pagos_screen.dart';
import 'contacto_screen.dart';
import 'cessum_ui.dart';
import 'cessum_anim.dart';
import 'mi_titulacion_screen.dart';
import 'logros_screen.dart';
import 'tutor_ia_screen.dart';
import 'curp_aviso.dart';

/// Mi panel: tablero de inicio del alumno. Reúne en un vistazo su promedio,
/// materias, pagos pendientes y su actividad en el Aula, con accesos rápidos.
class MiPanelScreen extends StatefulWidget {
  const MiPanelScreen({super.key});

  @override
  State<MiPanelScreen> createState() => _MiPanelScreenState();
}

class _MiPanelScreenState extends State<MiPanelScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  String _nombre = '';
  String _matricula = '';
  Uint8List? _fotoPerfil;
  bool _subiendoFoto = false;

  bool _acadCargando = true;
  bool _acadError = false;
  String? _promedio;
  int _materias = 0;
  int _pagos = 0;

  bool _aulaCargando = true;
  bool _aulaError = false;
  bool _enMoodle = false;
  int _cursos = 0;
  int _tareasPend = 0;
  String _materiaEnCurso = '';
  DateTime? _ultimaCarga;

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : Colors.black87;
  Color get _textoSuave => cessumMuted(context);

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    final perfil = await StudentProfile.load();
    _matricula = perfil?.matricula ?? '';
    _nombre = perfil?.nombreCompleto ?? '';
    if (_matricula.isEmpty) {
      setState(() {
        _acadCargando = false;
        _aulaCargando = false;
        _acadError = true;
        _aulaError = true;
      });
      return;
    }
    _cargarAcademico();
    _cargarAula();
    _cargarFotoPerfil();
  }

  Future<void> _cargarFotoPerfil() async {
    if (_matricula.isEmpty) return;
    try {
      final uri = Uri.parse('$guardianUrl?accion=perfil_foto'
          '&matricula=${Uri.encodeComponent(_matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['existe'] == true) {
        final b64 = (data['b64'] ?? '').toString();
        if (b64.isNotEmpty && mounted) {
          setState(() => _fotoPerfil = base64Decode(b64));
        }
      }
    } catch (_) {/* sin foto: se muestran las iniciales */}
  }

  Future<void> _cambiarFotoPerfil() async {
    if (_matricula.isEmpty || _subiendoFoto) return;
    try {
      final foto = await seleccionarFoto();
      if (foto == null) return;
      setState(() => _subiendoFoto = true);
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'perfil_foto_guardar',
              'matricula': _matricula,
              'fotoBase64': base64Encode(foto.bytes),
              'fotoMime': foto.mime,
            }),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _subiendoFoto = false;
        if (data['ok'] == true) _fotoPerfil = Uint8List.fromList(foto.bytes);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['ok'] == true
              ? 'Foto actualizada. Ya aparecerá al solicitar tu credencial.'
              : 'No se pudo guardar la foto: ${data['error'] ?? ''}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _subiendoFoto = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo abrir el selector de fotos.')));
    }
  }

  Widget _avatarPerfil() {
    final iniciales = _nombre.trim().isEmpty
        ? '·'
        : _nombre
            .trim()
            .split(' ')
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join();
    return GestureDetector(
      onTap: _cambiarFotoPerfil,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            backgroundImage:
                _fotoPerfil != null ? MemoryImage(_fotoPerfil!) : null,
            child: _fotoPerfil == null
                ? Text(iniciales,
                    style: const TextStyle(
                        color: cessumRed,
                        fontWeight: FontWeight.w800,
                        fontSize: 20))
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration:
                  const BoxDecoration(color: cessumGold, shape: BoxShape.circle),
              child: _subiendoFoto
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.edit, size: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cargarAcademico() async {
    setState(() {
      _acadCargando = true;
      _acadError = false;
    });
    try {
      final uri = Uri.parse('$guardianUrl?accion=panel_alumno'
          '&matricula=${Uri.encodeComponent(_matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      if (!mounted) return;
      setState(() {
        _promedio = data['promedio'] == null ? null : '${data['promedio']}';
        _materias = (data['materias'] ?? 0) as int;
        _pagos = (data['pagosPendientes'] ?? 0) as int;
        if ((_nombre).isEmpty) _nombre = (data['nombre'] ?? '').toString();
        _acadCargando = false;
        _ultimaCarga = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acadCargando = false;
        _acadError = true;
      });
    }
  }

  Future<void> _cargarAula() async {
    setState(() {
      _aulaCargando = true;
      _aulaError = false;
    });
    try {
      final uri = Uri.parse('$guardianUrl?accion=moodle_alumno'
          '&matricula=${Uri.encodeComponent(_matricula)}&dias=30');
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      final insc = (data['inscripciones'] as List?) ?? [];
      final tareas = (data['tareas'] as List?) ?? [];
      int pendTotal = 0;
      for (final t in tareas) {
        if ((t as Map)['entregado'] != true) pendTotal++;
      }
      // Solo las pendientes de la MATERIA EN CURSO (si el backend la detectó);
      // si no, como respaldo, el total.
      final tmActual = data['tareasMateriaActual'];
      final int pend = (tmActual is num) ? tmActual.toInt() : pendTotal;
      if (!mounted) return;
      setState(() {
        _enMoodle = data['enMoodle'] == true;
        _cursos = insc.length;
        _tareasPend = pend;
        _materiaEnCurso = (data['materiaEnCurso'] ?? '').toString();
        _aulaCargando = false;
        _ultimaCarga = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aulaCargando = false;
        _aulaError = true;
      });
    }
  }

  void _abrir(Widget pantalla) {
    Navigator.push(context, cessumFadeRoute(pantalla));
  }

  /// (8-sep) TITULACIÓN: UNA SOLA PUERTA.
  /// El alumno tenía tres entradas a lo mismo —`MiExpedienteScreen` (junio,
  /// ya retirada), `MiExpedienteTitulacionScreen` y `MiTitulacionScreen`—,
  /// y los documentos no viven en un solo lugar: los del expediente están en
  /// la hoja «Expediente documental» y solo se copian a la de «Titulación» al
  /// presentar la solicitud. Entrar por la puerta equivocada significaba
  /// entregar donde ya nadie revisa. Ahora todo entra por «Mi titulación»,
  /// que es la que sabe en qué etapa va y a dónde mandarlo.
  void _abrirExpediente() => _abrir(const MiTitulacionScreen());

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
            onPressed: () {
              _cargarAcademico();
              _cargarAula();
            },
            style: TextButton.styleFrom(foregroundColor: cessumRed),
            child: const Text('Reintentar',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
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
            onPressed: () {
              _cargarAcademico();
              _cargarAula();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: cessumRed,
        onRefresh: () async {
          await Future.wait([_cargarAcademico(), _cargarAula()]);
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
                  style: TextStyle(fontSize: 11.5, color: cessumFaint(context)),
                ),
              ),
            const SizedBox(height: 16),
            const CurpAvisoCard(),
            if (_acadError || _aulaError) _bannerError(),
          _seccionTitulo('Mi avance'),
          Row(
            children: [
              _kpi('Promedio', _acadCargando, _acadError,
                  _promedio ?? '—', Icons.star, cessumGold),
              const SizedBox(width: 10),
              _kpi('Materias', _acadCargando, _acadError, '$_materias',
                  Icons.menu_book, cessumRed),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _kpi('Cursos en Aula', _aulaCargando, _aulaError, '$_cursos',
                  Icons.school, cessumRed),
              const SizedBox(width: 10),
              _kpi('Tareas por entregar', _aulaCargando, _aulaError,
                  '$_tareasPend', Icons.assignment_late,
                  _tareasPend > 0 ? cessumRed : _verde),
            ],
          ),
          if (_materiaEnCurso.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                'Tareas de tu materia en curso: $_materiaEnCurso',
                style: TextStyle(fontSize: 11.5, color: _textoSuave),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _kpi('Pagos pendientes', _acadCargando, _acadError, '$_pagos',
                  Icons.account_balance_wallet,
                  _pagos > 0 ? cessumRed : _verde),
              const SizedBox(width: 10),
              const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 20),
          _seccionTitulo('Accesos rápidos'),
          _mosaicoAccesos(),
          ],
        ),
      ),
    );
  }

  String get _saludoHora {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'Buenos días';
    if (h >= 12 && h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  Widget _chipHero(IconData icono, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(texto,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _encabezado() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [cessumRed, Color(0xFF8E1622)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Profundidad: círculos dorados muy sutiles al fondo.
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cessumGold.withValues(alpha: 0.16),
                ),
              ),
            ),
            Positioned(
              right: 30,
              bottom: -40,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _avatarPerfil(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_saludoHora,
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          _nombre.trim().isEmpty ? 'Bienvenido' : _nombre.split(' ').first,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (_matricula.isNotEmpty)
                              _chipHero(Icons.badge_outlined, _matricula),
                            if (_materiaEnCurso.trim().isNotEmpty)
                              _chipHero(Icons.menu_book, _materiaEnCurso),
                          ],
                        ),
                        if (!_aulaCargando && !_aulaError && !_enMoodle) ...[
                          const SizedBox(height: 10),
                          const Text('Aún no apareces inscrito en el Aula Virtual.',
                              style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

  Widget _kpi(String etiqueta, bool cargando, bool error, String valor,
      IconData icono, Color color) {
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
              child: cargando
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumRed)),
                    )
                  : Text(error ? '—' : valor,
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

  Widget _mosaicoAccesos() {
    final items = <Widget>[
      _accesoMosaico('Mi progreso', Icons.assessment, cessumRed,
          () => _abrir(const MiProgresoScreen())),
      _accesoMosaico('Mis logros', Icons.emoji_events, cessumGold,
          () => _abrir(const LogrosScreen())),
      _accesoMosaico('Tutor IA', Icons.smart_toy, cessumRed,
          () => _abrir(const TutorIaScreen())),
      _accesoMosaico('Mi titulación', Icons.workspace_premium, cessumRed,
          _abrirExpediente),
      _accesoMosaico('Mi Aula Virtual', Icons.school, cessumRed,
          () => _abrir(const MiAulaScreen())),
      _accesoMosaico('Mis pagos', Icons.account_balance_wallet, cessumGold,
          () => _abrir(const MiPagosScreen())),
      _accesoMosaico('Contacto', Icons.contact_support, cessumGold,
          () => _abrir(const ContactoScreen())),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: items,
    );
  }

  Widget _accesoMosaico(String texto, IconData icono, Color color, VoidCallback onTap) {
    return CessumPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icono, color: color, size: 24),
            ),
            Text(
              texto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _acceso(String texto, IconData icono, Color color, VoidCallback onTap) {
    return CessumPressable(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
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
          trailing: Icon(Icons.chevron_right, color: cessumFaint(context)),
        ),
      ),
    );
  }
}

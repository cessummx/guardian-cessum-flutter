import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'cessum_header.dart';
import 'constants.dart';
import 'student_profile.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

import 'mi_boleta_screen.dart';
import 'mi_credencial_screen.dart';
import 'solicitud_adaptacion_modalidad_screen.dart';
import 'cessum_ui.dart';

/// Pantalla "Mis documentos": un solo lugar donde el alumno encuentra los
/// documentos que la app ya sabe emitir (constancia de estudios, boleta de
/// calificaciones y credencial). No descarga nada nuevo: solo reúne y abre
/// las pantallas que ya existían, para que el alumno no las busque sueltas.
///
/// Recibe la matrícula desde el menú. El perfil completo (que necesitan la
/// constancia y la boleta) se carga aquí mismo con StudentProfile.load(),
/// que devuelve el perfil de la sesión activa del propio alumno.
class MisDocumentosScreen extends StatefulWidget {
  final String matricula;

  const MisDocumentosScreen({super.key, required this.matricula});

  @override
  State<MisDocumentosScreen> createState() => _MisDocumentosScreenState();
}

class _MisDocumentosScreenState extends State<MisDocumentosScreen> {
  StudentProfile? _perfil;
  bool _cargando = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargarPerfil();
  }

  Future<void> _cargarPerfil() async {
    final p = await StudentProfile.load();
    if (!mounted) return;
    setState(() {
      _perfil = p;
      _cargando = false;
    });
  }

  void _abrir(Widget pantalla) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => pantalla),
    );
  }

  void _msg(String t, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t),
        backgroundColor: ok ? const Color(0xFF1E8E3E) : cessumRed));
  }

  Future<bool> _confirmar(String titulo, String mensaje, String accion) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(accion),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<Map<String, dynamic>> _enviarTramite(
      String tipoTramite, Map<String, dynamic> extra) async {
    final correo = await SessionStore.realEmail() ?? '';
    final p = _perfil;
    final body = <String, dynamic>{
      'accion': 'tramite_enviar',
      'tipoTramite': tipoTramite,
      'matricula': p?.matricula ?? widget.matricula,
      'nombre': p?.nombreCompleto ?? '',
      'correo': correo,
      'programa': p?.programa ?? '',
      'modalidad': p?.modalidad ?? '',
      'generacion': p?.generacion ?? '',
      ...extra,
    };
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _solicitarConstancia() async {
    final ok = await _confirmar(
        'Constancia de estudios',
        'La constancia de estudios se tramita con administración y tiene un '
            'costo. Se registrará como trámite y administración te indicará el '
            'proceso de pago. ¿Deseas enviar la solicitud?',
        'Enviar solicitud');
    if (!ok) return;
    setState(() => _enviando = true);
    try {
      final data = await _enviarTramite('Constancia de estudios', {});
      if (data['ok'] == true) {
        _msg('Solicitud enviada a trámites. Administración te indicará el '
            'proceso de pago.', ok: true);
      } else {
        _msg(data['error']?.toString() ?? 'No se pudo enviar la solicitud.');
      }
    } catch (e) {
      _msg('Error de conexión: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context, const Color(0xFFF5F1E8)),
      appBar: const CessumAppBar(titulo: 'Mis documentos'),
      body: _cargando
          ? const CessumSkeletonList()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Matrícula: ${widget.matricula}',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : cessumInk(context),
                    ),
                  ),
                ),
                _tarjeta(
                  icono: Icons.verified_outlined,
                  color: cessumRed,
                  titulo: 'Constancia de estudios',
                  subtitulo:
                      'Se solicita como trámite (tiene costo). La procesa administración.',
                  onTap: _enviando ? null : _solicitarConstancia,
                ),
                const SizedBox(height: 12),
                // (2-sep) LA BOLETA NO ES UN TRÁMITE. El alumno la genera y la
                // descarga solo desde «Mi boleta», eligiendo el ciclo. Pedirla
                // aquí abría una solicitud que administración tenía que revisar
                // y emitir a mano, para un documento que el sistema ya arma
                // solo. Ahora esta tarjeta lleva directo a esa pantalla.
                _tarjeta(
                  icono: Icons.receipt_long_outlined,
                  color: cessumGold,
                  titulo: 'Boleta de calificaciones',
                  subtitulo:
                      'Descárgala tú mismo: elige el ciclo y se genera al momento. Solo ciclos completos.',
                  onTap: _enviando
                      ? null
                      : () => _abrir(const MiBoletaScreen()),
                ),
                const SizedBox(height: 12),
                _tarjeta(
                  icono: Icons.badge_outlined,
                  color: cessumRed,
                  titulo: 'Credencial digital',
                  subtitulo:
                      'Solicítala; administración la revisa antes de emitirla.',
                  onTap: _enviando
                      ? null
                      : () => _abrir(const MiCredencialScreen()),
                ),
                const SizedBox(height: 12),
                _tarjeta(
                  icono: Icons.swap_horiz,
                  color: cessumGold,
                  titulo: 'Adaptación de modalidad',
                  subtitulo:
                      'Solicita cursar virtual un periodo (modalidad Mixta). La evalúa el Consejo Directivo (máx. 72 h).',
                  onTap: _enviando
                      ? null
                      : () =>
                          _abrir(const SolicitudAdaptacionModalidadScreen()),
                ),
              ],
            ),
    );
  }

  Widget _tarjeta({
    required IconData icono,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Pressable(
        onTap: onTap ?? () {},
        child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
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
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 13,
                        color: cessumMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

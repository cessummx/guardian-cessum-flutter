import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'foto_web_picker.dart';
import 'teacher_profile.dart';
import 'teacher_setup_screen.dart';

// =====================================================================
// PANTALLA: "Mi credencial" (DOCENTE) — versión OFICIAL
// ---------------------------------------------------------------------
// Flujo espejo del alumno, con clave = correo institucional:
//   GET  credencial_docente_estado ?correo -> { estado, fotoUrl, folio, verUrl, ... }
//   GET  credencial_docente_foto   ?correo -> { b64 }
//   POST solicitar_credencial_docente { correo, nombre, titulo, fotoBase64, fotoMime }
// La foto se guarda en Drive; el admin aprueba; el QR valida contra CESSUM.
// =====================================================================

class CredencialProfesorScreen extends StatefulWidget {
  const CredencialProfesorScreen({super.key});

  @override
  State<CredencialProfesorScreen> createState() =>
      _CredencialProfesorScreenState();
}

class _CredencialProfesorScreenState extends State<CredencialProfesorScreen> {
  static const String _cct = '26PSU0110Z';

  TeacherProfile? _perfil;
  String _correo = '';
  String _estado = 'NoSolicitada';
  String _observaciones = '';
  String _verUrl = '';
  String _fotoUrl = '';
  String _folio = '';

  Uint8List? _fotoServidor; // foto ya guardada (viene del Guardián)
  Uint8List? _fotoNueva; // foto recién elegida, pendiente de enviar
  String _fotoMime = 'image/jpeg';

  bool _cargando = true;
  bool _enviando = false;
  bool _verReverso = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    final perfil = await TeacherProfile.load();
    final correo = (await SessionStore.validEmail()) ?? '';
    if (!mounted) return;
    setState(() {
      _perfil = perfil;
      _correo = correo;
    });
    if (perfil == null || correo.isEmpty) {
      setState(() => _cargando = false);
      return;
    }
    await _consultarEstado();
  }

  Future<void> _consultarEstado() async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'credencial_docente_estado',
        'correo': _correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final e = (data['estado'] as Map<String, dynamic>? ?? {});
      if (!mounted) return;
      setState(() {
        _estado = (e['estado'] ?? 'NoSolicitada').toString();
        _observaciones = (e['observaciones'] ?? '').toString();
        _verUrl = (e['verUrl'] ?? '').toString();
        _fotoUrl = (e['fotoUrl'] ?? '').toString();
        _folio = (e['folio'] ?? '').toString();
        _cargando = false;
      });
      if (_fotoUrl.isNotEmpty) {
        _cargarFotoServidor();
      } else if (mounted) {
        setState(() => _fotoServidor = null);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No pudimos consultar el estado de tu credencial. '
            'Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  Future<void> _cargarFotoServidor() async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'credencial_docente_foto',
        'correo': _correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final b64 = (data['b64'] ?? '').toString();
      if (data['ok'] == true && b64.isNotEmpty) {
        if (!mounted) return;
        setState(() => _fotoServidor = base64Decode(b64));
      }
    } catch (_) {}
  }

  Future<void> _elegirFoto() async {
    try {
      final foto = await seleccionarFoto();
      if (foto == null) return;
      if (!mounted) return;
      setState(() {
        _fotoNueva = Uint8List.fromList(foto.bytes);
        _fotoMime = foto.mime;
      });
    } catch (e) {
      _aviso('No se pudo abrir el selector de fotos: $e', esError: true);
    }
  }

  Future<void> _solicitar() async {
    final perfil = _perfil;
    if (perfil == null) return;
    final tieneFoto = _fotoNueva != null || _fotoServidor != null;
    if (!tieneFoto) {
      _aviso('Primero sube una foto para tu credencial.', esError: true);
      return;
    }
    setState(() => _enviando = true);
    try {
      final payload = <String, dynamic>{
        'accion': 'solicitar_credencial_docente',
        'correo': _correo,
        'nombre': perfil.nombreCompleto,
        'titulo': perfil.titulo,
      };
      if (_fotoNueva != null) {
        payload['fotoBase64'] = base64Encode(_fotoNueva!);
        payload['fotoMime'] = _fotoMime;
      }
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _fotoNueva = null;
      });
      if (data['ok'] == true) {
        _aviso('Solicitud enviada. Queda en revisión.');
        _consultarEstado();
      } else {
        _aviso('${data['error'] ?? 'No se pudo enviar la solicitud.'}',
            esError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('Error de conexión al enviar.', esError: true);
    }
  }

  Future<void> _descargarPdf() async {
    _aviso('Generando tu credencial…');
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'credencial_docente_pdf',
        'correo': _correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final url = (data['url'] ?? '').toString();
      if (data['ok'] == true && url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        _aviso('${data['error'] ?? 'No se pudo generar el PDF.'}', esError: true);
      }
    } catch (_) {
      _aviso('Error al generar el PDF.', esError: true);
    }
  }

  void _aviso(String texto, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: esError ? cessumRed : CC.goldDark,
    ));
  }

  bool get _aprobada => _estado.toLowerCase() == 'aprobada';
  bool get _pendiente => _estado.toLowerCase() == 'pendiente';

  String get _badge {
    switch (_estado.toLowerCase()) {
      case 'aprobada':
        return 'VIGENTE';
      case 'pendiente':
        return 'EN REVISIÓN';
      case 'rechazada':
        return 'RECHAZADA';
      case 'observaciones':
        return 'OBSERVACIONES';
      default:
        return 'DOCENTE';
    }
  }

  Widget _foto() {
    final bytes = _fotoNueva ?? _fotoServidor;
    if (bytes != null) {
      return Image.memory(bytes, width: 72, height: 90, fit: BoxFit.cover);
    }
    return const Icon(Icons.person, color: Colors.white70, size: 38);
  }

  Widget _tarjetaFrente() {
    final p = _perfil;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CC.gold.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset('assets/images/logo.png',
                    height: 34,
                    errorBuilder: (_, __, ___) => const Text('CESSUM',
                        style: TextStyle(
                            color: cessumRed,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: 2))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [CC.gold, CC.goldDark]),
                      borderRadius: BorderRadius.circular(30)),
                  child: Text(_badge,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2)),
                ),
              ],
            ),
          ),
          Container(
            height: 3,
            decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [cessumRed, CC.gold])),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [CC.gold, CC.goldDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      borderRadius: BorderRadius.all(Radius.circular(12))),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 78,
                      height: 96,
                      color: CC.hueso,
                      alignment: Alignment.center,
                      child: _foto(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p != null && p.nombreCompleto.isNotEmpty
                            ? p.nombreCompleto
                            : 'Docente',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: CC.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.15),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: cessumRed.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          p != null && p.titulo.isNotEmpty
                              ? '${p.titulo} · Docente'
                              : 'Docente',
                          style: const TextStyle(
                              color: cessumRed,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('CORREO INSTITUCIONAL',
                          style: TextStyle(
                              color: CC.muted,
                              fontSize: 8.5,
                              letterSpacing: 1)),
                      Text(
                        _correo.isNotEmpty ? _correo : '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: CC.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: cessumRed,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'CCT 26PSU0110Z · Folio ${_folio.isEmpty ? "—" : _folio}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFF3D9A6),
                        fontSize: 9,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.qr_code_2, color: Colors.white70, size: 13),
                    SizedBox(width: 3),
                    Text('Ver QR',
                        style: TextStyle(color: Colors.white70, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaReverso() {
    final p = _perfil;
    final puedeQR = _aprobada && _verUrl.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CC.gold.withValues(alpha: 0.55), width: 1.2),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Image.asset('assets/images/logo.png',
                    height: 28,
                    errorBuilder: (_, __, ___) => const Text('CESSUM',
                        style: TextStyle(
                            color: cessumRed,
                            fontWeight: FontWeight.w800,
                            fontSize: 16))),
                const Text('Verificación oficial',
                    style: TextStyle(
                        color: cessumRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Container(
              height: 3,
              decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [cessumRed, CC.gold]))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 118,
                  height: 118,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: CC.gold.withValues(alpha: 0.45))),
                  child: puedeQR
                      ? Image.network(
                          'https://api.qrserver.com/v1/create-qr-code/?size=240x240&margin=0&data=${Uri.encodeComponent(_verUrl)}',
                          fit: BoxFit.contain,
                          loadingBuilder: (ctx, child, prog) => prog == null
                              ? child
                              : const Center(
                                  child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: CC.muted))),
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.qr_code_2,
                              size: 56,
                              color: CC.muted),
                        )
                      : const Center(
                          child: Icon(Icons.qr_code_2,
                              size: 56, color: CC.muted)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(p?.saludoCompleto ?? 'Docente CESSUM',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: CC.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                          puedeQR
                              ? 'Escanea el QR para validar a este docente ante CESSUM.'
                              : 'El QR aparece cuando la credencial es aprobada.',
                          style: const TextStyle(
                              color: CC.muted, fontSize: 11, height: 1.35)),
                      const SizedBox(height: 8),
                      const Text('CCT 26PSU0110Z',
                          style: TextStyle(
                              color: CC.goldDark,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.hueso,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi credencial'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : RefreshIndicator(
              color: cessumRed,
              onRefresh: _cargarTodo,
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: _contenido(),
              ),
            ),
    );
  }

  List<Widget> _contenido() {
    if (_perfil == null) return [_tarjetaSinPerfil()];
    if (_error.isNotEmpty) {
      return [
        _tarjetaInfo(
            icon: Icons.wifi_off,
            titulo: 'Sin conexión',
            texto: _error),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed)),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
            onPressed: _cargarTodo,
          ),
        ),
      ];
    }

    final w = <Widget>[
      GestureDetector(
        onTap: () => setState(() => _verReverso = !_verReverso),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _verReverso ? _tarjetaReverso() : _tarjetaFrente(),
        ),
      ),
      const SizedBox(height: 10),
      Center(
        child: Text(
          _verReverso
              ? 'Toca la tarjeta para ver el frente'
              : 'Toca la tarjeta para ver el QR',
          style: const TextStyle(color: CC.muted, fontSize: 12),
        ),
      ),
      const SizedBox(height: 18),
    ];

    // Mensaje de estado
    if (_pendiente) {
      w.add(_tarjetaInfo(
          icon: Icons.hourglass_top,
          titulo: 'En revisión',
          texto:
              'Tu solicitud fue enviada. Administración la revisará y te avisará '
              'por correo cuando esté aprobada.'));
      w.add(const SizedBox(height: 12));
    } else if (_aprobada) {
      w.add(_tarjetaInfo(
          icon: Icons.verified,
          titulo: 'Credencial aprobada',
          texto:
              'Tu credencial es oficial y verificable con el QR. Puedes cambiar '
              'tu foto y volver a solicitarla si lo necesitas.'));
      w.add(const SizedBox(height: 12));
      w.add(SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: CC.goldDark,
              side: const BorderSide(color: CC.gold),
              padding: const EdgeInsets.symmetric(vertical: 13)),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Descargar credencial (PDF)'),
          onPressed: _descargarPdf,
        ),
      ));
      w.add(const SizedBox(height: 12));
    } else if (_estado.toLowerCase() == 'rechazada' ||
        _estado.toLowerCase() == 'observaciones') {
      w.add(_tarjetaInfo(
          icon: Icons.error_outline,
          titulo: _estado.toLowerCase() == 'rechazada'
              ? 'Solicitud rechazada'
              : 'Solicitud con observaciones',
          texto: _observaciones.isNotEmpty
              ? _observaciones
              : 'Revisa tu foto y vuelve a enviarla.'));
      w.add(const SizedBox(height: 12));
    }

    // Botones
    w.add(SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            foregroundColor: cessumRed,
            side: const BorderSide(color: cessumRed),
            padding: const EdgeInsets.symmetric(vertical: 13)),
        icon: const Icon(Icons.photo_camera_outlined),
        label: Text((_fotoNueva != null || _fotoServidor != null)
            ? 'Cambiar mi foto'
            : 'Subir mi foto'),
        onPressed: _enviando ? null : _elegirFoto,
      ),
    ));
    w.add(const SizedBox(height: 10));
    w.add(SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: cessumRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14)),
        icon: _enviando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.badge_outlined),
        label: Text(_pendiente
            ? 'Reenviar solicitud'
            : (_aprobada ? 'Actualizar y reenviar' : 'Solicitar mi credencial')),
        onPressed: _enviando ? null : _solicitar,
      ),
    ));

    return w;
  }

  Widget _tarjetaSinPerfil() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CC.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_outlined, color: cessumRed),
              SizedBox(width: 8),
              Expanded(
                child: Text('Completa tu perfil docente',
                    style: TextStyle(
                        color: CC.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
              'Para generar tu credencial necesitamos tu título y tu nombre '
              'completo. Configúralos una sola vez.',
              style: TextStyle(color: CC.ink, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Configurar mi perfil'),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TeacherSetupScreen()),
                );
                _cargarTodo();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaInfo(
      {required IconData icon,
      required String titulo,
      required String texto}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CC.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: CC.goldDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: const TextStyle(
                        color: CC.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(texto,
                    style: const TextStyle(
                        color: CC.ink, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

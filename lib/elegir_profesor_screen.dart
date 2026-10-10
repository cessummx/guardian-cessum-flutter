import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'active_profile.dart';
import 'auth/session_store.dart';
import 'alumnos_service.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'teacher_menu_screen.dart';
import 'teacher_profile.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Vista de administrador: elegir un profesor REAL del padrón y entrar al
/// portal docente tal como lo ve ese profesor (sus clases, sus actas, etc.).
class ElegirProfesorScreen extends StatefulWidget {
  const ElegirProfesorScreen({super.key});

  @override
  State<ElegirProfesorScreen> createState() => _ElegirProfesorScreenState();
}

class _ElegirProfesorScreenState extends State<ElegirProfesorScreen> {
  final TextEditingController _busqueda = TextEditingController();
  List<ProfesorInfo> _todos = [];
  List<ProfesorInfo> _filtrados = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
    _busqueda.addListener(_filtrar);
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final lista = await AlumnosService.listarProfesores();
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _filtrados = lista;
        _cargando = false;
        if (lista.isEmpty) {
          _error = 'No se encontraron profesores en el padrón.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la lista de profesores.';
      });
    }
  }

  String _norm(String s) => s.trim().toLowerCase();

  void _filtrar() {
    final q = _norm(_busqueda.text);
    setState(() {
      if (q.isEmpty) {
        _filtrados = _todos;
      } else {
        _filtrados = _todos.where((p) {
          return _norm(p.nombre).contains(q) ||
              p.correo.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  Future<void> _accionesProfesor(ProfesorInfo p) async {
    final titulo = p.titulo.trim().isEmpty ? 'Dr.' : p.titulo.trim();
    final opcion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('$titulo ${p.nombre}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            ListTile(
              leading: const Icon(Icons.login, color: cessumRed),
              title: const Text('Ver como este profesor'),
              subtitle: const Text('Entra a su portal con efectos reales'),
              onTap: () => Navigator.pop(ctx, 'entrar'),
            ),
            ListTile(
              leading: const Icon(Icons.draw_outlined, color: cessumRed),
              title: const Text('Subir su firma'),
              subtitle:
                  const Text('Queda registrada como si \u00e9l la subiera'),
              onTap: () => Navigator.pop(ctx, 'firma'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (opcion == 'entrar') {
      await _entrarComoProfesor(p);
    } else if (opcion == 'firma') {
      await _subirFirma(p);
    }
  }

  // '' = PNG con transparencia (válido); si no, el motivo del rechazo.
  String _motivoPngInvalido(Uint8List b) {
    if (b.length < 33) return 'archivo_invalido';
    const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < 8; i++) {
      if (b[i] != sig[i]) return 'no_png';
    }
    final ct = b[25];
    if (ct == 6 || ct == 4) return '';
    if (ct == 3) {
      for (var j = 8; j < b.length - 4; j++) {
        if (b[j] == 0x74 && b[j + 1] == 0x52 && b[j + 2] == 0x4E &&
            b[j + 3] == 0x53) {
          return '';
        }
      }
      return 'sin_transparencia';
    }
    return 'sin_transparencia';
  }

  String _msgFirmaInvalida(String motivo) {
    switch (motivo) {
      case 'no_png':
        return 'La firma debe ser un archivo PNG con fondo transparente (sin fondo).';
      case 'sin_transparencia':
        return 'La firma debe ser un PNG SIN fondo (transparente). Quítale el fondo y vuelve a subirla.';
      default:
        return 'No pudimos leer la imagen. Sube un PNG con fondo transparente.';
    }
  }

  // Lee un PNG CRUDO del disco (sin re-codificar), para conservar la
  // transparencia. NO usa el selector de foto porque ese re-exporta a JPEG
  // (pierde el alfa y deja de ser PNG). Devuelve null si se cancela.
  Future<Uint8List?> _leerPngCrudo() async {
    final input = html.FileUploadInputElement()..accept = 'image/png';
    input.click();
    await input.onChange.first;
    final files = input.files;
    if (files == null || files.isEmpty) return null;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(files.first);
    await reader.onLoadEnd.first;
    final res = reader.result;
    if (res is Uint8List) return res;
    if (res is ByteBuffer) return res.asUint8List();
    if (res is List<int>) return Uint8List.fromList(res);
    return null;
  }

  Future<void> _subirFirma(ProfesorInfo p) async {
    final bytes = await _leerPngCrudo();
    if (bytes == null || !mounted) return;
    final motivo = _motivoPngInvalido(bytes);
    if (motivo.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_msgFirmaInvalida(motivo)),
          backgroundColor: cessumRed,
        ));
      }
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subir firma'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vas a registrar esta firma para:\n${p.nombre}\n${p.correo}',
                style: const TextStyle(height: 1.4)),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.memory(bytes, height: 90, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Requisito: la firma debe ser PNG con fondo transparente (sin fondo). '
              'Si tiene fondo, no se aceptará.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.3),
            ),
          ],
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
            child: const Text('Guardar firma'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    final admin =
        (await SessionStore.realEmail()) ?? (await SessionStore.validEmail()) ?? '';
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final resp = await http.post(
        Uri.parse(guardianUrl),
        headers: {'Content-Type': 'text/plain;charset=utf-8'},
        body: jsonEncode({
          'accion': 'firma_docente_guardar',
          'correo': p.correo,
          'imagenBase64': base64Encode(bytes),
          'conFondo': false,
          'solicitante': admin,
        }),
      ).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Firma registrada para ${p.nombre}.'),
          backgroundColor: const Color(0xFF1E8E3E)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar: ${data['error'] ?? ''}'),
          backgroundColor: cessumRed));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo guardar la firma. Revisa tu conexi\u00f3n.'),
        backgroundColor: cessumRed));
    }
  }

  Future<void> _entrarComoProfesor(ProfesorInfo p) async {
    final titulo = p.titulo.trim().isEmpty ? 'Dr.' : p.titulo.trim();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ver como este profesor'),
        content: Text(
          'Vas a entrar al portal docente como:\n\n'
          '$titulo ${p.nombre}\n${p.correo}\n\n'
          'La app usará SU identidad: lo que hagas (subir firma, capturar, '
          'validar) tendrá efecto REAL a nombre de este profesor. '
          'Para volver a tu cuenta, usa el aviso superior “Saliendo como…”.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    await SessionStore.startImpersonation(p.correo, nombre: '$titulo ${p.nombre}');
    final perfil = TeacherProfile(
      titulo: titulo,
      nombreCompleto: p.nombre,
    );
    await perfil.save();
    await ActiveProfile.setActive(ProfileType.teacher);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TeacherMenuScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Elegir profesor'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _busqueda,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o correo',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
          if (!_cargando && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtrados.length} profesor(es)',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_off_outlined,
                  color: cessumFaint(context), size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: _cargar,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_filtrados.isEmpty) {
      return const Center(
        child: Text('Sin coincidencias.',
            style: TextStyle(color: Colors.black54)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _filtrados.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = _filtrados[i];
        final titulo = p.titulo.trim().isEmpty ? '' : '${p.titulo.trim()} ';
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _accionesProfesor(p),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: cessumRed.withValues(alpha: 0.12),
                    child: const Icon(Icons.school, color: cessumRed, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$titulo${p.nombre}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.correo,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black26),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

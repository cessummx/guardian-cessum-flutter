import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Pantalla para DAR DE ALTA un docente. Escribe directo en la hoja
/// "Docentes" del Guardián (título, nombre, correo, semblanza).
class DocenteAltaScreen extends StatefulWidget {
  const DocenteAltaScreen({super.key});

  @override
  State<DocenteAltaScreen> createState() => _DocenteAltaScreenState();
}

class _DocenteAltaScreenState extends State<DocenteAltaScreen> {
  final _titulo = TextEditingController();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _semblanza = TextEditingController();
  bool _guardando = false;
  bool _bienvenida = true;
  String _correoActor = '';

  @override
  void initState() {
    super.initState();
    _cargarActor();
  }

  Future<void> _cargarActor() async {
    final c = await SessionStore.realEmail();
    if (mounted && c != null) setState(() => _correoActor = c);
  }

  @override
  void dispose() {
    _titulo.dispose();
    _nombre.dispose();
    _correo.dispose();
    _semblanza.dispose();
    super.dispose();
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
      content: Text(m),
    ));
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    final correo = _correo.text.trim().toLowerCase();
    if (nombre.isEmpty) {
      _aviso('Escribe el nombre del docente.', error: true);
      return;
    }
    if (!correo.contains('@')) {
      _aviso('Escribe un correo válido.', error: true);
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar alta', style: TextStyle(fontSize: 16)),
        content: Text(
          'Se dará de alta al docente:\n\n'
          '$nombre\n$correo\n\n'
          'Quedará escrito en la hoja Docentes (con su semblanza) y '
          'aparecerá en la app de inmediato.'
          '${_bienvenida ? '\n\nSe le enviará su correo de bienvenida.' : ''}'
          '\n\n¿Continuar?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dar de alta'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    setState(() => _guardando = true);
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'docente_alta',
              'titulo': _titulo.text.trim(),
              'nombre': nombre,
              'correo': correo,
              'semblanza': _semblanza.text.trim(),
              'actor': _correoActor,
              'bienvenida': _bienvenida,
            }),
          )
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final actualizado = data['actualizado'] == true;
        final fila = data['fila']?.toString() ?? '?';
        var msg = actualizado
            ? 'Ya existía: se actualizaron sus datos (fila $fila).'
            : 'Docente dado de alta (fila $fila).';
        // El backend regresa el resultado del correo por separado: el alta
        // puede quedar bien aunque el correo falle por cuota.
        final b = data['bienvenida'];
        if (b is Map) {
          msg += b['ok'] == true
              ? ' Bienvenida enviada.'
              : ' OJO: la bienvenida NO se envió.';
        }
        _aviso(msg);
        _titulo.clear();
        _nombre.clear();
        _correo.clear();
        _semblanza.clear();
      } else {
        _aviso(data['error']?.toString() ?? 'No se pudo dar de alta.',
            error: true);
      }
    } catch (_) {
      _aviso('No se pudo conectar. Revisa tu conexión.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Dar de alta docente',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
            ),
            child: const Text(
              'Queda escrito en la hoja Docentes (título, nombre, correo y '
              'semblanza) y aparece en la app de inmediato. La semblanza es '
              'la que usan las cartas descriptivas y las portadas de '
              'asignatura. Para que pueda entrar, su cuenta debe existir en '
              'Workspace y ser @cessum.mx. Si el correo ya está en la hoja, '
              'no se duplica: se actualizan sus datos.',
              style: TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _titulo,
            decoration: const InputDecoration(
              labelText: 'Título (Dr., Mtro., Lic.)',
              border: OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nombre,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre completo *',
              border: OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _correo,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo institucional *',
              hintText: 'nombre.apellido@cessum.mx',
              border: OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _semblanza,
            maxLines: 8,
            minLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Semblanza',
              hintText: 'Grados, trayectoria y líneas de trabajo. Sale en las '
                  'cartas descriptivas y portadas.',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _bienvenida,
            onChanged: _guardando
                ? null
                : (v) => setState(() => _bienvenida = v ?? false),
            activeColor: cessumRed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Enviar correo de bienvenida',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: const Text(
              'Le explica cómo entrar y qué hacer primero: subir su firma '
              'digital y firmar su contrato.',
              style: TextStyle(fontSize: 11.5, color: Colors.black54),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add),
              label: Text(_guardando ? 'Guardando...' : 'Dar de alta'),
            ),
          ),
        ],
      ),
    );
  }
}

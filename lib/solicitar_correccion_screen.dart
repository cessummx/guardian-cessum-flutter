import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Pantalla del DOCENTE para solicitar una corrección de calificación.
/// El docente NO edita directamente: llena esta solicitud (alumno, nueva
/// calificación, motivo) y se la envía al admin para que la apruebe.
class SolicitarCorreccionScreen extends StatefulWidget {
  final String programa;
  final String generacion;
  final String grupo;
  final String materia;
  final String docente;

  const SolicitarCorreccionScreen({
    super.key,
    required this.programa,
    required this.generacion,
    required this.grupo,
    required this.materia,
    required this.docente,
  });

  @override
  State<SolicitarCorreccionScreen> createState() =>
      _SolicitarCorreccionScreenState();
}

class _AlumnoCal {
  final String matricula;
  final String nombre;
  final String calificacion;
  const _AlumnoCal({
    required this.matricula,
    required this.nombre,
    required this.calificacion,
  });
}

class _SolicitarCorreccionScreenState
    extends State<SolicitarCorreccionScreen> {
  List<_AlumnoCal> _alumnos = [];
  bool _cargando = true;
  String? _error;

  _AlumnoCal? _seleccionado;
  final TextEditingController _calCtrl = TextEditingController();
  final TextEditingController _motivoCtrl = TextEditingController();
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargarAlumnos();
  }

  @override
  void dispose() {
    _calCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  // Carga los alumnos de este grupo con su calificación actual, usando la
  // acción progreso_alumno no sirve aquí (es por matrícula). Usamos la lista
  // de alumnos del grupo y su calificación de la materia vía 'alumnos'.
  Future<void> _cargarAlumnos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // Traemos los alumnos del grupo (acción 'alumnos').
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alumnos',
        'programa': widget.programa,
        'generacion': widget.generacion,
        'grupo': widget.grupo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final lista = (data['alumnos'] as List<dynamic>? ?? []);
      final alumnos = lista.map((e) {
        final m = e as Map<String, dynamic>;
        return _AlumnoCal(
          matricula: (m['matricula'] ?? '').toString(),
          nombre: (m['nombre'] ?? '').toString(),
          calificacion: '',
        );
      }).toList();
      if (mounted) {
        setState(() {
          _alumnos = alumnos;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudieron cargar los alumnos. Revisa tu conexión.';
        });
      }
    }
  }

  Future<void> _enviar() async {
    if (_seleccionado == null) {
      _aviso('Elige primero al alumno.');
      return;
    }
    final cal = _calCtrl.text.trim();
    final calNum = int.tryParse(cal);
    if (calNum == null || calNum < 6 || calNum > 10) {
      _aviso('La calificación debe ser un número entre 6 y 10.');
      return;
    }
    if (_motivoCtrl.text.trim().isEmpty) {
      _aviso('Escribe el motivo de la corrección.');
      return;
    }

    setState(() => _enviando = true);
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final payload = {
        'accion': 'solicitud_correccion',
        'programa': widget.programa,
        'generacion': widget.generacion,
        'grupo': widget.grupo,
        'materia': widget.materia,
        'matricula': _seleccionado!.matricula,
        'nombre': _seleccionado!.nombre,
        'calificacionPropuesta': calNum,
        'motivo': _motivoCtrl.text.trim(),
        'docente': widget.docente,
        'correo': correo,
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _enviando = false);

      if (data['ok'] == true) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Solicitud enviada'),
            content: const Text(
              'Tu solicitud de corrección fue enviada a la Vicerrectoría. '
              'Te avisaremos cuando sea revisada.',
              style: TextStyle(height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      } else {
        throw Exception(data['error'] ?? 'No se pudo enviar');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('Error al enviar: $e');
    }
  }

  void _aviso(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Solicitar corrección'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _formulario(),
    );
  }

  Widget _formulario() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Datos de la materia
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.materia,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cessumInk(context))),
              const SizedBox(height: 2),
              Text(
                '${widget.programa} • Gen. ${widget.generacion} • Grupo ${widget.grupo}',
                style: TextStyle(fontSize: 12, color: cessumMuted(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Text('1. Elige al alumno',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cessumInk(context))),
        const SizedBox(height: 8),
        DropdownButtonFormField<_AlumnoCal>(
          initialValue: _seleccionado,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            hintText: 'Selecciona un alumno',
          ),
          items: _alumnos.map((a) {
            return DropdownMenuItem<_AlumnoCal>(
              value: a,
              child: Text(
                a.nombre.isNotEmpty ? a.nombre : a.matricula,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (a) => setState(() => _seleccionado = a),
        ),
        const SizedBox(height: 20),

        Text('2. Nueva calificación (6 a 10)',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cessumInk(context))),
        const SizedBox(height: 8),
        TextField(
          controller: _calCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            hintText: 'Ej. 9',
          ),
        ),
        const SizedBox(height: 20),

        Text('3. Motivo de la corrección',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cessumInk(context))),
        const SizedBox(height: 8),
        TextField(
          controller: _motivoCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            hintText: 'Explica brevemente por qué debe corregirse.',
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _enviando ? null : _enviar,
            icon: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.send, size: 18),
            label: Text(_enviando ? 'Enviando...' : 'Enviar solicitud'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'La Vicerrectoría revisará tu solicitud. Si la aprueba, la '
          'calificación se actualizará automáticamente.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: cessumFaint(context), height: 1.3),
        ),
      ],
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargarAlumnos,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

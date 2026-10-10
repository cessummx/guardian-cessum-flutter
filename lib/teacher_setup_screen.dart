import 'package:flutter/material.dart';

import 'alumnos_service.dart';
import 'auth/session_store.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'teacher_menu_screen.dart';
import 'teacher_profile.dart';

class TeacherSetupScreen extends StatefulWidget {
  final bool esEdicion;
  final TeacherProfile? perfilExistente;

  const TeacherSetupScreen({
    super.key,
    this.esEdicion = false,
    this.perfilExistente,
  });

  @override
  State<TeacherSetupScreen> createState() => _TeacherSetupScreenState();
}

class _TeacherSetupScreenState extends State<TeacherSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();

  String? _tituloSeleccionado;
  bool _guardando = false;
  bool _autocompletado = false;

  @override
  void initState() {
    super.initState();

    if (widget.esEdicion && widget.perfilExistente != null) {
      _tituloSeleccionado = widget.perfilExistente!.titulo;
      _nombreController.text = widget.perfilExistente!.nombreCompleto;
    } else {
      // Perfil nuevo: intentar autocompletar desde la lista de docentes
      // usando el correo con el que inicio sesion.
      _autollenarDesdeListaDocentes();
    }
  }

  Future<void> _autollenarDesdeListaDocentes() async {
    try {
      final correo = await SessionStore.validEmail();
      if (correo == null || correo.isEmpty) return;

      final res = await AlumnosService.buscar(correo);
      if (res.estado != EstadoAlumno.profesor) return;
      if (!mounted) return;

      setState(() {
        final nombre = res.nombreProfesor ?? '';
        if (nombre.isNotEmpty && _nombreController.text.trim().isEmpty) {
          _nombreController.text = nombre;
        }
        final titulo = res.tituloProfesor ?? '';
        if (titulo.isNotEmpty &&
            _tituloSeleccionado == null &&
            titulosAcademicos.contains(titulo)) {
          _tituloSeleccionado = titulo;
        }
        _autocompletado = nombre.isNotEmpty || _tituloSeleccionado != null;
      });
    } catch (_) {
      // Si falla, el docente simplemente captura a mano (sin problema).
    }
  }

  @override
  void dispose() {
    _nombreController.dispose();
    super.dispose();
  }

  String? _validarNombre(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresa tu nombre completo';
    }
    if (value.trim().length < 5) {
      return 'Ingresa nombre y apellidos';
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_tituloSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Selecciona como quieres que te llamen'),
        ),
      );
      return;
    }

    final titulo = _tituloSeleccionado!;
    final nombre = _nombreController.text.trim();

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirma tu informacion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Asi te identificaremos en la app:',
              style: TextStyle(fontSize: 13, color: cessumMuted(context)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
              ),
              child: Text(
                '$titulo $nombre',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: cessumRed,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Editar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;
    if (!mounted) return;

    setState(() => _guardando = true);

    final perfil = TeacherProfile(
      titulo: titulo,
      nombreCompleto: nombre,
    );

    await perfil.save();

    if (!mounted) return;

    if (widget.esEdicion) {
      Navigator.pop(context, perfil);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TeacherMenuScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        title: Text(
          widget.esEdicion ? 'Editar perfil' : 'Mi perfil docente',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        automaticallyImplyLeading: widget.esEdicion,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.school, color: cessumGold, size: 22),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bienvenido docente',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Comparte como quieres que te identifiquemos. Estos datos solo se guardan en tu telefono.',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_autocompletado) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.check_circle, color: cessumRed, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Encontramos tus datos. Revisalos y guarda; puedes corregirlos si hace falta.',
                        style: TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Titulo
            const _Etiqueta('Como quieres que te digamos'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _tituloSeleccionado,
              isExpanded: true,
              hint: const Text('Selecciona tu titulo'),
              decoration: _campoDecoration(''),
              items: titulosAcademicos
                  .map((t) => DropdownMenuItem<String>(
                        value: t,
                        child: Text(t),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _tituloSeleccionado = v),
              validator: (v) =>
                  v == null ? 'Selecciona tu titulo' : null,
            ),
            const SizedBox(height: 20),

            // Nombre completo
            const _Etiqueta('Nombre completo'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nombreController,
              textCapitalization: TextCapitalization.words,
              decoration: _campoDecoration('Ej. Carlos Mendez Lopez'),
              validator: _validarNombre,
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.esEdicion
                            ? 'Actualizar perfil'
                            : 'Guardar y continuar',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  InputDecoration _campoDecoration(String hint) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      filled: true,
      fillColor: Theme.of(context).cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: cessumRed, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  const _Etiqueta(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }
}
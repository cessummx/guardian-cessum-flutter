import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Alta de alumnos (administrador). Registra al alumno en el padrón maestro de
/// grupos (base de actas/calificaciones) y en el padrón (con modalidad y
/// estatus). Reusa las acciones del Guardián: agregar_alumno + padron_override_set.
class AltaAlumnoScreen extends StatefulWidget {
  const AltaAlumnoScreen({super.key});

  @override
  State<AltaAlumnoScreen> createState() => _AltaAlumnoScreenState();
}

class _AltaAlumnoScreenState extends State<AltaAlumnoScreen> {
  final _matricula = TextEditingController();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _generacion = TextEditingController();
  String _grupo = '1 - entre semana';

  String? _programa;
  String _modalidad = modalidadesEstudio.first;
  String _estatus = 'Activo';

  bool _enviando = false;
  bool _enviarBienvenida = true;

  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : cessumInk(context);
  Color get _textoSuave => cessumMuted(context);

  // Grupos válidos según la modalidad elegida (evita mezclar mixta con no esc.).
  //
  // (18-sep) LICENCIATURA MANDA SOBRE LA MODALIDAD.
  // Su plan dice «Mixta», así que aquí solo se ofrecía «1 - mixta» y el alumno
  // quedaba en un grupo que no existe: sus siete materias están asignadas a
  // «1 - sabatino». Sin clases, sin aulas y sin calificaciones que cuadraran.
  // El Guardián ya corrige el grupo al guardarlo, pero el formulario debe
  // ofrecer el correcto: lo que se ve en pantalla tiene que ser lo que se
  // guarda, o quien captura no entiende qué pasó.
  bool get _esLicenciatura => (_programa ?? '')
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .contains('licenciatura');

  List<String> get _gruposDisponibles {
    if (_esLicenciatura) return const ['1 - sabatino'];
    return _modalidad.toLowerCase().contains('mixt')
        ? const ['1 - mixta']
        : const ['1 - entre semana', '2 - sabatino'];
  }

  @override
  void initState() {
    super.initState();
    _programa = programasAcademicos.first.nombre;
    _grupo = _gruposDisponibles.first;
  }

  @override
  void dispose() {
    _matricula.dispose();
    _nombre.dispose();
    _correo.dispose();
    _generacion.dispose();
    super.dispose();
  }

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
    ));
  }

  // Deja SOLO caracteres válidos de correo (quita espacios y cualquier carácter
  // invisible: espacio duro, ancho cero, etc., que rompen la validación).
  String _limpiarCorreo(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._%+\-@]'), '');

  String? _validar() {
    if (_matricula.text.trim().isEmpty) return 'Falta la matrícula.';
    if (_nombre.text.trim().isEmpty) return 'Falta el nombre completo.';
    final c = _limpiarCorreo(_correo.text);
    if (!c.contains('@')) return 'Falta el correo.';
    if (!c.endsWith('@cessum.mx')) return 'El correo debe ser @cessum.mx.';
    if ((_programa ?? '').isEmpty) return 'Elige el programa.';
    if (_generacion.text.trim().isEmpty) return 'Falta la generación (ej. 25-1).';
    return null;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _darDeAlta() async {
    final err = _validar();
    if (err != null) {
      _aviso(err, error: true);
      return;
    }
    // (24-sep) Correo REAL: en «Ver como profesor» validEmail() devuelve el del profesor.
    final actor = (await SessionStore.realEmail()) ?? '';
    if (actor.isEmpty) {
      _aviso('Tu sesión expiró. Vuelve a entrar.', error: true);
      return;
    }

    setState(() => _enviando = true);

    final matricula = _matricula.text.trim();
    final nombre = _nombre.text.trim();
    final correo = _limpiarCorreo(_correo.text);
    final programa = _programa ?? '';
    final generacion = _generacion.text.trim();
    final grupo = _grupo;

    try {
      // 1) Alta en el padrón maestro de grupos (actas/calificaciones).
      final r1 = await _post({
        'accion': 'agregar_alumno',
        'actor': actor,
        'programa': programa,
        'generacion': generacion,
        'grupo': grupo,
        'modalidad': _modalidad,
        'matricula': matricula,
        'nombre': nombre,
        'correo': correo,
      });

      final yaEnGrupo = (r1['ok'] != true) &&
          ('${r1['error'] ?? ''}'.toLowerCase().contains('ya esta') ||
              '${r1['error'] ?? ''}'.toLowerCase().contains('ya está'));

      if (r1['ok'] != true && !yaEnGrupo) {
        if (!mounted) return;
        setState(() => _enviando = false);
        _aviso('${r1['error'] ?? 'No se pudo agregar al grupo.'}', error: true);
        return;
      }

      // 2) Registro en el padrón (modalidad + estatus) para que el sistema
      // reconozca al alumno.
      final r2 = await _post({
        'accion': 'padron_override_set',
        'actor': actor,
        'matricula': matricula,
        'nombre': nombre,
        'correo': correo,
        'modalidad': _modalidad,
        'programa': programa,
        'generacion': generacion,
        'grupo': grupo,
        'estatus': _estatus,
      });

      if (!mounted) return;
      setState(() => _enviando = false);

      if (r2['ok'] == true) {
        String extra = '';
        if (_enviarBienvenida && !yaEnGrupo && correo.contains('@')) {
          try {
            final rb = await _post({
              'accion': 'correo_bienvenida',
              'actor': actor,
              'matricula': matricula,
              'correo': correo,
              'nombre': nombre,
              'programa': programa,
            });
            extra = rb['ok'] == true
                ? ' Se envió su correo de bienvenida.'
                : ' (La bienvenida no se pudo enviar ahora.)';
          } catch (_) {
            extra = ' (La bienvenida no se pudo enviar ahora.)';
          }
        }
        if (!mounted) return;
        _aviso((yaEnGrupo
                ? 'El alumno ya estaba en el grupo; se actualizó su registro en el padrón.'
                : 'Alumno dado de alta correctamente.') +
            extra);
        _limpiar();
      } else {
        _aviso('Se agregó al grupo, pero el padrón falló: '
            '${r2['error'] ?? ''}', error: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No me pude conectar. Intenta de nuevo.', error: true);
    }
  }

  void _limpiar() {
    _matricula.clear();
    _nombre.clear();
    _correo.clear();
    _generacion.clear();
    setState(() {
      _programa = programasAcademicos.first.nombre;
      _modalidad = modalidadesEstudio.first;
      _estatus = 'Activo';
      _grupo = _gruposDisponibles.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Dar de alta alumno',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cessumRed, cessumRed.withValues(alpha: 0.78)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Registrar un alumno nuevo',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text(
                  'Se agrega al grupo (para actas y calificaciones) y al padrón. '
                  'El correo debe ser del dominio @cessum.mx.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _campo('Matrícula', _matricula,
              hint: 'Ej. 25060100', teclado: TextInputType.number),
          _campo('Nombre completo', _nombre, hint: 'Nombre(s) y apellidos'),
          _campo('Correo institucional', _correo,
              hint: 'nombre@cessum.mx', teclado: TextInputType.emailAddress),
          _dropdown(
            'Programa',
            _programa,
            programasAcademicos.map((p) => p.nombre).toList(),
            (v) => setState(() {
              _programa = v;
              /* El grupo depende del programa: al cambiarlo hay que recalcular
                 o queda uno que ya no corresponde. */
              if (!_gruposDisponibles.contains(_grupo)) {
                _grupo = _gruposDisponibles.first;
              }
            }),
          ),
          _dropdown(
            'Modalidad',
            _modalidad,
            modalidadesEstudio,
            (v) => setState(() {
              _modalidad = v ?? modalidadesEstudio.first;
              if (!_gruposDisponibles.contains(_grupo)) {
                _grupo = _gruposDisponibles.first;
              }
            }),
          ),
          _campo('Generación', _generacion, hint: 'Ej. 25-1'),
          _dropdown(
            'Grupo',
            _grupo,
            _gruposDisponibles,
            (v) => setState(() => _grupo = v ?? _gruposDisponibles.first),
          ),
          _dropdown(
            'Estatus',
            _estatus,
            const ['Activo', 'Baja'],
            (v) => setState(() => _estatus = v ?? 'Activo'),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _enviarBienvenida,
            onChanged: (v) => setState(() => _enviarBienvenida = v ?? true),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: cessumRed,
            dense: true,
            title: Text('Enviar correo de bienvenida al alumno',
                style: TextStyle(fontSize: 13.5, color: _textoFuerte)),
            subtitle: Text(
                'Se envía a su correo institucional con sus accesos a app.cessum.mx.',
                style: TextStyle(fontSize: 11.5, color: _textoSuave)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              onPressed: _enviando ? null : _darDeAlta,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.person_add_alt_1),
              label: Text(_enviando ? 'Dando de alta…' : 'Dar de alta',
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Nota: si el ingreso de alumnos a la app depende del archivo '
            'alumnos.json, recuerda regenerarlo para que el alumno pueda '
            'iniciar sesión; en el sistema (grupos, actas, padrón) queda '
            'registrado de inmediato.',
            style: TextStyle(fontSize: 11.5, color: _textoSuave, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _campo(String etiqueta, TextEditingController ctrl,
      {String? hint, TextInputType? teclado}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _textoFuerte)),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: teclado,
            style: TextStyle(color: _textoFuerte),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: _superficie,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: cessumIsDark(context)
                        ? Colors.white24
                        : cessumFaint(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: cessumIsDark(context)
                        ? Colors.white24
                        : cessumFaint(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: cessumRed, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String etiqueta, String? valor, List<String> opciones,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _textoFuerte)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _superficie,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: cessumIsDark(context)
                      ? Colors.white24
                      : cessumFaint(context)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: valor,
                isExpanded: true,
                dropdownColor: _superficie,
                style: TextStyle(color: _textoFuerte, fontSize: 14),
                items: opciones
                    .map((o) =>
                        DropdownMenuItem<String>(value: o, child: Text(o)))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

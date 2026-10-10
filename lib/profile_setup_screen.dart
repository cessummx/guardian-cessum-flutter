import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'alumnos_service.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'curps_service.dart';
import 'foto_web_picker.dart';
import 'generaciones_service.dart';
import 'helpers.dart';
import 'menu_screen.dart';
import 'student_profile.dart';
import 'welcome_screen.dart';
import 'selector_buscable.dart'; // (24-sep) generación con búsqueda

class ProfileSetupScreen extends StatefulWidget {
  final bool esEdicion;
  final StudentProfile? perfilExistente;

  const ProfileSetupScreen({
    super.key,
    this.esEdicion = false,
    this.perfilExistente,
  });

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _matriculaController = TextEditingController();
  final _nombreController = TextEditingController();
  final _curpController = TextEditingController();

  String? _programaSeleccionado;
  String? _modalidadSeleccionada;
  String? _generacionSeleccionada;

  // Valores oficiales del padrón (alumnos.json), con acentos y formato canónico.
  // Se guardan tal cual para que coincidan exactamente con lo que usa el backend
  // (grupos, calificaciones, kardex). El menú es solo para mostrar/seleccionar.
  String? _programaOficial;
  String? _modalidadOficial;
  String? _generacionOficial;

  List<GeneracionItem> _generaciones = [];
  bool _cargandoGeneraciones = true;
  String? _errorGeneraciones;

  bool _guardando = false;
  String _curpOriginal = '';

  /* (1-sep) FOTO DE PERFIL. Es la MISMA que usa la credencial: el Guardián
     guarda una sola (hoja FotosPerfil) y la credencial la toma de ahí, así
     que actualizarla aquí la actualiza en los dos lados. */
  Uint8List? _fotoBytes;      // la que se ve ahora (guardada o recién elegida)
  Uint8List? _fotoNueva;      // elegida y todavía sin enviar
  String _fotoMime = 'image/jpeg';
  bool _cargandoFoto = false;
  bool _subiendoFoto = false;
  String _fotoActualizadaEl = '';

  // Autocompletado por matrícula desde el padrón (alumnos.json).
  bool _buscandoDatos = false;
  bool _datosAutollenados = false;
  String _ultimaMatriculaBuscada = '';

  /// Compara textos sin importar acentos, mayusculas ni espacios extra.
  static String _llave(String s) {
    const con = 'áéíóúüÁÉÍÓÚÜñÑ';
    const sin = 'aeiouuAEIOUUnN';
    var t = s;
    for (var i = 0; i < con.length; i++) {
      t = t.replaceAll(con[i], sin[i]);
    }
    return t.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Busca [valor] dentro de [opciones] tolerando diferencias de escritura.
  String? _matchOpcion(String valor, List<String> opciones) {
    if (valor.trim().isEmpty) return null;
    final k = _llave(valor);
    for (final o in opciones) {
      if (_llave(o) == k) return o;
    }
    for (final o in opciones) {
      if (_llave(o).contains(k) || k.contains(_llave(o))) return o;
    }
    return null;
  }

  /// Mapea cualquier modalidad almacenada a una de las dos oficiales:
  /// "No escolarizada" (incluye el antiguo "Virtual") o "Mixta".
  String? _modalidadAOpcion(String valor) {
    final k = _llave(valor);
    if (k.isEmpty) return null;
    if (k.contains('mixt')) return 'Mixta';
    if (k.contains('virtual') ||
        k.contains('escolar') ||
        k.contains('distancia') ||
        k.contains('linea') ||
        k.contains('línea')) {
      return 'No escolarizada';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _cargarGeneraciones();
    _cargarFotoPerfil();

    if (widget.esEdicion && widget.perfilExistente != null) {
      final p = widget.perfilExistente!;
      _matriculaController.text = p.matricula;
      _nombreController.text = p.nombreCompleto;
      _curpController.text = p.curp;
      _curpOriginal = p.curp.trim();
      _programaSeleccionado = _matchOpcion(
        p.programa,
        programasAcademicos.map((x) => x.nombre).toList(),
      );
      _modalidadSeleccionada = _modalidadAOpcion(p.modalidad);
      // La generacion se ajusta cuando termina de cargar la lista.
      _generacionSeleccionada =
          p.generacion.trim().isEmpty ? null : p.generacion.trim();
      // Trae los datos OFICIALES con los overrides del padrón aplicados, para
      // que si un administrador corrigió el nombre (u otro dato) se refleje
      // aquí aunque el perfil guardado todavía tenga el valor anterior.
      _refrescarDesdeCanonico();
    }

    // Si no hay CURP todavía, la buscamos sola por matrícula (curps.json).
    _prellenarCurpSiFalta();

    // En alta nueva, autocompletar Programa/Generación/Modalidad/Nombre
    // desde el padrón en cuanto la matrícula esté completa.
    if (!widget.esEdicion) {
      _matriculaController.addListener(_alCambiarMatricula);
    }
  }

  // Trae los datos oficiales del alumno (overrides del padrón ya aplicados) y
  // actualiza el formulario. Así, si un administrador corrigió el nombre desde
  // PADRÓN-CORRECCIONES, aquí se ve el valor corregido.
  Future<void> _refrescarDesdeCanonico() async {
    final mat = (widget.perfilExistente?.matricula ?? '').trim();
    if (mat.isEmpty) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alumno_canonico',
        'matricula': mat,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || data['alumno'] is! Map) return;
      final al = data['alumno'] as Map<String, dynamic>;
      final nombre = (al['nombre'] ?? '').toString().trim();
      final programa = (al['programa'] ?? '').toString().trim();
      final modalidad = (al['modalidad'] ?? '').toString().trim();
      final generacion = (al['generacion'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        if (nombre.isNotEmpty) _nombreController.text = nombre;
        if (programa.isNotEmpty) {
          _programaOficial = programa;
          final opc = _matchOpcion(
              programa, programasAcademicos.map((x) => x.nombre).toList());
          if (opc != null) _programaSeleccionado = opc;
        }
        if (modalidad.isNotEmpty) {
          _modalidadOficial = modalidad;
          final mo = _modalidadAOpcion(modalidad);
          if (mo != null) _modalidadSeleccionada = mo;
        }
        if (generacion.isNotEmpty) {
          _generacionOficial = generacion;
          _generacionSeleccionada = _generaciones.isEmpty
              ? generacion
              : (_matchOpcion(
                      generacion, _generaciones.map((g) => g.nombre).toList()) ??
                  generacion);
        }
      });
    } catch (_) {}
  }

  void _alCambiarMatricula() {
    final mat = _matriculaController.text.trim();
    if (mat.length == matriculaLongitud && mat != _ultimaMatriculaBuscada) {
      _ultimaMatriculaBuscada = mat;
      _autopoblarPorMatricula(mat);
    }
  }

  /// Busca al alumno por matrícula en el padrón y rellena los campos con los
  /// valores oficiales, ya emparejados con las opciones de los menús. Así se
  /// evita que el alumno escriba un programa/generación que no empate exacto.
  Future<void> _autopoblarPorMatricula(String matricula) async {
    setState(() {
      _buscandoDatos = true;
      _datosAutollenados = false;
    });
    try {
      final a = await AlumnosService.buscarPorMatricula(matricula);
      if (!mounted) return;
      if (a == null) {
        setState(() => _buscandoDatos = false);
        return;
      }
      final progOpc = _matchOpcion(
        a.programa,
        programasAcademicos.map((x) => x.nombre).toList(),
      );
      final modOpc = _modalidadAOpcion(a.modalidad);
      final genOpc = _generaciones.isEmpty
          ? (a.generacion.trim().isEmpty ? null : a.generacion.trim())
          : _matchOpcion(a.generacion, _generaciones.map((g) => g.nombre).toList());
      setState(() {
        if (a.nombre.trim().isNotEmpty &&
            _nombreController.text.trim().isEmpty) {
          _nombreController.text = a.nombre.trim();
        }
        // Conservar los valores oficiales del padrón (con acentos) para guardarlos
        // tal cual; el menú solo muestra la opción emparejada.
        if (a.programa.trim().isNotEmpty) _programaOficial = a.programa.trim();
        if (a.modalidad.trim().isNotEmpty) _modalidadOficial = a.modalidad.trim();
        if (a.generacion.trim().isNotEmpty) _generacionOficial = a.generacion.trim();
        if (progOpc != null) _programaSeleccionado = progOpc;
        if (modOpc != null) _modalidadSeleccionada = modOpc;
        if (genOpc != null) _generacionSeleccionada = genOpc;
        _buscandoDatos = false;
        _datosAutollenados = true;
      });
    } catch (_) {
      if (mounted) setState(() => _buscandoDatos = false);
    }
  }

  // Trae la CURP del servidor por matrícula y la pone si el campo está vacío.
  Future<void> _prellenarCurpSiFalta() async {
    if (_curpController.text.trim().isNotEmpty) return;
    final mat = _matriculaController.text.trim();
    if (mat.isEmpty) return;
    var curp = await CurpsService.curpDe(mat);
    // Si curps.json no la tiene, intenta la CURP que el propio alumno guardó
    // antes desde su perfil (endpoint curp_de del backend).
    if (curp.isEmpty) {
      try {
        final uri = Uri.parse(guardianUrl).replace(queryParameters: {
          'accion': 'curp_de',
          'matricula': mat,
        });
        final resp = await http.get(uri).timeout(const Duration(seconds: 12));
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          curp = (data['curp'] ?? '').toString().trim().toUpperCase();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (curp.isNotEmpty && _curpController.text.trim().isEmpty) {
      setState(() => _curpController.text = curp);
    }
  }

  @override
  void dispose() {
    _matriculaController.removeListener(_alCambiarMatricula);
    _matriculaController.dispose();
    _nombreController.dispose();
    _curpController.dispose();
    super.dispose();
  }

  Future<void> _cargarGeneraciones() async {
    setState(() {
      _cargandoGeneraciones = true;
      _errorGeneraciones = null;
    });

    try {
      final lista = await GeneracionesService.obtener();
      if (!mounted) return;
      setState(() {
        _generaciones = lista;
        _cargandoGeneraciones = false;
        // Empareja la generacion guardada con la lista (tolerante a escritura).
        if (_generacionSeleccionada != null) {
          final nombres = lista.map((g) => g.nombre).toList();
          _generacionSeleccionada =
              _matchOpcion(_generacionSeleccionada!, nombres) ??
                  _generacionSeleccionada;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoGeneraciones = false;
        _errorGeneraciones = 'No se pudo cargar la lista de generaciones';
      });
    }
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_programaSeleccionado == null ||
        _modalidadSeleccionada == null ||
        _generacionSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Por favor completa todos los campos'),
        ),
      );
      return;
    }

    final matricula = _matriculaController.text.trim();
    final nombre = _nombreController.text.trim();
    final curp = _curpController.text.trim().toUpperCase();

    // Si aún no tenemos los valores oficiales del padrón (p. ej. al editar),
    // buscarlos ahora para guardarlos con su formato canónico (con acentos).
    if (_programaOficial == null && matricula.isNotEmpty) {
      final a = await AlumnosService.buscarPorMatricula(matricula);
      if (a != null) {
        if (a.programa.trim().isNotEmpty) _programaOficial = a.programa.trim();
        if (a.modalidad.trim().isNotEmpty) _modalidadOficial = a.modalidad.trim();
        if (a.generacion.trim().isNotEmpty) {
          _generacionOficial = a.generacion.trim();
        }
      }
    }

    // Preferir el texto oficial del padrón cuando coincide con lo seleccionado
    // (misma llave normalizada). Así el dato guardado empata exacto con el
    // backend; si el alumno eligió algo distinto a propósito, se respeta.
    var programa = _programaSeleccionado!;
    if (_programaOficial != null &&
        _llave(_programaOficial!) == _llave(programa)) {
      programa = _programaOficial!;
    }
    var modalidad = _modalidadSeleccionada!;
    if (_modalidadOficial != null &&
        _llave(_modalidadOficial!) == _llave(modalidad)) {
      modalidad = _modalidadOficial!;
    }
    var generacion = _generacionSeleccionada!;
    if (_generacionOficial != null &&
        _llave(_generacionOficial!) == _llave(generacion)) {
      generacion = _generacionOficial!;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirma tu informacion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verifica que estos datos sean correctos:',
              style: TextStyle(fontSize: 13, color: cessumMuted(context)),
            ),
            const SizedBox(height: 12),
            _ConfirmRow(etiqueta: 'Nombre:', valor: nombre),
            const SizedBox(height: 8),
            _ConfirmRow(etiqueta: 'Matricula:', valor: matricula),
            const SizedBox(height: 8),
            _ConfirmRow(etiqueta: 'CURP:', valor: curp),
            const SizedBox(height: 8),
            _ConfirmRow(etiqueta: 'Programa:', valor: programa),
            const SizedBox(height: 8),
            _ConfirmRow(etiqueta: 'Modalidad:', valor: modalidad),
            const SizedBox(height: 8),
            _ConfirmRow(etiqueta: 'Generacion:', valor: generacion),
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

    final perfil = StudentProfile(
      matricula: matricula,
      nombreCompleto: nombre,
      programa: programa,
      modalidad: modalidad,
      generacion: generacion,
      curp: curp,
    );

    await perfil.save();

    // Además del guardado local, manda la CURP al servidor para que quede
    // registrada (se usa en documentos y credencial) y persista entre sesiones
    // y dispositivos. Si falla la red, no bloquea el guardado local.
    if (curp.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'curp_guardar',
                'matricula': matricula,
                'curp': curp,
              }),
            )
            .timeout(const Duration(seconds: 20));
      } catch (_) {}
    }

    if (!mounted) return;

    if (widget.esEdicion) {
      Navigator.pop(context, perfil);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MenuScreen()),
      );
    }
  }

  String? _validarMatricula(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresa tu matricula';
    }
    final v = value.trim();
    if (v.length != matriculaLongitud) {
      return 'La matricula debe tener $matriculaLongitud digitos';
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(v)) {
      return 'La matricula solo debe contener numeros';
    }
    return null;
  }

  String? _validarNombre(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresa tu nombre completo';
    }
    if (value.trim().length < 5) {
      return 'Ingresa tu nombre completo (nombre y apellidos)';
    }
    return null;
  }

  String? _validarCurp(String? value) {
    final v = (value ?? '').trim().toUpperCase();
    if (v.isEmpty) {
      return 'Ingresa tu CURP';
    }
    if (v.length != 18) {
      return 'La CURP debe tener exactamente 18 caracteres';
    }
    if (!RegExp(r'^[A-Z0-9]{18}$').hasMatch(v)) {
      return 'La CURP solo debe tener letras y numeros (sin espacios)';
    }
    return null;
  }

  // ---------------------------------------------------------------
  // FOTO DE PERFIL (la misma de la credencial)
  // ---------------------------------------------------------------
  String get _matriculaActual =>
      (widget.perfilExistente?.matricula ?? _matriculaController.text).trim();

  Future<void> _cargarFotoPerfil() async {
    final mat = _matriculaActual;
    if (mat.isEmpty) return;
    setState(() => _cargandoFoto = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'perfil_foto',
        'matricula': mat,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final b64 = (data['b64'] ?? '').toString();
      if (data['ok'] == true && data['existe'] == true && b64.isNotEmpty) {
        final bytes = base64Decode(b64);
        if (!mounted) return;
        setState(() => _fotoBytes = bytes);
      }
    } catch (_) {
      // Sin foto o sin conexión: se queda el avatar con iniciales.
    } finally {
      if (mounted) setState(() => _cargandoFoto = false);
    }
  }

  Future<void> _elegirFotoPerfil() async {
    try {
      final foto = await seleccionarFoto();
      if (foto == null || !mounted) return;
      setState(() {
        _fotoNueva = Uint8List.fromList(foto.bytes);
        _fotoBytes = _fotoNueva;
        _fotoMime = foto.mime;
      });
      await _subirFotoPerfil();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('No se pudo abrir el selector de fotos: $e'),
      ));
    }
  }

  Future<void> _subirFotoPerfil() async {
    final mat = _matriculaActual;
    final bytes = _fotoNueva;
    if (mat.isEmpty || bytes == null) return;
    setState(() => _subiendoFoto = true);
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'perfil_foto_guardar',
              'matricula': mat,
              'fotoBase64': base64Encode(bytes),
              'fotoMime': _fotoMime,
            }),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _fotoNueva = null;
          _fotoActualizadaEl = 'hoy';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF1E8E3E),
          content: Text('Foto actualizada. También se usará en tu credencial.'),
        ));
      } else {
        throw Exception(data['error'] ?? 'No se pudo guardar la foto');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('No se pudo guardar tu foto: $e'),
      ));
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  String get _iniciales {
    final partes = _nombreController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((x) => x.isNotEmpty)
        .toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first.substring(0, 1).toUpperCase();
    return (partes[0].substring(0, 1) + partes[1].substring(0, 1)).toUpperCase();
  }

  Widget _avatarPerfil() {
    final tieneMat = _matriculaActual.isNotEmpty;
    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cessumGold.withValues(alpha: 0.15),
                border: Border.all(color: cessumGold.withValues(alpha: 0.5), width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: _cargandoFoto
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cessumRed),
                      ),
                    )
                  : (_fotoBytes != null
                      ? Image.memory(_fotoBytes!, fit: BoxFit.cover)
                      : Center(
                          child: Text(
                            _iniciales,
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w700,
                              color: cessumRed,
                            ),
                          ),
                        )),
            ),
            Material(
              color: cessumRed,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: (_subiendoFoto || !tieneMat) ? null : _elegirFotoPerfil,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _subiendoFoto
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.photo_camera,
                          size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: (_subiendoFoto || !tieneMat) ? null : _elegirFotoPerfil,
          icon: const Icon(Icons.photo_library_outlined,
              size: 18, color: cessumRed),
          label: Text(
            _fotoBytes != null ? 'Cambiar foto' : 'Subir mi foto',
            style: const TextStyle(color: cessumRed, fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          tieneMat
              ? 'Esta es la foto que aparece en tu credencial. Usa una foto '
                  'de frente, con fondo claro.'
              : 'Escribe tu matrícula para poder subir tu foto.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.35, color: cessumMuted(context)),
        ),
      ],
    );
  }

  /// CURP completa (18 caracteres). Mientras no esté, no se puede salir.
  bool get _curpListo => _curpController.text.trim().length == 18;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _curpListo,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Registra tu CURP (18 caracteres) antes de salir.'),
          ));
        }
      },
      child: Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        title: Text(
          widget.esEdicion ? 'Editar perfil' : 'Mi perfil',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        automaticallyImplyLeading: widget.esEdicion,
        leading: widget.esEdicion
            ? null
            : IconButton(
                icon: const Icon(Icons.home),
                tooltip: 'Volver al inicio',
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                ),
              ),
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
                children: [
                  const Icon(Icons.info_outline, color: cessumGold, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Importante',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.esEdicion
                              ? 'Estos son tus datos oficiales registrados. Si alguno es incorrecto, usa el boton "Solicitar modificacion de datos" al final de esta pantalla.'
                              : 'Confirma en tu correo electronico institucional el numero de matricula que te fue asignado al inscribirte. Si no la encuentras, contacta a contacto@cessum.mx',
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Foto de perfil (la misma que usa la credencial)
            _avatarPerfil(),
            const SizedBox(height: 20),

            // Nombre completo
            const _Etiqueta('Nombre completo'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nombreController,
              readOnly: widget.esEdicion,
              textCapitalization: TextCapitalization.words,
              decoration: _campoDecoration('Ej. Maria Lopez Garcia',
                  bloqueado: widget.esEdicion),
              validator: _validarNombre,
            ),
            const SizedBox(height: 20),

            // Matricula
            const _Etiqueta('Matricula'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _matriculaController,
              readOnly: widget.esEdicion,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(matriculaLongitud),
              ],
              decoration: _campoDecoration('Ej. 25090245',
                  bloqueado: widget.esEdicion),
              validator: _validarMatricula,
            ),
            const SizedBox(height: 12),

            if (!widget.esEdicion && _buscandoDatos)
              Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cessumRed),
                    ),
                    SizedBox(width: 10),
                    Text('Buscando tus datos...',
                        style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
                  ],
                ),
              ),
            if (!widget.esEdicion && _datosAutollenados && !_buscandoDatos)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E8E3E).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: Color(0xFF1E8E3E), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Encontramos tus datos y llenamos tu programa, modalidad y generacion. Verifica que esten correctos.',
                        style: TextStyle(fontSize: 12, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),

            if (!widget.esEdicion) ...[
              TextButton.icon(
                onPressed: () => _mostrarAyudaMatricula(context),
                icon:
                    const Icon(Icons.help_outline, size: 18, color: cessumRed),
                label: const Text(
                  'No encuentro mi matricula',
                  style: TextStyle(color: cessumRed, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // CURP
            const _Etiqueta('CURP'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _curpController,
              readOnly: widget.esEdicion && _curpOriginal.isNotEmpty,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                _UpperCaseTextFormatter(),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(18),
              ],
              decoration: _campoDecoration(
                  '18 caracteres, ej. MISJ850101HSRRLN09',
                  bloqueado: widget.esEdicion && _curpOriginal.isNotEmpty),
              validator: _validarCurp,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            // Programa
            const _Etiqueta('Programa academico'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _programaSeleccionado,
              isExpanded: true,
              hint: const Text('Selecciona tu programa'),
              decoration: _campoDecoration('',
                  bloqueado:
                      widget.esEdicion && _programaSeleccionado != null),
              items: programasAcademicos
                  .map((p) => DropdownMenuItem<String>(
                        value: p.nombre,
                        child: Text(p.nombre, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: widget.esEdicion && _programaSeleccionado != null
                  ? null
                  : (v) => setState(() => _programaSeleccionado = v),
              disabledHint: Text(
                _programaSeleccionado ?? '',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: cessumInk(context)),
              ),
              validator: (v) => v == null ? 'Selecciona tu programa' : null,
            ),
            const SizedBox(height: 20),

            // Modalidad
            const _Etiqueta('Modalidad'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _modalidadSeleccionada,
              isExpanded: true,
              hint: const Text('Selecciona tu modalidad'),
              decoration: _campoDecoration('',
                  bloqueado:
                      widget.esEdicion && _modalidadSeleccionada != null),
              items: modalidadesEstudio
                  .map((m) => DropdownMenuItem<String>(
                        value: m,
                        child: Text(m),
                      ))
                  .toList(),
              onChanged: widget.esEdicion && _modalidadSeleccionada != null
                  ? null
                  : (v) => setState(() => _modalidadSeleccionada = v),
              disabledHint: Text(
                _modalidadSeleccionada ?? '',
                style: TextStyle(color: cessumInk(context)),
              ),
              validator: (v) => v == null ? 'Selecciona tu modalidad' : null,
            ),
            const SizedBox(height: 20),

            // Generacion
            const _Etiqueta('Generacion'),
            const SizedBox(height: 6),
            if (_cargandoGeneraciones)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cessumRed,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('Cargando generaciones...',
                        style: TextStyle(color: cessumMuted(context))),
                  ],
                ),
              )
            else if (_errorGeneraciones != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_errorGeneraciones!),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _cargarGeneraciones,
                      icon: const Icon(Icons.refresh,
                          size: 16, color: cessumRed),
                      label: const Text('Reintentar',
                          style: TextStyle(color: cessumRed)),
                    ),
                  ],
                ),
              )
            else
              // (24-sep) Con búsqueda: son TODAS las generaciones. Va dentro de un
              // FormField para conservar la validación del formulario.
              FormField<String>(
                initialValue: _generacionSeleccionada,
                validator: (_) =>
                    _generacionSeleccionada == null ? 'Selecciona tu generación' : null,
                builder: (campo) {
                  final bloqueado = widget.esEdicion && _generacionSeleccionada != null;
                  return CessumSelectorBuscable<String>(
                    label: 'Generación',
                    valor: _generacionSeleccionada,
                    opciones: [
                      if (_generacionSeleccionada != null &&
                          !_generaciones.any((g) => g.nombre == _generacionSeleccionada))
                        _generacionSeleccionada!,
                      ..._generaciones.map((g) => g.nombre),
                    ],
                    etiqueta: (g) => g,
                    hint: 'Selecciona tu generación',
                    decoracion: _campoDecoration('', bloqueado: bloqueado)
                        .copyWith(errorText: campo.errorText),
                    onChanged: bloqueado
                        ? null
                        : (v) {
                            setState(() => _generacionSeleccionada = v);
                            campo.didChange(v);
                          },
                  );
                },
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
            if (widget.esEdicion) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumGold,
                    side: const BorderSide(color: cessumGold, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _solicitarModificacion,
                  icon: const Icon(Icons.edit_note, size: 20),
                  label: const Text(
                    'Solicitar modificacion de datos',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
      ),
    );
  }

  /// Dialogo para pedir a Vicerrectoria la correccion de un dato oficial.
  Future<void> _solicitarModificacion() async {
    final campos = <String>[
      'Nombre completo',
      'CURP',
      'Programa academico',
      'Modalidad',
      'Generacion',
      'Matricula',
    ];
    String campo = campos.first;
    final valorCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();

    final enviar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Solicitar modificacion'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Indica que dato es incorrecto y cual es el valor correcto. Vicerrectoria revisara tu solicitud.',
                  style: TextStyle(fontSize: 13, color: cessumMuted(context)),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: campo,
                  isExpanded: true,
                  decoration: _campoDecoration(''),
                  items: campos
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setLocal(() => campo = v ?? campo),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valorCtrl,
                  decoration: _campoDecoration('Valor correcto'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: motivoCtrl,
                  maxLines: 2,
                  decoration:
                      _campoDecoration('Motivo o comentario (opcional)'),
                ),
              ],
            ),
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
              onPressed: () {
                if (valorCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );

    if (enviar != true || !mounted) return;

    final valorActual = switch (campo) {
      'Nombre completo' => _nombreController.text.trim(),
      'CURP' => _curpController.text.trim(),
      'Programa academico' => _programaSeleccionado ?? '',
      'Modalidad' => _modalidadSeleccionada ?? '',
      'Generacion' => _generacionSeleccionada ?? '',
      _ => _matriculaController.text.trim(),
    };

    final obs = StringBuffer()
      ..writeln('SOLICITUD DE MODIFICACION DE DATOS DE PERFIL')
      ..writeln('Dato a modificar: $campo')
      ..writeln('Valor actual: $valorActual')
      ..writeln('Valor correcto solicitado: ${valorCtrl.text.trim()}');
    if (motivoCtrl.text.trim().isNotEmpty) {
      obs.writeln('Motivo: ${motivoCtrl.text.trim()}');
    }

    try {
      final correo = await SessionStore.validEmail() ?? '';
      final payload = {
        'accion': 'tramite_enviar',
        'nombre': _nombreController.text.trim(),
        'matricula': _matriculaController.text.trim(),
        'correo': correo,
        'programa': _programaSeleccionado ?? '',
        'modalidad': _modalidadSeleccionada ?? '',
        'generacion': _generacionSeleccionada ?? '',
        'tipoTramite': 'Modificacion de datos de perfil',
        'observaciones': obs.toString(),
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo enviar la solicitud.');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text(
              'Solicitud enviada. Vicerrectoria revisara la modificacion.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
              'No se pudo enviar la solicitud. Intenta de nuevo. ($e)'),
        ),
      );
    }
  }

  InputDecoration _campoDecoration(String hint, {bool bloqueado = false}) {
    return InputDecoration(
      hintText: hint.isEmpty ? null : hint,
      filled: true,
      // (24-sep) Modo oscuro: con relleno blanco fijo, el texto (del tema) salía blanco sobre blanco.
      fillColor: bloqueado ? cessumMuted(context).withValues(alpha: 0.10) : Theme.of(context).cardColor,
      suffixIcon: bloqueado
          ? Icon(Icons.lock_outline, size: 18, color: cessumFaint(context))
          : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).dividerColor),
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

  void _mostrarAyudaMatricula(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Como encontrar mi matricula'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tu matricula te fue enviada por correo electronico al momento de inscribirte. Busca correos de CESSUM o contacto@cessum.mx.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
            SizedBox(height: 12),
            Text(
              'Si aun asi no la encuentras, escribenos a contacto@cessum.mx con tu nombre completo y te confirmaremos tu matricula.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Helpers.abrirCorreo(
                context: context,
                destinatario: correoInstitucional,
                asunto: 'Solicitud de matricula',
                cuerpo:
                    'Buen dia equipo CESSUM,\n\nNo encuentro mi matricula en mis correos. Mis datos:\n\nNombre completo: \nPrograma academico: \nGeneracion: \n\nAgradezco su apoyo.',
              );
            },
            child: const Text('Escribir correo'),
          ),
        ],
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

class _ConfirmRow extends StatelessWidget {
  final String etiqueta;
  final String valor;

  const _ConfirmRow({required this.etiqueta, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(etiqueta,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

/// Convierte a MAYUSCULAS todo lo que el alumno escribe en el campo CURP.
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
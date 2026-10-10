import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'foto_web_picker.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';
import 'profile_setup_screen.dart';
import 'student_profile.dart';

// =====================================================================
// PANTALLA: "Mi credencial" (lado del ALUMNO)
// ---------------------------------------------------------------------
// Lee la CURP del perfil del alumno (no la vuelve a pedir). Deja subir
// una foto, solicitar la credencial y ver en que estado va.
//
// CONTRATO CON EL GUARDIAN (debe coincidir con guardian_cessum.gs):
//   estado_credencial (GET, parametro: matricula)
//     -> { ok: true, estado: { estado, curp, observaciones, pdfUrl, fotoUrl } }
//     estado es uno de: NoSolicitada / Pendiente / Observaciones /
//                       Aprobada / Rechazada
//   solicitar_credencial (POST JSON, campos: accion, matricula, nombre,
//     programa, modalidad, generacion, correo, curp, fotoBase64, fotoMime)
//     -> { ok: true, id: 'CRED-...' }
// =====================================================================
class MiCredencialScreen extends StatefulWidget {
  const MiCredencialScreen({super.key});

  @override
  State<MiCredencialScreen> createState() => _MiCredencialScreenState();
}

class _MiCredencialScreenState extends State<MiCredencialScreen> {
  StudentProfile? _perfil;

  bool _cargando = true;
  bool _esEgresado = false;
  String? _error;

  // Datos que devuelve el Guardian sobre el estado de la credencial.
  String _estado = 'NoSolicitada';
  String _observaciones = '';
  String _pdfUrl = '';
  // (25-sep) Versión imprimible: hoja carta con las dos caras a tamaño real.
  String _pdfImprimible = '';
  bool _hayImprimible = false;
  bool _generandoImprimible = false;
  String _fotoUrl = '';
  String _verUrl = '';

  // Foto nueva que el alumno acaba de elegir (todavia no enviada).
  Uint8List? _fotoBytes;
  String _fotoMime = 'image/jpeg';

  // Foto del alumno ya guardada, traída del Guardián en base64 para mostrarla
  // en la tarjeta (Drive no carga directo en Image.network).
  Uint8List? _fotoCardBytes;

  bool _enviando = false;

  // El alumno pidió actualizar/volver a solicitar su credencial (Aprobada o
  // Rechazada). Muestra el selector de foto para reenviar.
  bool _reSolicitar = false;

  /* (1-sep) FOTO DE PERFIL. La foto del perfil y la de la credencial son la
     misma en el Guardián: si el alumno ya subió la suya en "Editar perfil",
     aquí se le ofrece usarla tal cual en vez de volver a buscarla. Si sube
     una actualizada, el Guardián la copia al perfil, así que la app también
     queda actualizada. */
  bool _perfilTieneFoto = false;
  String _perfilFotoEl = '';
  Uint8List? _perfilFotoBytes;
  bool _usarFotoPerfil = false;   // el alumno eligió usar la del perfil

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : cessumInk(context);
  Color get _textoSuave => cessumMuted(context);

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    final perfil = await StudentProfile.load();
    if (!mounted) return;

    if (perfil == null) {
      setState(() {
        _cargando = false;
        _error = 'No encontramos tu perfil. Vuelve al inicio e ingresa tus '
            'datos antes de solicitar tu credencial.';
      });
      return;
    }

    _perfil = perfil;
    await _consultarEstado();
    await _consultarFotoPerfil();
  }

  // ¿Ya tiene foto de perfil? Si sí, la bajamos para ofrecérsela.
  Future<void> _consultarFotoPerfil() async {
    final perfil = _perfil;
    if (perfil == null) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'perfil_foto_estado',
        'matricula': perfil.matricula,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || data['existe'] != true) return;
      if (!mounted) return;
      setState(() {
        _perfilTieneFoto = true;
        _perfilFotoEl = (data['actualizadaEl'] ?? '').toString();
      });
      // Traemos la imagen para la vista previa.
      final uri2 = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'perfil_foto',
        'matricula': perfil.matricula,
      });
      final r2 = await http.get(uri2).timeout(const Duration(seconds: 25));
      final d2 = jsonDecode(r2.body) as Map<String, dynamic>;
      final b64 = (d2['b64'] ?? '').toString();
      if (d2['ok'] == true && b64.isNotEmpty && mounted) {
        setState(() => _perfilFotoBytes = base64Decode(b64));
      }
    } catch (_) {
      // Sin foto de perfil o sin conexión: sigue el flujo normal.
    }
  }

  // Bloque de decisión: usar la foto del perfil o subir una actualizada.
  Widget _decisionFotoPerfil() {
    if (!_perfilTieneFoto) return const SizedBox.shrink();
    final usando = _usarFotoPerfil && _fotoBytes == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: usando ? cessumGold : (cessumIsDark(context) ? Colors.white24 : Colors.grey.shade300),
            width: usando ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ya tienes una foto en tu perfil',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: _textoFuerte)),
          const SizedBox(height: 4),
          Text(
            _perfilFotoEl.isEmpty
                ? '¿Quieres usarla para tu credencial o subir una actualizada?'
                : 'Actualizada el $_perfilFotoEl. ¿La usas para tu credencial o subes una actualizada?',
            style: TextStyle(fontSize: 12.5, height: 1.35, color: _textoSuave),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 84,
                height: 106,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: cessumIsDark(context) ? Colors.white24 : Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: _perfilFotoBytes != null
                    ? Image.memory(_perfilFotoBytes!, fit: BoxFit.cover)
                    : const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumRed),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: usando ? cessumGold : cessumRed,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: (_enviando || _perfilFotoBytes == null)
                          ? null
                          : () => setState(() {
                                _usarFotoPerfil = true;
                                _fotoBytes = null;   // el Guardián toma la del perfil
                              }),
                      icon: Icon(usando ? Icons.check_circle : Icons.person_outline,
                          size: 18),
                      label: Text(usando ? 'Usarás esta foto' : 'Usar esta foto'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumRed),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: _enviando
                          ? null
                          : () async {
                              setState(() => _usarFotoPerfil = false);
                              await _elegirFoto();
                            },
                      icon: const Icon(Icons.photo_camera, size: 18, color: cessumRed),
                      label: const Text('Subir una actualizada',
                          style: TextStyle(color: cessumRed)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_fotoBytes != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Usarás la foto nueva que acabas de elegir. También quedará '
                'como tu foto de perfil en la app.',
                style: TextStyle(fontSize: 12, color: _textoSuave),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _consultarEstado() async {
    final perfil = _perfil;
    if (perfil == null) return;

    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'estado_credencial',
        'matricula': perfil.matricula,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida del servidor');
      }

      final estado = (data['estado'] as Map<String, dynamic>? ?? {});
      if (!mounted) return;
      setState(() {
        _estado = (estado['estado'] ?? 'NoSolicitada').toString();
        _esEgresado = estado['esEgresado'] == true;
        _observaciones = (estado['observaciones'] ?? '').toString();
        _pdfUrl = (estado['pdfUrl'] ?? '').toString();
        _pdfImprimible = (estado['pdfImprimible'] ?? '').toString();
        _hayImprimible = estado['hayImprimible'] == true;
        _fotoUrl = (estado['fotoUrl'] ?? '').toString();
        _verUrl = (estado['verUrl'] ?? '').toString();
        _cargando = false;
      });
      if (_fotoUrl.isNotEmpty) {
        _cargarFotoTarjeta();
      } else if (mounted) {
        setState(() => _fotoCardBytes = null);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No pudimos consultar el estado de tu credencial. '
            'Revisa tu conexion e intenta de nuevo.';
      });
    }
  }

  // Trae la foto del alumno en base64 desde el Guardián (Drive no carga
  // directo en Image.network) y la deja lista para mostrarla con Image.memory.
  Future<void> _cargarFotoTarjeta() async {
    final perfil = _perfil;
    if (perfil == null) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'credencial_foto',
        'matricula': perfil.matricula,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final b64 = (data['b64'] ?? '').toString();
      if (data['ok'] == true && b64.isNotEmpty) {
        final bytes = base64Decode(b64);
        if (!mounted) return;
        setState(() => _fotoCardBytes = bytes);
      }
    } catch (_) {
      // Si falla, se queda el ícono; no es crítico.
    }
  }

  Future<void> _elegirFoto() async {
    try {
      final foto = await seleccionarFoto();
      if (foto == null) return; // el usuario cancelo
      if (!mounted) return;
      setState(() {
        _fotoBytes = Uint8List.fromList(foto.bytes);
        _fotoMime = foto.mime;
        _usarFotoPerfil = false;
      });
    } catch (e) {
      _aviso('No se pudo abrir el selector de fotos: $e', esError: true);
    }
  }

  Future<void> _solicitar({bool permitirSinFoto = false}) async {
    final perfil = _perfil;
    if (perfil == null) return;

    if (_fotoBytes == null && !permitirSinFoto && !_usarFotoPerfil) {
      _aviso(
          _perfilTieneFoto
              ? 'Elige si usas la foto de tu perfil o subes una actualizada.'
              : 'Primero elige una foto para tu credencial.',
          esError: true);
      return;
    }

    final correo = await SessionStore.validEmail();
    if (!mounted) return;
    if (correo == null || correo.isEmpty) {
      _aviso('Tu sesion expiro. Vuelve a entrar con tu correo.',
          esError: true);
      return;
    }

    setState(() => _enviando = true);

    final payload = <String, dynamic>{
      'accion': 'solicitar_credencial',
      'matricula': perfil.matricula,
      'nombre': perfil.nombreCompleto,
      'programa': perfil.programa,
      'modalidad': perfil.modalidad,
      'generacion': perfil.generacion,
      'correo': correo,
      'curp': perfil.curp,
    };
    // Solo mandamos foto si el alumno eligió una nueva. Si re-solicita sin
    // cambiarla, el Guardián conserva la foto anterior.
    if (_fotoBytes != null) {
      payload['fotoBase64'] = base64Encode(_fotoBytes!);
      payload['fotoMime'] = _fotoMime;
    }

    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));

      if (resp.statusCode != 200) {
        throw Exception('http ${resp.statusCode}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'El servidor reporto un error');
      }

      if (!mounted) return;
      setState(() {
        _enviando = false;
        _fotoBytes = null; // ya se envio
        _reSolicitar = false;
      });
      _aviso('Tu solicitud fue enviada. Queda en revision.');
      await _consultarEstado();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No se pudo enviar tu solicitud. Intenta de nuevo.',
          esError: true);
    }
  }

  Future<void> _editarPerfil() async {
    final perfil = _perfil;
    if (perfil == null) return;
    final actualizado = await Navigator.push<StudentProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          esEdicion: true,
          perfilExistente: perfil,
        ),
      ),
    );
    if (!mounted) return;
    if (actualizado != null) {
      _perfil = actualizado;
    }
    // Recargamos todo por si la CURP cambio.
    _cargarTodo();
  }

  void _aviso(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: esError ? Colors.redAccent : const Color(0xFF1E8E3E),
        content: Text(mensaje),
      ),
    );
  }

  // Botón "Volver a solicitar" y, al activarlo, el selector de foto para
  // reenviar. Se usa en los estados Aprobada y Rechazada.
  Widget _bloqueReSolicitar({String titulo = 'Volver a solicitar'}) {
    // (30-sep) Ya egresado: puede seguir viendo la credencial que le
    // aprobaron mientras era alumno activo, pero no volver a tramitarla.
    if (_esEgresado) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Tu programa concluyó, así que ya no puedes volver a tramitar '
          'esta credencial.',
          style: TextStyle(fontSize: 12.5, height: 1.4),
        ),
      );
    }
    if (!_reSolicitar) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _enviando ? null : () => setState(() => _reSolicitar = true),
          icon: const Icon(Icons.refresh, color: cessumRed),
          label: Text(titulo, style: const TextStyle(color: cessumRed)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: cessumRed),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _decisionFotoPerfil(),
        _selectorFoto(),
        const SizedBox(height: 8),
        Text(
          'Si no cambias la foto, conservaremos la actual. Al reenviar, tu '
          'credencial volverá a revisión.',
          style: TextStyle(fontSize: 12, color: cessumMuted(context)),
        ),
        const SizedBox(height: 12),
        _botonPrincipal(
          texto: 'Reenviar solicitud',
          onPressed:
              _enviando ? null : () => _solicitar(permitirSinFoto: true),
        ),
        const SizedBox(height: 2),
        TextButton(
          onPressed: _enviando
              ? null
              : () => setState(() {
                    _reSolicitar = false;
                    _fotoBytes = null;
                  }),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        title: const Text(
          'Mi credencial',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: cessumRed),
            )
          : RefreshIndicator(
              color: cessumRed,
              onRefresh: _cargarTodo,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [_contenido()],
              ),
            ),
    );
  }

  Widget _contenido() {
    if (_error != null) {
      return _tarjetaInfo(
        icono: Icons.error_outline,
        color: cessumRed,
        titulo: 'Algo salio mal',
        texto: _error!,
        accion: TextButton.icon(
          onPressed: _cargarTodo,
          icon: const Icon(Icons.refresh, color: cessumRed),
          label: const Text('Reintentar', style: TextStyle(color: cessumRed)),
        ),
      );
    }

    // Si el alumno aun no tiene CURP en su perfil, no puede solicitar.
    final perfil = _perfil!;
    // (30-sep) Egresado sin credencial previa: ya no aplica tramitarla.
    if (_esEgresado && _estado == 'NoSolicitada') {
      return _tarjetaInfo(
        icono: Icons.school_outlined,
        color: cessumGold,
        titulo: 'Tu credencial de alumno ya no aplica',
        texto: 'Tu programa concluyó, así que la credencial de alumno '
            'vigente ya no te corresponde. Si necesitas una constancia o '
            'documento oficial, pídelo en Trámites y documentos.',
      );
    }
    if (_estado == 'NoSolicitada' && perfil.curp.isEmpty) {
      return _tarjetaInfo(
        icono: Icons.assignment_ind,
        color: cessumGold,
        titulo: 'Falta tu CURP',
        texto:
            'Para tu credencial necesitamos tu CURP. Agregala en tu perfil y '
            'regresa a esta pantalla.',
        accion: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumGold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _editarPerfil,
            icon: const Icon(Icons.edit),
            label: const Text('Completar mi perfil'),
          ),
        ),
      );
    }

    switch (_estado) {
      case 'Pendiente':
        return _estadoPendiente();
      case 'Observaciones':
        return _estadoObservaciones();
      case 'Aprobada':
        return _estadoAprobada();
      case 'Rechazada':
        return _estadoRechazada();
      case 'NoSolicitada':
      default:
        return _estadoNoSolicitada();
    }
  }

  // ----- Estado: aun no ha solicitado -----
  Widget _estadoNoSolicitada() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tarjetaInfo(
          icono: Icons.badge,
          color: cessumRed,
          titulo: 'Solicita tu credencial digital',
          texto:
              'Sube una foto tipo identificacion (de frente, fondo claro) y '
              'envia tu solicitud. El area correspondiente la revisara y, una '
              'vez aprobada, podras descargar tu credencial en PDF.',
        ),
        const SizedBox(height: 16),
        _decisionFotoPerfil(),
        if (!_perfilTieneFoto || _fotoBytes != null) _selectorFoto(),
        const SizedBox(height: 20),
        _botonPrincipal(
          texto: 'Solicitar credencial',
          onPressed: ((_fotoBytes == null && !_usarFotoPerfil) || _enviando)
              ? null
              : _solicitar,
        ),
      ],
    );
  }

  // ----- Estado: en revision -----
  Widget _estadoPendiente() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tarjetaInfo(
          icono: Icons.hourglass_top,
          color: cessumGold,
          titulo: 'En revision',
          texto:
              'Ya recibimos tu solicitud. La estamos revisando; te avisaremos '
              'aqui mismo cuando este lista o si necesitamos algun cambio.',
        ),
        if (_fotoUrl.isNotEmpty) ...[
          const SizedBox(height: 16),
          _fotoEnviada(),
        ],
      ],
    );
  }

  // ----- Estado: el admin pidio cambios -----
  Widget _estadoObservaciones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tarjetaInfo(
          icono: Icons.feedback_outlined,
          color: cessumGold,
          titulo: 'Necesita correcciones',
          texto: _observaciones.isNotEmpty
              ? _observaciones
              : 'Se solicitaron cambios en tu credencial. Sube una nueva foto '
                  'y vuelve a enviar.',
        ),
        const SizedBox(height: 16),
        _selectorFoto(),
        const SizedBox(height: 20),
        _botonPrincipal(
          texto: 'Corregir y reenviar',
          onPressed: ((_fotoBytes == null && !_usarFotoPerfil) || _enviando)
              ? null
              : _solicitar,
        ),
      ],
    );
  }

  // ----- Estado: aprobada -----
  Widget _estadoAprobada() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _credencialLujo(),
        const SizedBox(height: 18),
        _tarjetaInfo(
          icono: Icons.verified,
          color: const Color(0xFF1E8E3E),
          titulo: 'Credencial aprobada',
          texto: 'Toca la tarjeta para ver el código QR. Descárgala en PDF con '
              'el botón de abajo para guardarla o imprimirla.',
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E8E3E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: _pdfUrl.isEmpty
                ? null
                : () => Helpers.abrirUrlExterna(_pdfUrl, context),
            icon: const Icon(Icons.download),
            label: const Text(
              'Descargar credencial',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (_hayImprimible) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E8E3E),
                side: const BorderSide(color: Color(0xFF1E8E3E)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _pdfUrl.isEmpty || _generandoImprimible ? null : _descargarImprimible,
              icon: _generandoImprimible
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined),
              label: Text(
                _generandoImprimible ? 'Preparando tu hoja…' : 'Versión imprimible (tamaño real)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hoja carta con el frente y el reverso a tamaño real (85.6 × 54 mm, como una tarjeta bancaria) y marcas de corte. '
            'Imprímela al 100 %, sin ajustar a la página, y recorta por las marcas.',
            style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context)),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        _bloqueReSolicitar(
            titulo: '¿Actualizar tu credencial? Volver a solicitar'),
      ],
    );
  }

  /// (25-sep) Pide (o genera la primera vez) la hoja imprimible y la abre.
  Future<void> _descargarImprimible() async {
    if (_pdfImprimible.isNotEmpty) {
      Helpers.abrirUrlExterna(_pdfImprimible, context);
      return;
    }
    final p = _perfil;
    if (p == null) return;
    setState(() => _generandoImprimible = true);
    try {
      final uri = Uri.parse('$guardianUrl?accion=credencial_imprimible&matricula=${Uri.encodeComponent(p.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No se pudo generar.');
      if (!mounted) return;
      setState(() => _pdfImprimible = '${data['url'] ?? ''}');
      if (_pdfImprimible.isNotEmpty) Helpers.abrirUrlExterna(_pdfImprimible, context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _generandoImprimible = false);
    }
  }

  // Tarjeta visual de la credencial, con animación de volteo.
  Widget _credencialLujo() {
    final p = _perfil!;

    Widget fotoMini() {
      if (_fotoBytes != null) {
        return Image.memory(_fotoBytes!, fit: BoxFit.cover);
      }
      if (_fotoCardBytes != null) {
        return Image.memory(_fotoCardBytes!, fit: BoxFit.cover);
      }
      if (_fotoUrl.isNotEmpty) {
        return Image.network(
          _fotoUrl,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, prog) => prog == null
              ? child
              : const Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54))),
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.person, color: Colors.white70, size: 38),
        );
      }
      return const Icon(Icons.person, color: Colors.white70, size: 38);
    }

    final front = Container(
      decoration: BoxDecoration(
        color: Colors.white, // credencial: blanca a propósito (imita la tarjeta y el QR debe escanearse)
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
                  child: const Text('VIGENTE',
                      style: TextStyle(
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
                      child: fotoMini(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.nombreCompleto.isNotEmpty
                            ? p.nombreCompleto
                            : 'Alumno',
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
                          p.programa,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: cessumRed,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.15),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('MATRÍCULA',
                          style: TextStyle(
                              color: CC.muted,
                              fontSize: 8.5,
                              letterSpacing: 1)),
                      Text(
                        p.matricula,
                        style: const TextStyle(
                            color: CC.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5),
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
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text('Más que una universidad, una familia',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Color(0xFFF3D9A6),
                          fontSize: 9,
                          fontStyle: FontStyle.italic)),
                ),
                Row(
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

    final back = Container(
      decoration: BoxDecoration(
        color: Colors.white, // credencial: blanca a propósito (imita la tarjeta y el QR debe escanearse)
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
                      color: Colors.white, // credencial: blanca a propósito (imita la tarjeta y el QR debe escanearse)
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: CC.gold.withValues(alpha: 0.45))),
                  child: _verUrl.isEmpty
                      ? const Center(
                          child:
                              Icon(Icons.qr_code_2, size: 56, color: CC.muted))
                      : Image.network(
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
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                          p.nombreCompleto.isNotEmpty
                              ? p.nombreCompleto
                              : p.matricula,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: CC.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text(
                          'Escanea el QR para validar esta credencial ante CESSUM.',
                          style: TextStyle(
                              color: CC.muted, fontSize: 11, height: 1.35)),
                      const SizedBox(height: 8),
                      Text('Matrícula ${p.matricula}',
                          style: const TextStyle(
                              color: CC.goldDark,
                              fontSize: 11,
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

    return FlipCard(front: front, back: back);
  }

  // ----- Estado: rechazada -----
  Widget _estadoRechazada() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tarjetaInfo(
          icono: Icons.cancel_outlined,
          color: cessumRed,
          titulo: 'Solicitud rechazada',
          texto: _observaciones.isNotEmpty
              ? _observaciones
              : 'Tu solicitud de credencial fue rechazada. Si crees que es un '
                  'error, comunicate con control escolar.',
        ),
        const SizedBox(height: 16),
        _bloqueReSolicitar(titulo: 'Volver a solicitar mi credencial'),
      ],
    );
  }

  // ----- Widgets reutilizables -----

  Widget _selectorFoto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Foto para la credencial',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _textoFuerte,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: _enviando ? null : _elegirFoto,
            child: Container(
              width: 150,
              height: 190,
              decoration: BoxDecoration(
                color: _superficie,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: cessumIsDark(context)
                        ? Colors.white24
                        : Colors.grey.shade300,
                    width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: _fotoBytes != null
                  ? Image.memory(_fotoBytes!, fit: BoxFit.cover)
                  : (_fotoCardBytes != null
                      ? Image.memory(_fotoCardBytes!, fit: BoxFit.cover)
                      : (_fotoUrl.isNotEmpty
                          ? Image.network(
                              _fotoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _placeholderFoto(),
                            )
                          : _placeholderFoto())),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton.icon(
            onPressed: _enviando ? null : _elegirFoto,
            icon: const Icon(Icons.photo_camera, size: 18, color: cessumRed),
            label: Text(
              _fotoBytes != null ? 'Cambiar foto' : 'Elegir foto',
              style: const TextStyle(color: cessumRed),
            ),
          ),
        ),
      ],
    );
  }

  Widget _placeholderFoto() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo, color: Colors.grey.shade400, size: 36),
        const SizedBox(height: 8),
        Text(
          'Toca para\nelegir foto',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      ],
    );
  }

  Widget _fotoEnviada() {
    return Column(
      children: [
        Text(
          'Foto que enviaste',
          style: TextStyle(fontSize: 13, color: cessumMuted(context)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 130,
            height: 165,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumIsDark(context) ? Colors.white24 : Colors.grey.shade300),
            ),
            clipBehavior: Clip.antiAlias,
            child: _fotoCardBytes != null
                ? Image.memory(_fotoCardBytes!, fit: BoxFit.cover)
                : Image.network(
                    _fotoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderFoto(),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _botonPrincipal({required String texto, VoidCallback? onPressed}) {
    return SizedBox(
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
        onPressed: onPressed,
        child: _enviando
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                texto,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _tarjetaInfo({
    required IconData icono,
    required Color color,
    required String titulo,
    required String texto,
    Widget? accion,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icono, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _textoFuerte,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      texto,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: _textoSuave,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (accion != null) ...[
            const SizedBox(height: 14),
            accion,
          ],
        ],
      ),
    );
  }
}

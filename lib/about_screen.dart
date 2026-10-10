import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/auth_gate.dart';
import 'auth/auth_service.dart';
import 'auth/session_store.dart';
import 'splash_screen.dart';
import 'welcome_screen.dart';
import 'helpers.dart';
import 'profile_setup_screen.dart';
import 'student_profile.dart';
import 'acceso_service.dart';   // (24-sep) cerrar también la llave de sesión en el servidor
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'curp_aviso.dart' show reCurpSec, UpperCaseTextFormatter;
import 'curps_service.dart';   // (8-oct-2026) refrescar el CURP contra el servidor al abrir esta pantalla
import 'mi_credencial_screen.dart';
import 'mi_expediente_screen.dart';
import 'acerca_comun.dart';   // (24-sep) bloques compartidos con el Acerca de docente

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  StudentProfile? _perfil;
  // (24-sep) Lo que le falta al alumno (mi_pendientes).
  Map<String, dynamic>? _pend;
  bool _cargandoPend = false;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = 'v${info.version} (build ${info.buildNumber})';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _version = 'v1.0.0';
        });
      }
    }

    final perfil = await StudentProfile.load();
    if (mounted) {
      setState(() {
        _perfil = perfil;
      });
    }
    await _refrescarCurp();
    await _cargarPendientes();
  }

  /* (8-oct-2026) El CURP guardado en este dispositivo (StudentProfile.load())
     solo se escribía al vincular la cuenta la primera vez o al capturarlo
     aquí mismo con _capturarCurp(): la resincronización en segundo plano
     (StudentAutoLink.sincronizarPerfilGuardado) corrige programa/modalidad/
     generación pero deja el CURP tal cual estaba guardado. Si se registraba
     o corregía por otra vía después de ese primer vínculo, esta pantalla
     seguía mostrando «No registrada» aunque sí estuviera en el sistema. Se
     vuelve a pedir al servidor cada vez que se abre «Acerca de»; si la
     consulta falla, se conserva el valor que ya había — nunca se borra un
     CURP que el alumno ya tenía guardado. */
  Future<void> _refrescarCurp() async {
    final p = _perfil;
    if (p == null || p.matricula.trim().isEmpty) return;
    try {
      final curpServidor = await CurpsService.curpDe(p.matricula.trim());
      if (curpServidor.isNotEmpty && curpServidor != p.curp) {
        final actualizado = StudentProfile(
          matricula: p.matricula,
          nombreCompleto: p.nombreCompleto,
          programa: p.programa,
          modalidad: p.modalidad,
          generacion: p.generacion,
          curp: curpServidor,
          esVistaAdmin: p.esVistaAdmin,
        );
        await actualizado.save();
        if (mounted) setState(() => _perfil = actualizado);
      }
    } catch (_) {
      // Sin conexión o falla del servidor: se queda con el valor local.
    }
  }

  /* ======================================================================
     (24-sep) LO QUE TE FALTA. Reúne en un solo lugar lo que el alumno tiene
     pendiente y lo lleva a donde se resuelve: la CURP y el promedio se
     capturan aquí mismo; los documentos abren «Mi expediente» y la
     credencial «Mi credencial». El Guardián solo le muestra lo suyo.
     ====================================================================== */
  Future<void> _cargarPendientes() async {
    final mat = _perfil?.matricula.trim() ?? '';
    if (mat.isEmpty) return;
    if (mounted) setState(() => _cargandoPend = true);
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'mi_pendientes', 'matricula': mat}))
          .timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _pend = d['ok'] == true ? d : null;
        _cargandoPend = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoPend = false);
    }
  }

  void _aviso(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : const Color(0xFF1E7F52),
      content: Text(m),
    ));
  }

  Future<void> _capturarCurp() async {
    final ctl = TextEditingController();
    final curp = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar mi CURP', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Escríbela tal como aparece en tu CURP oficial: 18 letras y números.',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              UpperCaseTextFormatter(),
              FilteringTextInputFormatter.allow(RegExp('[A-Z0-9]')),
              LengthLimitingTextInputFormatter(18),
            ],
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'CURP'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctl.text.trim().toUpperCase()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (curp == null || curp.isEmpty) return;
    if (!reCurpSec.hasMatch(curp)) {
      _aviso('Esa CURP no es válida: revisa la fecha de nacimiento, el sexo (H/M) y la clave del estado.', error: true);
      return;
    }
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'curp_guardar',
                'matricula': _perfil!.matricula.trim(),
                'curp': curp,
                'origen': 'Alumno (Acerca de)',
              }))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('CURP registrada. Gracias.');
      // (24-sep) También en el perfil de este navegador: «Mi perfil» la muestra al instante.
      final p0 = _perfil;
      if (p0 != null) {
        final nuevo = StudentProfile(
          matricula: p0.matricula,
          nombreCompleto: p0.nombreCompleto,
          programa: p0.programa,
          modalidad: p0.modalidad,
          generacion: p0.generacion,
          curp: curp,
          esVistaAdmin: p0.esVistaAdmin,
        );
        await nuevo.save();
        if (mounted) setState(() => _perfil = nuevo);
      }
      await _cargarPendientes();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _capturarPromedio() async {
    final ctl = TextEditingController();
    final texto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promedio de mi nivel anterior', style: TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
              'Es el promedio general que aparece en el certificado de tu licenciatura (o de tu maestría, si estudias un doctorado). '
              'Escríbelo tal cual, de 0 a 10 o de 0 a 100.',
              style: TextStyle(fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Promedio'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (texto == null || texto.isEmpty) return;
    final v = double.tryParse(texto.replaceAll(',', '.'));
    if (v == null || v <= 0 || v > 100) {
      _aviso('Escribe un número de 0 a 10 (o de 0 a 100).', error: true);
      return;
    }
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'promedio_ingreso_guardar',
            'matricula': _perfil!.matricula.trim(),
            'promedio': '$v',
          }))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Promedio registrado. Gracias.');
      await _cargarPendientes();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  /// (24-sep) Celular del alumno, para avisos por WhatsApp y SMS.
  Future<void> _capturarCelular() async {
    final ctl = TextEditingController();
    var acepta = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Registrar mi celular', style: TextStyle(fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Escríbelo a 10 dígitos. Lo usamos para avisarte de tus materias, pagos y trámites.',
                style: TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.phone,
              maxLength: 14,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Celular', hintText: '6421234567'),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: acepta,
              onChanged: (v) => setLocal(() => acepta = v == true),
              title: const Text('Acepto recibir avisos de CESSUM por WhatsApp', style: TextStyle(fontSize: 13)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final texto = ctl.text.trim();
    ctl.dispose();
    if (ok != true || texto.isEmpty) return;
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'celular_guardar',
                'matricula': _perfil?.matricula ?? '',
                'celular': texto,
                'acepta': acepta,
              }))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Celular registrado. Gracias.');
      await _cargarPendientes();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _resolver(String accion) async {
    switch (accion) {
      case 'curp':
        await _capturarCurp();
        return;
      case 'celular':
        await _capturarCelular();
        return;
      case 'promedio':
        await _capturarPromedio();
        return;
      case 'expediente':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MiExpedienteScreen()));
        break;
      case 'credencial':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MiCredencialScreen()));
        break;
      default:
        return;
    }
    await _cargarPendientes(); // al volver, se actualiza lo que falta
  }

  static const Map<String, String> _textoBoton = {
    'curp': 'Registrar mi CURP',
    'celular': 'Registrar mi celular',
    'promedio': 'Registrar mi promedio',
    'expediente': 'Ir a Mi expediente',
    'credencial': 'Ir a Mi credencial',
  };

  List<Widget> _seccionPendientes() {
    if (_perfil == null) return const [];
    if (_pend == null) {
      if (!_cargandoPend) return const [];
      return [
        const Padding(
          padding: EdgeInsets.only(bottom: 20),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))),
        ),
      ];
    }
    final items = ((_pend!['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (items.isEmpty) return const [];
    final faltan = (_pend!['faltan'] as num?)?.toInt() ?? 0;
    return [
      AcercaSeccion(
        titulo: faltan == 0 ? 'Tu expediente está completo' : 'Lo que te falta · $faltan',
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(it['ok'] == true ? Icons.check_circle : Icons.error_outline,
                    size: 20, color: it['ok'] == true ? const Color(0xFF1E7F52) : cessumRed),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${it['titulo']}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cessumInk(context))),
                    const SizedBox(height: 2),
                    Text('${it['detalle'] ?? ''}',
                        style: TextStyle(fontSize: 12.5, height: 1.35, color: cessumMuted(context))),
                    if ((it['ok'] != true || it['accion'] == 'celular') && _textoBoton.containsKey('${it['accion']}'))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cessumRed,
                            side: const BorderSide(color: cessumRed),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _resolver('${it['accion']}'),
                          child: Text(it['ok'] == true && it['accion'] == 'celular' ? 'Actualizar mi celular' : _textoBoton['${it['accion']}']!),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
        ],
      ),
      const SizedBox(height: 20),
    ];
  }

  void _volverAlMenu() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _editarPerfil() async {
    final actualizado = await Navigator.push<StudentProfile?>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          esEdicion: true,
          perfilExistente: _perfil,
        ),
      ),
    );

    if (actualizado != null && mounted) {
      setState(() {
        _perfil = actualizado;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: cessumRed,
          content: Text('Perfil actualizado correctamente'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cerrar sesión'),
        content: Text(
          'Se cerrará tu sesión en este dispositivo y volverás a la pantalla '
          'de inicio de sesión. Tendrás que entrar de nuevo con tu correo '
          'institucional.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Cerrar sesión'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    // (24-sep) Primero se expira la llave de sesión firmada del servidor: si
    // no, seguía valiendo hasta 12 horas en este navegador.
    await AccesoService.cerrarSesionServidor();
    await AuthService.instance.signOut();
    await SessionStore.clear();
    await WelcomeScreen.clearAll();

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AuthGate(child: SplashScreen())),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: Text(
          'Acerca de',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(Icons.home),
            tooltip: 'Inicio',
            onPressed: _volverAlMenu,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(20),
        children: [
          // Cabecera con logo, nombre y version
          Center(
            child: Column(
              children: [
                SizedBox(height: 8),
                Image.asset(
                  'assets/images/logo.png',
                  height: 110,
                  fit: BoxFit.contain,
                ),
                SizedBox(height: 16),
                Text(
                  'Aula CESSUM',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: cessumInk(context),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  _version.isEmpty ? 'Cargando...' : _version,
                  style: TextStyle(
                    fontSize: 13,
                    color: cessumMuted(context),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 28),

          // Mi perfil (solo si hay perfil guardado)
          if (_perfil != null) ...[
            AcercaSeccion(
              titulo: 'Mi perfil',
              children: [
                AcercaFila(
                  icono: Icons.badge,
                  texto: 'Matrícula: ${_perfil!.matricula}',
                ),
                AcercaFila(
                  icono: Icons.school,
                  texto: _perfil!.programa,
                ),
                AcercaFila(
                  icono: Icons.menu_book,
                  texto: 'Modalidad: ${_perfil!.modalidad}',
                ),
                AcercaFila(
                  icono: Icons.event,
                  texto: 'Generación: ${_perfil!.generacion}',
                ),
                AcercaFila(
                  icono: Icons.fingerprint,
                  texto: 'CURP: '
                      '${_perfil!.curp.trim().isEmpty ? 'No registrada (agrégala para tu credencial)' : _perfil!.curp}',
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed,
                        side: BorderSide(color: cessumRed),
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _editarPerfil,
                      icon: Icon(Icons.edit, size: 18),
                      label: Text(
                        'Editar mi perfil',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
          ],

          // (24-sep) Lo que te falta: CURP, promedio, documentos y credencial.
          ..._seccionPendientes(),

          // Institución: bloque compartido (acerca_comun.dart)
          const AcercaInstitucion(),
          SizedBox(height: 20),

          // Contacto - atencion alumnos
          AcercaSeccion(
            titulo: 'Atención a alumnos',
            children: [
              AcercaFilaAccion(
                icono: Icons.chat,
                etiqueta: 'WhatsApp',
                valor: formatoWhatsApp(whatsappNumero),   // (24-sep) de la constante, no escrito a mano
                color: Color(0xFF25D366),
                onTap: () => Helpers.abrirWhatsApp(context),
              ),
              AcercaFilaAccion(
                icono: Icons.email,
                etiqueta: 'Correo',
                valor: correoInstitucional,
                color: cessumRed,
                onTap: () => Helpers.abrirCorreo(
                  context: context,
                  destinatario: correoInstitucional,
                  asunto: 'Consulta - Aula CESSUM',
                  cuerpo: '',
                ),
              ),
            ],
          ),
          SizedBox(height: 20),

          // Contacto - admisiones
          AcercaSeccion(
            titulo: 'Admisiones (nuevos alumnos)',
            children: [
              AcercaFilaAccion(
                icono: Icons.phone,
                etiqueta: 'Teléfono',
                valor: telefonoAdmisionesFormateado,
                color: cessumRed,
                onTap: () => Helpers.llamarPorTelefono(
                  context,
                  telefonoAdmisiones,
                ),
              ),
              AcercaFilaAccion(
                icono: Icons.chat,
                etiqueta: 'WhatsApp Admisiones',
                valor: telefonoAdmisionesFormateado,
                color: Color(0xFF25D366),
                onTap: () => Helpers.abrirWhatsAppAdmisiones(context),
              ),
            ],
          ),
          SizedBox(height: 20),

          // En línea y oferta académica con RVOE: bloques compartidos
          const AcercaEnLinea(),
          SizedBox(height: 20),
          const AcercaOferta(),
          SizedBox(height: 20),

          // Sesion
          AcercaSeccion(
            titulo: 'Sesión',
            children: [
              Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      side: BorderSide(color: cessumRed),
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _cerrarSesion,
                    icon: Icon(Icons.logout, size: 18),
                    label: Text(
                      'Cerrar sesión',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 32),

          const AcercaPie(),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

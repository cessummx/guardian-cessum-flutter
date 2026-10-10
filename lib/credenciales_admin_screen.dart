import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'credenciales_docentes_admin_screen.dart';
import 'constants.dart';
import 'auth/session_store.dart';
import 'cessum_ui.dart';
import 'package:url_launcher/url_launcher.dart';

// =====================================================================
// PANTALLA: "Credenciales" (lado del ADMINISTRADOR)
// ---------------------------------------------------------------------
// Lista las credenciales pendientes con la foto, y permite Aprobar,
// Pedir cambios o Rechazar. Arriba administra las vigencias.
//
// CONTRATO CON EL GUARDIAN (debe coincidir con guardian_cessum.gs):
//   listar_credenciales (GET, sin parametros)
//     -> { ok: true, credenciales: [ { id, matricula, nombre, curp,
//          programa, modalidad, generacion, correo, fotoUrl, fotoId } ] }
//   aprobar_credencial  (GET, parametro: id)              -> { ok, pdfUrl }
//   rechazar_credencial (GET, parametros: id, observaciones) -> { ok }
//   observar_credencial (POST JSON: accion, id, observaciones) -> { ok }
//   listar_vigencias    (GET) -> { ok, vigencias: { lista, activa } }
//   agregar_vigencia    (GET, parametro: texto) -> { ok, lista }
//   activar_vigencia    (GET, parametro: texto) -> { ok, activa }
//   eliminar_vigencia   (GET, parametro: texto) -> { ok, lista }
// =====================================================================
class CredencialesAdminScreen extends StatefulWidget {
  const CredencialesAdminScreen({super.key});

  @override
  State<CredencialesAdminScreen> createState() =>
      _CredencialesAdminScreenState();
}

class _CredencialesAdminScreenState extends State<CredencialesAdminScreen> {
  // Vigencias
  List<String> _vigencias = [];
  String _vigenciaActiva = '';
  bool _cargandoVig = true;
  String? _errorVig;
  final _nuevaVigenciaCtrl = TextEditingController();
  bool _ocupadoVig = false;

  // Credenciales pendientes
  List<Map<String, dynamic>> _credenciales = [];
  bool _cargandoCreds = true;
  String? _errorCreds;
  String? _procesandoId; // id de la credencial que se esta procesando

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _nuevaVigenciaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    await Future.wait([_cargarVigencias(), _cargarCredenciales()]);
  }

  // ===================== VIGENCIAS =====================

  Future<void> _cargarVigencias() async {
    setState(() {
      _cargandoVig = true;
      _errorVig = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'listar_vigencias'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      final v = (data['vigencias'] as Map<String, dynamic>? ?? {});
      if (!mounted) return;
      setState(() {
        _vigencias = _comoListaTexto(v['lista']);
        _vigenciaActiva = (v['activa'] ?? '').toString();
        _cargandoVig = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoVig = false;
        _errorVig = 'No se pudieron cargar las vigencias.';
      });
    }
  }

  Future<void> _agregarVigencia() async {
    final texto = _nuevaVigenciaCtrl.text.trim();
    if (texto.isEmpty) {
      _aviso('Escribe la vigencia, por ejemplo "Junio 2027".', esError: true);
      return;
    }
    setState(() => _ocupadoVig = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'agregar_vigencia',
        'texto': texto,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _vigencias = _comoListaTexto(data['lista']);
        _ocupadoVig = false;
        _nuevaVigenciaCtrl.clear();
      });
      _aviso('Vigencia agregada.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupadoVig = false);
      _aviso('No se pudo agregar la vigencia.', esError: true);
    }
  }

  Future<void> _activarVigencia(String texto) async {
    setState(() => _ocupadoVig = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'activar_vigencia',
        'texto': texto,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _vigenciaActiva = (data['activa'] ?? texto).toString();
        _ocupadoVig = false;
      });
      _aviso('Vigencia activa: $_vigenciaActiva');
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupadoVig = false);
      _aviso('No se pudo activar la vigencia.', esError: true);
    }
  }

  Future<void> _eliminarVigencia(String texto) async {
    final confirmar = await _confirmar(
      titulo: 'Eliminar vigencia',
      mensaje: 'Se eliminara "$texto" de la lista. Esto no cambia las '
          'credenciales ya generadas. Continuar?',
      colorBoton: cessumRed,
      textoBoton: 'Eliminar',
    );
    if (confirmar != true) return;

    setState(() => _ocupadoVig = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'eliminar_vigencia',
        'texto': texto,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _vigencias = _comoListaTexto(data['lista']);
        if (_vigenciaActiva == texto) _vigenciaActiva = '';
        _ocupadoVig = false;
      });
      _aviso('Vigencia eliminada.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupadoVig = false);
      _aviso('No se pudo eliminar la vigencia.', esError: true);
    }
  }

  // ===================== CREDENCIALES =====================

  Future<void> _cargarCredenciales() async {
    setState(() {
      _cargandoCreds = true;
      _errorCreds = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'listar_credenciales'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      final lista = (data['credenciales'] as List<dynamic>? ?? []);
      if (!mounted) return;
      setState(() {
        _credenciales = lista
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((c) {
              // Solo las que siguen pendientes de revisar; las Aprobadas,
              // Rechazadas u Observadas salen de la lista.
              final est = (c['estado'] ?? '').toString().trim().toLowerCase();
              return est.isEmpty || est == 'pendiente';
            })
            .toList();
        _cargandoCreds = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoCreds = false;
        _errorCreds = 'No se pudieron cargar las credenciales pendientes.';
      });
    }
  }

  Future<void> _aprobar(String id) async {
    setState(() => _procesandoId = id);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'aprobar_credencial',
        'id': id,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      _aviso('Credencial aprobada. El PDF ya se genero.');
    } catch (e) {
      _aviso('No se pudo aprobar la credencial.', esError: true);
    } finally {
      if (mounted) setState(() => _procesandoId = null);
      await _cargarCredenciales();
    }
  }

  // (14-sep) NOTA INTERNA: el alumno no la ve. La columna «Observaciones»
  // que ya existía es el texto que se le manda a él al pedir cambios; para
  // anotar «tiene adeudo» o «ya se le llamó» no servía.
  Future<void> _nota(Map<String, dynamic> c) async {
    final id = (c['id'] ?? '').toString();
    final actual = (c['notaInterna'] ?? '').toString();
    final ctrl = TextEditingController(text: actual);
    final texto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nota interna', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Solo la ve el personal. Queda con tu nombre y la fecha.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Por qué no se ha tramitado, qué se le dijo…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (texto == null || !mounted) return;
    await _accionCred('credencial_nota', {'id': id, 'nota': texto.trim()},
        'Nota guardada');
  }

  // Detiene el reloj: lo que sigue depende del alumno, no de nosotros.
  Future<void> _ponerEnEspera(Map<String, dynamic> c) async {
    final id = (c['id'] ?? '').toString();
    final ad = (c['adeudo'] is Map) ? c['adeudo'] as Map : const {};
    final pend = (ad['pendientes'] is num) ? (ad['pendientes'] as num).toInt() : 0;
    final sugerido = pend > 0
        ? 'Tiene $pend pago(s) pendiente(s)'
        : '';
    final ctrl = TextEditingController(text: sugerido);
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Poner en espera del alumno', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Mientras esté en espera, el reloj se detiene: el tiempo de '
                'esta pausa no cuenta contra las 72 horas.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 2,
              maxLength: 200,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Motivo (adeudo, documento faltante…)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumGold, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Detener reloj'),
          ),
        ],
      ),
    );
    if (motivo == null || motivo.trim().isEmpty || !mounted) return;
    await _accionCred('credencial_espera', {'id': id, 'motivo': motivo.trim()},
        'Reloj detenido');
  }

  Future<void> _reanudar(Map<String, dynamic> c) async {
    await _accionCred('credencial_reanudar', {'id': (c['id'] ?? '').toString()},
        'Reloj reanudado');
  }

  Future<void> _accionCred(
      String accion, Map<String, dynamic> extra, String exito) async {
    final id = (extra['id'] ?? '').toString();
    setState(() => _procesandoId = id);
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final cuerpo = <String, dynamic>{'accion': accion, 'actor': actor}
        ..addAll(extra);
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(cuerpo))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Respuesta inválida');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(exito), backgroundColor: const Color(0xFF1E8E3E)));
      await _cargarCredenciales();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo: $e'), backgroundColor: cessumRed));
    } finally {
      if (mounted) setState(() => _procesandoId = '');
    }
  }

  Future<void> _pedirCambios(String id) async {
    final texto = await _dialogoObservaciones();
    if (texto == null) return; // cancelo
    if (texto.trim().isEmpty) {
      _aviso('Escribe que se debe corregir.', esError: true);
      return;
    }

    setState(() => _procesandoId = id);
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'observar_credencial',
              'id': id,
              'observaciones': texto.trim(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      _aviso('Se enviaron las observaciones al alumno.');
    } catch (e) {
      _aviso('No se pudieron enviar las observaciones.', esError: true);
    } finally {
      if (mounted) setState(() => _procesandoId = null);
      await _cargarCredenciales();
    }
  }

  Future<void> _rechazar(String id) async {
    final motivo = await _dialogoObservaciones(
      titulo: 'Rechazar credencial',
      ayuda: 'Puedes escribir el motivo (opcional). El alumno lo vera.',
      etiquetaBoton: 'Rechazar',
      colorBoton: cessumRed,
    );
    if (motivo == null) return; // cancelo

    setState(() => _procesandoId = id);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'rechazar_credencial',
        'id': id,
        'observaciones': motivo.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      _aviso('Credencial rechazada.');
    } catch (e) {
      _aviso('No se pudo rechazar la credencial.', esError: true);
    } finally {
      if (mounted) setState(() => _procesandoId = null);
      await _cargarCredenciales();
    }
  }

  // ===================== UI =====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        title: const Text(
          'Credenciales',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.badge_outlined, size: 18),
            label: const Text('Docentes'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CredencialesDocentesAdminScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: cessumRed,
        onRefresh: _cargarTodo,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _seccionVigencias(),
            const SizedBox(height: 24),
            _seccionPendientes(),
          ],
        ),
      ),
    );
  }

  Widget _seccionVigencias() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_available, color: cessumGold, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Vigencias',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (_ocupadoVig)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: cessumGold),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _vigenciaActiva.isEmpty
                ? 'No hay una vigencia activa.'
                : 'Vigencia activa: $_vigenciaActiva',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 14),
          if (_cargandoVig)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: CircularProgressIndicator(color: cessumRed),
              ),
            )
          else if (_errorVig != null)
            _errorLinea(_errorVig!, _cargarVigencias)
          else
            ..._vigencias.map(_filaVigencia),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nuevaVigenciaCtrl,
                  decoration: InputDecoration(
                    hintText: 'Nueva vigencia (ej. Junio 2027)',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF7F7F7),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumGold,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onPressed: _ocupadoVig ? null : _agregarVigencia,
                child: const Text('Agregar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filaVigencia(String texto) {
    final activa = texto == _vigenciaActiva;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            activa ? Icons.check_circle : Icons.radio_button_unchecked,
            color: activa ? const Color(0xFF1E8E3E) : Colors.grey.shade400,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 14,
                fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          if (activa)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E8E3E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'ACTIVA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E8E3E),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _ocupadoVig ? null : () => _activarVigencia(texto),
              child: const Text('Activar',
                  style: TextStyle(color: cessumGold)),
            ),
          IconButton(
            tooltip: 'Eliminar',
            onPressed: _ocupadoVig ? null : () => _eliminarVigencia(texto),
            icon: Icon(Icons.delete_outline, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _seccionPendientes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.badge, color: cessumRed, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Solicitudes pendientes (${_credenciales.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_cargandoCreds)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(color: cessumRed)),
          )
        else if (_errorCreds != null)
          _errorLinea(_errorCreds!, _cargarCredenciales)
        else if (_credenciales.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: const Column(
              children: [
                Icon(Icons.inbox, color: Colors.black26, size: 36),
                SizedBox(height: 8),
                Text(
                  'No hay credenciales pendientes por revisar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          )
        else
          ..._credenciales.map(_tarjetaCredencial),
      ],
    );
  }

  // Genera y abre el PDF REAL de la credencial (plantilla + foto) para revisarla.
  Future<void> _abrirPdfCredencial(Map<String, dynamic> c,
      {String formato = 'imprimible'}) async {
    final mat = (c['matricula'] ?? '').toString();
    if (mat.isEmpty) return;
    bool abierto = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    void cerrar() {
      if (abierto && mounted) {
        Navigator.pop(context);
        abierto = false;
      }
    }
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'credencial_preview_pdf',
        'matricula': mat,
        'formato': formato,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      cerrar();
      final url = (data['url'] ?? '').toString();
      if (data['ok'] == true && url.isNotEmpty) {
        await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      } else {
        throw Exception(data['error'] ?? 'No se pudo generar');
      }
    } catch (e) {
      cerrar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed,
          content: Text('No se pudo generar la credencial: '
              '${e.toString().replaceAll('Exception: ', '')}'),
        ));
      }
    }
  }

  // Vista previa de la credencial ARMADA (foto + datos) antes de validar.
  void _vistaPreviaCredencial(Map<String, dynamic> c) {
    final nombre = (c['nombre'] ?? '').toString();
    final matricula = (c['matricula'] ?? '').toString();
    final curp = (c['curp'] ?? '').toString();
    final programa = (c['programa'] ?? '').toString();
    final modalidad = (c['modalidad'] ?? '').toString();
    final generacion = (c['generacion'] ?? '').toString();
    final fotoUrl = (c['fotoUrl'] ?? '').toString();
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  color: cessumRed,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CESSUM',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              letterSpacing: 1)),
                      Text('Credencial de estudiante',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 110,
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                          color: Colors.grey.shade100,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _FotoCredencial(
                          fotoId: (c['fotoId'] ?? '').toString(),
                          fotoUrl: fotoUrl,
                          width: 110,
                          height: 140,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nombre,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: cessumRed)),
                            const SizedBox(height: 6),
                            _dato('Matrícula', matricula),
                            _dato('CURP', curp),
                            _dato('Programa', programa),
                            _dato('Modalidad', modalidad),
                            if (generacion.isNotEmpty)
                              _dato('Generación', generacion),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  color: cessumGold.withValues(alpha: 0.10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: const Text(
                    'Así se verá la credencial impresa.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.black54, height: 1.4),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Contador de 72 horas HÁBILES (lun-vie) desde la solicitud ----
  static const int _kHorasCred = 72;

  DateTime? _parseFechaCred(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final m1 = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m1 != null) {
      return DateTime(int.parse(m1.group(1)!), int.parse(m1.group(2)!),
          int.parse(m1.group(3)!));
    }
    final m2 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
    if (m2 != null) {
      return DateTime(int.parse(m2.group(3)!), int.parse(m2.group(2)!),
          int.parse(m2.group(1)!));
    }
    const meses = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
    };
    final m3 =
        RegExp(r'([A-Za-z]{3})[a-z]*\s+(\d{1,2})\s+(\d{4})').firstMatch(s);
    if (m3 != null) {
      final mes = meses[m3.group(1)!.toLowerCase()];
      if (mes != null) {
        return DateTime(
            int.parse(m3.group(3)!), mes, int.parse(m3.group(2)!));
      }
    }
    return null;
  }

  double _horasHabilesCred(DateTime desde, DateTime hasta) {
    if (!hasta.isAfter(desde)) return 0;
    double horas = 0;
    var cursor = desde;
    while (cursor.isBefore(hasta)) {
      final sig = cursor.add(const Duration(hours: 1));
      final finTramo = sig.isBefore(hasta) ? sig : hasta;
      if (cursor.weekday >= 1 && cursor.weekday <= 5) {
        horas += finTramo.difference(cursor).inMinutes / 60.0;
      }
      cursor = sig;
    }
    return horas;
  }

  // Badge del timer. Solo para solicitudes PENDIENTES.
  Widget _timerCred(Map<String, dynamic> c) {
    final estado = (c['estado'] ?? 'Pendiente').toString();
    if (estado.isNotEmpty && estado != 'Pendiente') {
      return const SizedBox.shrink();
    }
    // 'marca' es el timestamp de la solicitud (dd/MM/yyyy HH:mm).
    final ini = _parseFechaCred((c['marca'] ?? '').toString());
    if (ini == null) return const SizedBox.shrink();
    // (14-sep) EL RELOJ NO CUENTA LO QUE NO NOS TOCA.
    // Antes contaba desde que el alumno solicitó, pasara lo que pasara, y
    // marcaba «Vencida (+109 h)» aunque el trámite estuviera detenido porque
    // el alumno debe colegiaturas. Ese número culpaba a Servicios Escolares
    // de una espera ajena. Ahora, mientras la solicitud está en espera del
    // alumno el reloj se detiene, y al reanudar se descuentan esas horas.
    final enEspera = (c['enEsperaDesde'] ?? '').toString().isNotEmpty;
    final yaEsperadas = (c['horasEnEspera'] is num)
        ? (c['horasEnEspera'] as num).toDouble()
        : double.tryParse('${c['horasEnEspera'] ?? 0}') ?? 0;
    if (enEspera) {
      final desde = _parseFechaCred((c['enEsperaDesde'] ?? '').toString());
      final enPausa = desde == null ? 0 : _horasHabilesCred(desde, DateTime.now());
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pause_circle_outline, size: 12, color: cessumGold),
            const SizedBox(width: 3),
            Text('En espera del alumno · ${enPausa.toStringAsFixed(0)} h',
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: cessumGold)),
          ],
        ),
      );
    }
    final transcurridas =
        _horasHabilesCred(ini, DateTime.now()) - yaEsperadas;
    final restan = _kHorasCred - transcurridas;
    final vencida = restan <= 0;
    const verdeOk = Color(0xFF1E8E3E);
    final Color color;
    final String texto;
    if (vencida) {
      color = cessumRed;
      texto = 'Vencida (+${(-restan).toStringAsFixed(0)} h háb.)'
          '${yaEsperadas > 0 ? ' · sin ${yaEsperadas.toStringAsFixed(0)} h de espera' : ''}';
    } else if (restan <= 12) {
      color = cessumRed;
      texto = 'Faltan ${restan.toStringAsFixed(0)} h háb.';
    } else if (restan <= 24) {
      color = cessumGold;
      texto = 'Faltan ${restan.toStringAsFixed(0)} h háb.';
    } else {
      color = verdeOk;
      texto = 'Faltan ${restan.toStringAsFixed(0)} h háb.';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vencida ? Icons.alarm_off : Icons.alarm, size: 12, color: color),
          const SizedBox(width: 3),
          Text(texto,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _tarjetaCredencial(Map<String, dynamic> c) {
    final id = (c['id'] ?? '').toString();
    final nombre = (c['nombre'] ?? '').toString();
    final matricula = (c['matricula'] ?? '').toString();
    final curp = (c['curp'] ?? '').toString();
    final programa = (c['programa'] ?? '').toString();
    final modalidad = (c['modalidad'] ?? '').toString();
    final generacion = (c['generacion'] ?? '').toString();
    final fotoUrl = (c['fotoUrl'] ?? '').toString();

    final procesando = _procesandoId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                clipBehavior: Clip.antiAlias,
                child: _FotoCredencial(
                  fotoId: (c['fotoId'] ?? '').toString(),
                  fotoUrl: fotoUrl,
                  width: 80,
                  height: 100,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        _timerCred(c),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _dato('Matricula', matricula),
                    _dato('CURP', curp),
                    _dato('Programa', programa),
                    _dato('Modalidad', modalidad),
                    if (generacion.isNotEmpty) _dato('Generacion', generacion),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _abrirPdfCredencial(c, formato: 'imprimible'),
                  icon: const Icon(Icons.badge_outlined,
                      size: 16, color: cessumRed),
                  label: const Text('Imprimible',
                      style: TextStyle(color: cessumRed, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cessumRed),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _abrirPdfCredencial(c, formato: 'digital'),
                  icon: const Icon(Icons.qr_code_2,
                      size: 16, color: cessumGold),
                  label: const Text('Digital',
                      style: TextStyle(color: cessumGold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cessumGold),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (procesando)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: cessumRed),
                ),
              ),
            )
          else ...[
            // (14-sep) LO QUE EXPLICA POR QUÉ NO SE HA TRAMITADO.
            // El adeudo no se captura a mano: sale de la hoja de
            // vencimientos que el Guardián ya lee.
            if (_adeudoDe(c) > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.07),
                  border: Border(left: BorderSide(color: cessumRed, width: 2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        size: 15, color: cessumRed),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Tiene ${_adeudoDe(c)} pago(s) pendiente(s)'
                        '${_montoDe(c) > 0 ? ' · \$${_montoDe(c).toStringAsFixed(2)}' : ''}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600, color: cessumRed),
                      ),
                    ),
                  ],
                ),
              ),
            if ((c['notaInterna'] ?? '').toString().isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBF6EC),
                  border: Border(left: BorderSide(color: cessumGold, width: 2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.sticky_note_2_outlined, size: 15, color: cessumGold),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text((c['notaInterna'] ?? '').toString(),
                          style: const TextStyle(fontSize: 12, height: 1.4)),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cessumGold,
                      side: const BorderSide(color: cessumGold),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    onPressed: () => _nota(c),
                    icon: const Icon(Icons.sticky_note_2_outlined, size: 16),
                    label: Text(
                        (c['notaInterna'] ?? '').toString().isEmpty
                            ? 'Nota interna'
                            : 'Editar nota',
                        style: const TextStyle(fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: (c['enEsperaDesde'] ?? '').toString().isNotEmpty
                      ? OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1E8E3E),
                            side: const BorderSide(color: Color(0xFF1E8E3E)),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          onPressed: () => _reanudar(c),
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Reanudar reloj',
                              style: TextStyle(fontSize: 12.5)),
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black54,
                            side: const BorderSide(color: Color(0xFFD8CDB9)),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                          ),
                          onPressed: () => _ponerEnEspera(c),
                          icon: const Icon(Icons.pause, size: 16),
                          label: const Text('En espera del alumno',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E8E3E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _aprobar(id),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Aprobar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumGold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _pedirCambios(id),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Cambios'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      side: const BorderSide(color: cessumRed),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => _rechazar(id),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Rechazar'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  int _adeudoDe(Map<String, dynamic> c) {
    final ad = c['adeudo'];
    if (ad is Map && ad['pendientes'] is num) return (ad['pendientes'] as num).toInt();
    return 0;
  }

  double _montoDe(Map<String, dynamic> c) {
    final ad = c['adeudo'];
    if (ad is Map && ad['total'] is num) return (ad['total'] as num).toDouble();
    return 0;
  }

  // Convierte una URL/ID de Google Drive en una URL que SÍ carga en <img>.
  // Las 'uc?export=view' ya no funcionan; 'thumbnail?id=' sí (archivo público).
  Widget _dato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          children: [
            TextSpan(
              text: '$etiqueta: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: valor.isEmpty ? '-' : valor),
          ],
        ),
      ),
    );
  }

  Widget _errorLinea(String mensaje, VoidCallback reintentar) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mensaje, style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: reintentar,
            icon: const Icon(Icons.refresh, size: 16, color: cessumRed),
            label:
                const Text('Reintentar', style: TextStyle(color: cessumRed)),
          ),
        ],
      ),
    );
  }

  // ===================== Helpers de dialogo =====================

  Future<String?> _dialogoObservaciones({
    String titulo = 'Pedir cambios',
    String ayuda = 'Escribe que debe corregir el alumno (ej. foto borrosa, '
        'fondo no adecuado).',
    String etiquetaBoton = 'Enviar',
    Color colorBoton = cessumGold,
  }) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ayuda,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Observaciones',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorBoton,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(etiquetaBoton),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmar({
    required String titulo,
    required String mensaje,
    required String textoBoton,
    required Color colorBoton,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colorBoton,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(textoBoton),
          ),
        ],
      ),
    );
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

  List<String> _comoListaTexto(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return [];
  }
}

// =====================================================================
// Caché en memoria de las fotos de credencial (por id de Drive).
final Map<String, Uint8List> _credFotoCache = {};

String _extraerFotoId(String fotoId, String fotoUrl) {
  String id = fotoId.trim();
  if (id.isEmpty && fotoUrl.isNotEmpty) {
    final m1 = RegExp(r'[?&]id=([A-Za-z0-9_-]+)').firstMatch(fotoUrl);
    final m2 = RegExp(r'/d/([A-Za-z0-9_-]+)').firstMatch(fotoUrl);
    if (m1 != null) {
      id = m1.group(1)!;
    } else if (m2 != null) {
      id = m2.group(1)!;
    }
  }
  return id;
}

// Carga la foto de la credencial DESDE EL BACKEND (base64), no desde Drive,
// para que siempre se vea (Drive a veces bloquea el thumbnail con 403).
class _FotoCredencial extends StatefulWidget {
  final String fotoId;
  final String fotoUrl;
  final double width;
  final double height;
  const _FotoCredencial({
    required this.fotoId,
    required this.fotoUrl,
    required this.width,
    required this.height,
  });

  @override
  State<_FotoCredencial> createState() => _FotoCredencialState();
}

class _FotoCredencialState extends State<_FotoCredencial> {
  Uint8List? _bytes;
  bool _cargando = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final id = _extraerFotoId(widget.fotoId, widget.fotoUrl);
    if (id.isEmpty) {
      if (mounted) setState(() {
        _cargando = false;
        _error = true;
      });
      return;
    }
    if (_credFotoCache.containsKey(id)) {
      if (mounted) setState(() {
        _bytes = _credFotoCache[id];
        _cargando = false;
      });
      return;
    }
    try {
      final uri = Uri.parse(guardianUrl).replace(
        queryParameters: {'accion': 'credencial_foto', 'id': id},
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body);
      final b64 = (data is Map ? (data['b64'] ?? '') : '').toString();
      if (data is Map && data['ok'] == true && b64.isNotEmpty) {
        final b = base64Decode(b64);
        _credFotoCache[id] = b;
        if (mounted) setState(() {
          _bytes = b;
          _cargando = false;
        });
      } else {
        if (mounted) setState(() {
          _cargando = false;
          _error = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _cargando = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error || _bytes == null) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person,
                color: Colors.grey.shade400, size: widget.width * 0.4),
            const SizedBox(height: 4),
            const Text('Sin foto',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      width: widget.width,
      height: widget.height,
    );
  }
}

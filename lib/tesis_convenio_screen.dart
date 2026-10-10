import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'foto_web_picker.dart';
import 'helpers.dart';
import 'firma_alumno_screen.dart';

/// =====================================================================
/// PANTALLA: Tesis · Convenio de trabajo, asignación de asesor,
/// hitos de entrega y seguimiento. Role-aware:
///   rol = 'admin'  -> asigna asesor, define convenio, firma autoridad
///   rol = 'alumno' -> firma como estudiante, sube entregables
///   rol = 'asesor' -> firma como asesor, revisa entregables
/// Se apoya en el Guardián: titu_detalle, titu_docentes,
/// titu_asignar_asesor, titu_convenio_guardar/firmar, titu_hito_entregar/revisar.
/// =====================================================================
class TesisConvenioScreen extends StatefulWidget {
  final String matricula;
  final String nombre;
  final String programa;
  final String generacion;
  final String correo;
  final String rol; // admin | alumno | asesor

  const TesisConvenioScreen({
    super.key,
    required this.matricula,
    this.nombre = '',
    this.programa = '',
    this.generacion = '',
    this.correo = '',
    this.rol = 'admin',
  });

  @override
  State<TesisConvenioScreen> createState() => _TesisConvenioScreenState();
}

class _TesisConvenioScreenState extends State<TesisConvenioScreen> {
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  Map<String, dynamic>? _tesis;
  Map<String, dynamic>? _convenio;
  List<Map<String, dynamic>> _hitos = [];
  List<Map<String, dynamic>> _interacciones = [];
  List<Map<String, dynamic>> _asesorias = [];
  int _etapaIndice = 0;
  int _totalEtapas = 1;
  bool _vrEsAsesor = false;
  String _titulo = '';
  String _asesorCorreo = '';
  List<Map<String, dynamic>> _autoridades = [];

  bool get _esAdmin => widget.rol == 'admin';
  bool get _esAlumno => widget.rol == 'alumno';
  bool get _esAsesor => widget.rol == 'asesor';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
    final resp = await http.get(uri).timeout(const Duration(seconds: 60));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 180));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargarConvenioExtra() async {
    try {
      final data = await _get(
          {'accion': 'titu_convenio_get', 'matricula': widget.matricula});
      if (data['ok'] == true && mounted) {
        setState(() {
          _titulo = '${data['titulo'] ?? ''}';
          _asesorCorreo = '${data['asesorCorreo'] ?? ''}';
          _autoridades = ((data['autoridades'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _verConvenio() async {
    setState(() => _guardando = true);
    try {
      final data = await _get(
          {'accion': 'titu_convenio_preview', 'matricula': widget.matricula});
      if (data['ok'] == true && '${data['url'] ?? ''}'.isNotEmpty) {
        Helpers.abrirUrlExterna('${data['url']}', context);
      } else {
        _snack('${data['error'] ?? 'No se pudo generar la vista previa.'}',
            error: true);
      }
    } catch (e) {
      _snack('Error de conexión.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await _get(
          {'accion': 'titu_detalle', 'matricula': widget.matricula});
      if (!mounted) return;
      if (data['ok'] != true) {
        // Sin tesis aún: el admin puede asignar asesor para crearla.
        setState(() {
          _tesis = null;
          _cargando = false;
        });
        return;
      }
      final t = (data['tesis'] as Map?) ?? {};
      setState(() {
        _tesis = Map<String, dynamic>.from(t);
        _convenio = data['convenio'] == null
            ? null
            : Map<String, dynamic>.from(data['convenio'] as Map);
        _hitos = ((data['hitos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _interacciones = ((data['interacciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _asesorias = ((data['asesorias'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _etapaIndice = (_tesis?['etapaIndice'] is int)
            ? _tesis!['etapaIndice'] as int
            : int.tryParse('${_tesis?['etapaIndice']}') ?? 0;
        final cat = (data['catalogoEtapas'] as List?) ?? const [];
        _totalEtapas = cat.isNotEmpty ? cat.length : 14;
        _vrEsAsesor = data['vicerrectorEsAsesor'] == true;
        _cargando = false;
      });
      await _cargarConvenioExtra();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la tesis. Revisa tu conexión.';
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: error ? Colors.red : Colors.green,
        content: Text(msg)));
  }

  // ---------------- Asignar asesor ----------------
  Future<void> _asignarAsesor() async {
    List<Map<String, dynamic>> docentes = [];
    try {
      final data = await _get({'accion': 'titu_docentes'});
      docentes = ((data['docentes'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((d) => '${d['nombre']}'.trim().isNotEmpty)
          .toList();
    } catch (_) {}
    if (docentes.isEmpty) {
      _snack('No se pudo cargar la lista de docentes.', error: true);
      return;
    }
    if (!mounted) return;
    Map<String, dynamic>? sel = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        Map<String, dynamic>? elegido;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text('Asignar asesor(a) de tesis'),
            content: SizedBox(
              width: 420,
              child: DropdownButtonFormField<Map<String, dynamic>>(
                isExpanded: true,
                value: elegido,
                decoration: const InputDecoration(
                    labelText: 'Docente CESSUM',
                    border: OutlineInputBorder()),
                items: docentes
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            '${d['titulo'] ?? ''} ${d['nombre']}'.trim(),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setS(() => elegido = v),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () => Navigator.pop(ctx, elegido),
                child: const Text('Asignar',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
    if (sel == null) return;
    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'titu_asignar_asesor',
        'matricula': widget.matricula,
        'nombre': widget.nombre,
        'programa': widget.programa,
        'generacion': widget.generacion,
        'correo': widget.correo,
        'asesorNombre': sel['nombre'],
        'asesorCorreo': sel['correo'] ?? '',
        'registro': widget.correo,
      });
      if (data['ok'] == true) {
        _snack('Asesor asignado. Se notificó por correo.');
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo asignar.'}', error: true);
      }
    } catch (e) {
      _snack('Error de conexión.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ---------------- Definir / editar convenio ----------------
  Future<void> _definirConvenio() async {
    final objetivoCtrl =
        TextEditingController(text: '${_convenio?['objetivo'] ?? ''}');
    final tituloCtrl = TextEditingController(
        text: _titulo.isNotEmpty ? _titulo : '${_tesis?['titulo'] ?? ''}');
    final iniCtrl =
        TextEditingController(text: '${_convenio?['fechaInicio'] ?? ''}');
    final finCtrl =
        TextEditingController(text: '${_convenio?['fechaTermino'] ?? ''}');
    final clausCtrl = TextEditingController(
        text: ((_convenio?['clausulas'] as List?)?.join('\n')) ?? '');
    // hitos editables
    final List<List<TextEditingController>> hitosCtrl = [];
    if (_hitos.isNotEmpty) {
      for (final h in _hitos) {
        hitosCtrl.add([
          TextEditingController(text: '${h['hito'] ?? ''}'),
          TextEditingController(text: '${h['fechaCompromiso'] ?? ''}'),
        ]);
      }
    } else {
      hitosCtrl.add([TextEditingController(), TextEditingController()]);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Convenio de trabajo de tesis'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // El aviso va ARRIBA, antes de que empiece a escribir: si ya
                  // hay firmas puestas, más vale que lo sepa antes de invertir
                  // diez minutos llenando el formulario.
                  if (_hayFirmas()) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                          color: cessumRed.withValues(alpha: 0.08),
                          border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Text(
                          '⚠ Este convenio ya tiene firmas. Si lo vuelves a '
                          'guardar, se borran todas y se rehacen los hitos: '
                          'todos tendrán que firmar de nuevo.',
                          style: TextStyle(fontSize: 12, height: 1.35)),
                    ),
                  ],
                  TextField(
                    controller: tituloCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Título tentativo de la tesis',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: objetivoCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Objetivo del trabajo de tesis',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: iniCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Inicio (dd/mm/aaaa)',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: finCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Término (dd/mm/aaaa)',
                            border: OutlineInputBorder()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                    controller: clausCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Cláusulas (una por línea, opcional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Hitos / entregables',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: cessumRed)),
                  ),
                  const SizedBox(height: 6),
                  ...List.generate(hitosCtrl.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: hitosCtrl[i][0],
                            decoration: InputDecoration(
                                labelText: 'Hito ${i + 1}',
                                isDense: true,
                                border: const OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: hitosCtrl[i][1],
                            decoration: const InputDecoration(
                                labelText: 'Fecha',
                                isDense: true,
                                border: OutlineInputBorder()),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red),
                          onPressed: hitosCtrl.length <= 1
                              ? null
                              : () => setS(() => hitosCtrl.removeAt(i)),
                        ),
                      ]),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar hito'),
                      onPressed: () => setS(() => hitosCtrl.add(
                          [TextEditingController(), TextEditingController()])),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    // (ago-8) ADVERTENCIA ANTES DE PISAR FIRMAS.
    // titu_convenio_guardar REINICIA las cuatro firmas y borra y rehace los
    // hitos. Al reeditar un convenio ya firmado se tiraba el trabajo de todos
    // sin decir una palabra: el alumno, el asesor y las dos autoridades tenían
    // que volver a firmar. Si ya hay firmas, se pide confirmación explícita.
    final firmasPuestas = <String>[];
    if ('${_convenio?['firmaAlumno'] ?? ''}'.startsWith('SÍ')) {
      firmasPuestas.add('el estudiante');
    }
    if ('${_convenio?['firmaAsesor'] ?? ''}'.startsWith('SÍ')) {
      firmasPuestas.add('el asesor');
    }
    if ('${_convenio?['firmaAutoridad'] ?? ''}'.startsWith('SÍ')) {
      firmasPuestas.add('la primera autoridad');
    }
    if ('${_convenio?['firmaAutoridad2'] ?? ''}'.startsWith('SÍ')) {
      firmasPuestas.add('la segunda autoridad');
    }
    if (firmasPuestas.isNotEmpty) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Este convenio ya está firmado',
              style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.08),
                    border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                    '⚠ Ya firmaron ${firmasPuestas.join(', ')}.\n\n'
                    'Al guardar se BORRAN esas firmas y todos tendrán que '
                    'volver a firmar. Los hitos también se rehacen: se pierden '
                    'las entregas y los dictámenes que ya tuvieran.',
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
              const SizedBox(height: 10),
              const Text(
                  'Si solo querías corregir el título, ciérralo aquí: eso se '
                  'puede cambiar sin tocar las firmas desde el expediente de '
                  'la tesis.',
                  style: TextStyle(fontSize: 12, height: 1.3)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('No, dejarlo como está')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Entiendo, rehacer el convenio'),
            ),
          ],
        ),
      );
      if (seguir != true) return;
    }

    final clausulas = clausCtrl.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final hitos = <Map<String, String>>[];
    for (final h in hitosCtrl) {
      final nombre = h[0].text.trim();
      if (nombre.isEmpty) continue;
      hitos.add({'hito': nombre, 'fecha': h[1].text.trim()});
    }
    if (hitos.isEmpty) {
      _snack('Agrega al menos un hito de entrega.', error: true);
      return;
    }

    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'titu_convenio_guardar',
        'matricula': widget.matricula,
        'titulo': tituloCtrl.text.trim(),
        'objetivo': objetivoCtrl.text.trim(),
        'fechaInicio': iniCtrl.text.trim(),
        'fechaTermino': finCtrl.text.trim(),
        'clausulas': clausulas,
        'hitos': hitos,
      });
      if (data['ok'] == true) {
        _snack('Convenio guardado. Listo para firmar.');
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo guardar.'}', error: true);
      }
    } catch (e) {
      _snack('Error de conexión.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// ¿El convenio ya tiene alguna firma puesta? Se usa para avisar antes de
  /// reeditarlo, porque guardar las borra todas.
  bool _hayFirmas() {
    final c = _convenio;
    if (c == null) return false;
    return '${c['firmaAlumno'] ?? ''}'.startsWith('SÍ') ||
        '${c['firmaAsesor'] ?? ''}'.startsWith('SÍ') ||
        '${c['firmaAutoridad'] ?? ''}'.startsWith('SÍ') ||
        '${c['firmaAutoridad2'] ?? ''}'.startsWith('SÍ');
  }

  // ---------------- Firmar convenio ----------------
  Future<void> _firmarConvenio(String parte) async {
    String etiqueta;
    if (parte == 'alumno') {
      etiqueta = 'como estudiante';
    } else if (parte == 'asesor') {
      etiqueta = 'como asesor(a)';
    } else {
      final idx = parte == 'autoridad2' ? 1 : 0;
      final cargo =
          idx < _autoridades.length ? '${_autoridades[idx]['cargo']}' : 'autoridad';
      etiqueta = 'como $cargo';
    }
    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Firmar convenio'),
        content: Text(
            'Vas a firmar el convenio de trabajo de tesis $etiqueta. '
            'Se usará tu firma digital registrada. ¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Firmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (conf != true) return;
    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'titu_convenio_firmar',
        'matricula': widget.matricula,
        'parte': parte,
        'correo': widget.correo,
      });
      if (data['ok'] == true) {
        _snack(data['firmado'] == true
            ? 'Convenio firmado por todas las partes. Seguimiento activado.'
            : 'Tu firma quedó registrada.');
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo firmar.'}', error: true);
      }
    } catch (e) {
      _snack('Error de conexión.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ---------------- Hitos: entrega del alumno ----------------
  Future<void> _entregarHito(Map<String, dynamic> h,
      {String tipo = 'revision'}) async {
    final doc = await seleccionarDocumento();
    if (doc == null) return;
    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'titu_hito_entregar',
        'matricula': widget.matricula,
        'num': h['num'],
        'tipoEntrega': tipo,
        'base64': base64Encode(doc.bytes),
        'mime': doc.mime,
        'registro': widget.correo,
      });
      if (data['ok'] == true) {
        _snack('Entrega enviada. Tu asesor(a) fue notificado(a).');
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo enviar.'}', error: true);
      }
    } catch (e) {
      _snack('Error al subir el archivo.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ---------------- Hitos: asesor sube observaciones (Word) ----------------
  Future<void> _subirObservaciones(Map<String, dynamic> h) async {
    final doc = await seleccionarDocumento();
    if (doc == null) return;
    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'titu_hito_observaciones',
        'matricula': widget.matricula,
        'num': h['num'],
        'base64': base64Encode(doc.bytes),
        'mime': doc.mime,
        'registro': widget.correo,
      });
      if (data['ok'] == true) {
        _snack('Observaciones subidas. El estudiante fue notificado.');
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo subir.'}', error: true);
      }
    } catch (e) {
      _snack('Error al subir el archivo.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ---------------- Hitos: revisión del asesor ----------------
  Future<void> _revisarHito(Map<String, dynamic> h, bool aprobar) async {
    final comentCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aprobar ? 'Aprobar entrega' : 'Solicitar cambios'),
        content: TextField(
          controller: comentCtrl,
          maxLines: 3,
          decoration: InputDecoration(
              labelText: aprobar
                  ? 'Comentario (opcional)'
                  : 'Indica los cambios solicitados',
              border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: aprobar ? Colors.green : cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(aprobar ? 'Aprobar' : 'Solicitar cambios',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'titu_hito_revisar',
        'matricula': widget.matricula,
        'num': h['num'],
        'decision': aprobar ? 'aprobado' : 'devuelto',
        'comentario': comentCtrl.text.trim(),
        'registro': widget.correo,
      });
      if (data['ok'] == true) {
        _snack('Revisión registrada. Se notificó al estudiante.');
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo registrar.'}', error: true);
      }
    } catch (e) {
      _snack('Error de conexión.', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ============================ UI ============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tesis · Convenio y seguimiento'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: _contenido(),
                  ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 40, color: Colors.grey),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                  onPressed: _cargar,
                  child: const Text('Reintentar',
                      style: TextStyle(color: Colors.white))),
            ],
          ),
        ),
      );

  List<Widget> _contenido() {
    final asesor = '${_tesis?['director'] ?? ''}'.trim();
    final hayTesis = _tesis != null;
    final estado = '${_tesis?['estado'] ?? ''}';
    final widgets = <Widget>[];

    // Encabezado
    widgets.add(_card([
      Text(widget.nombre.isNotEmpty ? widget.nombre : '${_tesis?['nombre'] ?? widget.matricula}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text('${widget.matricula} · ${widget.programa.isNotEmpty ? widget.programa : _tesis?['programa'] ?? ''}',
          style: TextStyle(color: cessumMuted(context))),
      if (hayTesis) ...[
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.flag, size: 16, color: cessumGold),
          const SizedBox(width: 6),
          Expanded(child: Text('Estado: $estado')),
        ]),
      ],
    ]));

    if (!hayTesis) {
      widgets.add(_card([
        const Text('Aún no hay tesis registrada para esta matrícula.'),
        const SizedBox(height: 8),
        if (_esAdmin)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
            icon: const Icon(Icons.person_add, color: Colors.white),
            label: const Text('Asignar asesor (crear tesis)',
                style: TextStyle(color: Colors.white)),
            onPressed: _guardando ? null : _asignarAsesor,
          )
        else
          Text(
              'Cuando Vicerrectoría asigne tu asesor(a), aquí aparecerá tu convenio y seguimiento.',
              style: TextStyle(color: cessumMuted(context))),
      ]));
      return widgets;
    }

    // Asesor
    widgets.add(_card([
      Row(children: [
        const Icon(Icons.school, color: cessumRed),
        const SizedBox(width: 8),
        const Text('Asesor(a) / Director(a)',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 6),
      Text(asesor.isEmpty ? 'Sin asignar' : asesor,
          style: const TextStyle(fontSize: 15)),
      if (_asesorCorreo.isNotEmpty) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.email_outlined, color: cessumRed),
          label: const Text('Contactar a mi asesor(a)',
              style: TextStyle(color: cessumRed)),
          onPressed: () => Helpers.abrirCorreo(
            context: context,
            destinatario: _asesorCorreo,
            asunto: 'Tesis · ${widget.matricula} ${widget.nombre}',
            cuerpo:
                'Hola, soy ${widget.nombre} (matrícula ${widget.matricula}). ',
          ),
        ),
      ],
      if (_esAdmin) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: Icon(asesor.isEmpty ? Icons.person_add : Icons.swap_horiz,
              color: cessumRed),
          label: Text(asesor.isEmpty ? 'Asignar asesor' : 'Cambiar asesor',
              style: const TextStyle(color: cessumRed)),
          onPressed: _guardando ? null : _asignarAsesor,
        ),
      ],
    ]));

    // Convenio
    widgets.add(_cardConvenio());

    // Hitos
    if (_hitos.isNotEmpty) widgets.add(_cardHitos());

    // Seguimiento
    widgets.add(_cardSeguimiento());

    return widgets;
  }

  Widget _cardConvenio() {
    final estado = '${_convenio?['estado'] ?? (_convenio == null ? 'Sin definir' : 'Borrador')}';
    final firmado = estado == 'Firmado';
    final fa = '${_convenio?['firmaAlumno'] ?? ''}'.startsWith('SÍ');
    final fs = '${_convenio?['firmaAsesor'] ?? ''}'.startsWith('SÍ');
    final fau = '${_convenio?['firmaAutoridad'] ?? ''}'.startsWith('SÍ');
    final fau2 = '${_convenio?['firmaAutoridad2'] ?? ''}'.startsWith('SÍ');
    final aut1 = _autoridades.isNotEmpty ? _autoridades[0] : null;
    final aut2 = _autoridades.length > 1 ? _autoridades[1] : null;
    final cargo1 = aut1 != null
        ? '${aut1['cargo']}'
        : (_vrEsAsesor ? 'Rector' : 'Vicerrector Académico');
    final cargo2 = aut2 != null ? '${aut2['cargo']}' : 'Directora de la Unidad Navojoa';
    final linkPdf = '${_convenio?['linkPdf'] ?? ''}';

    final hijos = <Widget>[
      Row(children: [
        const Icon(Icons.handshake, color: cessumRed),
        const SizedBox(width: 8),
        const Expanded(
            child: Text('Convenio de trabajo',
                style: TextStyle(fontWeight: FontWeight.bold))),
        _chip(estado, firmado ? Colors.green : cessumGold),
      ]),
      const SizedBox(height: 8),
    ];

    if (_convenio != null) {
      final obj = '${_convenio?['objetivo'] ?? ''}';
      if (obj.isNotEmpty) {
        hijos.add(Text('Objetivo: $obj'));
        hijos.add(const SizedBox(height: 4));
      }
      final ini = '${_convenio?['fechaInicio'] ?? ''}';
      final fin = '${_convenio?['fechaTermino'] ?? ''}';
      if (ini.isNotEmpty || fin.isNotEmpty) {
        hijos.add(Text('Vigencia: ${ini.isEmpty ? '—' : ini} a ${fin.isEmpty ? '—' : fin}',
            style: TextStyle(color: cessumMuted(context))));
      }
      hijos.add(const SizedBox(height: 8));
      hijos.add(_firmaLinea('Estudiante', fa));
      hijos.add(_firmaLinea('Asesor(a)', fs));
      hijos.add(_firmaLinea(cargo1, fau));
      hijos.add(_firmaLinea(cargo2, fau2));
    } else {
      hijos.add(Text(
          'Aún no se ha definido el convenio (objetivo, fechas e hitos).',
          style: TextStyle(color: cessumMuted(context))));
    }

    hijos.add(const SizedBox(height: 10));
    final acciones = <Widget>[];

    // Definir / editar (admin o asesor) mientras no esté firmado
    if ((_esAdmin || _esAsesor) && !firmado) {
      acciones.add(ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: cessumGold),
        icon: const Icon(Icons.edit_document, color: Colors.white),
        label: Text(_convenio == null ? 'Definir convenio' : 'Editar convenio',
            style: const TextStyle(color: Colors.white)),
        onPressed: _guardando ? null : _definirConvenio,
      ));
    }

    if (_convenio != null) {
      acciones.add(OutlinedButton.icon(
        icon: const Icon(Icons.visibility, color: cessumRed),
        label: const Text('Vista previa del convenio', style: TextStyle(color: cessumRed)),
        onPressed: _guardando ? null : _verConvenio,
      ));
    }

    // Firmar según rol (requiere convenio definido)
    if (_convenio != null && !firmado) {
      if (_esAlumno && !fa) {
        acciones.add(OutlinedButton.icon(
          icon: const Icon(Icons.draw_outlined, color: cessumRed),
          label: const Text('Mi firma digital', style: TextStyle(color: cessumRed)),
          onPressed: _guardando
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          FirmaAlumnoScreen(matricula: widget.matricula))),
        ));
        acciones.add(_btnFirmar('Firmar como estudiante', 'alumno'));
      }
      if (_esAsesor && !fs) {
        acciones.add(_btnFirmar('Firmar como asesor(a)', 'asesor'));
      }
      if (_esAdmin && !fau) {
        acciones.add(_btnFirmar('Firmar como $cargo1', 'autoridad1'));
      }
      if (_esAdmin && !fau2) {
        acciones.add(_btnFirmar('Firmar como $cargo2', 'autoridad2'));
      }
    }

    if (firmado && linkPdf.isNotEmpty) {
      acciones.add(OutlinedButton.icon(
        icon: const Icon(Icons.picture_as_pdf, color: cessumRed),
        label: const Text('Abrir convenio firmado',
            style: TextStyle(color: cessumRed)),
        onPressed: () => Helpers.abrirUrlExterna(linkPdf, context),
      ));
    }

    if (acciones.isNotEmpty) {
      hijos.add(Wrap(spacing: 8, runSpacing: 8, children: acciones));
    }
    return _card(hijos);
  }

  Widget _btnFirmar(String texto, String parte) => ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
        icon: const Icon(Icons.draw, color: Colors.white),
        label: Text(texto, style: const TextStyle(color: Colors.white)),
        onPressed: _guardando ? null : () => _firmarConvenio(parte),
      );

  Widget _firmaLinea(String quien, bool firmado) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(firmado ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18, color: firmado ? Colors.green : Colors.grey),
          const SizedBox(width: 8),
          Text(quien),
          const SizedBox(width: 6),
          Text(firmado ? 'firmado' : 'pendiente',
              style: TextStyle(
                  color: firmado ? Colors.green : Colors.grey,
                  fontStyle: FontStyle.italic)),
        ]),
      );

  Widget _cardHitos() {
    final hijos = <Widget>[
      Row(children: const [
        Icon(Icons.flag_circle, color: cessumRed),
        SizedBox(width: 8),
        Text('Hitos / entregables',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 6),
    ];
    for (final h in _hitos) {
      final estado = '${h['estado'] ?? 'pendiente'}';
      final link = '${h['link'] ?? ''}';
      final coment = '${h['comentario'] ?? ''}';
      final linkRev = '${h['linkRevision'] ?? ''}';
      final linkCor = '${h['linkCorreccion'] ?? ''}';
      final obs = '${h['observaciones'] ?? ''}';
      Color c = Colors.grey;
      if (estado == 'aprobado') c = Colors.green;
      else if (estado == 'entregado') c = cessumGold;
      else if (estado == 'devuelto') c = Colors.red;
      final acciones = <Widget>[];
      if (_esAlumno && estado != 'aprobado') {
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('Versión para revisión'),
          onPressed: _guardando ? null : () => _entregarHito(h, tipo: 'revision'),
        ));
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.task_alt, size: 18, color: cessumGold),
          label: const Text('Versión con correcciones',
              style: TextStyle(color: cessumGold)),
          onPressed:
              _guardando ? null : () => _entregarHito(h, tipo: 'correccion'),
        ));
      }
      if (_esAsesor || _esAdmin) {
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.rate_review, size: 18, color: cessumRed),
          label: const Text('Subir observaciones',
              style: TextStyle(color: cessumRed)),
          onPressed: _guardando ? null : () => _subirObservaciones(h),
        ));
      }
      if ((_esAsesor || _esAdmin) && estado == 'entregado') {
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.check, size: 18, color: Colors.green),
          label: const Text('Aprobar',
              style: TextStyle(color: Colors.green)),
          onPressed: _guardando ? null : () => _revisarHito(h, true),
        ));
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.undo, size: 18, color: Colors.red),
          label: const Text('Cambios', style: TextStyle(color: Colors.red)),
          onPressed: _guardando ? null : () => _revisarHito(h, false),
        ));
      }
      if (linkRev.isNotEmpty) {
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.attachment, size: 18),
          label: const Text('Ver revisión'),
          onPressed: () => Helpers.abrirUrlExterna(linkRev, context),
        ));
      }
      if (linkCor.isNotEmpty) {
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.attachment, size: 18, color: cessumGold),
          label: const Text('Ver correcciones',
              style: TextStyle(color: cessumGold)),
          onPressed: () => Helpers.abrirUrlExterna(linkCor, context),
        ));
      }
      if (linkRev.isEmpty && linkCor.isEmpty && link.isNotEmpty) {
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.attachment, size: 18),
          label: const Text('Ver entrega'),
          onPressed: () => Helpers.abrirUrlExterna(link, context),
        ));
      }
      if (obs.isNotEmpty) {
        acciones.add(TextButton.icon(
          icon: const Icon(Icons.comment, size: 18, color: cessumRed),
          label: const Text('Observaciones', style: TextStyle(color: cessumRed)),
          onPressed: () => Helpers.abrirUrlExterna(obs, context),
        ));
      }
      hijos.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                  radius: 12,
                  backgroundColor: c,
                  child: Text('${h['num']}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12))),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('${h['hito']}',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600))),
              _chip(estado, c),
            ]),
            if ('${h['fechaCompromiso'] ?? ''}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text('Compromiso: ${h['fechaCompromiso']}',
                    style: TextStyle(
                        fontSize: 12, color: cessumMuted(context))),
              ),
            if (coment.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text('Asesor(a): $coment',
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic)),
              ),
            if (acciones.isNotEmpty)
              Wrap(spacing: 4, children: acciones),
          ],
        ),
      ));
    }
    return _card(hijos);
  }

  Widget _cardSeguimiento() {
    final pct = _totalEtapas > 0
        ? ((_etapaIndice + 1) / _totalEtapas).clamp(0.0, 1.0)
        : 0.0;
    final hijos = <Widget>[
      Row(children: const [
        Icon(Icons.timeline, color: cessumRed),
        SizedBox(width: 8),
        Text('Seguimiento', style: TextStyle(fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 8),
      Text('Etapa actual: ${_tesis?['etapa'] ?? '—'}'),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: pct,
          minHeight: 10,
          backgroundColor: cessumMuted(context).withValues(alpha: 0.18),
          valueColor: const AlwaysStoppedAnimation(cessumRed),
        ),
      ),
      const SizedBox(height: 4),
      Text('Avance: ${(pct * 100).round()}%  (${_etapaIndice + 1}/$_totalEtapas etapas)',
          style: TextStyle(fontSize: 12, color: cessumMuted(context))),
    ];

    if (_interacciones.isNotEmpty) {
      hijos.add(const SizedBox(height: 12));
      hijos.add(const Text('Últimas interacciones',
          style: TextStyle(fontWeight: FontWeight.w600)));
      final ultimas = _interacciones.reversed.take(6).toList();
      for (final it in ultimas) {
        final estado = '${it['estado'] ?? ''}';
        Color c = Colors.grey;
        if (estado == 'vencida') c = Colors.red;
        else if (estado == 'pendiente') c = cessumGold;
        else if (estado == 'respondida') c = Colors.green;
        hijos.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.circle, size: 10, color: c),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${it['tipo']} · ${it['de'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if ('${it['desc'] ?? ''}'.isNotEmpty)
                    Text('${it['desc']}',
                        style: const TextStyle(fontSize: 12)),
                  Text(
                      'Límite: ${it['limite'] ?? '—'} · $estado',
                      style: TextStyle(
                          fontSize: 11, color: cessumMuted(context))),
                ],
              ),
            ),
          ]),
        ));
      }
    }
    return _card(hijos);
  }

  // ---------------- helpers UI ----------------
  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).cardColor
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: cessumMuted(context).withValues(alpha: 0.18), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _chip(String texto, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(texto,
            style: TextStyle(
                color: c, fontSize: 11, fontWeight: FontWeight.bold)),
      );
}

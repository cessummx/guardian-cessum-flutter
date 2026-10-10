import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'foto_web_picker.dart';
import 'constants.dart';
import 'cessum_ui.dart';

/// Detalle de una carpeta de la Autoevaluación CESSUM 2026.
///
/// Lista los indicadores de la carpeta y, si el usuario tiene permiso,
/// permite cambiar el estatus, escribir la revisión 1 y las acciones de
/// solventación, y registrar o quitar evidencias (por enlace).
class AutoevaluacionDetalleScreen extends StatefulWidget {
  final int numero;
  final String nombre;
  const AutoevaluacionDetalleScreen({
    super.key,
    required this.numero,
    this.nombre = '',
  });

  @override
  State<AutoevaluacionDetalleScreen> createState() =>
      _AutoevaluacionDetalleScreenState();
}

class _AutoevaluacionDetalleScreenState
    extends State<AutoevaluacionDetalleScreen> {
  static const Color _verde = Color(0xFF1E8E3E);
  static const Color _gris = Color(0xFF9AA0A6);
  static const List<String> _estatuses = [
    'Pendiente',
    'En proceso',
    'Completo',
    'Observado',
  ];

  Map<String, dynamic>? _carpeta;
  Map<String, dynamic> _datosAuto = {};
  bool _puedeEditar = false;
  bool _cargando = true;
  String? _error;
  String _correo = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'autoeval_carpeta',
        'numero': widget.numero.toString(),
        'correo': _correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      if (!mounted) return;
      setState(() {
        _carpeta = Map<String, dynamic>.from(data['carpeta'] as Map);
        _puedeEditar = data['puedeEditar'] == true;
        _cargando = false;
      });
      _cargarDatosAuto();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la carpeta. Revisa tu conexión.';
      });
    }
  }

  Color _colorEstatus(String s) {
    switch (s.trim()) {
      case 'Completo':
        return _verde;
      case 'En proceso':
        return cessumGold;
      case 'Observado':
        return cessumRed;
      default:
        return _gris; // Pendiente
    }
  }

  // ---- POST genérico al Guardián ----
  Future<Map<String, dynamic>?> _post(Map<String, dynamic> cuerpo) async {
    try {
      cuerpo['correo'] = _correo;
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(cuerpo),
          )
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        _aviso(data['error']?.toString() ?? 'No se pudo guardar.');
        return null;
      }
      return data;
    } catch (_) {
      _aviso('Error de conexión. Intenta de nuevo.');
      return null;
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _abrirEnlace(String url) async {
    try {
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el enlace.');
    }
  }

  List<Map<String, dynamic>> get _indicadores =>
      ((_carpeta?['indicadores'] as List<dynamic>?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  // ---- Cambiar estatus ----
  Future<void> _cambiarEstatus(Map<String, dynamic> ind) async {
    if (!_puedeEditar) return;
    final actual = (ind['estatus'] ?? 'Pendiente').toString();
    final elegido = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cessumBg(context, Colors.white),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Cambiar estatus',
                style: CessumType.heading(15, color: cessumInk(ctx))),
            const SizedBox(height: 8),
            for (final s in _estatuses)
              ListTile(
                leading: Icon(Icons.circle, size: 16, color: _colorEstatus(s)),
                title: Text(s, style: CessumType.body(14, color: cessumInk(ctx))),
                trailing: s == actual
                    ? Icon(Icons.check, color: cessumRed)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (elegido == null || elegido == actual) return;

    final data = await _post({
      'accion': 'autoeval_set_estatus',
      'carpetaNumero': widget.numero,
      'indicadorNumero': ind['numero'],
      'estatus': elegido,
    });
    if (data == null) return;
    setState(() {
      ind['estatus'] = elegido;
      if (data['resumen'] != null) {
        final r = Map<String, dynamic>.from(data['resumen'] as Map);
        _carpeta!['porcentajeAvance'] = r['porcentajeAvance'];
        _carpeta!['conteoPorEstatus'] = r['conteoPorEstatus'];
        _carpeta!['totalIndicadores'] = r['totalIndicadores'];
      }
    });
  }

  // ---- Editar revisión y acciones de solventación ----
  Future<void> _editarRevision(Map<String, dynamic> ind) async {
    if (!_puedeEditar) return;
    final rev = TextEditingController(text: (ind['revision1'] ?? '').toString());
    final acc = TextEditingController(
        text: (ind['accionesSolventacion'] ?? '').toString());
    String fecha = (ind['fechaSolventacion'] ?? '').toString();

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Revisión y solventación'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: rev,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Revisión 1',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: acc,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Acciones de solventación',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fecha.isEmpty ? 'Sin fecha de solventación' : 'Fecha: $fecha',
                        style: CessumType.body(13, color: cessumMuted(ctx)),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.event),
                      label: const Text('Fecha'),
                      onPressed: () async {
                        final hoy = DateTime.now();
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: hoy,
                          firstDate: DateTime(hoy.year - 1),
                          lastDate: DateTime(hoy.year + 2),
                        );
                        if (d != null) {
                          final mm = d.month.toString().padLeft(2, '0');
                          final dd = d.day.toString().padLeft(2, '0');
                          setLocal(() => fecha = '${d.year}-$mm-$dd');
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (guardado != true) return;

    final data = await _post({
      'accion': 'autoeval_set_revision',
      'carpetaNumero': widget.numero,
      'indicadorNumero': ind['numero'],
      'revision1': rev.text.trim(),
      'accionesSolventacion': acc.text.trim(),
      'fechaSolventacion': fecha,
    });
    if (data == null) return;
    setState(() {
      ind['revision1'] = rev.text.trim();
      ind['accionesSolventacion'] = acc.text.trim();
      ind['fechaSolventacion'] = fecha;
    });
  }

  // Trae los "datos automáticos" calculados por la app (padrón, grupos,
  // calificaciones, titulación). No bloquea: si falla, simplemente no se muestran.
  Future<void> _cargarDatosAuto() async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'autoeval_datos_auto',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true && data['datos'] != null) {
        setState(() {
          _datosAuto = Map<String, dynamic>.from(data['datos'] as Map);
        });
      }
    } catch (_) {}
  }

  // Vuelca el dato automático a la Revisión 1 del indicador, de un toque.
  Future<void> _usarDatoEnRevision(
      Map<String, dynamic> ind, Map<String, dynamic> dato) async {
    if (!_puedeEditar) return;
    final lineas = (dato['lineas'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final texto = [
      (dato['titulo'] ?? '').toString(),
      (dato['resumen'] ?? '').toString(),
      ...lineas,
    ].where((s) => s.isNotEmpty).join('\n');

    final data = await _post({
      'accion': 'autoeval_set_revision',
      'carpetaNumero': widget.numero,
      'indicadorNumero': ind['numero'],
      'revision1': texto,
      'accionesSolventacion': (ind['accionesSolventacion'] ?? '').toString(),
      'fechaSolventacion': (ind['fechaSolventacion'] ?? '').toString(),
    });
    if (data == null) return;
    setState(() => ind['revision1'] = texto);
    _aviso('Dato copiado a la Revisión 1.');
  }

  // ---- Registrar actividad (hoja registradora universal) ----
  Future<void> _registrarActividad(Map<String, dynamic> ind) async {
    if (!_puedeEditar) return;
    final titulo = TextEditingController();
    final nota = TextEditingController();
    String fecha = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Registrar actividad'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titulo,
                  decoration: const InputDecoration(
                    labelText: 'Actividad / acción realizada',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nota,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fecha.isEmpty ? 'Fecha: hoy' : 'Fecha: $fecha',
                        style: CessumType.body(13, color: cessumMuted(ctx)),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.event),
                      label: const Text('Fecha'),
                      onPressed: () async {
                        final hoy = DateTime.now();
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: hoy,
                          firstDate: DateTime(hoy.year - 2),
                          lastDate: DateTime(hoy.year + 1),
                        );
                        if (d != null) {
                          final mm = d.month.toString().padLeft(2, '0');
                          final dd = d.day.toString().padLeft(2, '0');
                          setLocal(() => fecha = '${d.year}-$mm-$dd');
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (titulo.text.trim().isEmpty) {
      _aviso('Escribe la actividad.');
      return;
    }
    final data = await _post({
      'accion': 'autoeval_act_registrar',
      'carpetaNumero': widget.numero,
      'indicadorNumero': ind['numero'],
      'titulo': titulo.text.trim(),
      'fecha': fecha,
      'nota': nota.text.trim(),
    });
    if (data == null) return;
    setState(() {
      ind['actividades'] = (data['actividades'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if ((ind['estatus'] ?? '').toString() == 'Pendiente') {
        ind['estatus'] = 'En proceso';
      }
    });
  }

  Future<void> _eliminarActividad(Map<String, dynamic> ind, String id) async {
    if (!_puedeEditar) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar actividad'),
        content: const Text('¿Seguro que quieres quitar esta actividad?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final data = await _post({
      'accion': 'autoeval_act_eliminar',
      'carpetaNumero': widget.numero,
      'indicadorNumero': ind['numero'],
      'id': id,
    });
    if (data == null) return;
    setState(() {
      ind['actividades'] = (data['actividades'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  // ---- Agregar evidencia: elegir entre subir archivo o pegar enlace ----
  Future<void> _agregarEvidencia(Map<String, dynamic> ind) async {
    if (!_puedeEditar) return;
    final opcion = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cessumBg(context, Colors.white),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Agregar evidencia',
                style: CessumType.heading(15, color: cessumInk(ctx))),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.upload_file, color: cessumRed),
              title: const Text('Subir archivo (imagen o PDF)'),
              onTap: () => Navigator.pop(ctx, 'archivo'),
            ),
            ListTile(
              leading: Icon(Icons.link, color: cessumGold),
              title: const Text('Pegar un enlace'),
              onTap: () => Navigator.pop(ctx, 'enlace'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (opcion == 'archivo') {
      await _subirArchivo(ind);
    } else if (opcion == 'enlace') {
      await _agregarPorEnlace(ind);
    }
  }

  // ---- Subir archivo a Drive ----
  Future<void> _subirArchivo(Map<String, dynamic> ind) async {
    DocElegido? doc;
    try {
      doc = await seleccionarDocumento(tipo: 'ambos');
    } catch (e) {
      _aviso(e.toString().replaceFirst('Exception: ', ''));
      return;
    }
    if (doc == null) return;
    _aviso('Subiendo archivo…');
    final data = await _post({
      'accion': 'autoeval_subir_evidencia',
      'carpetaNumero': widget.numero,
      'indicadorNumero': ind['numero'],
      'nombre': doc.nombre,
      'mime': doc.mime,
      'base64': base64Encode(doc.bytes),
    });
    if (data == null) return;
    setState(() {
      ind['evidencias'] = (data['evidencias'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
    _aviso('Evidencia subida.');
  }

  // ---- Agregar evidencia por enlace ----
  Future<void> _agregarPorEnlace(Map<String, dynamic> ind) async {
    final nombre = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar evidencia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombre,
              decoration: const InputDecoration(
                labelText: 'Nombre de la evidencia',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Enlace (Drive, cPanel, etc.)',
                hintText: 'https://...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (nombre.text.trim().isEmpty || url.text.trim().isEmpty) {
      _aviso('Escribe el nombre y el enlace.');
      return;
    }

    final data = await _post({
      'accion': 'autoeval_add_evidencia',
      'carpetaNumero': widget.numero,
      'indicadorNumero': ind['numero'],
      'nombre': nombre.text.trim(),
      'url': url.text.trim(),
    });
    if (data == null) return;
    setState(() {
      ind['evidencias'] = (data['evidencias'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  // ---- Quitar evidencia ----
  Future<void> _quitarEvidencia(Map<String, dynamic> ind, int indice) async {
    if (!_puedeEditar) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar evidencia'),
        content: const Text('¿Seguro que quieres quitar esta evidencia?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final data = await _post({
      'accion': 'autoeval_del_evidencia',
      'carpetaNumero': widget.numero,
      'indicadorNumero': ind['numero'],
      'indice': indice,
    });
    if (data == null) return;
    setState(() {
      ind['evidencias'] = (data['evidencias'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final titulo = widget.nombre.isNotEmpty
        ? '${widget.numero}. ${widget.nombre}'
        : 'Carpeta ${widget.numero}';
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text(titulo, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        color: cessumRed,
        child: _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          SkeletonCard(),
          SizedBox(height: 12),
          SkeletonCard(),
          SizedBox(height: 12),
          SkeletonCard(),
        ],
      );
    }
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        CessumEmptyState(
          title: 'No se pudo cargar',
          subtitle: _error,
          icon: Icons.wifi_off_rounded,
          action: FilledButton.icon(
            onPressed: _cargar,
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ]);
    }

    final inds = _indicadores;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: inds.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i == 0) return _cabeceraCarpeta();
        return _tarjetaIndicador(inds[i - 1]);
      },
    );
  }

  Widget _cabeceraCarpeta() {
    final isDark = cessumIsDark(context);
    final pct = (_carpeta?['porcentajeAvance'] as num?)?.round() ?? 0;
    final responsables = (_carpeta?['responsables'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final nombresResp = responsables
        .map((r) => (r['nombre'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .join(' · ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          StatRing(
            value: pct / 100,
            centerText: '$pct%',
            color: pct >= 100 ? _verde : (pct > 0 ? cessumGold : _gris),
            size: 80,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Avance de la carpeta',
                    style: CessumType.heading(15, color: cessumInk(context))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.person_outline,
                        size: 14, color: cessumMuted(context)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        nombresResp.isEmpty ? 'Sin responsable' : nombresResp,
                        style: CessumType.body(12, color: cessumMuted(context)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _puedeEditar
                      ? 'Puedes editar esta carpeta.'
                      : 'Solo lectura (no eres responsable).',
                  style: CessumType.label(11, color: cessumFaint(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaIndicador(Map<String, dynamic> ind) {
    final isDark = cessumIsDark(context);
    final numero = (ind['numero'] as num?)?.toInt() ?? 0;
    final nombre = (ind['nombre'] ?? '').toString();
    final descripcion = (ind['descripcion'] ?? '').toString();
    final estatus = (ind['estatus'] ?? 'Pendiente').toString();
    final color = _colorEstatus(estatus);
    final revision = (ind['revision1'] ?? '').toString();
    final acciones = (ind['accionesSolventacion'] ?? '').toString();
    final fecha = (ind['fechaSolventacion'] ?? '').toString();
    final evidencias = (ind['evidencias'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Título + estatus
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text('$numero. $nombre',
                    style: CessumType.heading(14, color: cessumInk(context))),
              ),
              const SizedBox(width: 8),
              _Pildora(
                texto: estatus,
                color: color,
                onTap: _puedeEditar ? () => _cambiarEstatus(ind) : null,
              ),
            ],
          ),
          if (descripcion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(descripcion,
                style: CessumType.body(12, color: cessumMuted(context))),
          ],

          _datoAutoWidget(ind, numero),

          _actividadesWidget(ind),

          // Evidencias
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.attach_file, size: 15, color: cessumMuted(context)),
              const SizedBox(width: 4),
              Text('Evidencias (${evidencias.length})',
                  style: CessumType.label(12, color: cessumMuted(context))),
              const Spacer(),
              if (_puedeEditar)
                TextButton.icon(
                  onPressed: () => _agregarEvidencia(ind),
                  icon: Icon(Icons.add, size: 18, color: cessumRed),
                  label: Text('Agregar',
                      style: CessumType.label(12, color: cessumRed)),
                ),
            ],
          ),
          if (evidencias.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 2),
              child: Text('Aún no hay evidencias.',
                  style: CessumType.label(11, color: cessumFaint(context))),
            )
          else
            for (int k = 0; k < evidencias.length; k++)
              _filaEvidencia(ind, evidencias[k], k),

          // Revisión y acciones de solventación
          const SizedBox(height: 10),
          Divider(color: cessumFaint(context).withValues(alpha: 0.3)),
          if (revision.isNotEmpty) _campoTexto('Revisión 1', revision),
          if (acciones.isNotEmpty)
            _campoTexto('Acciones de solventación', acciones),
          if (fecha.isNotEmpty)
            _campoTexto('Fecha de solventación', fecha),
          if (revision.isEmpty && acciones.isEmpty && fecha.isEmpty)
            Text('Sin revisión registrada.',
                style: CessumType.label(11, color: cessumFaint(context))),
          if (_puedeEditar) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _editarRevision(ind),
                icon: Icon(Icons.edit_note, size: 18, color: cessumGold),
                label: Text('Editar revisión / solventación',
                    style: CessumType.label(12, color: cessumGold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filaEvidencia(Map<String, dynamic> ind, Map<String, dynamic> ev, int k) {
    final nombre = (ev['nombre'] ?? '').toString();
    final url = (ev['url'] ?? '').toString();
    final fecha = (ev['fecha'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_outlined,
              size: 16, color: cessumGold),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: url.isEmpty ? null : () => _abrirEnlace(url),
              child: Text(
                fecha.isEmpty ? nombre : '$nombre  ·  $fecha',
                style: CessumType.body(12, color: cessumInk(context)).copyWith(
                  decoration:
                      url.isEmpty ? null : TextDecoration.underline,
                ),
              ),
            ),
          ),
          if (_puedeEditar)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 16, color: cessumMuted(context)),
              onPressed: () => _quitarEvidencia(ind, k),
            ),
        ],
      ),
    );
  }

  // Sección de actividades registradas (hoja registradora universal).
  Widget _actividadesWidget(Map<String, dynamic> ind) {
    final actividades = (ind['actividades'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.checklist_rtl, size: 15, color: cessumMuted(context)),
            const SizedBox(width: 4),
            Text('Actividades (${actividades.length})',
                style: CessumType.label(12, color: cessumMuted(context))),
            const Spacer(),
            if (_puedeEditar)
              TextButton.icon(
                onPressed: () => _registrarActividad(ind),
                icon: Icon(Icons.add, size: 18, color: cessumRed),
                label: Text('Registrar',
                    style: CessumType.label(12, color: cessumRed)),
              ),
          ],
        ),
        if (actividades.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 2),
            child: Text('Aún no hay actividades registradas.',
                style: CessumType.label(11, color: cessumFaint(context))),
          )
        else
          for (final act in actividades) _filaActividad(ind, act),
      ],
    );
  }

  Widget _filaActividad(Map<String, dynamic> ind, Map<String, dynamic> act) {
    final titulo = (act['titulo'] ?? '').toString();
    final fecha = (act['fecha'] ?? '').toString();
    final nota = (act['nota'] ?? '').toString();
    final id = (act['id'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.task_alt, size: 16, color: cessumGold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fecha.isEmpty ? titulo : '$titulo  ·  $fecha',
                  style: CessumType.body(12, color: cessumInk(context)),
                ),
                if (nota.isNotEmpty)
                  Text(nota,
                      style: CessumType.label(11, color: cessumMuted(context))),
              ],
            ),
          ),
          if (_puedeEditar)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, size: 16, color: cessumMuted(context)),
              onPressed: () => _eliminarActividad(ind, id),
            ),
        ],
      ),
    );
  }

  // Tarjeta de "dato automático" calculado por la app para este indicador.
  Widget _datoAutoWidget(Map<String, dynamic> ind, int numero) {
    final dato = _datosAuto['$numero'];
    if (dato == null) return const SizedBox.shrink();
    final d = Map<String, dynamic>.from(dato as Map);
    final titulo = (d['titulo'] ?? '').toString();
    final resumen = (d['resumen'] ?? '').toString();
    final lineas = (d['lineas'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights, size: 16, color: cessumGold),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titulo.isEmpty ? 'Dato automático (de la app)' : titulo,
                  style: CessumType.heading(12, color: cessumInk(context)),
                ),
              ),
            ],
          ),
          if (resumen.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(resumen, style: CessumType.body(13, color: cessumInk(context))),
          ],
          for (final l in lineas)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $l',
                  style: CessumType.body(12, color: cessumMuted(context))),
            ),
          if (_puedeEditar) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _usarDatoEnRevision(ind, d),
                icon: Icon(Icons.playlist_add_check, size: 18, color: cessumRed),
                label: Text('Usar en la Revisión 1',
                    style: CessumType.label(12, color: cessumRed)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _campoTexto(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta,
              style: CessumType.label(11, color: cessumMuted(context))),
          const SizedBox(height: 2),
          Text(valor, style: CessumType.body(13, color: cessumInk(context))),
        ],
      ),
    );
  }
}

// Píldora de estatus (tocable para cambiarlo si hay permiso).
class _Pildora extends StatelessWidget {
  final String texto;
  final Color color;
  final VoidCallback? onTap;
  const _Pildora({required this.texto, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final hijo = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: color),
          const SizedBox(width: 6),
          Text(texto, style: CessumType.label(11, color: color)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 14, color: color),
          ],
        ],
      ),
    );
    if (onTap == null) return hijo;
    return InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: hijo);
  }
}

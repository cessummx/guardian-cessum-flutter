import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'admin_config.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'autoevaluacion_detalle_screen.dart';

/// Tablero general de la Autoevaluación Institucional CESSUM 2026.
///
/// Comportamiento por rol:
///  - Administración (Rectoría/Vicerrectoría/superadmins): ve las 10 carpetas
///    y puede alternar entre "Todas" y "Mías", además de exportar.
///  - Responsable normal: ve automáticamente solo las carpetas que le tocan.
///
/// Si se pasa [soloCorreo] explícito, fuerza el modo "Mis carpetas".
class AutoevaluacionTableroScreen extends StatefulWidget {
  final String? soloCorreo;
  const AutoevaluacionTableroScreen({super.key, this.soloCorreo});

  @override
  State<AutoevaluacionTableroScreen> createState() =>
      _AutoevaluacionTableroScreenState();
}

class _AutoevaluacionTableroScreenState
    extends State<AutoevaluacionTableroScreen> {
  static const Color _verde = Color(0xFF1E8E3E);
  static const Color _gris = Color(0xFF9AA0A6);

  List<Map<String, dynamic>> _carpetas = [];
  bool _cargando = true;
  bool _exportando = false;
  String? _error;

  String _correo = '';
  bool _esAdmin = false;
  bool _verSoloMias = false;

  @override
  void initState() {
    super.initState();
    _inicial();
  }

  Future<void> _inicial() async {
    _correo = (await SessionStore.validEmail()) ?? '';
    _esAdmin = esAdmin(_correo);
    await _cargar();
  }

  // Correo por el que filtrar (vacío = todas).
  String get _filtroCorreo {
    final forzado = widget.soloCorreo?.trim();
    if (forzado != null && forzado.isNotEmpty) return forzado;
    if (!_esAdmin) return _correo; // responsable normal: solo las suyas
    return _verSoloMias ? _correo : '';
  }

  bool get _modoMisCarpetas =>
      (widget.soloCorreo != null && widget.soloCorreo!.isNotEmpty) ||
      (!_esAdmin) ||
      _verSoloMias;

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final params = <String, String>{'accion': 'autoeval_listar'};
      final f = _filtroCorreo;
      if (f.isNotEmpty) params['correo'] = f;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final lista = (data['carpetas'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _carpetas = lista;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el tablero. Revisa tu conexión.';
      });
    }
  }

  int get _avanceGlobal {
    if (_carpetas.isEmpty) return 0;
    var suma = 0;
    for (final c in _carpetas) {
      suma += (c['porcentajeAvance'] as num?)?.round() ?? 0;
    }
    return (suma / _carpetas.length).round();
  }

  Color _colorCarpeta(Map<String, dynamic> c) {
    final pct = (c['porcentajeAvance'] as num?)?.round() ?? 0;
    final conteo = Map<String, dynamic>.from(
        c['conteoPorEstatus'] as Map? ?? const {});
    final observados = (conteo['Observado'] as num?)?.toInt() ?? 0;
    if (observados > 0) return cessumRed;
    if (pct >= 100) return _verde;
    if (pct > 0) return cessumGold;
    return _gris;
  }

  Future<void> _abrirCarpeta(Map<String, dynamic> c) async {
    final numero = (c['numero'] as num?)?.toInt() ?? 0;
    final nombre = (c['nombre'] ?? '').toString();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AutoevaluacionDetalleScreen(numero: numero, nombre: nombre),
      ),
    );
    if (mounted) _cargar(); // refresca el avance al volver
  }

  Future<void> _abrirEnlace(String url) async {
    try {
      await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el enlace.')),
        );
      }
    }
  }

  // ---- Sincronizar evidencias desde Drive ----
  Future<void> _sincronizar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sincronizar evidencias de Drive'),
        content: const Text(
            'Revisaré la carpeta de Drive de la autoevaluación y registraré como '
            'evidencia los archivos que ya existen en cada indicador. Los que ya '
            'estaban no se duplican. Puede tardar un momento. ¿Continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sincronizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _exportando = true); // reutiliza el indicador de ocupado
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'autoeval_sincronizar_drive',
              'correo': _correo,
            }),
          )
          .timeout(const Duration(seconds: 300));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo sincronizar.');
      }
      if (!mounted) return;
      setState(() => _exportando = false);
      final ev = (data['evidenciasAgregadas'] as num?)?.toInt() ?? 0;
      final ind = (data['indicadoresActualizados'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ev == 0
            ? 'Todo al día: no había evidencias nuevas que registrar.'
            : 'Listo: $ev evidencias agregadas en $ind indicadores.'),
      ));
      _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _exportando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  // ---- Exportar concentrado ----
  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'autoeval_exportar',
        'correo': _correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo exportar.');
      }
      if (!mounted) return;
      setState(() => _exportando = false);
      _mostrarOpcionesExport(
        (data['url'] ?? '').toString(),
        (data['excelUrl'] ?? '').toString(),
        (data['pdfUrl'] ?? '').toString(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exportando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  void _mostrarOpcionesExport(String url, String excelUrl, String pdfUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: cessumBg(context, Colors.white),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 14),
            Text('Concentrado de autoevaluación',
                style: CessumType.heading(15, color: cessumInk(ctx))),
            const SizedBox(height: 8),
            if (excelUrl.isNotEmpty)
              ListTile(
                leading: Icon(Icons.grid_on, color: _verde),
                title: const Text('Descargar Excel'),
                onTap: () {
                  Navigator.pop(ctx);
                  _abrirEnlace(excelUrl);
                },
              ),
            if (pdfUrl.isNotEmpty)
              ListTile(
                leading: Icon(Icons.picture_as_pdf, color: cessumRed),
                title: const Text('Descargar PDF'),
                onTap: () {
                  Navigator.pop(ctx);
                  _abrirEnlace(pdfUrl);
                },
              ),
            if (url.isNotEmpty)
              ListTile(
                leading: Icon(Icons.open_in_new, color: cessumGold),
                title: const Text('Abrir la hoja en línea'),
                onTap: () {
                  Navigator.pop(ctx);
                  _abrirEnlace(url);
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text(_modoMisCarpetas && !_esAdmin
            ? 'Mis carpetas'
            : 'Autoevaluación CESSUM 2026'),
        actions: [
          if (_esAdmin)
            IconButton(
              tooltip: 'Sincronizar evidencias de Drive',
              icon: const Icon(Icons.sync),
              onPressed: _exportando ? null : _sincronizar,
            ),
          if (_esAdmin)
            IconButton(
              tooltip: 'Exportar concentrado',
              icon: _exportando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.file_download_outlined),
              onPressed: _exportando ? null : _exportar,
            ),
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

    if (_carpetas.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        CessumEmptyState(
          title: 'Sin carpetas asignadas',
          subtitle: 'No hay carpetas de autoevaluación para mostrar.',
          icon: Icons.folder_open_rounded,
        ),
      ]);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: _carpetas.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i == 0) return _resumenGlobal();
        return _tarjetaCarpeta(_carpetas[i - 1]);
      },
    );
  }

  Widget _resumenGlobal() {
    final isDark = cessumIsDark(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF211F1D) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              StatRing(
                value: _avanceGlobal / 100,
                centerText: '$_avanceGlobal%',
                color: cessumRed,
                size: 84,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Avance global',
                        style:
                            CessumType.heading(16, color: cessumInk(context))),
                    const SizedBox(height: 4),
                    Text('${_carpetas.length} carpetas mostradas',
                        style:
                            CessumType.body(13, color: cessumMuted(context))),
                    const SizedBox(height: 2),
                    Text('Promedio del avance de las carpetas mostradas.',
                        style:
                            CessumType.label(11, color: cessumFaint(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _semaforo(),
        if (_esAdmin &&
            (widget.soloCorreo == null || widget.soloCorreo!.isEmpty)) ...[
          const SizedBox(height: 12),
          _interruptorVista(),
        ],
      ],
    );
  }

  Widget _interruptorVista() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
            value: false, label: Text('Todas'), icon: Icon(Icons.apps)),
        ButtonSegment(
            value: true, label: Text('Mías'), icon: Icon(Icons.person)),
      ],
      selected: {_verSoloMias},
      onSelectionChanged: (s) {
        setState(() => _verSoloMias = s.first);
        _cargar();
      },
    );
  }

  Widget _semaforo() {
    if (_carpetas.isEmpty) return const SizedBox.shrink();
    final isDark = cessumIsDark(context);
    final enRiesgo = _carpetas.where((c) {
      final pct = (c['porcentajeAvance'] as num?)?.round() ?? 0;
      final conteo =
          Map<String, dynamic>.from(c['conteoPorEstatus'] as Map? ?? const {});
      final obs = (conteo['Observado'] as num?)?.toInt() ?? 0;
      return obs > 0 || pct == 0;
    }).length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.traffic, color: cessumRed, size: 20),
            const SizedBox(width: 8),
            Text('Semáforo por carpeta',
                style: CessumType.heading(15, color: cessumInk(context))),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final c in _carpetas) _semaforoTile(c)],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _leyenda(_verde, 'Al día'),
              _leyenda(cessumGold, 'En proceso'),
              _leyenda(cessumRed, 'Requiere atención'),
              _leyenda(_gris, 'Sin iniciar'),
            ],
          ),
          if (enRiesgo > 0) ...[
            const SizedBox(height: 10),
            Text(
              enRiesgo == 1
                  ? '1 carpeta requiere atención (observada o sin iniciar).'
                  : '$enRiesgo carpetas requieren atención (observadas o sin iniciar).',
              style: CessumType.body(12, color: cessumRed),
            ),
          ],
        ],
      ),
    );
  }

  Widget _semaforoTile(Map<String, dynamic> c) {
    final numero = (c['numero'] as num?)?.toInt() ?? 0;
    final pct = (c['porcentajeAvance'] as num?)?.round() ?? 0;
    final color = _colorCarpeta(c);
    return InkWell(
      onTap: () => _abrirCarpeta(c),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.6),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$numero', style: CessumType.heading(18, color: color)),
            Text('$pct%', style: CessumType.label(10, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _leyenda(Color color, String txt) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 5),
        Text(txt, style: CessumType.label(11, color: cessumMuted(context))),
      ],
    );
  }

  Widget _tarjetaCarpeta(Map<String, dynamic> c) {
    final isDark = cessumIsDark(context);
    final numero = (c['numero'] as num?)?.toInt() ?? 0;
    final nombre = (c['nombre'] ?? '').toString();
    final pct = (c['porcentajeAvance'] as num?)?.round() ?? 0;
    final total = (c['totalIndicadores'] as num?)?.toInt() ?? 0;
    final color = _colorCarpeta(c);

    final responsables = (c['responsables'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final nombresResp = responsables
        .map((r) => (r['nombre'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .join(' · ');

    final conteo =
        Map<String, dynamic>.from(c['conteoPorEstatus'] as Map? ?? const {});

    return Material(
      color: isDark ? const Color(0xFF211F1D) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _abrirCarpeta(c),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatRing(
                value: pct / 100,
                centerText: '$pct%',
                color: color,
                size: 72,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$numero. $nombre',
                        style:
                            CessumType.heading(15, color: cessumInk(context))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 14, color: cessumMuted(context)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            nombresResp.isEmpty
                                ? 'Sin responsable'
                                : nombresResp,
                            style: CessumType.body(12,
                                color: cessumMuted(context)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip('$total indicadores', _gris),
                        if (((conteo['Completo'] as num?)?.toInt() ?? 0) > 0)
                          _chip('${conteo['Completo']} completos', _verde),
                        if (((conteo['En proceso'] as num?)?.toInt() ?? 0) > 0)
                          _chip('${conteo['En proceso']} en proceso',
                              cessumGold),
                        if (((conteo['Observado'] as num?)?.toInt() ?? 0) > 0)
                          _chip('${conteo['Observado']} observados', cessumRed),
                        if (((conteo['Pendiente'] as num?)?.toInt() ?? 0) > 0)
                          _chip('${conteo['Pendiente']} pendientes', _gris),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(texto, style: CessumType.label(11, color: color)),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'foto_web_picker.dart';
import 'helpers.dart';

/// Apartado "Identidad CESSUM": descarga de logos en alta calidad y del
/// manual de identidad. El admin (Vicerrectoría) sube y administra los
/// archivos desde la app. Usa la hoja Formatos con categorías reservadas.
class IdentidadScreen extends StatefulWidget {
  final bool admin;
  const IdentidadScreen({super.key, this.admin = false});

  @override
  State<IdentidadScreen> createState() => _IdentidadScreenState();
}

class _IdentidadScreenState extends State<IdentidadScreen> {
  static const String catLogo = 'Logo';
  static const String catManual = 'Manual de identidad';
  static const List<String> _tiposSubir = [catLogo, catManual];

  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> p) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: p);
    final r = await http.get(uri).timeout(const Duration(seconds: 45));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 180));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  bool _esIdentidad(String cat) {
    final c = cat.toLowerCase();
    return c == 'logo' ||
        c == 'manual de identidad' ||
        c.contains('identidad');
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final data = await _get({
        'accion': 'formatos_listar',
        if (widget.admin) 'admin': '1',
      });
      if (!mounted) return;
      final all = ((data['formatos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((it) => _esIdentidad('${it['categoria'] ?? ''}'))
          .toList();
      setState(() {
        _items = all;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los recursos de identidad.';
      });
    }
  }

  List<Map<String, dynamic>> get _logos => _items
      .where((it) => '${it['categoria']}'.toLowerCase() == 'logo')
      .toList();
  List<Map<String, dynamic>> get _manuales => _items
      .where((it) => '${it['categoria']}'.toLowerCase() != 'logo')
      .toList();

  String? _driveId(String url) {
    final m1 = RegExp(r'/d/([A-Za-z0-9_-]{10,})').firstMatch(url);
    if (m1 != null) return m1.group(1);
    final m2 = RegExp(r'[?&]id=([A-Za-z0-9_-]{10,})').firstMatch(url);
    if (m2 != null) return m2.group(1);
    return null;
  }

  String _previewUrl(String url) {
    final id = _driveId(url);
    if (id != null) return 'https://drive.google.com/uc?export=view&id=$id';
    return url;
  }

  void _snack(String t, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t), backgroundColor: ok ? Colors.green : cessumRed));
  }

  // -------- Admin: subir --------
  Future<void> _subir() async {
    final tituloCtrl = TextEditingController();
    String tipo = catLogo;
    DocElegido? archivo;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Subir recurso de identidad'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Tipo', border: OutlineInputBorder()),
                  items: _tiposSubir
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setS(() => tipo = v ?? tipo),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tituloCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Nombre (ej. Logo principal, Logo blanco)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, color: cessumRed),
                  label: Text(
                    archivo == null
                        ? 'Elegir archivo (alta calidad)'
                        : archivo!.nombre,
                    style: const TextStyle(color: cessumRed),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () async {
                    try {
                      final d =
                          await seleccionarDocumento(tipo: 'original');
                      if (d != null) setS(() => archivo = d);
                    } catch (e) {
                      _snack('$e'.replaceAll('Exception: ', ''));
                    }
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Los logos se suben sin compresión (PNG, SVG, JPG). '
                  'El manual en PDF.',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () {
                if (archivo == null || tituloCtrl.text.trim().isEmpty) {
                  _snack('Pon un nombre y elige un archivo.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Subir', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || archivo == null) return;
    setState(() => _guardando = true);
    try {
      final data = await _post({
        'accion': 'formato_guardar',
        'titulo': tituloCtrl.text.trim(),
        'categoria': tipo,
        'descripcion': '',
        'activo': true,
        'orden': _items.length + 1,
        'base64': base64Encode(archivo!.bytes),
        'mime': archivo!.mime,
        'nombreArchivo': archivo!.nombre,
      });
      if (data['ok'] == true) {
        _snack('Recurso subido.', ok: true);
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo subir.'}');
      }
    } catch (e) {
      _snack('Error al subir el archivo.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar recurso'),
        content: Text('¿Eliminar "${it['titulo']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Eliminar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // (24-sep) Se revisa la respuesta: antes recargaba como si se hubiera borrado.
      final d = await _post({'accion': 'formato_eliminar', 'id': it['id']});
      if (d['ok'] != true) {
        _snack('${d['error'] ?? 'No se pudo eliminar.'}');
        return;
      }
      _snack('Recurso eliminado.', ok: true);
      await _cargar();
    } catch (_) {
      _snack('No se pudo eliminar. Revisa tu conexión.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Identidad CESSUM'),
      ),
      floatingActionButton: widget.admin
          ? FloatingActionButton.extended(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              onPressed: _guardando ? null : _subir,
              icon: const Icon(Icons.upload),
              label: const Text('Subir'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!),
                  const SizedBox(height: 10),
                  ElevatedButton(
                      style:
                          ElevatedButton.styleFrom(backgroundColor: cessumRed),
                      onPressed: _cargar,
                      child: const Text('Reintentar',
                          style: TextStyle(color: Colors.white))),
                ]))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                    children: _contenido(),
                  ),
                ),
    );
  }

  List<Widget> _contenido() {
    final w = <Widget>[];
    w.add(Text(
      'Descarga los logos oficiales en alta calidad y el manual de identidad '
      'de CESSUM. Úsalos respetando los lineamientos de la marca.',
      style: TextStyle(fontSize: 13, color: cessumMuted(context)),
    ));
    w.add(const SizedBox(height: 14));

    // Manual
    w.add(_titulo('Manual de identidad'));
    if (_manuales.isEmpty) {
      w.add(_vacio('Aún no se ha subido el manual.'));
    } else {
      for (final m in _manuales) {
        w.add(Card(
          color: Theme.of(context).cardColor,
          child: ListTile(
            leading: const Icon(Icons.menu_book, color: cessumRed, size: 30),
            title: Text('${m['titulo']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Manual de identidad · PDF'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.download, color: cessumRed),
                onPressed: '${m['url'] ?? ''}'.isEmpty
                    ? null
                    : () => Helpers.abrirUrlExterna('${m['url']}', context),
              ),
              if (widget.admin)
                IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () => _eliminar(m),
                ),
            ]),
          ),
        ));
      }
    }

    w.add(const SizedBox(height: 18));
    // Logos
    w.add(_titulo('Logos en alta calidad'));
    if (_logos.isEmpty) {
      w.add(_vacio('Aún no se han subido logos.'));
    } else {
      w.add(Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _logos.map(_logoCard).toList(),
      ));
    }
    return w;
  }

  Widget _logoCard(Map<String, dynamic> it) {
    final url = '${it['url'] ?? ''}';
    return SizedBox(
      width: 160,
      child: Card(
        color: Theme.of(context).cardColor,
        child: Column(
          children: [
            Container(
              height: 110,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F1E8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: url.isEmpty
                  ? Icon(Icons.image, color: cessumFaint(context), size: 40)
                  : ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Image.network(
                        _previewUrl(url),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.image_outlined,
                            color: cessumFaint(context),
                            size: 40),
                        loadingBuilder: (c, child, prog) => prog == null
                            ? child
                            : const Center(
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('${it['titulo']}',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Descargar',
                      style: TextStyle(fontSize: 12)),
                  onPressed: url.isEmpty
                      ? null
                      : () => Helpers.abrirUrlExterna(url, context),
                ),
                if (widget.admin)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.redAccent),
                    onPressed: () => _eliminar(it),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: cessumRed)),
      );

  Widget _vacio(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t, style: TextStyle(color: cessumMuted(context))),
      );
}

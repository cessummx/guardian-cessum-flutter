import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Herramienta para estudiantes: banco de formatos descargables (APA, oficios,
/// constancias, titulación…). Si admin = true, permite gestionarlos.
class FormatosScreen extends StatefulWidget {
  final bool admin;
  const FormatosScreen({super.key, this.admin = false});

  @override
  State<FormatosScreen> createState() => _FormatosScreenState();
}

class _FormatosScreenState extends State<FormatosScreen> {
  // (ago-24) El catálogo era de cinco categorías pensadas para el alumno.
  // Aquí también viven las plantillas que usa el docente —tareas, rúbricas,
  // planeación— y no tenían dónde caer: acababan todas en "Otros", que es
  // como no clasificarlas.
  static const List<String> _categorias = [
    'Plantillas de tareas',
    'Rúbricas y evaluación',
    'Planeación docente',
    'APA y citación',
    'Tesis y titulación',
    'Oficios y solicitudes',
    'Constancias',
    'Reglamentos y normativa',
    'Otros',
  ];

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
        .timeout(const Duration(seconds: 45));
    return jsonDecode(r.body) as Map<String, dynamic>;
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
      setState(() {
        _items = ((data['formatos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((it) {
              final c = '${it['categoria'] ?? ''}'.toLowerCase();
              return c != 'logo' &&
                  c != 'manual de identidad' &&
                  !c.contains('identidad');
            })
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar los formatos.';
      });
    }
  }

  void _snack(String t, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), backgroundColor: ok ? Colors.green : cessumRed));
  }

  Map<String, List<Map<String, dynamic>>> get _porCategoria {
    final m = <String, List<Map<String, dynamic>>>{};
    for (final it in _items) {
      final c = '${it['categoria'] ?? 'Otros'}';
      m.putIfAbsent(c, () => []).add(it);
    }
    return m;
  }

  // -------- Admin: crear/editar --------
  Future<void> _editar([Map<String, dynamic>? item]) async {
    final tituloCtrl = TextEditingController(text: '${item?['titulo'] ?? ''}');
    final descCtrl = TextEditingController(text: '${item?['descripcion'] ?? ''}');
    final urlCtrl = TextEditingController(text: '${item?['url'] ?? ''}');
    final ordenCtrl =
        TextEditingController(text: '${item?['orden'] ?? _items.length + 1}');
    String categoria = '${item?['categoria'] ?? 'Plantillas de tareas'}';
    if (!_categorias.contains(categoria)) categoria = 'Otros';
    bool activo = item == null ? true : (item['activo'] == true);
    // (ago-24) EL ARCHIVO SE SUBE, NO SE PEGA UNA URL.
    // El backend acepta base64 y lo guarda en Drive desde siempre; la
    // pantalla solo ofrecía un campo de URL, así que para subir una plantilla
    // había que subirla a Drive por fuera, compartirla, copiar el enlace y
    // pegarlo. Cuatro pasos manuales para lo que el sistema ya sabía hacer.
    String? archivoNombre;
    String? archivoB64;
    String? archivoMime;
    int archivoBytes = 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(item == null ? 'Nuevo formato' : 'Editar formato'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Título', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: categoria,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Categoría', border: OutlineInputBorder()),
                  items: _categorias
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setS(() => categoria = v ?? categoria),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                // Subir el archivo es el camino normal; la URL queda como
                // alternativa para lo que ya vive en Drive.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ARCHIVO',
                          style: TextStyle(
                              fontSize: 11,
                              letterSpacing: .5,
                              fontWeight: FontWeight.w800,
                              color: Colors.black45)),
                      const SizedBox(height: 6),
                      if (archivoNombre != null) ...[
                        Row(children: [
                          const Icon(Icons.description,
                              size: 18, color: cessumGold),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(archivoNombre!,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    '${(archivoBytes / 1024).round()} KB · se '
                                    'guarda en Drive al pulsar Guardar',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.black54)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setS(() {
                              archivoNombre = null;
                              archivoB64 = null;
                              archivoMime = null;
                              archivoBytes = 0;
                            }),
                          ),
                        ]),
                      ] else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: cessumGold,
                              side: const BorderSide(color: cessumGold),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                            onPressed: () {
                              final input = html.FileUploadInputElement()
                                ..accept =
                                    '.pdf,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.odt';
                              input.click();
                              input.onChange.listen((_) {
                                final f = input.files?.first;
                                if (f == null) return;
                                final reader = html.FileReader();
                                reader.readAsDataUrl(f);
                                reader.onLoadEnd.listen((_) {
                                  final res = reader.result as String? ?? '';
                                  final coma = res.indexOf(',');
                                  if (coma < 0) return;
                                  setS(() {
                                    archivoNombre = f.name;
                                    archivoB64 = res.substring(coma + 1);
                                    archivoMime = f.type.isNotEmpty
                                        ? f.type
                                        : 'application/octet-stream';
                                    archivoBytes = f.size;
                                    urlCtrl.clear();
                                  });
                                });
                              });
                            },
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: const Text('Subir archivo desde mi equipo'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: urlCtrl,
                        enabled: archivoNombre == null,
                        decoration: const InputDecoration(
                            labelText: 'o pega una URL de Drive',
                            helperText:
                                'Solo si el archivo ya está en Drive y '
                                'compartido con los alumnos.',
                            helperMaxLines: 2,
                            isDense: true,
                            border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: ordenCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Orden',
                          isDense: true,
                          border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(children: [
                    const Text('Activo'),
                    Switch(
                      activeThumbColor: cessumRed,
                      value: activo,
                      onChanged: (v) => setS(() => activo = v),
                    ),
                  ]),
                ]),
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
                // Un formato sin archivo ni URL es una ficha vacía: el alumno
                // la ve en la lista y al tocarla no pasa nada.
                if (tituloCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Falta el título.')));
                  return;
                }
                if (archivoB64 == null && urlCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text(
                          'Sube el archivo o pega una URL: sin uno de los '
                          'dos, el formato no se puede descargar.')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child:
                  const Text('Guardar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      final payload = <String, dynamic>{
        'accion': 'formato_guardar',
        'titulo': tituloCtrl.text.trim(),
        'categoria': categoria,
        'descripcion': descCtrl.text.trim(),
        'url': urlCtrl.text.trim(),
        'orden': int.tryParse(ordenCtrl.text.trim()) ?? 0,
        'activo': activo,
      };
      if (archivoB64 != null) {
        payload['base64'] = archivoB64;
        payload['mime'] = archivoMime;
        payload['nombreArchivo'] = archivoNombre;
      }
      if (item != null) payload['id'] = item['id'];
      final data = await _post(payload);
      if (data['ok'] == true) {
        await _cargar();
      } else {
        _snack('${data['error'] ?? 'No se pudo guardar.'}');
      }
    } catch (e) {
      _snack('Error de conexión.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _eliminar(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar formato'),
        content: Text('¿Eliminar "${item['titulo']}"?'),
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
      await _post({'accion': 'formato_eliminar', 'id': item['id']});
      await _cargar();
    } catch (_) {
      _snack('No se pudo eliminar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _porCategoria;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text(widget.admin ? 'Formatos (gestión)' : 'Banco de formatos'),
      ),
      floatingActionButton: widget.admin
          ? FloatingActionButton.extended(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              onPressed: _guardando ? null : () => _editar(),
              icon: const Icon(Icons.add),
              label: const Text('Formato'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        style:
                            ElevatedButton.styleFrom(backgroundColor: cessumRed),
                        onPressed: _cargar,
                        child: const Text('Reintentar',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          widget.admin
                              ? 'No hay formatos. Toca "Formato" para agregar el primero.'
                              : 'Aún no hay formatos disponibles. Vuelve pronto.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                        children: grupos.entries
                            .map((e) => _seccion(e.key, e.value))
                            .toList(),
                      ),
                    ),
    );
  }

  Widget _seccion(String categoria, List<Map<String, dynamic>> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Text(categoria,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: cessumRed)),
        ),
        ...items.map(_tile),
      ],
    );
  }

  Widget _tile(Map<String, dynamic> it) {
    final url = '${it['url'] ?? ''}';
    final activo = it['activo'] == true;
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: const Icon(Icons.description, color: cessumGold),
        title: Text('${it['titulo']}',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: (widget.admin && !activo) ? Colors.grey : Colors.black87)),
        subtitle: Text(
          [
            if ('${it['descripcion'] ?? ''}'.isNotEmpty) '${it['descripcion']}',
            if (widget.admin && !activo) '(inactivo)',
            if (url.isEmpty) 'Sin archivo aún',
          ].join('  ·  '),
          style: const TextStyle(fontSize: 12.5),
        ),
        trailing: widget.admin
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: cessumRed),
                  onPressed: () => _editar(it),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.redAccent),
                  onPressed: () => _eliminar(it),
                ),
              ])
            : (url.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.download, color: cessumRed),
                    onPressed: () => Helpers.abrirUrlExterna(url, context),
                  )
                : null),
        onTap: widget.admin
            ? () => _editar(it)
            : (url.isNotEmpty
                ? () => Helpers.abrirUrlExterna(url, context)
                : null),
      ),
    );
  }
}

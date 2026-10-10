// =====================================================================
//  CORREOS DE MARKETING (4-oct-2026) · para ASPIRANTES y prospectos.
//  (Para alumnos están Avisos y Circulares.)
//  1. Plantilla HTML con campos {{campo}}; si a una persona le falta un
//     dato, se omite. Para quitar un trozo entero: [[si:campo]] … [[/si:campo]].
//  2. Destinatarios: un archivo con la plantilla de datos (.xlsx o .csv)
//     o los prospectos que se registraron en cessum.mx (sin inscritos).
//  3. Revisar (no envía) · Vista previa · Enviarme una prueba · Enviar.
//  El Guardián quita inválidos, repetidos, bajas y a quien ya recibió la
//  misma campaña, así que un envío cortado se puede repetir sin duplicar.
//  Rutas: marketing_plantillas (GET) · marketing_destinatarios,
//  marketing_enviar, marketing_plantilla_guardar (POST).
// =====================================================================
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const Color _verde = Color(0xFF1E7B34);
const Color _ambar = Color(0xFFB7791F);

const _camposBase = ['nombre_corto', 'nombre', 'apellido', 'nombre_completo', 'programa', 'modalidad', 'ciudad', 'codigo_referido', 'asesor', 'whatsapp_asesor'];

class MarketingCorreosScreen extends StatefulWidget {
  const MarketingCorreosScreen({super.key});
  @override
  State<MarketingCorreosScreen> createState() => _MarketingCorreosScreenState();
}

class _MarketingCorreosScreenState extends State<MarketingCorreosScreen> {
  final _asunto = TextEditingController();
  final _html = TextEditingController();
  final _campana = TextEditingController();
  final _programa = TextEditingController();
  List<Map<String, dynamic>> _plantillas = [];
  String _plantillaSel = '';
  bool _cargandoPlantillas = true;
  String _errorPlantillas = '';

  String _fuente = 'archivo';     // archivo · prospectos
  bool _incluirInscritos = false;
  String _archivoNombre = '';
  String _archivoB64 = '';

  bool _trabajando = false;
  Map<String, dynamic>? _revision;
  String _mensaje = '';

  @override
  void initState() {
    super.initState();
    _cargarPlantillas();
  }

  @override
  void dispose() {
    _asunto.dispose(); _html.dispose(); _campana.dispose(); _programa.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  Future<void> _cargarPlantillas() async {
    setState(() { _cargandoPlantillas = true; _errorPlantillas = ''; });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'marketing_plantillas', 'actor': await _actor()});
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] != true) { setState(() { _cargandoPlantillas = false; _errorPlantillas = '${d['error'] ?? 'No se pudieron cargar las plantillas.'}'; }); return; }
      final lista = ((d['plantillas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _cargandoPlantillas = false;
        _plantillas = lista;
        if (lista.isNotEmpty && _plantillaSel.isEmpty) _usarPlantilla(lista.first);
      });
    } catch (_) {
      if (mounted) setState(() { _cargandoPlantillas = false; _errorPlantillas = 'No se pudieron cargar las plantillas (conexión). Intenta de nuevo.'; });
    }
  }

  void _usarPlantilla(Map<String, dynamic> p) {
    _plantillaSel = '${p['nombre']}';
    _asunto.text = '${p['asunto'] ?? ''}';
    _html.text = '${p['html'] ?? ''}';
    final hoy = DateTime.now();
    _campana.text = '${p['nombre']} · ${hoy.day.toString().padLeft(2, '0')}/${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';
    _revision = null;
  }

  Map<String, dynamic> _cuerpo(String accion) => {
        'accion': accion,
        'asunto': _asunto.text,
        'html': _html.text,
        'campana': _campana.text.trim(),
        'fuente': _fuente,
        if (_fuente == 'archivo') 'archivo': _archivoB64,
        if (_fuente == 'archivo') 'archivoNombre': _archivoNombre,
        if (_fuente == 'prospectos') 'programa': _programa.text.trim(),
        if (_fuente == 'prospectos' && _incluirInscritos) 'incluirInscritos': '1',
      };

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int segundos = 120}) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode({...body, 'actor': await _actor()}))
        .timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _aviso(String t, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: error ? cessumRed : null, content: Text(t)));
  }

  Future<void> _elegirArchivo() async {
    final input = html.FileUploadInputElement()..accept = '.xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv';
    input.click();
    await input.onChange.first;
    if (input.files == null || input.files!.isEmpty) return;
    final f = input.files!.first;
    if (f.size > 6 * 1024 * 1024) { _aviso('El archivo pesa más de 6 MB.', error: true); return; }
    final reader = html.FileReader();
    reader.readAsDataUrl(f);
    await reader.onLoad.first;
    final dataUrl = reader.result as String;
    final coma = dataUrl.indexOf(',');
    if (coma < 0) return;
    setState(() { _archivoNombre = f.name; _archivoB64 = dataUrl.substring(coma + 1); _revision = null; });
  }

  void _descargarPlantillaDatos() {
    const csv = 'correo,nombre,apellido,programa,modalidad,ciudad,codigo_referido,asesor,whatsapp_asesor\n'
        'ana.ruiz@gmail.com,Ana Lucía,Ruiz Soto,Maestría en Educación,En línea,Navojoa,CESAA1502,Janeth,6421234567\n'
        'luis.mora@hotmail.com,Luis,,Maestría en Educación,,,,,\n';
    final blob = html.Blob(['\uFEFF$csv'], 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)..download = 'plantilla_datos_marketing.csv'..click();
    html.Url.revokeObjectUrl(url);
  }

  bool get _listo => _asunto.text.trim().isNotEmpty && _html.text.trim().isNotEmpty && (_fuente == 'prospectos' || _archivoB64.isNotEmpty);

  Future<void> _revisar() async {
    if (!_listo) { _aviso('Falta el asunto, la plantilla o el archivo de destinatarios.', error: true); return; }
    setState(() { _trabajando = true; _mensaje = ''; });
    try {
      final d = await _post(_cuerpo('marketing_destinatarios'), segundos: 180);
      if (!mounted) return;
      setState(() { _trabajando = false; if (d['ok'] == true) { _revision = d; } else { _revision = null; _mensaje = '${d['error'] ?? 'No se pudo revisar.'}'; } });
    } catch (_) {
      if (mounted) setState(() { _trabajando = false; _mensaje = 'No se pudo revisar (conexión o tiempo). Intenta de nuevo.'; });
    }
  }

  void _vistaPrevia() {
    final vp = '${_revision?['vistaPrevia'] ?? ''}';
    if (vp.isEmpty) { _aviso('Primero pulsa «Revisar destinatarios».'); return; }
    final blob = html.Blob([vp], 'text/html;charset=utf-8');
    html.window.open(html.Url.createObjectUrlFromBlob(blob), '_blank');
  }

  Future<void> _pruebaAMi() async {
    if (!_listo) { _aviso('Falta el asunto, la plantilla o los destinatarios.', error: true); return; }
    setState(() => _trabajando = true);
    try {
      final d = await _post({..._cuerpo('marketing_enviar'), 'aMi': '1'});
      if (!mounted) return;
      setState(() => _trabajando = false);
      _aviso(d['ok'] == true ? 'Prueba enviada a ${d['enviadoA']}, con los datos de ${d['conDatosDe']}.' : '${d['error']}', error: d['ok'] != true);
    } catch (_) {
      if (mounted) setState(() => _trabajando = false);
      _aviso('No se pudo enviar la prueba.', error: true);
    }
  }

  Future<void> _enviar() async {
    final r = _revision;
    if (r == null) { _aviso('Primero revisa los destinatarios.'); return; }
    final total = (r['total'] as num?)?.toInt() ?? 0;
    if (total == 0) { _aviso('No hay a quién enviar.'); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar envío'),
        content: Text('Se enviará el correo a $total persona(s) — aspirantes y prospectos, no alumnos.\n\n'
            'Asunto (ejemplo): «${r['asuntoEjemplo']}»\n'
            'Campaña: «${_campana.text.trim()}»\n\n'
            'Sale desde contacto@cessum.mx y las respuestas llegan ahí. Quien ya la haya recibido no la vuelve a recibir.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white), onPressed: () => Navigator.pop(ctx, true), child: Text('Enviar a $total')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _trabajando = true; _mensaje = ''; });
    try {
      final d = await _post({..._cuerpo('marketing_enviar'), 'confirmar': '1'}, segundos: 290);
      if (!mounted) return;
      setState(() { _trabajando = false; _mensaje = d['ok'] == true ? '${d['nota']}' : '${d['error']}'; _revision = null; });
    } catch (_) {
      if (mounted) setState(() { _trabajando = false; _mensaje = 'La conexión se cortó; el envío pudo haber avanzado. Pulsa «Revisar destinatarios»: quien ya lo recibió ya no aparece.'; });
    }
  }

  Future<void> _guardarPlantilla() async {
    final nombre = TextEditingController(text: _plantillaSel);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar plantilla'),
        content: TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre de la plantilla')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true || nombre.text.trim().isEmpty) return;
    try {
      final d = await _post({'accion': 'marketing_plantilla_guardar', 'nombre': nombre.text.trim(), 'asunto': _asunto.text, 'html': _html.text});
      _aviso(d['ok'] == true ? 'Plantilla guardada.' : '${d['error']}', error: d['ok'] != true);
      if (d['ok'] == true) { _plantillaSel = nombre.text.trim(); _cargarPlantillas(); }
    } catch (_) {
      _aviso('No se pudo guardar.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(backgroundColor: cessumRed, foregroundColor: Colors.white, title: const Text('Correos de marketing')),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 40), children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFBF6EE), borderRadius: BorderRadius.circular(10), border: Border.all(color: _ambar.withValues(alpha: 0.5))),
            child: const Text('Para aspirantes y prospectos. Para alumnos usa Avisos o Circulares.', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(height: 12),
          _paso1(),
          const SizedBox(height: 12),
          _paso2(),
          const SizedBox(height: 12),
          _paso3(),
        ]),
        if (_trabajando) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator(color: cessumRed))),
      ]),
    );
  }

  Widget _tarjeta(String titulo, List<Widget> hijos) => Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: cessumRed)),
            const SizedBox(height: 10),
            ...hijos,
          ]),
        ),
      );

  Widget _paso1() {
    return _tarjeta('1. Plantilla del correo', [
      if (_cargandoPlantillas) const LinearProgressIndicator(color: cessumRed),
      if (_errorPlantillas.isNotEmpty) Text(_errorPlantillas, style: const TextStyle(color: cessumRed)),
      if (_plantillas.isNotEmpty)
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: _plantillas.any((p) => '${p['nombre']}' == _plantillaSel) ? _plantillaSel : null,
          decoration: const InputDecoration(labelText: 'Plantilla', isDense: true),
          items: [for (final p in _plantillas) DropdownMenuItem(value: '${p['nombre']}', child: Text('${p['nombre']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) { final p = _plantillas.firstWhere((x) => '${x['nombre']}' == v); setState(() => _usarPlantilla(p)); },
        ),
      const SizedBox(height: 10),
      TextField(controller: _asunto, decoration: const InputDecoration(labelText: 'Asunto (admite campos, p. ej. {{nombre_corto}})', isDense: true), onChanged: (_) => setState(() => _revision = null)),
      const SizedBox(height: 10),
      TextField(controller: _campana, decoration: const InputDecoration(labelText: 'Nombre de la campaña (evita enviar dos veces a la misma persona)', isDense: true)),
      const SizedBox(height: 10),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Editar el HTML', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: Text('${_html.text.length} caracteres', style: const TextStyle(fontSize: 11.5)),
        children: [
          TextField(
            controller: _html, maxLines: 14, minLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Pega aquí el HTML del correo'),
            onChanged: (_) => setState(() => _revision = null),
          ),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _guardarPlantilla, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Guardar como plantilla'))),
        ],
      ),
      const SizedBox(height: 4),
      Text('Campos (toca para copiar). Si a alguien le falta un dato, el campo se omite. Para quitar un trozo completo cuando falte: [[si:campo]] … [[/si:campo]].',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.4)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in {..._camposBase, ...(((_revision?['campos'] as List?) ?? []).map((e) => '$e'))})
          ActionChip(
            label: Text('{{$c}}', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
            onPressed: () { Clipboard.setData(ClipboardData(text: '{{$c}}')); _aviso('Copiado: {{$c}}'); },
          ),
      ]),
    ]);
  }

  Widget _paso2() {
    return _tarjeta('2. Destinatarios', [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'archivo', label: Text('Subir archivo'), icon: Icon(Icons.upload_file, size: 16)),
          ButtonSegment(value: 'prospectos', label: Text('Prospectos del sitio'), icon: Icon(Icons.public, size: 16)),
        ],
        selected: {_fuente},
        onSelectionChanged: (s) => setState(() { _fuente = s.first; _revision = null; }),
      ),
      const SizedBox(height: 10),
      if (_fuente == 'archivo') ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _elegirArchivo, icon: const Icon(Icons.attach_file), label: Text(_archivoNombre.isEmpty ? 'Elegir archivo (.xlsx o .csv)' : _archivoNombre)),
          TextButton.icon(onPressed: _descargarPlantillaDatos, icon: const Icon(Icons.download, size: 18), label: const Text('Descargar plantilla de datos')),
        ]),
        const SizedBox(height: 6),
        Text('Una fila por persona. Solo «correo» es obligatorio; las demás columnas son opcionales y puedes agregar otras: cada columna se vuelve un campo {{nombre_de_la_columna}}.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.4)),
      ],
      if (_fuente == 'prospectos') ...[
        Text('Personas que se registraron en cessum.mx (preinscripción y páginas de programas). No incluye el bot de WhatsApp, que no pide correo.',
            style: TextStyle(fontSize: 12, color: cessumMuted(context), height: 1.4)),
        const SizedBox(height: 8),
        TextField(controller: _programa, decoration: const InputDecoration(labelText: 'Solo de un programa (opcional, p. ej. «Educación»)', isDense: true), onChanged: (_) => setState(() => _revision = null)),
        SwitchListTile(
          dense: true, contentPadding: EdgeInsets.zero, value: _incluirInscritos,
          title: const Text('Incluir a quienes ya se inscribieron', style: TextStyle(fontSize: 13)),
          onChanged: (v) => setState(() { _incluirInscritos = v; _revision = null; }),
        ),
      ],
      const SizedBox(height: 8),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: cessumGold, foregroundColor: Colors.white),
        onPressed: _trabajando ? null : _revisar,
        icon: const Icon(Icons.fact_check_outlined), label: const Text('Revisar destinatarios (no envía nada)'),
      ),
      if (_mensaje.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_mensaje, style: const TextStyle(fontWeight: FontWeight.w700))),
      if (_revision != null) _resumenRevision(_revision!),
    ]);
  }

  Widget _resumenRevision(Map<String, dynamic> r) {
    final muestra = ((r['muestra'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    Widget fila(String t, dynamic n, Color c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [Expanded(child: Text(t, style: const TextStyle(fontSize: 13))), Text('$n', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c))]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _verde.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _verde.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Se enviaría a ${r['total']} persona(s)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _verde)),
        const SizedBox(height: 6),
        fila('Filas leídas', r['totalFilas'], Colors.black87),
        fila('Correos inválidos o vacíos (se omiten)', r['invalidos'], _ambar),
        fila('Repetidos (se envía una sola vez)', r['repetidos'], _ambar),
        fila('Pidieron BAJA (se omiten)', r['enBaja'], _ambar),
        fila('Ya recibieron esta campaña (se omiten)', r['yaRecibieron'], _ambar),
        fila('Envíos que quedan hoy en la cuenta', r['cuotaDiaria'], Colors.black54),
        if (((r['ejemplosInvalidos'] as List?) ?? []).isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Inválidos: ${(r['ejemplosInvalidos'] as List).join(', ')}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context)))),
        const SizedBox(height: 8),
        Text('Asunto con los datos de la primera persona: «${r['asuntoEjemplo']}»', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic)),
        const SizedBox(height: 6),
        for (final m in muestra)
          Text('• ${m['correo']}${'${m['nombre']}'.isNotEmpty ? ' — ${m['nombre']}' : ''}${'${m['programa']}'.isNotEmpty ? ' · ${m['programa']}' : ''}', style: const TextStyle(fontSize: 12)),
        if ((r['total'] as num? ?? 0) > muestra.length) Text('… y ${(r['total'] as num) - muestra.length} más', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
      ]),
    );
  }

  Widget _paso3() {
    final total = (_revision?['total'] as num?)?.toInt() ?? 0;
    return _tarjeta('3. Probar y enviar', [
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _revision == null ? null : _vistaPrevia, icon: const Icon(Icons.visibility_outlined), label: const Text('Ver vista previa')),
        OutlinedButton.icon(onPressed: _trabajando || !_listo ? null : _pruebaAMi, icon: const Icon(Icons.send_to_mobile_outlined), label: const Text('Enviarme una prueba')),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _trabajando || _revision == null || total == 0 ? null : _enviar,
          icon: const Icon(Icons.send),
          label: Text(_revision == null ? 'Revisa los destinatarios para habilitar el envío' : 'Enviar a $total persona(s)'),
        ),
      ),
      const SizedBox(height: 6),
      Text('Se envía desde contacto@cessum.mx. Cada correo lleva al pie la opción de darse de baja respondiendo BAJA.',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
    ]);
  }
}

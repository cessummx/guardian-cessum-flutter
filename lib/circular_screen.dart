import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

/// Aviso masivo (circular): envía un correo con branding CESSUM a todos los
/// alumnos de una generación, un programa, o a todos los activos.
class CircularScreen extends StatefulWidget {
  const CircularScreen({super.key});

  @override
  State<CircularScreen> createState() => _CircularScreenState();
}

class _CircularScreenState extends State<CircularScreen> {
  final _asunto = TextEditingController();
  final _cuerpo = TextEditingController();

  /// (ago-21) Modo HTML: el cuerpo se manda tal cual, sin envolver cada
  /// renglón en un párrafo. Es lo que permite pegar una circular ya diseñada
  /// para correo.
  bool _esHtml = false;
  bool _previaCargando = false;
  List<Map<String, dynamic>> _generaciones = [];
  List<Map<String, dynamic>> _historial = [];
  String? _programa; // null = todos
  String? _generacion; // null = todas
  // (14-sep) FILTROS QUE FALTABAN. Con solo programa y generación, para
  // avisarle a un grupo o a quienes deben había que mandársela a los 638 y
  // que cada quien viera si le tocaba.
  String? _grupo;
  String? _modalidad;
  String _adeudo = ''; // '', 'con', 'sin'
  String _vigencia = ''; // '', 'vigentes', 'egresados'
  bool _soloInstitucional = false;
  List<String> _opGrupos = [];
  List<String> _opModalidades = [];
  // El alcance deja de ser una suma local: lo cuenta el Guardián con los
  // mismos filtros con los que va a enviar. Antes decía 638 y salían 606.
  int? _alcanceReal;
  bool _contando = false;
  bool _cargando = true;
  bool _enviando = false;

  // (10-sep) ESTADO DE LA COLA, A LA VISTA.
  // Nace del incidente de hoy: una circular a 637 alumnos salió hasta seis
  // veces por persona y para pararla hubo que ir a la pantalla de
  // activadores de Apps Script. Quien manda una circular tiene que poder
  // ver cómo va y detenerla desde aquí, sin salir de la app.
  List<Map<String, dynamic>> _cola = [];
  bool _colaCargando = false;
  Timer? _tickCola;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarCola();
    // Cada 20 s mientras haya algo en curso: una circular grande tarda
    // minutos y sin refresco la barra parecería congelada.
    _tickCola = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _cola.isNotEmpty) _cargarCola();
    });
  }

  Future<void> _cargarCola() async {
    if (_colaCargando) return;
    _colaCargando = true;
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=circular_cola_estado'
              '&z=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _cola = ((data['trabajos'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      // Si falla, se deja lo último conocido: mejor un dato viejo que
      // borrar la barra y hacer creer que ya terminó.
    } finally {
      _colaCargando = false;
    }
  }

  Future<void> _detenerCola(int fila, String asunto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Detener este envío'),
        content: Text(
          'Se cancela «$asunto».\n\n'
          'Los correos que ya salieron NO se pueden recoger; lo que se detiene '
          'es lo que falta. Esta acción no se deshace.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir enviando')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Detener'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // (14-sep) FALTABA EL ACTOR, Y POR ESO «DETENER» NO DETENÍA.
      // La ruta exige rol de mando; sin actor ni clave respondía «Solo
      // Rectoría y Vicerrectoría» y el aviso se iba en un snackbar de dos
      // segundos: parecía que el botón no hacía nada.
      final correoActor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=circular_cola_cancelar'
              '&fila=$fila&frase=CANCELAR'
              '&actor=${Uri.encodeComponent(correoActor)}'
              '&z=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Envío detenido.'),
            backgroundColor: Color(0xFF1E8E3E)));
      } else {
        // Un fallo al detener un envío masivo no se avisa con un snackbar
        // que se va solo: hay que verlo.
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No se pudo detener', style: TextStyle(fontSize: 17)),
            content: Text('${data['error'] ?? 'El servidor no explicó por qué.'}',
                style: const TextStyle(fontSize: 13.5, height: 1.45)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido')),
            ],
          ),
        );
      }
      await _cargarCola();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo detener: '
            '${'$e'.replaceAll('Exception: ', '')}'),
      ));
    }
  }

  Widget _barraCola() {
    if (_cola.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Envíos en curso',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: cessumRed)),
        const SizedBox(height: 8),
        ..._cola.map((t) {
          final total = (t['total'] as num?)?.toInt() ?? 0;
          final hechos = (t['enviados'] as num?)?.toInt() ?? 0;
          final restan = (t['restan'] as num?)?.toInt() ?? (total - hechos);
          final pct = total > 0 ? (hechos / total).clamp(0.0, 1.0) : 0.0;
          final fila = (t['fila'] as num?)?.toInt() ?? 0;
          final asunto = '${t['asunto'] ?? ''}';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF7EF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(asunto,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: Colors.black12,
                    valueColor: const AlwaysStoppedAnimation(cessumGold),
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(
                      '$hechos de $total enviados · faltan $restan',
                      style: TextStyle(
                          fontSize: 12, color: cessumMuted(context)),
                    ),
                  ),
                  if (fila > 0)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: cessumRed),
                      icon: const Icon(Icons.stop_circle_outlined, size: 18),
                      label: const Text('Detener'),
                      onPressed: () => _detenerCola(fila, asunto),
                    ),
                ]),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  void dispose() {
    _tickCola?.cancel();
    _asunto.dispose();
    _cuerpo.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final g = await http
          .get(Uri.parse('$guardianUrl?accion=circular_generaciones'))
          .timeout(const Duration(seconds: 45));
      final gd = jsonDecode(g.body) as Map<String, dynamic>;
      final h = await http
          .get(Uri.parse('$guardianUrl?accion=circular_historial'))
          .timeout(const Duration(seconds: 45));
      final hd = jsonDecode(h.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _generaciones = ((gd['generaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _historial = ((hd['circulares'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
      // Primer conteo y llenado de los selectores de grupo y modalidad, que
      // salen del propio padrón: nunca de una lista escrita a mano que se
      // queda vieja en cuanto se abre un grupo nuevo.
      _contarAlcance();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  List<String> get _programas {
    final set = <String>{};
    for (final g in _generaciones) {
      set.add((g['programa'] ?? '').toString());
    }
    final l = set.toList()..sort();
    return l;
  }

  List<String> get _generacionesDe {
    if (_programa == null) return [];
    final l = _generaciones
        .where((g) => (g['programa'] ?? '') == _programa)
        .map((g) => (g['generacion'] ?? '').toString())
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return l;
  }

  int get _alcance {
    if (_programa == null) {
      return _generaciones.fold<int>(
          0, (a, g) => a + ((g['alumnos'] ?? 0) as num).toInt());
    }
    return _generaciones
        .where((g) =>
            (g['programa'] ?? '') == _programa &&
            (_generacion == null || (g['generacion'] ?? '') == _generacion))
        .fold<int>(0, (a, g) => a + ((g['alumnos'] ?? 0) as num).toInt());
  }

  // Los filtros viajan igual a contar, a previsualizar y a enviar: si se
  // arman en tres lugares distintos, tarde o temprano dejan de coincidir.
  Map<String, String> get _filtros => {
        'programa': _programa ?? '',
        'generacion': _generacion ?? '',
        'grupo': _grupo ?? '',
        'modalidad': _modalidad ?? '',
        'conAdeudo': _adeudo == 'con' ? '1' : '',
        'sinAdeudo': _adeudo == 'sin' ? '1' : '',
        'egresados': _vigencia == 'egresados'
            ? '1'
            : _vigencia == 'vigentes'
                ? '0'
                : '',
        'soloCorreoInstitucional': _soloInstitucional ? '1' : '',
      };

  String get _queryFiltros => _filtros.entries
      .where((e) => e.value.isNotEmpty)
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');

  // Cuenta contra el Guardián, con los filtros reales.
  Future<void> _contarAlcance() async {
    setState(() => _contando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=circular_destinatarios'
              '&$_queryFiltros&z=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        final op = (data['opciones'] is Map)
            ? Map<String, dynamic>.from(data['opciones'] as Map)
            : const <String, dynamic>{};
        setState(() {
          _alcanceReal = (data['total'] as num?)?.toInt();
          if (_opGrupos.isEmpty) {
            _opGrupos =
                ((op['grupos'] as List?) ?? []).map((e) => '$e').toList();
          }
          if (_opModalidades.isEmpty) {
            _opModalidades =
                ((op['modalidades'] as List?) ?? []).map((e) => '$e').toList();
          }
        });
      }
    } catch (_) {
      // Sin conteo del servidor se queda el estimado local; no vale la pena
      // interrumpir al usuario por esto.
    } finally {
      if (mounted) setState(() => _contando = false);
    }
  }

  Future<void> _verDestinatarios() async {
    try {
      final uri = Uri.parse('$guardianUrl?accion=circular_destinatarios'
          '&$_queryFiltros');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo cargar: ${data['error'] ?? 'error'}')));
        return;
      }
      final lista = ((data['destinatarios'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Destinatarios (${lista.length})',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: lista.isEmpty
                ? const Text('No hay destinatarios para ese filtro.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: lista.length,
                    itemBuilder: (ctx, i) {
                      final d = lista[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline,
                            size: 18, color: cessumRed),
                        title: Text((d['nombre'] ?? '').toString(),
                            style: const TextStyle(fontSize: 12.5)),
                        subtitle: Text(
                          '${d['correo'] ?? ''} · ${d['programa'] ?? ''} ${d['generacion'] ?? ''}',
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo conectar con el sistema.')));
    }
  }

  /// Abre el correo tal como lo verán los alumnos, con el marco CESSUM.
  ///
  /// Se abre en pestaña aparte y no en un diálogo pequeño: un correo se ve
  /// distinto a 300 px de ancho que a 640, y la idea es ver lo que va a
  /// llegar, no una miniatura.
  Future<void> _previsualizar() async {
    final cuerpo = _cuerpo.text.trim();
    if (cuerpo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escribe el mensaje antes de previsualizar.')));
      return;
    }
    final asunto = _asunto.text.trim();

    /* (4-sep) LA PREVIA YA NO SE ARMA AQUÍ.
       ---------------------------------------------------------------
       Esta pantalla tenía una COPIA de la plantilla escrita a mano. Al
       mejorar la del servidor, la copia se quedó atrás y la previa mostraba
       algo que NO era lo que se iba a enviar: todo en un bloque, con las
       marcas sin procesar («!!», «##», «|»), las etiquetas {{codigo}} en
       crudo y los acentos rotos. Una vista previa que miente es peor que no
       tenerla, porque se aprueba un correo distinto del que sale.
       Ahora se le pide al Guardián el HTML exacto, ya personalizado con los
       datos de un destinatario real del filtro. */
    setState(() => _previaCargando = true);
    try {
      final correo = await SessionStore.realEmail();
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'circular_preview',
              'asunto': asunto,
              'cuerpo': cuerpo,
              'esHtml': _esHtml ? '1' : '',
              if (_adjuntos.isNotEmpty) 'adjuntos': _adjuntos.map((a) => a['id']).toList(),
              ..._filtros,
              'actor': correo ?? '',
            }),
          )
          .timeout(const Duration(seconds: 45));
      if (!mounted) return;
      setState(() => _previaCargando = false);
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('${j['error'] ?? 'No se pudo generar la vista previa.'}')));
        return;
      }
      final doc = '${j['html'] ?? ''}';
      // El blob necesita el tipo con charset, si no el navegador lo lee como
      // Latin-1 y los acentos salen rotos aunque el HTML esté bien.
      final blob = html.Blob([doc], 'text/html;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
      final quien = '${j['muestraDe'] ?? ''}';
      final n = j['destinatarios'];
      if (quien.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Así se verá para $quien'
                '${n != null ? ' · $n destinatario(s) en este filtro' : ''}')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _previaCargando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo abrir la vista previa: $e')));
    }
  }

  // (25-sep) ADJUNTOS. Cada archivo se sube al Guardián (Drive) al elegirlo
  // y la circular viaja con sus ids: el primer lote los adjunta al momento y
  // la cola de segundo plano los adjunta en los demás correos.
  final List<Map<String, dynamic>> _adjuntos = [];
  bool _subiendoAdjunto = false;
  static const int _kMaxArchivo = 10 * 1024 * 1024;
  static const int _kMaxTotal = 20 * 1024 * 1024;

  int get _bytesAdjuntos => _adjuntos.fold(0, (a, x) => a + ((x['bytes'] ?? 0) as num).toInt());

  String _peso(num b) => b >= 1024 * 1024 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).round()} KB';

  Future<void> _adjuntar() async {
    final input = html.FileUploadInputElement()
      ..accept = 'application/pdf,image/*,.doc,.docx,.xls,.xlsx,.ppt,.pptx'
      ..multiple = true;
    input.click();
    await input.onChange.first;
    final files = input.files;
    if (files == null || files.isEmpty) return;
    for (final file in files) {
      if (file.size > _kMaxArchivo) {
        _avisoAdj('«${file.name}» pesa más de 10 MB; no se adjuntó.', false);
        continue;
      }
      if (_bytesAdjuntos + file.size > _kMaxTotal) {
        _avisoAdj('Con «${file.name}» la circular pasaría de 20 MB; no se adjuntó.', false);
        continue;
      }
      final reader = html.FileReader();
      reader.readAsDataUrl(file);
      await reader.onLoad.first;
      final dataUrl = reader.result as String;
      final coma = dataUrl.indexOf(',');
      if (coma < 0) continue;
      if (!mounted) return;
      setState(() => _subiendoAdjunto = true);
      try {
        final correo = await SessionStore.realEmail();
        final r = await http
            .post(Uri.parse(guardianUrl),
                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                body: jsonEncode({
                  'accion': 'circular_adjunto_subir',
                  'nombre': file.name,
                  'mime': file.type.isNotEmpty ? file.type : 'application/octet-stream',
                  'base64': dataUrl.substring(coma + 1),
                  'actor': correo ?? '',
                }))
            .timeout(const Duration(seconds: 180));
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo subir.');
        if (!mounted) return;
        setState(() => _adjuntos.add({'id': d['id'], 'nombre': d['nombre'] ?? file.name, 'bytes': d['bytes'] ?? file.size}));
      } catch (e) {
        _avisoAdj('No se pudo subir «${file.name}»: $e'.replaceAll('Exception: ', ''), false);
      } finally {
        if (mounted) setState(() => _subiendoAdjunto = false);
      }
    }
  }

  void _avisoAdj(String t, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: ok ? Colors.green : Colors.redAccent, content: Text(t)));
  }

  Widget _seccionAdjuntos() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.attach_file, size: 18, color: cessumRed),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Archivos adjuntos (opcional)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            onPressed: _subiendoAdjunto || _enviando ? null : _adjuntar,
            icon: _subiendoAdjunto
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add, size: 18),
            label: Text(_subiendoAdjunto ? 'Subiendo…' : 'Adjuntar archivo'),
          ),
        ]),
        if (_adjuntos.isEmpty)
          Text('PDF, imágenes u Office. Hasta 10 MB por archivo y 20 MB en total.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context)))
        else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in _adjuntos)
                InputChip(
                  avatar: const Icon(Icons.insert_drive_file, size: 16),
                  label: Text('${a['nombre']} · ${_peso((a['bytes'] ?? 0) as num)}',
                      style: const TextStyle(fontSize: 12)),
                  onDeleted: _enviando ? null : () => setState(() => _adjuntos.remove(a)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Total: ${_peso(_bytesAdjuntos)} de 20 MB. Cada correo llevará estos archivos.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ],
      ]),
    );
  }

  Future<void> _enviar() async {
    if (_asunto.text.trim().isEmpty || _cuerpo.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Escribe el asunto y el mensaje.'),
      ));
      return;
    }
    final destino = _programa == null
        ? 'TODOS los alumnos activos'
        : '$_programa${_generacion != null ? ' · Gen. $_generacion' : ' · todas las generaciones'}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar envío'),
        content: Text(
            'Se enviará la circular a:\n\n$destino\n(aprox. $_alcance alumnos)'
            '${_adjuntos.isNotEmpty ? '\n\nCon ${_adjuntos.length} archivo(s) adjunto(s): ${_adjuntos.map((a) => a['nombre']).join(', ')}' : ''}'
            '\n\n¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _enviando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'circular_enviar',
                'confirmar': 'ENVIAR', // (22-sep) ya se confirmó en el diálogo
                'asunto': _asunto.text.trim(),
                'cuerpo': _cuerpo.text.trim(),
                if (_esHtml) 'esHtml': '1',
                'programa': _programa ?? '',
                'generacion': _generacion ?? '',
                if (_adjuntos.isNotEmpty) 'adjuntos': _adjuntos.map((a) => a['id']).toList(),
              }))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('Circular enviada a ${data['enviados']} alumno(s).'),
        ));
        _asunto.clear();
        _cuerpo.clear();
        setState(() => _adjuntos.clear());
      }
      _cargar();
      _cargarCola();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo enviar: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Aviso masivo (circular)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _barraCola(),
                const Text('Destinatarios',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: _programa,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Programa',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos los programas (activos)')),
                    ..._programas.map((p) =>
                        DropdownMenuItem<String?>(value: p, child: Text(p))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _programa = v;
                      _generacion = null;
                    });
                    _contarAlcance();
                  },
                ),
                if (_programa != null) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: _generacion,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Generación',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Todas las generaciones')),
                      ..._generacionesDe.map((g) =>
                          DropdownMenuItem<String?>(value: g, child: Text(g))),
                    ],
                    onChanged: (v) {
                      setState(() => _generacion = v);
                      _contarAlcance();
                    },
                  ),
                ],
                const SizedBox(height: 8),
                if (_opGrupos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: _grupo,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Grupo',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Todos los grupos')),
                      ..._opGrupos.map((g) =>
                          DropdownMenuItem<String?>(value: g, child: Text(g))),
                    ],
                    onChanged: (v) {
                      setState(() => _grupo = v);
                      _contarAlcance();
                    },
                  ),
                ],
                if (_opModalidades.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    value: _modalidad,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Modalidad',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Todas las modalidades')),
                      ..._opModalidades.map((m) =>
                          DropdownMenuItem<String?>(value: m, child: Text(m))),
                    ],
                    onChanged: (v) {
                      setState(() => _modalidad = v);
                      _contarAlcance();
                    },
                  ),
                ],
                const SizedBox(height: 12),
                // Adeudo: el corte que más falta hacía. Un aviso de pago no
                // tiene por qué llegarle a quien está al corriente.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final op in const [
                      ['', 'Todos'],
                      ['con', 'Solo con adeudo'],
                      ['sin', 'Solo al corriente'],
                    ])
                      ChoiceChip(
                        label: Text(op[1], style: const TextStyle(fontSize: 12.5)),
                        selected: _adeudo == op[0],
                        selectedColor: cessumGold.withValues(alpha: 0.25),
                        onSelected: (_) {
                          setState(() => _adeudo = op[0]);
                          _contarAlcance();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final op in const [
                      ['', 'Vigentes y egresados'],
                      ['vigentes', 'Solo vigentes'],
                      ['egresados', 'Solo egresados'],
                    ])
                      ChoiceChip(
                        label: Text(op[1], style: const TextStyle(fontSize: 12.5)),
                        selected: _vigencia == op[0],
                        selectedColor: cessumGold.withValues(alpha: 0.25),
                        onSelected: (_) {
                          setState(() => _vigencia = op[0]);
                          _contarAlcance();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  value: _soloInstitucional,
                  onChanged: (v) {
                    setState(() => _soloInstitucional = v ?? false);
                    _contarAlcance();
                  },
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: cessumRed,
                  title: const Text('Solo correos @cessum.mx',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      'Deja fuera a quien tenga registrado un correo personal.',
                      style: TextStyle(fontSize: 11.5)),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (_contando)
                        const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF8A6118)))
                      else
                        const Icon(Icons.groups_outlined,
                            size: 16, color: Color(0xFF8A6118)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _contando
                              ? 'Contando destinatarios…'
                              : _alcanceReal != null
                                  // Cifra del Guardián, con los mismos filtros
                                  // con los que va a enviar: ya no dice 638 y
                                  // salen 606.
                                  ? 'Le llegará a $_alcanceReal persona(s)'
                                  : 'Alcance aproximado: $_alcance alumno(s)',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF8A6118)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Mensaje',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
                const SizedBox(height: 10),
                TextField(
                  controller: _asunto,
                  decoration: const InputDecoration(
                    labelText: 'Asunto',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _cuerpo,
                  maxLines: _esHtml ? 14 : 8,
                  style: _esHtml
                      ? const TextStyle(
                          fontFamily: 'monospace', fontSize: 12.5)
                      : null,
                  decoration: InputDecoration(
                    labelText:
                        _esHtml ? 'HTML del correo' : 'Cuerpo del mensaje',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    helperText: _esHtml
                        ? 'Se envía tal cual, dentro del marco CESSUM. '
                            'Previsualiza antes de mandar.'
                        : 'Cada salto de línea se respeta. Se envía con el '
                            'diseño CESSUM.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 6),
                _seccionAdjuntos(),
                const SizedBox(height: 6),
                // (ago-21) Interruptor de HTML + vista previa.
                //
                // Mandar una circular es irreversible: llega a cientos de
                // personas de golpe. Con HTML pegado el riesgo es mayor,
                // porque un error de etiquetas no se ve en el cuadro de
                // texto y sí en el buzón de todos. Por eso la previa está
                // junto al interruptor y no escondida.
                Row(children: [
                  Expanded(
                    child: SwitchListTile(
                      value: _esHtml,
                      onChanged: (v) => setState(() => _esHtml = v),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Pegar HTML',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: const Text(
                          'Para circulares ya diseñadas para correo.',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
                  TextButton.icon(
                    // La previa la arma el Guardián, así que tarda un momento:
                    // sin indicador parece que el botón no responde.
                    onPressed: _previaCargando ? null : _previsualizar,
                    icon: _previaCargando
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.visibility_outlined, size: 17),
                    label: Text(_previaCargando ? 'Generando…' : 'Previsualizar',
                        style: const TextStyle(fontSize: 13)),
                    style: TextButton.styleFrom(foregroundColor: cessumGold),
                  ),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      side: BorderSide(color: cessumRed.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _verDestinatarios,
                    icon: const Icon(Icons.group),
                    label: const Text('Ver destinatarios'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _enviando ? null : _enviar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    label: Text(_enviando ? 'Enviando...' : 'Enviar circular'),
                  ),
                ),
                if (_historial.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const Text('Circulares enviadas',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: cessumRed)),
                  const SizedBox(height: 8),
                  ..._historial.take(15).map((c) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading:
                              const Icon(Icons.mark_email_read, color: cessumRed),
                          title: Text('${c['asunto']}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${c['destino']}\n${c['enviados']} enviados · ${c['fecha']}',
                            style: const TextStyle(fontSize: 11.5, height: 1.4),
                          ),
                          isThreeLine: true,
                        ),
                      )),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

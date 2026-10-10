import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'foto_web_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// Panel de administración de la Mesa de Ayuda: ver, responder y cerrar
/// incidencias de los alumnos.
class IncidenciasAdminScreen extends StatefulWidget {
  const IncidenciasAdminScreen({super.key});

  @override
  State<IncidenciasAdminScreen> createState() => _IncidenciasAdminScreenState();
}

class _IncidenciasAdminScreenState extends State<IncidenciasAdminScreen> {
  static const List<String> _estatusList = ['Abierta', 'En proceso', 'Resuelta'];

  List<Map<String, dynamic>> _todas = [];
  String _filtro = 'Abierta';

  /// (ago-17) Con noventa incidencias, los chips de estatus ya no alcanzan:
  /// para encontrar una hay que bajar leyendo. Se busca por folio, nombre,
  /// matrícula, programa, categoría y por el texto de la descripción — que es
  /// donde suele estar la palabra que uno recuerda del caso.
  final TextEditingController _buscaCtrl = TextEditingController();
  String _busca = '';
  String _categoria = 'Todas';
  String _programa = 'Todos';
  bool _soloVencidas = false;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscaCtrl.dispose();
    super.dispose();
  }

  static String _n(String s) {
    var t = s.toLowerCase().trim();
    const ac = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
    ac.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  /// Valores presentes en los datos, no una lista fija: si mañana aparece una
  /// categoría nueva, el filtro la ofrece sin tocar código.
  List<String> _valoresDe(String campo, String todos) {
    final set = <String>{};
    for (final i in _todas) {
      final v = (i[campo] ?? '').toString().trim();
      if (v.isNotEmpty) set.add(v);
    }
    final lista = set.toList()..sort();
    return [todos, ...lista];
  }

  bool _estaVencida(Map<String, dynamic> i) {
    if ((i['estatus'] ?? '') == 'Resuelta') return false;
    final t = i['timer'];
    return t is Map && t['vencida'] == true;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$guardianUrl?accion=incidencias_listar');
      final resp = await http.get(uri).timeout(Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _todas = (data['incidencias'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las incidencias.';
      });
    }
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _n(_busca);
    return _todas.where((i) {
      if (_filtro != 'Todas' && (i['estatus'] ?? '') != _filtro) return false;
      if (_categoria != 'Todas' &&
          (i['categoria'] ?? '').toString() != _categoria) return false;
      if (_programa != 'Todos' &&
          (i['programa'] ?? '').toString() != _programa) return false;
      if (_soloVencidas && !_estaVencida(i)) return false;
      if (q.isEmpty) return true;
      final heno = _n([
        i['folio'], i['nombre'], i['matricula'], i['programa'],
        i['categoria'], i['descripcion'], i['correo']
      ].map((x) => (x ?? '').toString()).join(' '));
      // Todas las palabras deben aparecer: así "lopez pagos" acota de verdad
      // en vez de traer todo lo que contenga cualquiera de las dos.
      for (final w in q.split(RegExp(r'\s+'))) {
        if (w.isEmpty) continue;
        if (!heno.contains(w)) return false;
      }
      return true;
    }).toList();
  }

  /// Menú desplegable compacto para un filtro con muchas opciones.
  Widget _menuFiltro(String etiqueta, String valor, List<String> opciones,
      void Function(String) onElegir) {
    final activo = valor != opciones.first;
    return PopupMenuButton<String>(
      tooltip: etiqueta,
      onSelected: onElegir,
      itemBuilder: (_) => opciones
          .map((o) => PopupMenuItem<String>(
                value: o,
                child: Text(o,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            o == valor ? FontWeight.w700 : FontWeight.w400)),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: activo ? cessumRed.withValues(alpha: 0.10) : null,
          border: Border.all(
              color: activo ? cessumRed : cessumMuted(context).withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(activo ? valor : etiqueta,
              style: TextStyle(
                  fontSize: 12,
                  color: activo ? cessumRed : cessumMuted(context),
                  fontWeight: activo ? FontWeight.w700 : FontWeight.w500)),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down,
              size: 18, color: activo ? cessumRed : cessumMuted(context)),
        ]),
      ),
    );
  }

  Future<void> _atender(Map<String, dynamic> inc) async {
    String estatus = (inc['estatus'] ?? 'Abierta') as String;
    if (!_estatusList.contains(estatus)) estatus = 'Abierta';
    final respCtrl =
        TextEditingController(text: (inc['respuesta'] ?? '') as String);
    bool enviando = false;
    // (24-sep) Borrador con IA: urgencia, categoría y respuesta con datos reales.
    bool iaCargando = false;
    String iaInfo = '';
    final List<Map<String, dynamic>> adjuntos = []; // {bytes, mime, nombre}, hasta 5
    final evidAlumno = (inc['evidencia'] ?? '').toString();

    // Hilo de conversación del ticket.
    List<Map<String, dynamic>> hilo = [];
    bool cargandoHilo = true;
    // (ago-19) El chat empieza PLEGADO. Ocupaba media pantalla aunque no se
    // fuera a leer, y empujaba el estatus y el cuadro de respuesta fuera de la
    // vista: había que desplazarse para hacer lo que se venía a hacer.
    bool verChat = false;

    Future<void> cargarHilo(void Function(void Function()) setLocal) async {
      try {
        final r = await http
            .get(Uri.parse(
                '$guardianUrl?accion=incidencia_mensajes_listar&folio=${Uri.encodeComponent(inc['folio'] as String)}'))
            .timeout(const Duration(seconds: 30));
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          setLocal(() {
            hilo = ((data['mensajes'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            cargandoHilo = false;
          });
        } else {
          setLocal(() => cargandoHilo = false);
        }
      } catch (_) {
        setLocal(() => cargandoHilo = false);
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (cargandoHilo && hilo.isEmpty) {
            // Carga el hilo una sola vez al abrir.
            cargandoHilo = false;
            // ignore: discarded_futures
            Future.microtask(() => cargarHilo(setLocal));
          }
          return AlertDialog(
          title: Text('${inc['folio']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${inc['nombre']} (${inc['matricula']})\n${inc['programa']}\n${inc['categoria']} · ${inc['fecha']}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
                _chipTimer((inc['timer'] is Map)
                    ? Map<String, dynamic>.from(inc['timer'] as Map)
                    : <String, dynamic>{}),
                SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cessumEsOscuro(context) ? Colors.white10 : const Color(0xFFF5F1E8),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    (inc['descripcion'] ?? '') as String,
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                if (evidAlumno.isNotEmpty && evidAlumno != 'ERROR_EVIDENCIA')
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse(evidAlumno),
                          mode: LaunchMode.externalApplication),
                      icon: Icon(Icons.attachment,
                          size: 18, color: cessumGold),
                      label: Text('Ver evidencia del alumno',
                          style: TextStyle(color: cessumGold, fontSize: 13)),
                    ),
                  ),
                SizedBox(height: 14),
                // Hilo de conversación.
                if (cargandoHilo)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (hilo.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                          foregroundColor: cessumRed,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact),
                      onPressed: () => setLocal(() => verChat = !verChat),
                      icon: Icon(
                          verChat
                              ? Icons.keyboard_arrow_down
                              : Icons.chat_bubble_outline,
                          size: 18),
                      label: Text(
                          verChat
                              ? 'Ocultar el chat'
                              : 'Abrir chat · ${hilo.length} mensaje(s)',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  // Con el chat cerrado se ve el último mensaje: alcanza para
                  // saber si hay algo nuevo sin abrirlo.
                  if (!verChat)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                            'Último · ${hilo.last['autor'] == 'admin' ? 'CESSUM' : (hilo.last['nombre'] ?? 'Alumno')}: '
                            '${(hilo.last['mensaje'] ?? '').toString().length > 70 ? '${(hilo.last['mensaje'] ?? '').toString().substring(0, 70)}…' : hilo.last['mensaje'] ?? ''}',
                            style: TextStyle(
                                fontSize: 11.5, color: cessumMuted(context))),
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (verChat) Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Column(
                        children: hilo.map((m) {
                          final esAdmin =
                              (m['autor'] ?? '').toString() == 'admin';
                          final adj = (m['adjunto'] ?? '').toString();
                          return Align(
                            alignment: esAdmin
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.all(9),
                              constraints: const BoxConstraints(maxWidth: 420),
                              decoration: BoxDecoration(
                                color: esAdmin
                                    ? cessumRed.withValues(alpha: 0.10)
                                    : (cessumEsOscuro(context)
                                        ? Colors.white10
                                        : const Color(0xFFF0F0F0)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${esAdmin ? 'CESSUM' : (m['nombre'] ?? 'Alumno')} · ${m['fecha'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: cessumMuted(context)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text((m['mensaje'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 13)),
                                  // Puede haber VARIOS adjuntos (separados por \n).
                                  ...adj
                                      .split('\n')
                                      .where((u) => u.trim().startsWith('http'))
                                      .toList()
                                      .asMap()
                                      .entries
                                      .map((e) => TextButton.icon(
                                            onPressed: () => launchUrl(
                                                Uri.parse(e.value.trim()),
                                                mode: LaunchMode
                                                    .externalApplication),
                                            icon: Icon(Icons.attachment,
                                                size: 16, color: cessumGold),
                                            label: Text(
                                                'Ver adjunto ${e.key + 1}',
                                                style: TextStyle(
                                                    color: cessumGold,
                                                    fontSize: 12)),
                                          )),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (verChat) const SizedBox(height: 14),
                ],
                DropdownButtonFormField<String>(
                  value: estatus,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Estatus',
                    border: OutlineInputBorder(),
                  ),
                  items: _estatusList
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => setLocal(() => estatus = v ?? estatus),
                ),
                SizedBox(height: 12),
                // (8-sep) EL TOPE DE 600 CORTABA RESPUESTAS COMPLETAS.
                // Una incidencia de calificaciones no se resuelve en dos
                // líneas: hay que desglosar los trabajos con su puntaje, la
                // asistencia y el fundamento reglamentario. Con 600 caracteres
                // la respuesta se quedaba a media frase y el alumno recibía un
                // mensaje incompleto, que es peor que no contestar. Se sube a
                // 3000 y el campo crece a 10 líneas para que se vea lo escrito
                // antes de enviarlo. El backend no impone límite propio.
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: cessumGold),
                    onPressed: iaCargando
                        ? null
                        : () async {
                            setLocal(() => iaCargando = true);
                            try {
                              final r = await http
                                  .get(Uri.parse(guardianUrl).replace(queryParameters: {
                                    'accion': 'incidencia_ia_borrador',
                                    'folio': '${inc['folio'] ?? ''}',
                                  }))
                                  .timeout(const Duration(seconds: 120));
                              final d = jsonDecode(r.body) as Map<String, dynamic>;
                              if (d['ok'] == true) {
                                respCtrl.text = '${d['borrador'] ?? ''}';
                                iaInfo = 'Urgencia ${d['urgencia'] ?? '—'} · ${d['categoria'] ?? ''}'
                                    '${'${d['porque'] ?? ''}'.isNotEmpty ? ' · ${d['porque']}' : ''}'
                                    '\nBorrador con IA: revíselo y ajústelo antes de enviarlo.';
                              } else {
                                iaInfo = '${d['error'] ?? 'No se pudo generar el borrador.'}';
                              }
                            } catch (_) {
                              iaInfo = 'No se pudo conectar para generar el borrador.';
                            }
                            setLocal(() => iaCargando = false);
                          },
                    icon: iaCargando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cessumGold))
                        : const Icon(Icons.auto_awesome, size: 18),
                    label: Text(iaCargando ? 'Redactando…' : 'Borrador con IA'),
                  ),
                ),
                if (iaInfo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(iaInfo,
                        style: TextStyle(fontSize: 11.5, height: 1.35, color: cessumMuted(ctx), fontStyle: FontStyle.italic)),
                  ),
                TextField(
                  controller: respCtrl,
                  maxLines: 10,
                  minLines: 4,
                  maxLength: 3000,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: 'Escribe un mensaje al alumno',
                    helperText: 'Se agrega a la conversación y se envía por correo',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 4),
                // Adjuntos: hasta 5 archivos.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...adjuntos.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.insert_drive_file,
                                  size: 16, color: cessumRed),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  (e.value['nombre'] ?? 'archivo').toString(),
                                  style: const TextStyle(fontSize: 12.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                visualDensity: VisualDensity.compact,
                                onPressed: enviando
                                    ? null
                                    : () => setLocal(() => adjuntos.removeAt(e.key)),
                              ),
                            ],
                          ),
                        )),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: (enviando || adjuntos.length >= 5)
                            ? null
                            : () async {
                                final doc = await seleccionarDocumento();
                                if (doc != null) {
                                  setLocal(() => adjuntos.add({
                                        'bytes': doc.bytes,
                                        'mime': doc.mime,
                                        'nombre': doc.nombre,
                                      }));
                                }
                              },
                        icon: Icon(Icons.attach_file, size: 18, color: cessumRed),
                        label: Text(
                          adjuntos.isEmpty
                              ? 'Adjuntar archivo(s) a la respuesta'
                              : 'Agregar otro (${adjuntos.length}/5)',
                          style: const TextStyle(color: cessumRed, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.pop(ctx),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: enviando
                  ? null
                  : () async {
                      // Permite guardar con solo adjuntos (sin texto).
                      if (respCtrl.text.trim().isEmpty && adjuntos.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Colors.orange,
                            content: Text(
                                'Escribe un mensaje o adjunta al menos un archivo.'),
                          ),
                        );
                        return;
                      }
                      setLocal(() => enviando = true);
                      final ok = await _guardar(inc['folio'] as String, estatus,
                          respCtrl.text.trim(), adjuntos);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (ok && mounted) _cargar();
                    },
              child: enviando
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Guardar y notificar'),
            ),
          ],
        );
        },
      ),
    );
  }

  Future<bool> _guardar(String folio, String estatus, String respuesta,
      List<Map<String, dynamic>> adjuntos) async {
    try {
      // Serializa los adjuntos (hasta 5) para el backend.
      final adjPayload = adjuntos
          .map((a) => {
                'base64': base64Encode(a['bytes'] as List<int>),
                'mime': a['mime'],
              })
          .toList();
      // 1) Actualiza estatus + respuesta clásica (primer adjunto por compat).
      final payload = {
        'accion': 'incidencia_actualizar',
        'folio': folio,
        'estatus': estatus,
        'respuesta': respuesta,
        if (adjuntos.isNotEmpty)
          'evidenciaBase64': base64Encode(adjuntos.first['bytes'] as List<int>),
        if (adjuntos.isNotEmpty) 'evidenciaMime': adjuntos.first['mime'],
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      // 2) Agrega al HILO de conversación si hay texto O adjuntos.
      if (respuesta.isNotEmpty || adjuntos.isNotEmpty) {
        try {
          await http
              .post(
                Uri.parse(guardianUrl),
                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                body: jsonEncode({
                  'accion': 'incidencia_mensaje_agregar',
                  'folio': folio,
                  'autor': 'admin',
                  'nombre': 'CESSUM',
                  'mensaje': respuesta,
                  if (adjPayload.isNotEmpty) 'adjuntos': adjPayload,
                }),
              )
              .timeout(const Duration(seconds: 90));
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('$folio actualizada y alumno notificado.'),
        ));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo actualizar. Intenta de nuevo.'),
        ));
      }
      return false;
    }
  }

  Color _colorEstatus(String e) {
    switch (e) {
      case 'Resuelta':
        return Colors.green.shade700;
      case 'En proceso':
        return cessumGold;
      default:
        return cessumRed;
    }
  }

  // Chip del timer de 72 horas hábiles para responder la incidencia.
  // Verde = holgado, amarillo = 24h o menos, naranja = 12h o menos,
  // rojo = vencida. No se muestra si la incidencia ya está resuelta.
  Widget _chipTimer(Map<String, dynamic> timer) {
    if (timer.isEmpty || timer['aplica'] != true) {
      return const SizedBox.shrink();
    }
    if (timer['resuelta'] == true) {
      return const SizedBox.shrink();
    }
    final nivel = (timer['nivel'] ?? 'ok').toString();
    final vencida = timer['vencida'] == true;
    final horas = (timer['horasRestantes'] as num?)?.toInt() ?? 0;
    final limite = (timer['fechaLimite'] ?? '').toString();

    Color color;
    IconData icono;
    String texto;
    switch (nivel) {
      case 'vencida':
        color = Colors.red.shade700;
        icono = Icons.error;
        texto = 'VENCIDA · debió responderse antes del $limite';
        break;
      case 'critico':
        color = Colors.deepOrange;
        icono = Icons.warning_amber_rounded;
        texto = 'Quedan $horas h hábiles · antes del $limite';
        break;
      case 'alerta':
        color = cessumGold;
        icono = Icons.schedule;
        texto = 'Quedan $horas h hábiles · antes del $limite';
        break;
      default:
        color = Colors.green.shade700;
        icono = Icons.schedule;
        texto = 'Quedan $horas h hábiles · antes del $limite';
    }
    if (vencida) {
      texto = 'VENCIDA · debió responderse antes del $limite';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                texto,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtros = ['Abierta', 'En proceso', 'Resuelta', 'Todas'];
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Incidencias · Mesa de ayuda',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            onPressed: _cargar,
            icon: Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filtros.map((f) {
                  final activo = _filtro == f;
                  final cuantas = f == 'Todas'
                      ? _todas.length
                      : _todas.where((i) => (i['estatus'] ?? '') == f).length;
                  return Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$f ($cuantas)'),
                      selected: activo,
                      selectedColor: cessumRed.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: activo ? cessumRed : cessumInk(context),
                        fontWeight:
                            activo ? FontWeight.w700 : FontWeight.w400,
                      ),
                      onSelected: (_) => setState(() => _filtro = f),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _buscaCtrl,
              onChanged: (v) => setState(() => _busca = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar por folio, nombre, matrícula, programa o texto…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _busca.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() {
                          _buscaCtrl.clear();
                          _busca = '';
                        }),
                      ),
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: cessumRed, width: 1.6),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _menuFiltro('Categoría', _categoria,
                    _valoresDe('categoria', 'Todas'),
                    (v) => setState(() => _categoria = v)),
                const SizedBox(width: 8),
                _menuFiltro('Programa', _programa,
                    _valoresDe('programa', 'Todos'),
                    (v) => setState(() => _programa = v)),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Solo vencidas'),
                  selected: _soloVencidas,
                  selectedColor: const Color(0xFFC62828).withValues(alpha: 0.15),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _soloVencidas
                        ? const Color(0xFFC62828)
                        : cessumMuted(context),
                    fontWeight:
                        _soloVencidas ? FontWeight.w700 : FontWeight.w400,
                  ),
                  onSelected: (v) => setState(() => _soloVencidas = v),
                ),
                if (_busca.isNotEmpty ||
                    _categoria != 'Todas' ||
                    _programa != 'Todos' ||
                    _soloVencidas) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: cessumRed),
                    onPressed: () => setState(() {
                      _buscaCtrl.clear();
                      _busca = '';
                      _categoria = 'Todas';
                      _programa = 'Todos';
                      _soloVencidas = false;
                    }),
                    icon: const Icon(Icons.filter_alt_off, size: 16),
                    label: const Text('Quitar filtros',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ]),
            ),
          ),
          if (!_cargando && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Mostrando ${_visibles.length} de ${_todas.length}'
                    '${_todas.where(_estaVencida).isEmpty ? '' : ' · ${_todas.where(_estaVencida).length} vencida(s) sin resolver'}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: _todas.where(_estaVencida).isEmpty
                            ? cessumMuted(context)
                            : const Color(0xFFC62828),
                        fontWeight: _todas.where(_estaVencida).isEmpty
                            ? FontWeight.w400
                            : FontWeight.w700)),
              ),
            ),
          Expanded(
            child: _cargando
                ? Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!),
                            SizedBox(height: 8),
                            TextButton(
                                onPressed: _cargar,
                                child: Text('Reintentar')),
                          ],
                        ),
                      )
                    : _visibles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                  _busca.isEmpty
                                      ? 'Sin incidencias en este filtro.'
                                      : 'Nada coincide con «$_busca».',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: cessumMuted(context))),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.all(16),
                            itemCount: _visibles.length,
                            itemBuilder: (ctx, i) {
                              final inc = _visibles[i];
                              final estatus =
                                  (inc['estatus'] ?? '') as String;
                              final timer = (inc['timer'] is Map)
                                  ? Map<String, dynamic>.from(
                                      inc['timer'] as Map)
                                  : <String, dynamic>{};
                              return Card(
                                margin: EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                child: ListTile(
                                  onTap: () => _atender(inc),
                                  title: Text(
                                    '${inc['folio']} · ${inc['nombre']}',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${inc['categoria']} · ${inc['fecha']}\n${inc['descripcion']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12, height: 1.4),
                                      ),
                                      _chipTimer(timer),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _colorEstatus(estatus)
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      estatus,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: _colorEstatus(estatus),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'foto_web_picker.dart';
import 'student_profile.dart';

/// Mesa de Ayuda: el alumno reporta una incidencia y da seguimiento.
class MesaAyudaScreen extends StatefulWidget {
  final StudentProfile perfil;
  const MesaAyudaScreen({super.key, required this.perfil});

  @override
  State<MesaAyudaScreen> createState() => _MesaAyudaScreenState();
}

class _MesaAyudaScreenState extends State<MesaAyudaScreen> {
  static const List<String> _categorias = [
    'Plataforma / acceso',
    'Calificaciones',
    'Pagos',
    'Credencial',
    'Documentos y trámites',
    'Otro',
  ];

  List<Map<String, dynamic>> _incidencias = [];
  bool _cargando = true;
  String? _error;

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
      final uri = Uri.parse(
          '$guardianUrl?accion=incidencias_listar&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _incidencias = (data['incidencias'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus incidencias.';
      });
    }
  }

  Future<void> _nuevaIncidencia() async {
    String categoria = _categorias.first;
    final descCtrl = TextEditingController();
    // (10-sep) TELÉFONO, OPCIONAL. Hay incidencias que se resuelven en dos
    // minutos por WhatsApp y en tres correos de ida y vuelta si no. Va como
    // opcional a propósito: exigirlo dejaría fuera a quien no tiene el
    // celular a la mano, y el correo institucional ya asegura una vía.
    final telCtrl = TextEditingController();
    bool enviando = false;
    final List<DocElegido> adjuntos = [];

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Nueva incidencia'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Describe tu problema y el equipo CESSUM te respondera por correo y aqui mismo.',
                  style: TextStyle(fontSize: 13, color: cessumMuted(context)),
                ),
                SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: categoria,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(),
                  ),
                  items: _categorias
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setLocal(() => categoria = v ?? categoria),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  maxLines: 4,
                  maxLength: 600,
                  decoration: InputDecoration(
                    labelText: 'Describe la incidencia',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 4),
                TextField(
                  controller: telCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 15,
                  decoration: InputDecoration(
                    labelText: 'Teléfono (opcional)',
                    helperText: 'Por si conviene resolverlo por llamada o WhatsApp',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: (enviando || adjuntos.length >= 5)
                        ? null
                        : () async {
                            try {
                              final doc =
                                  await seleccionarDocumento(tipo: 'todos');
                              if (doc != null) {
                                setLocal(() => adjuntos.add(doc));
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                  backgroundColor: Colors.redAccent,
                                  content: Text(
                                      '$e'.replaceAll('Exception: ', '')),
                                ));
                              }
                            }
                          },
                    icon: Icon(Icons.attach_file, size: 18, color: cessumRed),
                    label: Text(
                      adjuntos.length >= 5
                          ? 'Máximo 5 archivos'
                          : 'Adjuntar imagen, video o PDF (${adjuntos.length}/5)',
                      style: TextStyle(color: cessumRed, fontSize: 13),
                    ),
                  ),
                ),
                if (adjuntos.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(adjuntos.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(_iconoAdjunto(adjuntos[i].mime),
                                size: 16, color: cessumGold),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                adjuntos[i].nombre,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            InkWell(
                              onTap: enviando
                                  ? null
                                  : () => setLocal(() => adjuntos.removeAt(i)),
                              child: const Icon(Icons.close,
                                  size: 16, color: Colors.redAccent),
                            ),
                          ],
                        ),
                      );
                    }),
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
                      if (descCtrl.text.trim().length < 10) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          backgroundColor: Colors.redAccent,
                          content:
                              Text('Describe tu incidencia (minimo 10 letras)'),
                        ));
                        return;
                      }
                      setLocal(() => enviando = true);
                      final ok = await _enviar(
                          categoria, descCtrl.text.trim(), adjuntos,
                          telCtrl.text.trim());
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
                  : Text('Enviar'),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconoAdjunto(String mime) {
    final m = mime.toLowerCase();
    if (m.startsWith('video/')) return Icons.videocam;
    if (m.contains('pdf')) return Icons.picture_as_pdf;
    return Icons.image;
  }

  Future<bool> _enviar(String categoria, String descripcion,
      List<DocElegido> adjuntos, [String telefono = '']) async {
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final payload = {
        'accion': 'incidencia_crear',
        'matricula': widget.perfil.matricula,
        'nombre': widget.perfil.nombreCompleto,
        'correo': correo,
        'programa': widget.perfil.programa,
        'categoria': categoria,
        'telefono': telefono,
        'modoPrueba': widget.perfil.esVistaAdmin == true,
        'descripcion': (widget.perfil.esVistaAdmin == true ? '[MODO PRUEBA - NO PROCESAR] ' : '') + descripcion,
        if (adjuntos.isNotEmpty)
          'adjuntos': adjuntos
              .map((a) => {
                    'base64': base64Encode(a.bytes),
                    'mime': a.mime,
                    'nombre': a.nombre,
                  })
              .toList(),
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text(
              'Incidencia ${data['folio']} registrada. Te avisaremos por correo.'),
        ));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo enviar. Intenta de nuevo.'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Mesa de ayuda',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            onPressed: _cargar,
            icon: Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _nuevaIncidencia,
        icon: Icon(Icons.add),
        label: Text('Nueva incidencia'),
      ),
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      SizedBox(height: 8),
                      TextButton(
                          onPressed: _cargar, child: Text('Reintentar')),
                    ],
                  ),
                )
              : _incidencias.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Aun no tienes incidencias.\nSi tienes algun problema con la plataforma, calificaciones, pagos o tramites, toca "Nueva incidencia".',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cessumMuted(context), height: 1.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: _incidencias.length,
                      itemBuilder: (ctx, i) {
                        final inc = _incidencias[i];
                        final estatus = (inc['estatus'] ?? '') as String;
                        final respuesta = (inc['respuesta'] ?? '') as String;
                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${inc['folio']} · ${inc['categoria']}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13),
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _colorEstatus(estatus)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        estatus,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _colorEstatus(estatus),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Text(
                                  (inc['fecha'] ?? '') as String,
                                  style: TextStyle(
                                      fontSize: 11, color: cessumFaint(context)),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  (inc['descripcion'] ?? '') as String,
                                  style: TextStyle(
                                      fontSize: 13, height: 1.4),
                                ),
                                if (respuesta.isNotEmpty) ...[
                                  SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          cessumGold.withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                            color: cessumGold, width: 4),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Respuesta de CESSUM',
                                          style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: cessumGold),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          respuesta,
                                          style: TextStyle(
                                              fontSize: 13, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _verConversacion(inc),
                                    icon: Icon(Icons.forum_outlined,
                                        size: 18, color: cessumRed),
                                    label: Text('Ver conversación',
                                        style: TextStyle(
                                            color: cessumRed, fontSize: 13)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  // Abre el hilo de conversación del ticket y permite al alumno responder.
  Future<void> _verConversacion(Map<String, dynamic> inc) async {
    final folio = (inc['folio'] ?? '').toString();
    final msgCtrl = TextEditingController();
    List<Map<String, dynamic>> hilo = [];
    bool cargando = true;
    bool enviando = false;

    Future<void> cargar(void Function(void Function()) setLocal) async {
      try {
        final r = await http
            .get(Uri.parse(
                '$guardianUrl?accion=incidencia_mensajes_listar&folio=${Uri.encodeComponent(folio)}'))
            .timeout(const Duration(seconds: 30));
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          setLocal(() {
            hilo = ((data['mensajes'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            cargando = false;
          });
        } else {
          setLocal(() => cargando = false);
        }
      } catch (_) {
        setLocal(() => cargando = false);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          if (cargando && hilo.isEmpty) {
            cargando = false;
            // ignore: discarded_futures
            Future.microtask(() => cargar(setLocal));
          }
          return AlertDialog(
            title: Text('$folio'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: hilo.map((m) {
                          final esAdmin =
                              (m['autor'] ?? '').toString() == 'admin';
                          final adj = (m['adjunto'] ?? '').toString();
                          return Align(
                            alignment: esAdmin
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.all(9),
                              constraints: const BoxConstraints(maxWidth: 300),
                              decoration: BoxDecoration(
                                color: esAdmin
                                    ? cessumGold.withValues(alpha: 0.12)
                                    : cessumRed.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${esAdmin ? 'CESSUM' : 'Tú'} · ${m['fecha'] ?? ''}',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        color: cessumFaint(context)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text((m['mensaje'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 13)),
                                  if (adj.isNotEmpty && adj.startsWith('http'))
                                    TextButton.icon(
                                      onPressed: () => launchUrl(
                                          Uri.parse(adj),
                                          mode:
                                              LaunchMode.externalApplication),
                                      icon: Icon(Icons.attachment,
                                          size: 16, color: cessumGold),
                                      label: Text('Ver adjunto',
                                          style: TextStyle(
                                              color: cessumGold,
                                              fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (cargando)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: msgCtrl,
                    maxLines: 3,
                    maxLength: 600,
                    decoration: const InputDecoration(
                      hintText: 'Escribe tu mensaje…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: enviando ? null : () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: enviando
                    ? null
                    : () async {
                        final texto = msgCtrl.text.trim();
                        if (texto.isEmpty) return;
                        setLocal(() => enviando = true);
                        try {
                          await http
                              .post(
                                Uri.parse(guardianUrl),
                                headers: {
                                  'Content-Type': 'text/plain;charset=utf-8'
                                },
                                body: jsonEncode({
                                  'accion': 'incidencia_mensaje_agregar',
                                  'folio': folio,
                                  'autor': 'alumno',
                                  'nombre': widget.perfil.nombreCompleto,
                                  'mensaje': texto,
                                }),
                              )
                              .timeout(const Duration(seconds: 60));
                          msgCtrl.clear();
                          await cargar(setLocal);
                        } catch (_) {}
                        setLocal(() => enviando = false);
                      },
                child: enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Enviar'),
              ),
            ],
          );
        },
      ),
    );
  }
}

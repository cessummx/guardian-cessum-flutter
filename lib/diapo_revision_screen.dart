import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';

/// (8-oct-2026) Revisión lámina por lámina de un deck ya generado.
/// El docente ve cada diapositiva, le da el visto bueno o abre el chat
/// para pedir un ajuste puntual — la IA reescribe solo esa lámina, sin
/// gastar una de las 3 versiones completas del proyecto.
class DiapoRevisionScreen extends StatefulWidget {
  final String id;
  final String tituloProyecto;

  const DiapoRevisionScreen({
    super.key,
    required this.id,
    this.tituloProyecto = 'Presentación',
  });

  @override
  State<DiapoRevisionScreen> createState() => _DiapoRevisionScreenState();
}

class _LaminaRevision {
  final int indice;
  final String titulo;
  final String tipo;
  final bool tieneInteractivo;
  String estado;
  int intentos;
  final int intentosMax;
  List<Map<String, dynamic>> chat;

  _LaminaRevision({
    required this.indice,
    required this.titulo,
    required this.tipo,
    required this.tieneInteractivo,
    required this.estado,
    required this.intentos,
    required this.intentosMax,
    required this.chat,
  });

  factory _LaminaRevision.fromJson(Map<String, dynamic> j) {
    return _LaminaRevision(
      indice: (j['indice'] is num) ? (j['indice'] as num).toInt() : 0,
      titulo: (j['titulo'] ?? '').toString(),
      tipo: (j['tipo'] ?? 'contenido').toString(),
      tieneInteractivo: j['tieneInteractivo'] == true,
      estado: (j['estado'] ?? 'pendiente').toString(),
      intentos: (j['intentos'] is num) ? (j['intentos'] as num).toInt() : 0,
      intentosMax:
          (j['intentosMax'] is num) ? (j['intentosMax'] as num).toInt() : 5,
      chat: ((j['chat'] ?? []) as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
    );
  }
}

class _DiapoRevisionScreenState extends State<DiapoRevisionScreen> {
  bool _cargando = true;
  String? _error;
  List<_LaminaRevision> _laminas = [];
  int _aprobadas = 0;
  String _correo = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      _correo = await SessionStore.validEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'diapo_revision_estado',
        'id': widget.id,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        final lista = ((data['laminas'] ?? []) as List)
            .map((e) => _LaminaRevision.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
        if (mounted) setState(() {
          _laminas = lista;
          _aprobadas = (data['aprobadas'] is num) ? (data['aprobadas'] as num).toInt() : 0;
          _cargando = false;
        });
      } else {
        if (mounted) setState(() {
          _cargando = false;
          _error = data['error']?.toString() ?? 'No se pudo cargar la revisión.';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _cargando = false;
        _error = 'Error de conexión. Revisa tu internet e intenta de nuevo.';
      });
    }
  }

  Future<void> _aprobar(_LaminaRevision l, {bool quitar = false}) async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'diapo_lamina_aprobar',
        'id': widget.id,
        'lamina': '${l.indice}',
        'estado': quitar ? 'pendiente' : 'aprobada',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && mounted) {
        setState(() {
          l.estado = data['estado']?.toString() ?? (quitar ? 'pendiente' : 'aprobada');
          _aprobadas = _laminas.where((x) => x.estado == 'aprobada').length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el visto bueno.')),
        );
      }
    }
  }

  Future<void> _abrirChat(_LaminaRevision l) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChatLaminaSheet(
        id: widget.id,
        lamina: l,
        correo: _correo,
        onCambio: () {
          if (mounted) setState(() {
            _aprobadas = _laminas.where((x) => x.estado == 'aprobada').length;
          });
        },
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
        title: Text('Revisar · ${widget.tituloProyecto}',
            overflow: TextOverflow.ellipsis),
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error != null
              ? _vistaError()
              : _laminas.isEmpty
                  ? const Center(child: Text('Este proyecto no tiene láminas.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          _resumen(),
                          const SizedBox(height: 12),
                          ..._laminas.map(_card),
                        ],
                      ),
                    ),
    );
  }

  Widget _resumen() {
    final total = _laminas.length;
    final listo = total > 0 && _aprobadas == total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: listo ? const Color(0xFF1E8E3E) : cessumRed,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(listo ? Icons.check_circle : Icons.rate_review,
              color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_aprobadas de $total láminas con visto bueno',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  listo
                      ? 'Listo para exportar o colocar en el aula.'
                      : 'Toca una lámina para aprobarla o pedir un ajuste.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(_LaminaRevision l) {
    final aprobada = l.estado == 'aprobada';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: aprobada
              ? const Color(0xFF1E8E3E).withValues(alpha: 0.5)
              : cessumMuted(context).withValues(alpha: 0.18),
          width: aprobada ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: aprobada
                ? const Color(0xFF1E8E3E)
                : cessumMuted(context).withValues(alpha: 0.25),
            child: Text('${l.indice + 1}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.titulo.isEmpty ? '(sin título)' : l.titulo,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _chip(l.tipo, cessumGold),
                    if (l.tieneInteractivo) _chip('interactivo', cessumRed),
                    if (l.intentos > 0)
                      _chip('${l.intentos}/${l.intentosMax} ajustes', cessumMuted(context)),
                    _chip(aprobada ? 'Aprobada' : 'Pendiente',
                        aprobada ? const Color(0xFF1E8E3E) : cessumMuted(context)),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _abrirChat(l),
                      icon: const Icon(Icons.chat_bubble_outline, size: 15, color: cessumRed),
                      label: const Text('Chat de ajuste', style: TextStyle(color: cessumRed, fontSize: 12.5)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumRed),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    aprobada
                        ? OutlinedButton.icon(
                            onPressed: () => _aprobar(l, quitar: true),
                            icon: const Icon(Icons.undo, size: 15),
                            label: const Text('Quitar visto bueno', style: TextStyle(fontSize: 12.5)),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: () => _aprobar(l),
                            icon: const Icon(Icons.check, size: 15, color: Colors.white),
                            label: const Text('Aprobar', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E8E3E),
                              minimumSize: const Size(0, 34),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, size: 48, color: cessumFaint(context)),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context))),
            const SizedBox(height: 14),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _cargar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja inferior con el chat de UNA lámina: historial + campo de texto +
/// botón de aprobar, todo en el mismo lugar.
class _ChatLaminaSheet extends StatefulWidget {
  final String id;
  final _LaminaRevision lamina;
  final String correo;
  final VoidCallback onCambio;

  const _ChatLaminaSheet({
    required this.id,
    required this.lamina,
    required this.correo,
    required this.onCambio,
  });

  @override
  State<_ChatLaminaSheet> createState() => _ChatLaminaSheetState();
}

class _ChatLaminaSheetState extends State<_ChatLaminaSheet> {
  final _ctrl = TextEditingController();
  bool _enviando = false;
  String? _error;

  Future<void> _enviar() async {
    final mensaje = _ctrl.text.trim();
    if (mensaje.isEmpty || _enviando) return;
    if (widget.lamina.intentos >= widget.lamina.intentosMax) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final resp = await http.post(
        Uri.parse(guardianUrl),
        body: {
          'accion': 'diapo_lamina_chat',
          'id': widget.id,
          'lamina': '${widget.lamina.indice}',
          'mensaje': mensaje,
          'actor': widget.correo,
        },
      ).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        if (mounted) setState(() {
          widget.lamina.chat.add({'quien': 'profesor', 'texto': mensaje});
          widget.lamina.chat.add({'quien': 'ia', 'texto': data['respuesta'] ?? 'Hecho.'});
          widget.lamina.intentos = (data['intentos'] is num) ? (data['intentos'] as num).toInt() : widget.lamina.intentos + 1;
          widget.lamina.estado = 'pendiente';
          _ctrl.clear();
          _enviando = false;
        });
        widget.onCambio();
      } else {
        if (mounted) setState(() {
          _enviando = false;
          _error = data['error']?.toString() ?? 'No se pudo aplicar el cambio.';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _enviando = false;
        _error = 'Error de conexión. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lamina;
    final sinIntentos = l.intentos >= l.intentosMax;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: cessumMuted(context).withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Lámina ${l.indice + 1} · ${l.titulo}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('${l.intentos}/${l.intentosMax}',
                        style: TextStyle(color: cessumMuted(context), fontSize: 12)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: l.chat.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Escribe qué quieres distinto de esta lámina: el texto, el interactivo, o ambos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cessumMuted(context)),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(14),
                        itemCount: l.chat.length,
                        itemBuilder: (context, i) {
                          final m = l.chat[i];
                          final esProfesor = m['quien'] == 'profesor';
                          return Align(
                            alignment: esProfesor ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              decoration: BoxDecoration(
                                color: esProfesor ? cessumRed : cessumMuted(context).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                (m['texto'] ?? '').toString(),
                                style: TextStyle(
                                  color: esProfesor ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(_error!, style: const TextStyle(color: cessumRed, fontSize: 12.5)),
                ),
              if (sinIntentos)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Esta lámina ya usó sus ${l.intentosMax} ajustes por chat. Edítala directamente o continúa con las demás.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cessumMuted(context), fontSize: 12.5),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          minLines: 1,
                          maxLines: 4,
                          enabled: !_enviando,
                          decoration: const InputDecoration(
                            hintText: 'Ej: haz la pregunta más sencilla, cambia el interactivo a escala…',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _enviando
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                            )
                          : IconButton(
                              onPressed: _enviar,
                              icon: const Icon(Icons.send, color: cessumRed),
                            ),
                    ],
                  ),
                ),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.check, color: Color(0xFF1E8E3E)),
                    label: const Text('Cerrar', style: TextStyle(color: Color(0xFF1E8E3E))),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF1E8E3E))),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

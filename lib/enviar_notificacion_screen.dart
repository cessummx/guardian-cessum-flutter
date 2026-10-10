import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Permite a un administrador enviar una notificación in-app a un alumno
/// (por correo o matrícula) o a todo un grupo. El alumno la verá en su buzón.
class EnviarNotificacionScreen extends StatefulWidget {
  const EnviarNotificacionScreen({super.key});

  @override
  State<EnviarNotificacionScreen> createState() =>
      _EnviarNotificacionScreenState();
}

class _EnviarNotificacionScreenState extends State<EnviarNotificacionScreen> {
  String _actor = '';
  String _destino = 'alumno'; // 'alumno' | 'grupo'

  final _para = TextEditingController();
  final _titulo = TextEditingController();
  final _mensaje = TextEditingController();

  // Catálogo de grupos encadenado.
  List<Map<String, dynamic>> _catalogo = [];
  String? _programa;
  String? _generacion;
  String? _grupo;

  bool _cargandoCat = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // (24-sep) El correo REAL: validEmail() en «Ver como profesor» devuelve el del
    // profesor, y la notificación saldría a su nombre (y sin permiso de administrador).
    _actor = (await SessionStore.realEmail()) ?? '';
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=grupos'))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (mounted && data['ok'] == true) {
        setState(() {
          _catalogo = ((data['catalogo'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _cargandoCat = false;
        });
      } else {
        if (mounted) setState(() => _cargandoCat = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoCat = false);
    }
  }

  @override
  void dispose() {
    _para.dispose();
    _titulo.dispose();
    _mensaje.dispose();
    super.dispose();
  }

  List<String> get _programas =>
      _catalogo.map((p) => (p['programa'] ?? '').toString()).toList();

  List<String> get _generaciones {
    final p = _catalogo.firstWhere(
        (x) => x['programa'] == _programa,
        orElse: () => <String, dynamic>{});
    final gens = (p['generaciones'] as List?) ?? [];
    return gens.map((g) => (g['generacion'] ?? '').toString()).toList();
  }

  List<String> get _grupos {
    final p = _catalogo.firstWhere(
        (x) => x['programa'] == _programa,
        orElse: () => <String, dynamic>{});
    final gens = (p['generaciones'] as List?) ?? [];
    final g = gens.firstWhere(
        (x) => (x as Map)['generacion'] == _generacion,
        orElse: () => <String, dynamic>{});
    final grs = (g is Map ? (g['grupos'] as List?) : null) ?? [];
    return grs.map((x) => x.toString()).toList();
  }

  Future<void> _enviar() async {
    if (_titulo.text.trim().isEmpty || _mensaje.text.trim().isEmpty) {
      _msg('Escribe el título y el mensaje.', Colors.redAccent);
      return;
    }
    final payload = <String, dynamic>{
      'accion': 'notificacion_enviar',
      'actor': _actor,
      'destino': _destino,
      'titulo': _titulo.text.trim(),
      'mensaje': _mensaje.text.trim(),
    };
    if (_destino == 'alumno') {
      if (_para.text.trim().isEmpty) {
        _msg('Escribe el correo o la matrícula del alumno.', Colors.redAccent);
        return;
      }
      payload['para'] = _para.text.trim();
    } else {
      if (_programa == null || _generacion == null || _grupo == null) {
        _msg('Elige programa, generación y grupo.', Colors.redAccent);
        return;
      }
      payload['programa'] = _programa;
      payload['generacion'] = _generacion;
      payload['grupo'] = _grupo;
    }

    // (24-sep) A un GRUPO: primero a quién le llegaría, y confirmación.
    if (_destino == 'grupo') {
      setState(() => _enviando = true);
      Map<String, dynamic> vp;
      try {
        final r = await http
            .post(Uri.parse(guardianUrl),
                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                body: jsonEncode({...payload, 'soloContar': true}))
            .timeout(const Duration(seconds: 60));
        vp = jsonDecode(r.body) as Map<String, dynamic>;
        if (vp['ok'] != true) throw Exception(vp['error'] ?? 'Error');
      } catch (e) {
        if (mounted) setState(() => _enviando = false);
        _msg('No se pudo preparar la vista previa: $e'.replaceAll('Exception: ', ''), Colors.redAccent);
        return;
      }
      if (!mounted) return;
      setState(() => _enviando = false);
      final total = (vp['total'] as num?)?.toInt() ?? 0;
      final nombres = ((vp['nombres'] as List?) ?? []).map((e) => '$e').toList();
      if (total == 0) {
        _msg('Ese grupo no tiene alumnos a quienes enviar.', cessumGold);
        return;
      }
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Enviar a $total alumno(s)', style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_programa · $_generacion · $_grupo', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Les aparecerá en su buzón de la app. No se envía correo.', style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                for (final n in nombres) Text('• $n', style: const TextStyle(fontSize: 12.5)),
                if (total > nombres.length) Text('… y ${total - nombres.length} más.', style: const TextStyle(fontSize: 12.5)),
                const Divider(height: 18),
                Text(_titulo.text.trim(), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(_mensaje.text.trim(), style: const TextStyle(fontSize: 12.5)),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Enviar a $total'),
            ),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }

    setState(() => _enviando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final enviados = (data['enviados'] ?? 0) as int;
      if (!mounted) return;
      if (enviados == 0) {
        _msg('No se envió ninguna. Revisa el destinatario o el grupo.',
            cessumGold);
      } else {
        _msg('Notificación enviada a $enviados destinatario(s).',
            const Color(0xFF1E8E3E));
        _titulo.clear();
        _mensaje.clear();
        _para.clear();
      }
    } catch (e) {
      _msg('No se pudo enviar: $e'.replaceAll('Exception: ', ''),
          Colors.redAccent);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _msg(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(backgroundColor: c, content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Enviar notificación',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Historial de lo enviado',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const _HistorialNotificaciones())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('¿A quién?',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'alumno', label: Text('Un alumno')),
              ButtonSegment(value: 'grupo', label: Text('Un grupo')),
            ],
            selected: {_destino},
            onSelectionChanged: (s) => setState(() => _destino = s.first),
          ),
          const SizedBox(height: 18),

          if (_destino == 'alumno') ...[
            const Text('Correo o matrícula del alumno',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
            const SizedBox(height: 6),
            TextField(
              controller: _para,
              decoration: const InputDecoration(
                hintText: 'correo@ejemplo.com  o  25090245',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ] else ...[
            if (_cargandoCat)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cessumRed)),
                  SizedBox(width: 10),
                  Text('Cargando grupos...'),
                ]),
              )
            else ...[
              _dropdown('Programa', _programa, _programas, (v) {
                setState(() {
                  _programa = v;
                  _generacion = null;
                  _grupo = null;
                });
              }),
              const SizedBox(height: 12),
              _dropdown('Generación', _generacion, _generaciones, (v) {
                setState(() {
                  _generacion = v;
                  _grupo = null;
                });
              }),
              const SizedBox(height: 12),
              _dropdown('Grupo', _grupo, _grupos,
                  (v) => setState(() => _grupo = v)),
            ],
          ],
          const SizedBox(height: 18),

          const Text('Título',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _titulo,
            decoration: const InputDecoration(
              hintText: 'Ej. Recordatorio de pago',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          const Text('Mensaje',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 6),
          TextField(
            controller: _mensaje,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Escribe aquí el mensaje que verá el alumno...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _enviando ? null : _enviar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_enviando ? 'Enviando...' : 'Enviar notificación'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String etiqueta, String? valor, List<String> opciones,
      ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: valor,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          hint: Text('Selecciona $etiqueta'.toLowerCase()),
          items: opciones
              .map((o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// (24-sep) Historial de lo que enviaron los administradores: fecha, título,
/// a cuántos y cuántos lo leyeron. Un «envío» = mismo título y mismo minuto.
class _HistorialNotificaciones extends StatefulWidget {
  const _HistorialNotificaciones();

  @override
  State<_HistorialNotificaciones> createState() => _HistorialNotificacionesState();
}

class _HistorialNotificacionesState extends State<_HistorialNotificaciones> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _envios = [];

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
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'notificaciones_enviadas'}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        throw Exception(d['sesion'] == 'requerida'
            ? 'Por seguridad, cierre sesión en la app y vuelva a entrar.'
            : (d['error'] ?? 'No se pudo consultar.'));
      }
      _envios = ((d['envios'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _error = '$e'.replaceAll('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Notificaciones enviadas'),
        actions: [IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : _envios.isEmpty
                  ? Center(child: Text('Todavía no hay notificaciones enviadas.', style: TextStyle(color: cessumMuted(context))))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _envios.length,
                      itemBuilder: (c, i) {
                        final e = _envios[i];
                        final dest = (e['destinatarios'] as num?)?.toInt() ?? 0;
                        final leidas = (e['leidas'] as num?)?.toInt() ?? 0;
                        final pct = dest == 0 ? 0.0 : leidas / dest;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(
                                  child: Text('${e['titulo'] ?? ''}',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                                ),
                                Text('${e['fecha'] ?? ''}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                              ]),
                              const SizedBox(height: 4),
                              Text('${e['mensaje'] ?? ''}',
                                  maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                              const SizedBox(height: 8),
                              Row(children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: pct.clamp(0.0, 1.0).toDouble(),
                                      minHeight: 7,
                                      backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
                                      color: const Color(0xFF1E8E3E),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text('Leída por $leidas de $dest',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              ]),
                              if (dest == 1)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text('Para: ${((e['para'] as List?) ?? []).join(', ')}',
                                      style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
    );
  }
}

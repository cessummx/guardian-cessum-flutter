import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Alta de alumnos por lote.
/// El administrador pega la lista (una fila por alumno, columnas separadas por
/// tabulador desde Excel o por coma): matrícula, nombre, correo @cessum.mx,
/// programa, generación, grupo, modalidad y CURP (opcional).
/// Primero hace una VISTA PREVIA (valida sin escribir) y luego EJECUTA el alta
/// en segundo plano (grupos + padrón + bienvenida) mostrando el progreso.
class AltaLoteScreen extends StatefulWidget {
  const AltaLoteScreen({super.key});

  @override
  State<AltaLoteScreen> createState() => _AltaLoteScreenState();
}

class _AltaLoteScreenState extends State<AltaLoteScreen> {
  final TextEditingController _ctrl = TextEditingController();
  bool _enviarBienvenida = true;

  bool _ocupado = false; // previa o iniciar en curso
  bool _ejecutando = false; // job en segundo plano
  String? _aviso;
  bool _avisoError = false;

  // Resumen
  int _total = 0, _daranAlta = 0, _omitidos = 0, _errores = 0, _bienvenidas = 0;
  int _procesados = 0;
  bool _esPrevia = false; // el reporte mostrado es de vista previa
  List<Map<String, dynamic>> _reporte = [];
  Timer? _poll;
  DateTime? _inicioSondeo;   // (5-oct-2026) para avisar si el alta no avanza
  bool _avisoSinAvance = false;

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // ---- parseo de la lista pegada ----
  List<Map<String, String>> _parsear() {
    final filas = <Map<String, String>>[];
    for (final raw in _ctrl.text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      List<String> c =
          line.contains('\t') ? line.split('\t') : line.split(RegExp(r'\s*[;,]\s*'));
      c = c.map((e) => e.trim()).toList();
      if (c.isEmpty || c[0].isEmpty) continue;
      final prim = c[0].toLowerCase();
      if (prim == 'matricula' || prim == 'matrícula') continue; // encabezado
      String at(int i) => i < c.length ? c[i] : '';
      filas.add({
        'matricula': at(0),
        'nombre': at(1),
        'correo': at(2),
        'programa': at(3),
        'generacion': at(4),
        'grupo': at(5),
        'modalidad': at(6),
        'curp': at(7),
      });
    }
    return filas;
  }

  void _msg(String m, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _aviso = m;
      _avisoError = error;
    });
  }

  Future<void> _vistaPrevia() async {
    final filas = _parsear();
    if (filas.isEmpty) {
      _msg('Pega al menos una fila de alumnos.', error: true);
      return;
    }
    setState(() {
      _ocupado = true;
      _aviso = null;
    });
    http.Response? resp;
    try {
      final actor = await SessionStore.realEmail() ?? '';
      resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'alta_lote_previa',
                'actor': actor,
                'enviarBienvenida': _enviarBienvenida,
                'alumnos': filas,
              }))
          .timeout(const Duration(minutes: 3));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _esPrevia = true;
          _total = (data['total'] ?? 0) as int;
          _daranAlta = (data['daranAlta'] ?? 0) as int;
          _omitidos = (data['omitidos'] ?? 0) as int;
          _errores = (data['errores'] ?? 0) as int;
          _bienvenidas = 0;
          _procesados = 0;
          _reporte = ((data['reporte'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
        _msg('Vista previa lista. Revisa el reporte antes de ejecutar.');
      } else {
        _msg('${data['error'] ?? 'No se pudo validar.'}', error: true);
      }
    } catch (e) {
      _msg(_causa(e, resp), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _ejecutar() async {
    final filas = _parsear();
    if (filas.isEmpty) {
      _msg('Pega al menos una fila de alumnos.', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ejecutar alta por lote'),
        content: Text(
          'Se dará de alta a los alumnos válidos en grupos y padrón'
          '${_enviarBienvenida ? ', y se les enviará el correo de bienvenida' : ''}. '
          'Los que ya existan o tengan errores se omiten (los verás en el reporte). '
          '¿Continuar?',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, ejecutar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _ocupado = true;
      _aviso = null;
      _reporte = [];
      _esPrevia = false;
    });
    http.Response? resp;
    try {
      final actor = await SessionStore.realEmail() ?? '';
      resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'alta_lote_iniciar',
                'actor': actor,
                'enviarBienvenida': _enviarBienvenida,
                'alumnos': filas,
              }))
          .timeout(const Duration(minutes: 3));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true && data['iniciado'] == true) {
        setState(() {
          _ejecutando = true;
          _total = (data['total'] ?? filas.length) as int;
          _procesados = 0;
          _altasCero();
        });
        _msg('Alta en proceso… puedes esperar aquí el reporte.');
        _iniciarSondeo();
      } else if (data['yaEjecutando'] == true) {
        _msg('Ya hay un alta por lote en proceso. Espera a que termine.',
            error: true);
      } else {
        _msg('${data['error'] ?? 'No se pudo iniciar.'}', error: true);
      }
    } catch (e) {
      _msg(_causa(e, resp), error: true);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  /// (5-oct-2026) La causa REAL de una falla. Antes todo decía «No me pude conectar», y así no se sabía si el Guardián tardó, si el
  /// proxy cortó o si respondió con un error.
  String _causa(Object e, [http.Response? r]) {
    if (e is TimeoutException) {
      return 'El Guardián tardó más de 3 minutos en responder. Con muchas filas puede pasar: intenta con la mitad de la lista.';
    }
    if (r != null && r.statusCode != 200) {
      return 'El servidor respondió con el código ${r.statusCode}. Intenta de nuevo en un minuto; si se repite, avísame con ese número.';
    }
    if (e is FormatException) {
      final cuerpo = r == null ? '' : r.body.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      return 'El Guardián respondió algo que no es un resultado${cuerpo.isEmpty ? '' : ': «${cuerpo.length > 160 ? '${cuerpo.substring(0, 160)}…' : cuerpo}»'}.';
    }
    final m = '$e'.replaceFirst('Exception: ', '');
    return m.contains('XMLHttpRequest') || m.contains('SocketException') || m.contains('Failed host lookup')
        ? 'No hubo conexión con el servidor. Revisa tu internet e intenta de nuevo.'
        : 'Error: $m';
  }

  void _altasCero() {
    _daranAlta = 0;
    _omitidos = 0;
    _errores = 0;
    _bienvenidas = 0;
  }

  void _iniciarSondeo() {
    _poll?.cancel();
    _inicioSondeo = DateTime.now();
    _avisoSinAvance = false;
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _consultarEstado());
    _consultarEstado();
  }

  Future<void> _consultarEstado() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'alta_lote_estado'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) return;
      final estado = '${data['estado'] ?? ''}';
      setState(() {
        _total = (data['total'] ?? _total) as int;
        _procesados = (data['procesados'] ?? 0) as int;
        _daranAlta = (data['altas'] ?? 0) as int;
        _omitidos = (data['omitidos'] ?? 0) as int;
        _errores = (data['errores'] ?? 0) as int;
        _bienvenidas = (data['bienvenidas'] ?? 0) as int;
        _reporte = ((data['reporte'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
      // (5-oct-2026) Si en 3 minutos no ha procesado ni una fila, se dice en lugar de esperar en silencio.
      if (estado == 'ejecutando' && _procesados == 0 && !_avisoSinAvance && _inicioSondeo != null &&
          DateTime.now().difference(_inicioSondeo!).inMinutes >= 3) {
        _avisoSinAvance = true;
        _msg('El alta no ha avanzado en 3 minutos: el proceso en segundo plano no arrancó. Avísale a Sistemas con la hora en que lo iniciaste.',
            error: true);
      }
      if (estado == 'listo' || estado == 'error') {
        _poll?.cancel();
        setState(() => _ejecutando = false);
        _msg(estado == 'listo'
            ? 'Alta terminada: $_daranAlta altas, $_omitidos omitidos, $_errores errores'
                '${_bienvenidas > 0 ? ', $_bienvenidas bienvenidas' : ''}.'
            : 'El alta terminó con un error. Revisa el reporte.',
            error: estado == 'error');
      }
    } catch (_) {
      // Sondeo silencioso: si falla una vuelta, lo intenta en la siguiente.
    }
  }

  Color _colorEstado(String e) {
    switch (e) {
      case 'alta':
      case 'listo':
        return const Color(0xFF1E8E3E);
      case 'omitido':
        return cessumGold;
      case 'error':
        return cessumRed;
      default:
        return cessumGold;
    }
  }

  IconData _iconoEstado(String e) {
    switch (e) {
      case 'alta':
        return Icons.check_circle;
      case 'listo':
        return Icons.task_alt;
      case 'omitido':
        return Icons.remove_circle_outline;
      case 'error':
        return Icons.error_outline;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final puedeActuar = !_ocupado && !_ejecutando;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Alta de alumnos por lote'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Pega una fila por alumno con estas columnas, en este orden:\n'
            'matrícula · nombre · correo @cessum.mx · programa · generación · '
            'grupo · modalidad · CURP (opcional).',
            style: TextStyle(fontSize: 13, color: cessumMuted(context), height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Tip: cópialas desde Excel (quedan separadas por tabulador). '
            'Si pones una fila de encabezados, se ignora.',
            style: TextStyle(fontSize: 12, color: cessumFaint(context), height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            minLines: 6,
            maxLines: 14,
            enabled: puedeActuar,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            inputFormatters: [LengthLimitingTextInputFormatter(60000)],
            decoration: InputDecoration(
              hintText:
                  '24050301\tAna López Ruiz\tana.lopez@cessum.mx\tMaestría en Educación\t26-2\t1\tNo escolarizada\t',
              border: const OutlineInputBorder(),
              fillColor:
                  cessumEsOscuro(context) ? const Color(0xFF211F1D) : Colors.white,
              filled: true,
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            value: _enviarBienvenida,
            onChanged:
                puedeActuar ? (v) => setState(() => _enviarBienvenida = v ?? true) : null,
            activeColor: cessumRed,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Enviar correo de bienvenida a cada alumno nuevo',
                style: TextStyle(fontSize: 14, color: cessumInk(context))),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: puedeActuar ? _vistaPrevia : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: _ocupado && !_ejecutando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumRed))
                      : const Icon(Icons.fact_check, size: 18),
                  label: const Text('Vista previa'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: puedeActuar ? _ejecutar : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: _ejecutando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.group_add, size: 18),
                  label: Text(_ejecutando ? 'Procesando…' : 'Ejecutar alta'),
                ),
              ),
            ],
          ),
          if (_aviso != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_avisoError ? cessumRed : const Color(0xFF1E8E3E))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_aviso!,
                  style: TextStyle(
                      fontSize: 13,
                      color: _avisoError ? cessumRed : const Color(0xFF1E8E3E),
                      fontWeight: FontWeight.w600)),
            ),
          ],
          if (_ejecutando && _total > 0) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: _total > 0 ? _procesados / _total : null,
              backgroundColor: cessumFaint(context).withValues(alpha: 0.2),
              color: cessumRed,
            ),
            const SizedBox(height: 4),
            Text('Procesados $_procesados de $_total',
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          ],
          if (_reporte.isNotEmpty) ...[
            const SizedBox(height: 16),
            _resumen(),
            const SizedBox(height: 10),
            ..._reporte.map(_fila),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _resumen() {
    final chips = <Widget>[
      _chip(_esPrevia ? 'Darán alta: $_daranAlta' : 'Altas: $_daranAlta',
          const Color(0xFF1E8E3E)),
      _chip('Omitidos: $_omitidos', cessumGold),
      _chip('Errores: $_errores', cessumRed),
    ];
    if (!_esPrevia && _bienvenidas > 0) {
      chips.add(_chip('Bienvenidas: $_bienvenidas', cessumRed));
    }
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _chip(String t, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(t,
          style:
              TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Widget _fila(Map<String, dynamic> r) {
    final estado = '${r['estado'] ?? ''}';
    final c = _colorEstado(estado);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(_iconoEstado(estado), color: c, size: 22),
        title: Text(
          '${r['nombre'] ?? ''}  ·  ${r['matricula'] ?? ''}',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(context)),
        ),
        subtitle: Text(
          '${r['programa'] ?? ''} · ${r['generacion'] ?? ''} · G${r['grupo'] ?? ''}\n'
          '${r['detalle'] ?? ''}',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        isThreeLine: true,
      ),
    );
  }
}

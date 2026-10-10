import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart'; // (24-sep) la de lib/auth: la copia vieja de lib/ ya no la usa nadie
import 'constants.dart';
import 'cargando_venado.dart';
import 'helpers.dart';
import 'cessum_ui.dart';

/// Seguimiento de trámites del alumno: estado de cada solicitud y descarga
/// del documento cuando Vicerrectoría lo genera.
class MisTramitesScreen extends StatefulWidget {
  final String matricula;
  const MisTramitesScreen({super.key, required this.matricula});

  @override
  State<MisTramitesScreen> createState() => _MisTramitesScreenState();
}

class _MisTramitesScreenState extends State<MisTramitesScreen> {
  List<Map<String, dynamic>> _tramites = [];
  bool _cargando = true;
  String? _error;
  int? _generandoFila;
  int? _urgiendoFila;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _cargar();
    // Refresca la cuenta regresiva de entrega cada 30 s.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(
          // (ago-29) Se manda el correo de la sesión: la ruta ya no entrega
          // el historial de trámites de cualquier matrícula que se le pase.
          '$guardianUrl?accion=tramites_de'
          '&matricula=${Uri.encodeComponent(widget.matricula)}'
          '&correo=${Uri.encodeComponent(await SessionStore.validEmail() ?? '')}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _tramites = (data['tramites'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
      _registrarVistos();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus trámites.';
      });
    }
  }

  // Registra el visto en-app de los tramites ya resueltos (Atendido/Rechazado).
  void _registrarVistos() {
    for (final t in _tramites) {
      final estatus = (t['estatus'] ?? '').toString();
      if (!_esAtendido(estatus) && !_esRechazo(estatus)) continue;
      final fila = t['fila'];
      if (fila == null) continue;
      http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({
              'accion': 'visto_app',
              'tipo': 'Trámite',
              'ref': 'T-$fila',
              'quien': widget.matricula,
            }),
          )
          .timeout(const Duration(seconds: 20))
          .catchError((_) => http.Response('', 200));
    }
  }

  // Detecta un rechazo de forma robusta (insensible a mayúsculas/variantes).
  bool _esRechazo(String e) {
    final s = e.toLowerCase();
    return s.contains('rechaz') ||
        s.contains('cancel') ||
        s.contains('negad') ||
        s.contains('denegad') ||
        s.contains('improceden');
  }

  // 'Atendido' y 'Atendida' (boletas) cuentan como atendido.
  bool _esAtendido(String e) => e.toLowerCase().startsWith('atend');

  // ¿El tipo de trámite tiene un documento que la app puede generar?
  // (mismo criterio que tipoDocDeTramite_ en el Guardián.)
  bool _generable(String tipo) {
    final n = tipo.toLowerCase();
    return n.contains('ficha de plan') ||
        n.contains('plan y programa') ||
        n.contains('rvoe') ||
        n.contains('kardex') ||
        n.contains('pasante') ||
        n.contains('terminaci') ||
        n.contains('informe financiero') ||
        n.contains('adeudo') ||
        n.contains('inscrip') ||
        n.contains('certificad') ||
        n.contains('constancia');
  }

  // Genera (bajo demanda) el documento probatorio de un trámite ya atendido
  // que aún no lo tiene, lo liga y permite descargarlo.
  Future<void> _obtenerDoc(int fila) async {
    setState(() => _generandoFila = fila);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              // (ago-29) Se manda el correo de la sesión. El backend ya no
              // acepta generar el documento de otra persona: si quien pide no
              // es administrador, su correo tiene que coincidir con el del
              // trámite. Sin este dato, el alumno no podría bajar el suyo.
              body: jsonEncode({
                'accion': 'tramite_generar_doc',
                'fila': fila,
                'matricula': widget.matricula,
                'correo': await SessionStore.validEmail() ?? '',
              }))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true && (data['pdfUrl'] ?? '').toString().isNotEmpty) {
        await _cargar();
        if (mounted) Helpers.abrirUrlExterna(data['pdfUrl'].toString(), context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text(data['error']?.toString() ??
                'No se pudo generar el documento.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: cessumRed,
            content: Text('No se pudo generar el documento.')));
      }
    } finally {
      if (mounted) setState(() => _generandoFila = null);
    }
  }

  Color _colorPago(String e) {
    switch (e) {
      case 'Validado y emitido':
        return Colors.green;
      case 'Pago en validación':
        return Colors.orange;
      case 'Pendiente de pago':
        return const Color(0xFFC8202F);
      case 'Rechazado':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  Color _colorEstatus(String e) {
    if (_esAtendido(e)) return Colors.green.shade700;
    if (_esRechazo(e)) return cessumRed;
    return cessumGold; // Pendiente
  }

  Future<void> _urgencia(int fila) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _urgiendoFila = fila);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'tramite_urgencia',
        'matricula': widget.matricula,
        'fila': '$fila',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      messenger.showSnackBar(SnackBar(
        content: Text(
            (data['mensaje'] ?? data['error'] ?? 'Listo').toString()),
        backgroundColor:
            data['ok'] == true ? const Color(0xFF1E7D32) : cessumRed,
      ));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No se pudo enviar el recordatorio.')));
    }
    if (mounted) setState(() => _urgiendoFila = null);
  }

  // Milisegundos HÁBILES entre dos instantes (excluye sábado y domingo);
  // durante el fin de semana el conteo queda en pausa.
  int _habilRestanteMs(int fromMs, int toMs) {
    if (toMs <= fromMs) return 0;
    int total = 0;
    DateTime cursor = DateTime.fromMillisecondsSinceEpoch(fromMs);
    final to = DateTime.fromMillisecondsSinceEpoch(toMs);
    while (cursor.isBefore(to)) {
      final nextMid = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final segEnd = nextMid.isBefore(to) ? nextMid : to;
      final dow = cursor.weekday;
      if (dow != 6 && dow != 7) {
        total += segEnd.difference(cursor).inMilliseconds;
      }
      cursor = segEnd;
    }
    return total;
  }

  // Caja de un dígito grande, para el reloj visual (día/horas/minutos).
  Widget _cajaTiempo(String valor, String etiqueta, Color color) {
    return Column(
      children: [
        Container(
          width: 58,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            valor,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(etiqueta,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: cessumMuted(context))),
      ],
    );
  }

  // Cuenta regresiva de 72 h hábiles para la entrega, como reloj grande y
  // visible, con Maaso. Al llegar a 0, en vez de solo avisar que venció,
  // dirige claramente a comunicarse con Atención a Estudiantes.
  Widget _bloqueEntrega(Map<String, dynamic> t, String estatus, int fila) {
    if (_esAtendido(estatus) || _esRechazo(estatus)) {
      return const SizedBox.shrink();
    }
    final limiteMs =
        (t['limiteMs'] is num) ? (t['limiteMs'] as num).toInt() : null;
    if (limiteMs == null) return const SizedBox.shrink();
    final now = DateTime.now().millisecondsSinceEpoch;
    final restante = _habilRestanteMs(now, limiteMs);
    final finde = DateTime.now().weekday >= 6;
    if (now < limiteMs) {
      final d = restante ~/ 86400000;
      final h = (restante % 86400000) ~/ 3600000;
      final m = (restante % 3600000) ~/ 60000;
      final poco = restante < 12 * 3600000;
      final color = poco ? cessumRed : cessumGold;
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset('assets/images/maaso.png',
                    height: 34, fit: BoxFit.contain),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Maaso está trabajando en tu trámite',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _cajaTiempo(d.toString().padLeft(2, '0'), 'DÍAS', color),
                  const SizedBox(width: 8),
                  _cajaTiempo(h.toString().padLeft(2, '0'), 'HORAS', color),
                  const SizedBox(width: 8),
                  _cajaTiempo(m.toString().padLeft(2, '0'), 'MIN', color),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Tiempo hábil restante para tu entrega (plazo de 72 h)'
                '${finde ? ' · en pausa (fin de semana)' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11, color: cessumMuted(context)),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumRed.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/maaso.png',
                  height: 34, fit: BoxFit.contain),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'El plazo de 72 horas hábiles ya venció',
                  style: TextStyle(
                      fontSize: 13,
                      color: cessumRed,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comunícate con Atención a Estudiantes',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: cessumRed),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Toma una captura de pantalla de este trámite y envíala '
                  'junto con tu mensaje, para agilizar tu atención.',
                  style: TextStyle(fontSize: 11.5, height: 1.4),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.phone, size: 15, color: cessumMuted(context)),
                    const SizedBox(width: 6),
                    const Text('642 130 5193',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: (_urgiendoFila == fila || fila <= 0)
                  ? null
                  : () => _urgencia(fila),
              icon: _urgiendoFila == fila
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.notifications_active, size: 18),
              label: Text(_urgiendoFila == fila
                  ? 'Enviando…'
                  : 'Enviar recordatorio de urgencia'),
            ),
          ),
        ],
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
        title: const Text('Mis trámites',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: _cargando
          ? const CargandoVenado()
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _tramites.isEmpty
                  ? const CessumEmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'Aún no tienes trámites',
                      subtitle:
                          'Cuando envíes una solicitud, aquí podrás seguir su estado y descargar tus documentos.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _tramites.length,
                      itemBuilder: (ctx, i) {
                        final t = _tramites[i];
                        final estatus = (t['estatus'] ?? '') as String;
                        final doc = (t['documento'] ?? '') as String;
                        final notas = (t['notas'] ?? '') as String;
                        final tipo = (t['tipo'] ?? '') as String;
                        final tipoLimpio =
                            (t['tipoLimpio'] ?? t['tipo'] ?? '') as String;
                        final costoTexto = (t['costoTexto'] ?? '') as String;
                        final estatusPago = (t['estatusPago'] ?? '') as String;
                        final fila = (t['fila'] is int)
                            ? t['fila'] as int
                            : int.tryParse('${t['fila']}') ?? 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tipoLimpio,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _colorEstatus(estatus)
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        estatus.isEmpty
                                            ? 'Pendiente'
                                            : estatus,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _colorEstatus(estatus),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  (t['fecha'] ?? '') as String,
                                  style: TextStyle(
                                      fontSize: 11, color: cessumFaint(context)),
                                ),
                                _bloqueEntrega(t, estatus, fila),
                                if (estatusPago.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      if (costoTexto.isNotEmpty) ...[
                                        Icon(Icons.payments,
                                            size: 14, color: cessumMuted(context)),
                                        const SizedBox(width: 4),
                                        Text(costoTexto,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(width: 10),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _colorPago(estatusPago)
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(estatusPago,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color:
                                                    _colorPago(estatusPago))),
                                      ),
                                    ],
                                  ),
                                ],
                                if (notas.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: cessumGold.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Nota de CESSUM: $notas',
                                      style: const TextStyle(
                                          fontSize: 12, height: 1.4),
                                    ),
                                  ),
                                ],
                                if (doc.isNotEmpty && !_esRechazo(estatus)) ...[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: cessumGold,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () =>
                                          Helpers.abrirUrlExterna(
                                              doc, context),
                                      icon: const Icon(
                                          Icons.picture_as_pdf,
                                          size: 18),
                                      label: const Text(
                                          'Descargar mi documento (PDF)'),
                                    ),
                                  ),
                                ] else if (doc.isEmpty &&
                                    _esAtendido(estatus) &&
                                    _generable(tipo) &&
                                    fila > 0) ...[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: cessumRed,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: _generandoFila == fila
                                          ? null
                                          : () => _obtenerDoc(fila),
                                      icon: _generandoFila == fila
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white),
                                            )
                                          : const Icon(Icons.download,
                                              size: 18),
                                      label: Text(_generandoFila == fila
                                          ? 'Generando…'
                                          : 'Obtener documento (PDF)'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

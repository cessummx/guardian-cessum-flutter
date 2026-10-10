import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'foto_web_picker.dart';
import 'helpers.dart';
import 'student_profile.dart';
import 'tesis_convenio_screen.dart';
import 'firma_alumno_screen.dart';
import 'respuesta_guardian.dart';

/// Titulación: el alumno presenta su solicitud de obtención de grado y
/// después integra su expediente documental y su pago, todo desde la app.
class TitulacionScreen extends StatefulWidget {
  final StudentProfile perfil;
  final String correo;
  const TitulacionScreen(
      {super.key, required this.perfil, required this.correo});

  @override
  State<TitulacionScreen> createState() => _TitulacionScreenState();
}

class _TitulacionScreenState extends State<TitulacionScreen> {
  Map<String, dynamic>? _exp; // expediente; null = aún sin solicitud
  bool _cargando = true;
  bool _enviando = false;
  String? _error;
  String? _subiendoTipo;
  Map<String, dynamic>? _malla;

  // True solo cuando conocemos el plan y la malla NO está completa.
  bool get _mallaIncompleta =>
      _malla != null &&
      _malla!['conocido'] == true &&
      _malla!['completa'] != true;

  // Programa/generación TITULABLE: si la malla trae el programa ya completado
  // (caso doble programa), gana sobre el del perfil (que es el programa actual).
  String get _progTit {
    final p = (_malla?['programa'] ?? '').toString().trim();
    return p.isNotEmpty ? p : widget.perfil.programa;
  }

  String get _genTit {
    final g = (_malla?['generacion'] ?? '').toString().trim();
    return g.isNotEmpty ? g : widget.perfil.generacion;
  }

  final _telefono = TextEditingController();
  String? _opcion;
  String? _fotoOpcion;
  bool _declara = false;
  bool _tieneFirma = false;
  bool _puedeResolicitar = false;
  // (22-sep) Precio de cada opción para el programa y la generación del alumno.
  Map<String, dynamic>? _precios;

  @override
  void dispose() {
    _telefono.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarFirma();
  }

  Future<void> _cargarFirma() async {
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=firma_alumno_estado&matricula=${Uri.encodeComponent(widget.perfil.matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _tieneFirma = data['tiene'] == true);
    } catch (_) {}
  }

  Widget _firmaSeccion() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: _tieneFirma ? Colors.green : cessumRed),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(_tieneFirma ? Icons.verified : Icons.draw_outlined,
              color: _tieneFirma ? Colors.green : cessumRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _tieneFirma
                  ? 'Firma digital registrada. La solicitud se firmará con ella.'
                  : 'Sube tu firma digital para firmar el documento.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            icon: Icon(_tieneFirma ? Icons.edit : Icons.upload,
                size: 18, color: cessumRed),
            label: Text(_tieneFirma ? 'Cambiar' : 'Subir firma',
                style: const TextStyle(color: cessumRed)),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        FirmaAlumnoScreen(matricula: widget.perfil.matricula)),
              );
              _cargarFirma();
            },
          ),
        ],
      ),
    );
  }

  // (ago-3) Candado reglamentario: Excelencia académica exige NO haber
  // reprobado asignatura alguna (arts. 71-I y 85-II). El backend lo evalúa
  // sobre el historial (reprobatorias y materias marcadas Recursada).
  bool _excelenciaBloqueada = false;
  String _motivoExcelencia = '';

  List<String> get _opciones {
    final esDoctorado =
        _progTit.toLowerCase().contains('doctorado');
    return [
      if (!esDoctorado && !_excelenciaBloqueada) 'Excelencia académica',
      'Producción académica',
      'Tesis',
      'Créditos de nivel superior cursados en CESSUM',
      if (esDoctorado) 'Estancia postdoctoral',
    ];
  }

  // ---------------------------------------------------------------------
  // (22-sep) PRECIO DE TITULACIÓN. Se le pedía al alumno escribir cuánto
  // pagó, pero nunca se le decía cuánto debía depositar. El monto sale de su
  // programa, su generación y su opción (Maestría en Educación: +$1,000 desde
  // la 26-3; demás maestrías: desde la 26-2).
  // ---------------------------------------------------------------------
  static String _miles(num v) {
    final e = v.round().abs().toString(), b = StringBuffer();
    for (var i = 0; i < e.length; i++) {
      if (i > 0 && (e.length - i) % 3 == 0) b.write(',');
      b.write(e[i]);
    }
    return b.toString();
  }

  static String _pesos(num v) => '\$${_miles(v)} MXN';

  static String _claveOpcion(String op) {
    final o = op.toLowerCase();
    if (o.contains('excelencia') || o.contains('promedio')) return 'excelencia';
    if (o.contains('produc')) return 'produccion';
    if (o.contains('tesis')) return 'tesis';
    if (o.contains('crédito') || o.contains('credito')) return 'creditos';
    if (o.contains('estancia') || o.contains('postdoc') || o.contains('posdoc')) {
      return 'estancia';
    }
    return '';
  }

  /// Costo del expediente ya solicitado (lo calcula el Guardián).
  Map<String, dynamic>? get _costoExp {
    final c = _exp?['costoTitulacion'];
    if (c is! Map) return null;
    final m = Map<String, dynamic>.from(c);
    return (m['texto'] ?? '').toString().isEmpty ? null : m;
  }

  /// Costo de una opción, para el formulario de solicitud.
  Map<String, dynamic>? _precioOpcion(String opcion) {
    final p = _precios;
    if (p == null) return null;
    final ops = p['opciones'] is Map
        ? Map<String, dynamic>.from(p['opciones'] as Map)
        : <String, dynamic>{};
    final v = ops[_claveOpcion(opcion)];
    if (v is num && v > 0) {
      return {'monto': v, 'texto': _pesos(v), 'opcionTexto': opcion};
    }
    final min = p['min'], max = p['max'];
    if (min is! num || max is! num) return null;
    return {
      'monto': null,
      'texto':
          'Entre ${_pesos(min).replaceAll(' MXN', '')} y ${_pesos(max)}, según la opción de titulación',
      'opcionTexto': opcion,
    };
  }

  Widget _cajaMonto(Map<String, dynamic> c, {String? titulo}) {
    final monto = c['monto'] as num?;
    final opcion = (c['opcionTexto'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo ?? (monto != null ? 'Monto a depositar' : 'Costo de titulación'),
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: cessumRed)),
          const SizedBox(height: 2),
          Text(monto != null ? _pesos(monto) : (c['texto'] ?? '').toString(),
              style: TextStyle(
                  fontSize: monto != null ? 20 : 13.5,
                  fontWeight: FontWeight.w800)),
          if (opcion.isNotEmpty)
            Text('Titulación por ${opcion[0].toLowerCase()}${opcion.substring(1)}',
                style: const TextStyle(fontSize: 11.5, height: 1.35)),
        ],
      ),
    );
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(
          '$guardianUrl?accion=titulacion_de&matricula=${Uri.encodeComponent(widget.perfil.matricula)}'
          '&programa=${Uri.encodeComponent(widget.perfil.programa)}'
          '&generacion=${Uri.encodeComponent(widget.perfil.generacion)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      final eleg = data['elegibilidad'] is Map
          ? Map<String, dynamic>.from(data['elegibilidad'] as Map)
          : null;
      setState(() {
        _excelenciaBloqueada = eleg?['excelenciaDisponible'] == false;
        _motivoExcelencia = (eleg?['motivo'] ?? '').toString();
        _exp = data['expediente'] == null
            ? null
            : Map<String, dynamic>.from(data['expediente'] as Map);
        // (2-sep) Un expediente RECHAZADO es un trámite cerrado sin título:
        // el backend avisa que se puede volver a solicitar, y la pantalla
        // muestra otra vez el formulario en lugar de dejar al alumno topado.
        _puedeResolicitar = data['puedeResolicitar'] == true;
        _malla = data['malla'] is Map
            ? Map<String, dynamic>.from(data['malla'] as Map)
            : null;
        _precios = data['preciosTitulacion'] is Map
            ? Map<String, dynamic>.from(data['preciosTitulacion'] as Map)
            : null;
        _cargando = false;
      });
      _registrarVisto();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar tu información.';
      });
    }
  }

  // Registra el visto en-app del expediente de titulacion al abrirlo.
  void _registrarVisto() {
    final e = _exp;
    if (e == null) return;
    final folio = (e['folio'] ?? '').toString();
    if (folio.isEmpty) return;
    http
        .post(
          Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode({
            'accion': 'visto_app',
            'tipo': 'Titulación',
            'ref': folio,
            'quien': widget.perfil.matricula,
          }),
        )
        .timeout(const Duration(seconds: 20))
        .catchError((_) => http.Response('', 200));
  }

  Future<void> _solicitar() async {
    if (_opcion == null) {
      _aviso('Selecciona tu opción de obtención de grado.');
      return;
    }
    if (_telefono.text.trim().length < 10) {
      _aviso('Escribe tu teléfono de contacto (10 dígitos).');
      return;
    }
    if (!_declara) {
      _aviso('Marca la declaración para continuar.');
      return;
    }
    if (!_tieneFirma) {
      _aviso('Sube tu firma digital para firmar la solicitud.');
      return;
    }
    setState(() => _enviando = true);
    try {
      final payload = {
        'accion': 'titulacion_solicitar',
        'matricula': widget.perfil.matricula,
        'nombre': widget.perfil.nombreCompleto,
        // El backend toma el nombre y el correo del PADRÓN, no de aquí: este
        // correo queda como contacto oficial del título y no puede venir del
        // navegador. Se sigue enviando solo como respaldo si el padrón no lo
        // tiene, y para identificar quién hace la solicitud.
        'correo': widget.correo,
        'telefono': _telefono.text.trim(),
        'programa': _progTit,
        'generacion': _genTit,
        'opcion': _opcion,
      };
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        final msg = (data['mensaje'] ?? data['error'] ?? 'Error').toString();
        if (!mounted) return;
        setState(() => _enviando = false);
        _aviso(msg);
        if (data['error'] == 'malla_incompleta') _cargar();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text(
            'Solicitud ${data['folio']} enviada. La Dirección la validará en máximo 72 horas hábiles.'),
      ));
      setState(() => _enviando = false);
      _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      _aviso('No se pudo enviar: $e');
    }
  }

  Future<void> _subir(String tipo, String etiqueta) async {
    var cantidad = '';
    var otros = '';
    if (tipo == 'comprobante') {
      final ok = await _dialogoPago((c, o) {
        cantidad = c;
        otros = o;
      });
      if (ok != true) return;
    }
    try {
      final doc = await seleccionarDocumento();
      if (doc == null) return;
      setState(() => _subiendoTipo = tipo);
      final payload = {
        'accion': 'titulacion_documento',
        'matricula': widget.perfil.matricula,
        // (ago-29) Correo de la sesión: sin él, la ruta acepta subir
        // documentos al expediente de cualquier matrícula.
        'correo': widget.correo,
        'tipo': tipo,
        'base64': base64Encode(doc.bytes),
        'mime': doc.mime,
        'nombreArchivo': doc.nombre,
        if (tipo == 'comprobante') 'cantidad': cantidad,
        if (tipo == 'comprobante') 'otros': otros,
      };
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 180));
      // (ago-9) Antes esto reventaba con "FormatException: Unexpected token
      // '<'" cuando el servidor contestaba una página de error. A un
      // administrador le molesta; a un alumno subiendo los papeles de su
      // título lo hace abandonar el trámite y llamar por teléfono.
      final r = leerRespuesta(resp, accion: 'titulacion_documento');
      if (!mounted) return;
      if (!r.ok) {
        setState(() => _subiendoTipo = null);
        _aviso(r.mensaje);
        if (r.incierto) _cargar();
        return;
      }
      // (25-sep) Revisión automática con IA al subir: si detectó un problema
      // (otro documento, ilegible, nombre distinto, monto o cuenta), se avisa
      // en ese momento para que el alumno lo corrija sin esperar el rechazo.
      final ia = r.datos['ia'] is Map ? Map<String, dynamic>.from(r.datos['ia'] as Map) : null;
      final sugIa = '${ia?['sugerencia'] ?? ''}';
      final hallIa = ((ia?['hallazgos'] as List?) ?? []).map((e) => '$e').toList();
      setState(() => _subiendoTipo = null);
      if (ia != null && sugIa != 'Aprobado' && hallIa.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(children: [
              Icon(sugIa == 'Rechazado' ? Icons.report_problem : Icons.info_outline,
                  color: sugIa == 'Rechazado' ? cessumRed : cessumGold),
              const SizedBox(width: 8),
              const Expanded(child: Text('Revisa tu archivo', style: TextStyle(fontSize: 17))),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Subimos tu $etiqueta, pero la revisión automática detectó:',
                  style: const TextStyle(fontSize: 13.5, height: 1.4)),
              const SizedBox(height: 8),
              for (final h in hallIa)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $h', style: const TextStyle(fontSize: 13.5, height: 1.4)),
                ),
              const SizedBox(height: 8),
              const Text(
                  'Si te equivocaste de archivo, vuelve a subirlo. Si es correcto, no hagas nada: Control Escolar lo revisará.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: Colors.black54)),
            ]),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('$etiqueta subido. Quedó en revisión.'),
        ));
      }
      _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _subiendoTipo = null);
      _aviso('No se pudo subir: $e');
    }
  }

  Future<bool?> _dialogoPago(void Function(String, String) onOk) {
    // (22-sep) El monto que le toca, arriba de los datos bancarios, y la
    // cantidad ya escrita (la puede cambiar si pagó distinto).
    final costo = _costoExp;
    final montoNum = costo?['monto'] as num?;
    final cantCtrl =
        TextEditingController(text: montoNum != null ? _miles(montoNum) : '');
    final otrosCtrl = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registro de pago'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (costo != null) ...[
                _cajaMonto(costo),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _huesoBox,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Datos para tu depósito o transferencia:\n'
                  '• A nombre de: CESSUM\n'
                  '• Concepto: Titulación + tu nombre\n'
                  '• Cuenta BBVA: 0120887013\n'
                  '• CLABE: 012777001208870132',
                  style: TextStyle(fontSize: 12, height: 1.45),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cantCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Cantidad pagada (MXN) *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: otrosCtrl,
                decoration: const InputDecoration(
                  labelText: 'Otros (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (cantCtrl.text.trim().isEmpty) return;
              onOk(cantCtrl.text.trim(), otrosCtrl.text.trim());
              Navigator.pop(ctx, true);
            },
            child: const Text('Continuar y elegir archivo'),
          ),
        ],
      ),
    );
  }

  void _aviso(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.redAccent,
      content: Text(m),
    ));
  }

  Color _colorEtapa(String e) {
    if (e == 'Expediente aprobado') return Colors.green.shade700;
    if (e == 'Rechazada') return cessumRed;
    return cessumGold;
  }

  Color _colorDoc(String e) {
    switch (e) {
      case 'Aprobado':
        return Colors.green.shade700;
      case 'Rechazado':
        return cessumRed;
      case 'En revisión':
        return cessumGold;
      default:
        return cessumIsDark(context) ? Colors.white38 : Colors.black38;
    }
  }

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _fillCampo =>
      cessumIsDark(context) ? const Color(0xFF26241F) : Colors.white;
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoSuave => cessumMuted(context);
  Color get _huesoBox =>
      cessumIsDark(context) ? const Color(0xFF26241F) : const Color(0xFFF5F1E8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Titulación',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar'),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : (_exp == null || _puedeResolicitar)
                  ? (_mallaIncompleta
                      ? _vistaMallaIncompleta()
                      : _formularioSolicitud())
                  : _vistaExpediente(),
    );
  }

  Widget _vistaMallaIncompleta() {
    final m = _malla ?? {};
    final validadas = (m['validadas'] ?? 0).toString();
    final total = (m['totalPlan'] ?? 0).toString();
    final faltan = (m['faltan'] ?? 0).toString();
    final tp = int.tryParse(total) ?? 0;
    final va = int.tryParse(validadas) ?? 0;
    final pct = tp > 0 ? (va / tp).clamp(0.0, 1.0) : 0.0;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_clock, color: cessumGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Aún no puedes titularte',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: cessumIsDark(context)
                                ? Colors.white
                                : Colors.black87)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'El trámite de titulación se habilita cuando completas el '
                '100% de tu malla curricular.',
                style: TextStyle(
                    fontSize: 13.5, height: 1.45, color: cessumMuted(context)),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 10,
                  backgroundColor: Colors.black12,
                  valueColor: const AlwaysStoppedAnimation<Color>(cessumGold),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Llevas $validadas de $total materias validadas · te falta(n) '
                '$faltan.',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cessumIsDark(context) ? Colors.white : Colors.black87),
              ),
              // (ago-29) SE DICE CUÁLES FALTAN, POR NOMBRE.
              // Antes solo decía "te faltan 3" y mandaba al alumno a
              // preguntar. El dato existía —el plan de estudios está en
              // cartas.json— pero nadie lo cruzaba con su historial, así que
              // Control Escolar terminaba haciendo a mano una comparación que
              // el sistema podía hacer sola.
              if ((m['faltantes'] as List<dynamic>? ?? []).isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('Te falta acreditar:',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cessumIsDark(context)
                            ? Colors.white
                            : Colors.black87)),
                const SizedBox(height: 4),
                ...(m['faltantes'] as List<dynamic>).map((x) => Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('·  $x',
                          style: TextStyle(
                              fontSize: 12.8,
                              height: 1.4,
                              color: cessumMuted(context))),
                    )),
              ],
              if ((m['avisoConteo'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('${m['avisoConteo']}',
                      style: const TextStyle(fontSize: 12.5, height: 1.45)),
                ),
              ],
              const SizedBox(height: 14),
              Text(
                'Si ya acreditaste alguna de estas y aún aparece aquí, puede '
                'que falte validar su calificación. Comunícate con Control '
                'Escolar y menciona la materia: así lo resuelven de inmediato.',
                style: TextStyle(
                    fontSize: 12, height: 1.4, color: cessumMuted(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // (2-sep) Aviso del rechazo anterior, con el motivo que escribió Control
  // Escolar. Va arriba del formulario para que el alumno corrija justo eso.
  Widget _avisoRechazo() {
    final motivo = (_exp?['motivoRechazo'] ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.info_outline, color: cessumRed, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('Tu solicitud anterior no procedió',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: cessumRed)),
            ),
          ]),
          if (motivo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(motivo, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 8),
          const Text(
            'Puedes presentar una nueva solicitud aquí mismo. Revisa sobre '
            'todo tu opción de obtención de grado antes de enviarla.',
            style: TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _formularioSolicitud() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_puedeResolicitar) _avisoRechazo(),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
          ),
          child: const Text(
            'Solicitud de Ingreso al Proceso de Obtención de Grado '
            '(Artículo 73 del Reglamento General), dirigida a la Dirección '
            'de la Unidad Académica de Navojoa, Mtra. Maribel Solís '
            'Palomares. La validación se realiza en un plazo máximo de 72 '
            'horas hábiles; te avisaremos por correo y aquí mismo.',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
        const SizedBox(height: 16),
        _dato('Nombre completo', widget.perfil.nombreCompleto),
        _dato('Matrícula', widget.perfil.matricula),
        _dato('Programa cursado', _progTit),
        _dato('Generación', _genTit),
        _dato('Correo electrónico', widget.correo),
        const SizedBox(height: 12),
        TextField(
          controller: _telefono,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: 'Teléfono de contacto *',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: _fillCampo,
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _opcion,
          isExpanded: true,
          hint: const Text('Opción de obtención de grado *'),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: _fillCampo,
            isDense: true,
          ),
          items: _opciones
              .map((o) => DropdownMenuItem(
                  value: o,
                  child: Text(o, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _opcion = v),
        ),
        // (22-sep) El costo de la opción elegida, antes de solicitar.
        if (_opcion != null && _precioOpcion(_opcion!) != null) ...[
          const SizedBox(height: 8),
          _cajaMonto(_precioOpcion(_opcion!)!,
              titulo: 'Costo de titulación con esta opción'),
        ],
        if (_excelenciaBloqueada) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE65100).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFFE65100).withValues(alpha: 0.4)),
            ),
            child: Text(
              'ℹ La opción de Excelencia académica no aparece disponible: '
              '${_motivoExcelencia.isNotEmpty ? _motivoExcelencia : 'existe asignatura no acreditada en evaluación ordinaria (arts. 71-I y 85-II del Reglamento Escolar Institucional).'} '
              'Las demás opciones quedan plenamente disponibles.',
              style: const TextStyle(fontSize: 11.5, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _firmaSeccion(),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _declara,
          activeColor: cessumRed,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Declaro haber cumplido con los requisitos académicos y '
            'administrativos correspondientes, y me comprometo a atender '
            'los procedimientos y lineamientos que establece el reglamento '
            'institucional.',
            style: TextStyle(fontSize: 12.5, height: 1.4),
          ),
          onChanged: (v) => setState(() => _declara = v ?? false),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
            onPressed: _enviando ? null : _solicitar,
            icon: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.school),
            label: Text(_enviando ? 'Enviando...' : 'Presentar solicitud'),
          ),
        ),
      ],
    );
  }

  Widget _dato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(etiqueta,
                style: TextStyle(fontSize: 12, color: _textoSuave)),
          ),
          Expanded(
            child: Text(valor,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _vistaExpediente() {
    final e = _exp!;
    final etapa = (e['etapa'] ?? '') as String;
    final docs = (e['documentos'] as List)
        .map((d) => Map<String, dynamic>.from(d as Map))
        .toList();
    final puedeSubir = etapa == 'Integración de expediente' ||
        etapa == 'Expediente en revisión';
    final obligatorios =
        docs.where((d) => d['obligatorio'] == true).toList();
    final completados = obligatorios.where((d) {
      final u = (d['url'] ?? '') as String;
      final st = (d['estatus'] ?? '') as String;
      return u.isNotEmpty && st != 'Rechazado';
    }).length;
    final totalObl = obligatorios.length;
    final avance = totalObl > 0 ? completados / totalObl : 0.0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Folio ${e['folio']}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _colorEtapa(etapa).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(etapa,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _colorEtapa(etapa))),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${e['programa']} · ${e['generacion']}\nOpción: ${e['opcion']}\nSolicitada el ${e['fecha']}',
                  style: const TextStyle(fontSize: 12.5, height: 1.45),
                ),
                if (((e['notas'] ?? '') as String).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _huesoBox,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Nota de la Dirección: ${e['notas']}',
                        style:
                            const TextStyle(fontSize: 12, height: 1.4)),
                  ),
                ],
                if (((e['solicitudPdf'] ?? '') as String).isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Helpers.abrirUrlExterna(
                          (e['solicitudPdf'] ?? '') as String, context),
                      icon: const Icon(Icons.picture_as_pdf,
                          size: 16, color: cessumGold),
                      label: const Text('Descargar mi solicitud (PDF)',
                          style: TextStyle(
                              color: cessumGold, fontSize: 12.5)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        if ((e['opcion'] ?? '').toString().toLowerCase().contains('tesis'))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumGold,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TesisConvenioScreen(
                      matricula: widget.perfil.matricula,
                      nombre: widget.perfil.nombreCompleto,
                      programa: _progTit,
                      generacion: _genTit,
                      correo: widget.correo,
                      rol: 'alumno',
                    ),
                  ),
                ),
                icon: const Icon(Icons.handshake, size: 18),
                label: const Text('Mi tesis · convenio y seguimiento'),
              ),
            ),
          ),
        if (etapa == 'Solicitud en validación')
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Tu solicitud está en validación por la Dirección (máximo 72 '
              'horas hábiles). Cuando sea aceptada, aquí mismo podrás subir '
              'tus documentos y registrar tu pago.',
              style: TextStyle(
                  fontSize: 12.5, color: _textoSuave, height: 1.5),
            ),
          ),
        if (puedeSubir) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _superficie,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: cessumIsDark(context)
                      ? Colors.white12
                      : const Color(0xFFE8E0CE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Avance de tu expediente',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: cessumRed)),
                    Text('${(avance * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: cessumGold)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: avance,
                    minHeight: 10,
                    backgroundColor: cessumIsDark(context) ? Colors.white12 : const Color(0xFFEDE7D8),
                    valueColor:
                        const AlwaysStoppedAnimation(cessumGold),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$completados de $totalObl documentos obligatorios listos'
                  '${avance >= 1.0 ? ' · ¡Expediente completo!' : ''}',
                  style: TextStyle(fontSize: 12, color: _textoSuave),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              'Expediente documental',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: cessumRed),
            ),
          ),
          ...docs.map((d) {
            final estatus = (d['estatus'] ?? '') as String;
            final url = (d['url'] ?? '') as String;
            final obs = (d['observacion'] ?? '') as String;
            final tipo = (d['tipo'] ?? '') as String;
            final etiqueta = (d['etiqueta'] ?? '') as String;
            final oblig = d['obligatorio'] == true;
            final subiendo = _subiendoTipo == tipo;
            /// (8-sep) UN DOCUMENTO EN REVISIÓN SIGUE SIENDO DEL ALUMNO.
            /// El candado exigía el estatus formal «Rechazado» para dejar
            /// reemplazar. Pero Control Escolar tarda en dictaminar, y
            /// mientras tanto todo queda «En revisión»: quien subía el archivo
            /// equivocado y lo notaba enseguida no tenía cómo corregirlo, y su
            /// única salida era abrir una incidencia. Es el mismo candado que
            /// bloqueó las fotografías de Alejandra Ojeda, aquí multiplicado
            /// por los siete documentos obligatorios.
            /// Deja de poder cuando la institución lo acepta, no antes. Es el
            /// mismo criterio que ya usaba la pantalla del expediente previo.
            final estN = estatus.toLowerCase();
            final yaAceptado = estN.contains('acept') ||
                estN.contains('valid') ||
                estN.contains('aprob');
            final puedeEste = url.isEmpty || !yaAceptado;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            etiqueta + (oblig ? ' *' : ' (opcional)'),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            url.isEmpty
                                ? 'Sin subir'
                                : estatus +
                                    (obs.isNotEmpty ? ' · $obs' : ''),
                            style: TextStyle(
                                fontSize: 11.5,
                                color: _colorDoc(
                                    url.isEmpty ? '' : estatus),
                                fontWeight: FontWeight.w600,
                                height: 1.35),
                          ),
                          // (22-sep) Cuánto depositar, junto al comprobante.
                          if (tipo == 'comprobante' && _costoExp != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                  (_costoExp!['monto'] != null
                                          ? 'Monto a depositar: '
                                          : 'Costo: ') +
                                      (_costoExp!['texto'] ?? '').toString(),
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: cessumRed)),
                            ),
                        ],
                      ),
                    ),
                    if (subiendo)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumRed),
                        ),
                      )
                    else if (puedeEste)
                      TextButton.icon(
                        onPressed: () => _subir(tipo, etiqueta),
                        icon: const Icon(Icons.upload_file,
                            size: 17, color: cessumRed),
                        label: Text(
                            url.isEmpty
                                ? 'Subir'
                                : (estatus == 'Rechazado'
                                    ? 'Re-subir'
                                    : 'Reemplazar'),
                            style: const TextStyle(
                                color: cessumRed, fontSize: 12.5)),
                      )
                    else
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 22),
                  ],
                ),
              ),
            );
          }),
          _tarjetaFotos(e),
          const SizedBox(height: 4),
          Text(
            'Formatos aceptados: imagen, PDF o Word (.doc/.docx) (máx. 8 MB). Los documentos '
            'con * son obligatorios; al completarlos, tu expediente pasa '
            'automáticamente a revisión de la Dirección.',
            style: TextStyle(
                fontSize: 11.5, color: _textoSuave, height: 1.45),
          ),
          _avisoEntrega(e),
        ],
      ],
    );
  }

  /// (ago-9) `parte` distingue QUÉ se está subiendo. El backend ya lo aceptaba
  /// desde siempre —'imagen' va a su propia columna, 'pago' y 'guia' a otra—
  /// pero esta pantalla nunca lo mandaba, así que TODO se guardaba como
  /// comprobante de pago. Por eso a los alumnos que eligen impresión en CESSUM
  /// se les rechazaba con "falta subir las fotos" sin tener cómo subirlas:
  /// no existía el botón.
  Future<void> _subirFotos(String opcion, {String parte = ''}) async {
    try {
      final doc = await seleccionarDocumento();
      if (doc == null) return;
      setState(() => _subiendoTipo = 'fotos');
      final payload = {
        'accion': 'titulacion_fotos',
        'matricula': widget.perfil.matricula,
        'correo': widget.correo,
        'opcion': opcion,
        if (parte.isNotEmpty) 'parte': parte,
        'base64': base64Encode(doc.bytes),
        'mime': doc.mime,
        'nombreArchivo': doc.nombre,
      };
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 180));
      final r = leerRespuesta(resp, accion: 'titulacion_fotos');
      if (!mounted) return;
      if (!r.ok) {
        setState(() => _subiendoTipo = null);
        _aviso(r.mensaje);
        if (r.incierto) _cargar();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text(parte == 'imagen'
            ? 'Fotografías recibidas. Quedaron en revisión.'
            : (parte == 'guia'
                ? 'Guía de envío recibida. Quedó en revisión.'
                : 'Comprobante recibido. Quedó en revisión.')),
      ));
      setState(() {
        _subiendoTipo = null;
        // Se conserva la opción elegida: con impresión en CESSUM hay que subir
        // dos archivos, y volver a cero obligaba a re-seleccionar entre carga
        // y carga, con el riesgo de cambiar de opción y borrar lo entregado.
        _fotoOpcion = opcion;
      });
      _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _subiendoTipo = null);
      _aviso('No se pudo registrar: $e');
    }
  }

  // Especificaciones oficiales de las fotografías para el título y datos de
  // entrega (envío por paquetería o impresión en CESSUM).
  void _verEspecificacionesFotos() {
    Widget punto(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: TextStyle(height: 1.4)),
              Expanded(
                child: Text(t,
                    style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
            ],
          ),
        );
    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: cessumRed)),
        );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Especificaciones de las fotografías'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Fotografías mate en blanco y negro:',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              punto('6 ovaladas para título (9 cm × 6 cm)'),
              punto('6 infantiles'),
              titulo('Requisitos'),
              punto('Papel mate, autoadheribles'),
              punto('Saco color claro'),
              punto('Frente despejada'),
              punto('Sin aretes'),
              punto('Maquillaje discreto'),
              titulo('Opción 1 · Las envías tú'),
              const Text(
                'Envíalas por paquetería y adjunta aquí la guía de envío. '
                'Domicilio de entrega:',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F1E7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'CESSUM · Centro de Estudios Superiores del Mayo\n'
                  'Av. Leona Vicario 104, entre No Reelección y Pesqueira,\n'
                  'Col. Juárez, C.P. 85870, Navojoa, Sonora.',
                  style: TextStyle(
                      fontSize: 13, height: 1.45, fontWeight: FontWeight.w600),
                ),
              ),
              titulo('Opción 2 · Las imprimimos en CESSUM'),
              const Text(
                'Nosotros mandamos imprimir tus fotografías con todas las '
                'especificaciones. Cubre el costo de \$500 y adjunta aquí tu '
                'comprobante de pago; no necesitas enviar nada físico.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(color: cessumRed)),
          ),
        ],
      ),
    );
  }

  /// (7-sep) LA TARJETA YA NO SE CIERRA A MEDIO CAMINO.
  /// El candado era `registradas = fotosUrl.isNotEmpty` y
  /// `puede = !registradas || estatus == 'Rechazado'`. Pero `fotosUrl` es la
  /// columna donde caen la GUÍA o el COMPROBANTE, no la fotografía: la foto
  /// del titulado vive aparte, en `fotosUrl2`. Así que al alumno que elegía
  /// impresión en CESSUM y subía primero su comprobante de $500 se le cerraba
  /// todo el bloque de carga, y la tarjeta le decía al mismo tiempo
  /// «Incompleto · Falta la fotografía del titulado» y le quitaba la única
  /// forma de subirla. Es el caso de Alejandra Ojeda.
  /// Ahora se leen LAS DOS piezas, se dice cuál falta, y el bloque sigue
  /// abierto mientras Control Escolar no acepte el requisito —mismo criterio
  /// que ya se aplicó en el expediente de titulación.
  Widget _tarjetaFotos(Map<String, dynamic> e) {
    final opcionG = (e['fotosOpcion'] ?? '') as String;
    final estatus = (e['fotosEstatus'] ?? '') as String;
    final urlPrin = (e['fotosUrl'] ?? '') as String;
    final obs = (e['fotosObs'] ?? '') as String;

    // (8-sep) La fotografía ya vive en su propia columna en el expediente
    // —antes compartía celda con el motivo del rechazo y se pisaban—, pero la
    // guarda se queda: en los expedientes viejos, hasta que corra la
    // migración, ahí puede seguir habiendo texto en vez de un enlace.
    final crudo2 = (e['fotosUrl2'] ?? '') as String;
    final urlFoto = crudo2.startsWith('http') ? crudo2 : '';

    final esImpresion = opcionG == 'impresion';
    final hayAlgo = urlPrin.isNotEmpty || urlFoto.isNotEmpty;
    final completo =
        esImpresion ? (urlPrin.isNotEmpty && urlFoto.isNotEmpty) : urlPrin.isNotEmpty;

    final estN = estatus.toLowerCase();
    final yaAceptado = estN.contains('acept') ||
        estN.contains('valid') ||
        estN.contains('aprob');
    // Mientras no esté aceptado, el requisito sigue siendo del alumno.
    final puede = !yaAceptado;

    // Si ya eligió una opción, queda preseleccionada. Sin esto el radio volvía
    // a cero después de cada carga y bastaba un descuido para cambiar de
    // opción: el backend limpia lo adjuntado al cambiarla, y se perdía el
    // comprobante ya entregado.
    final sel = _fotoOpcion ?? (opcionG.isNotEmpty ? opcionG : null);
    final subiendo = _subiendoTipo == 'fotos';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Fotografías para el título *',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _verEspecificacionesFotos,
                  icon: const Icon(Icons.info_outline,
                      size: 16, color: cessumRed),
                  label: const Text('Ver especificaciones',
                      style: TextStyle(color: cessumRed, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              !hayAlgo
                  ? 'Sin registrar'
                  : (esImpresion
                          ? 'Impresión en CESSUM (\$500)'
                          : 'Enviadas (guía adjunta)') +
                      ' · ' +
                      estatus +
                      (obs.isNotEmpty ? ' · $obs' : ''),
              style: TextStyle(
                  fontSize: 11.5,
                  color: _colorDoc(hayAlgo ? estatus : ''),
                  fontWeight: FontWeight.w600,
                  height: 1.35),
            ),

            // Cada pieza por separado: se ve qué llegó y qué falta.
            if (urlPrin.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Helpers.abrirUrlExterna(urlPrin, context),
                  icon: const Icon(Icons.attach_file,
                      size: 16, color: cessumRed),
                  label: Text(
                      esImpresion
                          ? 'Ver comprobante de pago'
                          : 'Ver guía de envío',
                      style: const TextStyle(color: cessumRed, fontSize: 12)),
                ),
              ),
            if (urlFoto.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Helpers.abrirUrlExterna(urlFoto, context),
                  icon: const Icon(Icons.photo_outlined,
                      size: 16, color: cessumRed),
                  label: const Text('Ver la fotografía adjunta',
                      style: TextStyle(color: cessumRed, fontSize: 12)),
                ),
              ),
            if (esImpresion && hayAlgo && !completo)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFBF6EE),
                    border: Border.all(color: CC.goldBorder),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                    urlFoto.isEmpty
                        ? 'Falta el archivo con tu fotografía. Adjúntalo aquí '
                            'abajo y tu expediente queda completo.'
                        : 'Falta el comprobante del pago de \$500. Adjúntalo '
                            'aquí abajo y tu expediente queda completo.',
                    style: const TextStyle(fontSize: 11.5, height: 1.35)),
              ),

            if (puede) ...[
              const SizedBox(height: 6),
              Text('¿Cómo entregarás tus fotografías físicas?',
                  style: TextStyle(fontSize: 12, color: _textoSuave)),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: 'enviadas',
                groupValue: sel,
                activeColor: cessumRed,
                onChanged: subiendo
                    ? null
                    : (v) => setState(() => _fotoOpcion = v),
                title: const Text('Enviadas (adjunto la guía de envío)',
                    style: TextStyle(fontSize: 12.5)),
                subtitle: const Text(
                  'Envíalas por paquetería a: Av. Leona Vicario 104, entre '
                  'No Reelección y Pesqueira, Col. Juárez, C.P. 85870, '
                  'Navojoa, Sonora. Adjunta aquí tu guía de envío.',
                  style: TextStyle(fontSize: 11, height: 1.35),
                ),
                isThreeLine: true,
              ),
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: 'impresion',
                groupValue: sel,
                activeColor: cessumRed,
                onChanged: subiendo
                    ? null
                    : (v) => setState(() => _fotoOpcion = v),
                title: const Text(
                    'Solicito impresión en CESSUM (adjunto pago \$500)',
                    style: TextStyle(fontSize: 12.5)),
                subtitle: const Text(
                  'Nosotros mandamos imprimir tus fotografías con todas las '
                  'especificaciones. No envías nada físico: solo adjunta aquí '
                  'tu comprobante de pago de \$500.',
                  style: TextStyle(fontSize: 11, height: 1.35),
                ),
                isThreeLine: true,
              ),
              if (hayAlgo && sel != null && sel != opcionG)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFDECEC),
                      border: Border.all(color: cessumRed),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                      'Si cambias de opción se borrará lo que ya adjuntaste y '
                      'tendrás que subirlo otra vez.',
                      style: TextStyle(fontSize: 11.5, height: 1.35)),
                ),
              const SizedBox(height: 4),
              if (sel == 'impresion') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFBF6EE),
                      border: Border.all(color: CC.goldBorder),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text(
                      'Necesitas adjuntar DOS cosas: el archivo con tus '
                      'fotografías (para imprimirlas) y el comprobante del '
                      'pago de \$500. Puedes subirlas en el orden que quieras.',
                      style: TextStyle(fontSize: 11.5, height: 1.35)),
                ),
              ],
              subiendo
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: cessumRed)),
                    )
                  : Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (sel == 'impresion')
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: cessumGold,
                                foregroundColor: Colors.white),
                            onPressed: () =>
                                _subirFotos('impresion', parte: 'imagen'),
                            icon: const Icon(Icons.photo_library_outlined,
                                size: 17),
                            label: Text(
                                urlFoto.isEmpty
                                    ? 'Adjuntar mis fotografías'
                                    : 'Reemplazar mis fotografías',
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: cessumRed,
                              foregroundColor: Colors.white),
                          onPressed: sel == null
                              ? null
                              : () => _subirFotos(sel,
                                  parte:
                                      sel == 'impresion' ? 'pago' : 'guia'),
                          icon: const Icon(Icons.upload_file, size: 17),
                          label: Text(
                              sel == 'impresion'
                                  ? (urlPrin.isEmpty
                                      ? 'Adjuntar comprobante \$500'
                                      : 'Reemplazar comprobante \$500')
                                  : (urlPrin.isEmpty
                                      ? 'Adjuntar guía de envío'
                                      : 'Reemplazar guía de envío'),
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _avisoEntrega(Map<String, dynamic> e) {
    final f = (e['entregaFecha'] ?? '') as String;
    final h = (e['entregaHora'] ?? '') as String;
    final l = (e['entregaLugar'] ?? '') as String;
    if (f.isEmpty && h.isEmpty && l.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumIsDark(context) ? const Color(0xFF14301F) : const Color(0xFFEAF5EC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.celebration, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Entrega oficial de tu título',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: Colors.green)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (f.isNotEmpty)
            Text('Fecha: $f', style: const TextStyle(fontSize: 13)),
          if (h.isNotEmpty)
            Text('Hora: $h', style: const TextStyle(fontSize: 13)),
          if (l.isNotEmpty)
            Text('Lugar: $l', style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

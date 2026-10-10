import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'student_profile.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// Seguimiento de pagos (solo informativo). Separa Reinscripciones de Pagos de
/// materia. Los pagos nuevos llegan como "Por validar" (en gris) y NO suman
/// hasta que el administrador los valida. En modo admin se puede validar,
/// editar, eliminar y revisar el comprobante.
class MiPagosScreen extends StatefulWidget {
  final String? matriculaForzada;
  final String? nombreAlumno;
  const MiPagosScreen({super.key, this.matriculaForzada, this.nombreAlumno, this.embebido = false});
  /// (4-oct-2026) Dentro de «Pagos» (pestañas) va sin barra propia: la pone el contenedor.
  final bool embebido;


  @override
  State<MiPagosScreen> createState() => _MiPagosScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);
const Color _gris = Color(0xFF9E9E9E);

class _MiPagosScreenState extends State<MiPagosScreen> {
  // INTERRUPTOR DE PRIVACIDAD DEL SALDO PARA EL ALUMNO.
  // Mientras esté en false, el alumno NO ve su saldo (solo el admin lo ve).
  // Cuando el Dr. confirme la hoja PlanPagos y capture los ajustes de becas,
  // cambie esta línea a true para mostrar el estado de cuenta al alumno.
  static const bool _mostrarSaldoAlumno = false;

  bool _cargando = true;
  bool _emitiendo = false;
  String? _error;
  String _matricula = '';
  // (29-sep) Solicitud de convenio de pago, iniciada por el alumno.
  Map<String, dynamic>? _miSolicitudConvenio;
  bool _enviandoSolicitud = false;
  String _nombre = '';
  bool _sinBase = false;
  int _porValidar = 0;
  bool _continuidad = false;
  String _programaActual = '';
  String _genDoctorado = '';
  List<Map<String, dynamic>> _pagos = [];
  Map<String, dynamic>? _estadoCuenta;
  List<Map<String, dynamic>> _vencimientos = [];
  /// (4-oct-2026) Lo que no se pudo cargar: se avisa arriba en lugar de esconderlo.
  final List<String> _fallas = [];

  bool get _admin => widget.matriculaForzada != null;
  bool get _verSaldo => _admin || _mostrarSaldoAlumno;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    _fallas.clear();
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      var mat = widget.matriculaForzada?.trim() ?? '';
      if (mat.isEmpty) {
        final perfil = await StudentProfile.load();
        mat = perfil?.matricula.trim() ?? '';
      }
      if (mat.isEmpty) {
        setState(() {
          _cargando = false;
          _error = 'No encontramos tu matrícula en este dispositivo.';
        });
        return;
      }
      _matricula = mat;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pagos_seguimiento_alumno',
        'matricula': mat,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (mounted) {
        setState(() {
          _sinBase = data['sinBase'] == true;
          _porValidar = (data['porValidar'] ?? 0) as int;
          _continuidad = data['continuidad'] == true;
          _programaActual = (data['programaActual'] ?? '').toString();
          _genDoctorado = (data['generacionDoctorado'] ?? '').toString();
          _nombre = (data['nombre'] ?? widget.nombreAlumno ?? '').toString();
          _pagos = (data['pagos'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _cargando = false;
        });
      }
      // Estado de cuenta (solo si se va a mostrar el saldo).
      if (_verSaldo) {
        try {
          final uri2 = Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'pagos_estado_cuenta',
            'matricula': mat,
          });
          final resp2 =
              await http.get(uri2).timeout(const Duration(seconds: 30));
          final data2 = jsonDecode(resp2.body) as Map<String, dynamic>;
          if (data2['ok'] == true) {
            final lista = (data2['alumnos'] as List<dynamic>? ?? []);
            if (lista.isNotEmpty && mounted) {
              setState(() =>
                  _estadoCuenta = Map<String, dynamic>.from(lista.first as Map));
            }
          } else {
            _fallas.add('el estado de cuenta');
          }
        } catch (_) {
          _fallas.add('el estado de cuenta');
        }
        // (29-sep) Vencimientos capturados a mano desde Trámites (p. ej.
        // reinscripción pendiente): mismo candado que el estado de cuenta,
        // para respetar la decisión ya tomada de no mostrarle saldo al
        // alumno hasta que _mostrarSaldoAlumno se active.
        try {
          final uri3 = Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'mis_vencimientos',
            'matricula': mat,
            'correo': await SessionStore.validEmail() ?? '',
          });
          final resp3 =
              await http.get(uri3).timeout(const Duration(seconds: 20));
          final data3 = jsonDecode(resp3.body) as Map<String, dynamic>;
          if (data3['ok'] == true && mounted) {
            setState(() {
              _vencimientos = (data3['pendientes'] as List<dynamic>? ?? [])
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            });
          } else if (data3['ok'] != true) {
            _fallas.add('los pagos pendientes');
          }
        } catch (_) {
          _fallas.add('los pagos pendientes');
        }
        // (29-sep) Si ya tiene una solicitud de convenio de pago en curso,
        // para no dejarlo mandar otra ni mostrar el botón sin necesidad.
        try {
          final uri4 = Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'convenio_solicitud_mia',
            'matricula': mat,
          });
          final resp4 =
              await http.get(uri4).timeout(const Duration(seconds: 20));
          final data4 = jsonDecode(resp4.body) as Map<String, dynamic>;
          if (data4['ok'] == true && mounted) {
            setState(() {
              _miSolicitudConvenio = data4['solicitud'] == null
                  ? null
                  : Map<String, dynamic>.from(data4['solicitud'] as Map);
            });
          } else if (data4['ok'] != true) {
            _fallas.add('tu solicitud de convenio');
          }
        } catch (_) {
          _fallas.add('tu solicitud de convenio');
        }
        if (_fallas.isNotEmpty && mounted) setState(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar tu historial. Revisa tu conexión.';
        });
      }
    }
  }

  bool _esPorValidar(Map<String, dynamic> p) => p['estatus'] == 'Por validar';
  double _montoNum(Map<String, dynamic> p) =>
      double.tryParse((p['monto'] ?? '').toString().replaceAll(
          RegExp(r'[^0-9.]'), '')) ??
      0;

  Future<void> _abrirLink(String url) async {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    try {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el enlace.');
    }
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse('https://wa.me/$whatsappNumero'
        '?text=${Uri.encodeComponent('Hola, tengo una duda sobre mis pagos. '
        'Mi matrícula es $_matricula.')}');
    try {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir WhatsApp.');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _admin ? 'Pagos del alumno' : 'Mi seguimiento de pagos';
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: widget.embebido ? null : AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text(titulo),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _contenido(),
    );
  }

  Widget _contenido() {
    final reins = _pagos.where((p) => p['tipo'] == 'Reinscripción').toList();
    final mats = _pagos.where((p) => p['tipo'] != 'Reinscripción').toList();

    final matVal = mats.where((p) => !_esPorValidar(p)).toList();
    final reinsVal = reins.where((p) => !_esPorValidar(p)).toList();
    final sumaMat = matVal.fold<double>(0, (s, p) => s + _montoNum(p));
    final sumaReins = reinsVal.fold<double>(0, (s, p) => s + _montoNum(p));

    final avisoFallas = _fallas.isEmpty
        ? null
        : Container(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFBF6EE), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFB7791F))),
            child: Row(children: [
              const Icon(Icons.cloud_off, color: Color(0xFFB7791F), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('No se pudo cargar ${_fallas.toSet().join(', ')}. Desliza hacia abajo para reintentar.', style: const TextStyle(fontSize: 12.5))),
            ]),
          );
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (avisoFallas != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: avisoFallas),
          _resumen(matVal.length, sumaMat, reinsVal.length, sumaReins),
          if (_verSaldo && _estadoCuenta != null) ...[
            const SizedBox(height: 12),
            _tarjetaEstadoCuenta(),
          ],
          if (_verSaldo && _vencimientos.isNotEmpty) ...[
            const SizedBox(height: 12),
            _tarjetaVencimientos(),
          ],
          const SizedBox(height: 12),
          _avisoInformativo(),
          const SizedBox(height: 16),
          if (_pagos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                children: [
                  Icon(Icons.receipt_long,
                      color: cessumFaint(context), size: 52),
                  const SizedBox(height: 12),
                  Text(
                    _sinBase
                        ? 'Todavía no se ha generado el historial de pagos.'
                        : 'No encontramos pagos registrados con esta matrícula.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cessumMuted(context), height: 1.4),
                  ),
                ],
              ),
            ),
          if (mats.isNotEmpty || reins.isNotEmpty) ...[
            if (_continuidad) ...[
              _bannerContinuidad(),
              const SizedBox(height: 8),
              ..._seccionesEtapa('Doctorado'),
              ..._seccionesEtapa('Maestría'),
            ] else ...[
              if (mats.isNotEmpty) ...[
                _encabezadoSeccion('Pagos registrados (colegiaturas)',
                    matVal.length, sumaMat, mats.length - matVal.length),
                ...mats.map(_tarjetaPago),
                const SizedBox(height: 8),
              ],
              if (reins.isNotEmpty) ...[
                _encabezadoSeccion('Reinscripciones', reinsVal.length,
                    sumaReins, reins.length - reinsVal.length),
                ...reins.map(_tarjetaPago),
              ],
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Aviso de continuidad maestría -> doctorado.
  Widget _bannerContinuidad() {
    final detalle = [
      if (_programaActual.isNotEmpty) _programaActual,
      if (_genDoctorado.isNotEmpty) 'Gen. $_genDoctorado',
    ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.school, color: cessumGold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Continuaste de maestría a doctorado conservando tu matrícula. '
              'Tus pagos se muestran separados por programa.'
              '${detalle.isEmpty ? '' : '\nPrograma actual: $detalle'}',
              style: TextStyle(
                  fontSize: 13, height: 1.4, color: cessumInk(context)),
            ),
          ),
        ],
      ),
    );
  }

  /// Secciones de pagos de una etapa (Doctorado o Maestría):
  /// colegiaturas y reinscripciones de esa etapa, con sus subtotales.
  List<Widget> _seccionesEtapa(String etapa) {
    final deEtapa =
        _pagos.where((p) => (p['etapa'] ?? '') == etapa).toList();
    if (deEtapa.isEmpty) return [];
    final mats =
        deEtapa.where((p) => p['tipo'] != 'Reinscripción').toList();
    final reins =
        deEtapa.where((p) => p['tipo'] == 'Reinscripción').toList();
    final matVal = mats.where((p) => !_esPorValidar(p)).toList();
    final reinsVal = reins.where((p) => !_esPorValidar(p)).toList();
    final sumaMat = matVal.fold<double>(0, (s, p) => s + _montoNum(p));
    final sumaReins =
        reinsVal.fold<double>(0, (s, p) => s + _montoNum(p));
    final sumaEtapa = sumaMat + sumaReins;
    final esDoc = etapa == 'Doctorado';

    return [
      const SizedBox(height: 10),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: esDoc ? cessumRed : Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(esDoc ? Icons.workspace_premium : Icons.history_edu,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                esDoc ? 'Pagos de Doctorado' : 'Pagos de Maestría',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '\$${sumaEtapa.toStringAsFixed(2)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      if (mats.isNotEmpty) ...[
        _encabezadoSeccion('$etapa · Colegiaturas', matVal.length, sumaMat,
            mats.length - matVal.length),
        ...mats.map(_tarjetaPago),
      ],
      if (reins.isNotEmpty) ...[
        _encabezadoSeccion('$etapa · Reinscripciones', reinsVal.length,
            sumaReins, reins.length - reinsVal.length),
        ...reins.map(_tarjetaPago),
      ],
      const SizedBox(height: 8),
    ];
  }

  Widget _tarjetaEstadoCuenta() {
    final est = _estadoCuenta!;
    final planDef = est['planDefinido'] == true;
    final saldo = (est['saldo'] as num?)?.toDouble();
    final plan = ((est['plan'] ?? 0) as num).toDouble();
    final pagado = ((est['pagado'] ?? 0) as num).toDouble();
    final ajuste = ((est['ajuste'] ?? 0) as num).toDouble();

    if (!planDef || saldo == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: cessumGold, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'El plan de pagos de este programa aún no está configurado. '
                'El estado de cuenta se mostrará en cuanto se defina.',
                style: TextStyle(fontSize: 12.5, color: cessumInk(context)),
              ),
            ),
          ],
        ),
      );
    }

    final cubierto = saldo <= 0;
    final color = cubierto ? const Color(0xFF1E8E3E) : cessumRed;

    Widget fila(String etiqueta, String valor, {bool fuerte = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(etiqueta,
                  style: TextStyle(
                      fontSize: fuerte ? 14 : 12.5,
                      color: fuerte ? Colors.black : Colors.black54,
                      fontWeight: fuerte ? FontWeight.w700 : FontWeight.w400)),
              Text(valor,
                  style: TextStyle(
                      fontSize: fuerte ? 16 : 13,
                      fontWeight: fuerte ? FontWeight.w800 : FontWeight.w600,
                      color: fuerte ? color : Colors.black87)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: color, size: 20),
              const SizedBox(width: 8),
              const Text('Estado de cuenta',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              if (_admin) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('por revisar',
                      style: TextStyle(fontSize: 9.5, color: Colors.black54)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          fila('Plan del programa', '\$${plan.toStringAsFixed(0)}'),
          fila('Pagado', '\$${pagado.toStringAsFixed(0)}'),
          if (ajuste != 0)
            fila('Beca / descuento', '\$${ajuste.toStringAsFixed(0)}'),
          const Divider(height: 18),
          fila(cubierto ? 'Saldo (cubierto)' : 'Saldo pendiente',
              '\$${saldo.abs().toStringAsFixed(0)}',
              fuerte: true),
          const SizedBox(height: 8),
          Text(
            cubierto
                ? '¡Tu plan está cubierto! Si tienes dudas, contáctanos.'
                : 'Este saldo es respecto al total del programa. '
                    'Para detalles, contáctanos.',
            style: const TextStyle(fontSize: 11, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  // (29-sep) Vencimientos capturados a mano desde Trámites (reinscripción,
  // u otro concepto puntual) — distinto del estado de cuenta general: aquí
  // solo aparece lo que Administración registró explícitamente como
  // pendiente, con su fecha límite.
  Widget _tarjetaVencimientos() {
    final hayVencido = _vencimientos.any((v) => (v['estatus'] ?? '') == 'Vencido');
    final color = hayVencido ? cessumRed : cessumGold;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_busy_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              const Text('Pagos pendientes',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ..._vencimientos.map((v) {
            final estatus = (v['estatus'] ?? '').toString();
            final vencido = estatus == 'Vencido';
            final dias = v['diasRestantes'] as int?;
            final cVenc = vencido ? cessumRed : const Color(0xFFB07D12);
            final monto = (v['monto'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(vencido ? Icons.error_outline : Icons.schedule,
                      size: 16, color: cVenc),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${v['concepto']}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                          vencido
                              ? 'Venció el ${v['fechaLimite']}'
                              : 'Vence ${v['fechaLimite']}'
                                  '${dias != null ? (dias == 0 ? ' · hoy' : ' · en $dias día(s)') : ''}',
                          style: TextStyle(fontSize: 11.5, color: cVenc),
                        ),
                      ],
                    ),
                  ),
                  if (monto.isNotEmpty)
                    Text('\$$monto',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: cVenc)),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          const Text(
            'Si ya realizaste este pago, contáctanos para que lo actualicemos.',
            style: TextStyle(fontSize: 11, color: Colors.black45),
          ),
          if (!_admin) ...[
            const Divider(height: 20),
            _bloqueSolicitudConvenio(),
          ],
        ],
      ),
    );
  }

  // (29-sep) Convenio de pago: el alumno pide plazo para ponerse al
  // corriente. Si ya tiene una solicitud en curso, muestra su estado en vez
  // del botón; si fue rechazada, muestra el motivo y permite reintentar.
  Widget _bloqueSolicitudConvenio() {
    final s = _miSolicitudConvenio;
    if (s != null && s['estado'] == 'Pendiente') {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.hourglass_top, size: 18, color: cessumGold),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Ya enviaste una solicitud de convenio de pago — está en revisión. Te avisaremos en cuanto se resuelva.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s != null && s['estado'] == 'Rechazada') ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tu solicitud anterior no se pudo conceder así:',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${s['motivo'] ?? ''}',
                    style: const TextStyle(fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
            onPressed: _enviandoSolicitud ? null : _abrirSolicitudConvenio,
            icon: const Icon(Icons.handshake_outlined, size: 18),
            label: const Text('Solicitar convenio de pago'),
          ),
        ),
      ],
    );
  }

  Future<void> _abrirSolicitudConvenio() async {
    final mensaje = TextEditingController();
    final pagos = TextEditingController(text: '3');
    DateTime fechaInicio = DateTime.now().add(const Duration(days: 7));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Solicitar convenio de pago',
              style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cuéntanos brevemente tu situación — esto nos ayuda a proponerte un plan justo.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: mensaje,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Por ejemplo: esta quincena tuve un gasto imprevisto y necesito unas semanas más…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: pagos.text,
                        decoration: const InputDecoration(
                          labelText: 'En cuántos pagos',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          for (final n in ['1', '2', '3', '4', '5', '6'])
                            DropdownMenuItem(value: n, child: Text(n)),
                        ],
                        onChanged: (v) => setLocal(() => pagos.text = v ?? '3'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final f = await showDatePicker(
                            context: context,
                            initialDate: fechaInicio,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 90)),
                          );
                          if (f != null) setLocal(() => fechaInicio = f);
                        },
                        child: Text(
                            'Desde ${fechaInicio.day}/${fechaInicio.month}/${fechaInicio.year}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                if (mensaje.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Cuéntanos brevemente tu situación.')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _enviandoSolicitud = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'convenio_solicitud_crear',
                'matricula': _matricula,
                'mensaje': mensaje.text.trim(),
                'pagosDeseados': pagos.text,
                'fechaInicioDeseada':
                    '${fechaInicio.year}-${fechaInicio.month.toString().padLeft(2, '0')}-${fechaInicio.day.toString().padLeft(2, '0')}',
              }))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Solicitud enviada. Te avisaremos en cuanto la revisen.'),
        ));
        setState(() {
          _enviandoSolicitud = false;
          _miSolicitudConvenio = {'estado': 'Pendiente'};
        });
      } else {
        throw Exception(data['error'] ?? 'Error');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviandoSolicitud = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text('No se pudo enviar: $e'),
      ));
    }
  }

  Widget _resumen(int totMat, double sumaMat, int totReins, double sumaReins) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cessumRed,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_nombre.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(_nombre,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ),
          Text('Matrícula: $_matricula',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$totMat',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800)),
                    const Text('pagos registrados',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('\$${sumaMat.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Container(width: 1, height: 54, color: Colors.white24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$totReins',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800)),
                    const Text('reinscripciones',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('\$${sumaReins.toStringAsFixed(2)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          if (_porValidar > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$_porValidar pago(s) por validar (aún no suman)',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _avisoInformativo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: cessumGold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Información automatizada',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: cessumInk(context))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Este historial se arma de forma automatizada con los comprobantes '
            'enviados en los formularios de pago, por lo que es MERAMENTE '
            'INFORMATIVO y PUEDE CONTENER ERRORES. No es un comprobante ni un '
            'estado de cuenta oficial.',
            style: TextStyle(fontSize: 12.5, color: cessumInk(context), height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            'Para tener certeza, ingresa a Servicios Académicos y '
            'Administrativos y solicita tu desglose de pagos. Ese desglose '
            'también es informativo y no constituye un comprobante de historial '
            'de pago.',
            style: TextStyle(fontSize: 12.5, color: cessumInk(context), height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _verdeOk,
                side: const BorderSide(color: _verdeOk),
              ),
              onPressed: _whatsapp,
              icon: const Icon(Icons.chat, size: 18),
              label: const Text('¿Dudas? Habla con un asesor (642 130 5193)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezadoSeccion(
      String titulo, int cuenta, double suma, int porValidar) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8, left: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$titulo  ($cuenta)',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context))),
                if (porValidar > 0)
                  Text('$porValidar por validar',
                      style: const TextStyle(fontSize: 11, color: _gris)),
              ],
            ),
          ),
          Text('\$${suma.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cessumRed)),
        ],
      ),
    );
  }

  Widget _tarjetaPago(Map<String, dynamic> p) {
    final porValidar = _esPorValidar(p);
    final fecha = (p['fecha'] ?? '').toString();
    final monto = (p['monto'] ?? '').toString();
    final concepto = (p['concepto'] ?? '').toString();
    final fuente = (p['fuente'] ?? '').toString();
    final comprobante = (p['comprobante'] ?? '').toString();
    final tieneComp = comprobante.contains('http');
    final colorPrincipal = porValidar ? _gris : Colors.black87;
    final colorMonto = porValidar ? _gris : cessumRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: porValidar ? const Color(0xFFF2F2F2) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: porValidar ? _gris.withValues(alpha: 0.4) : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (porValidar ? _gris : _verdeOk).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(porValidar ? Icons.hourglass_empty : Icons.check_circle,
                    color: porValidar ? _gris : _verdeOk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(fecha.isEmpty ? 'Sin fecha' : fecha,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colorPrincipal)),
                        ),
                        if (porValidar) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _gris.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('POR VALIDAR',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF616161))),
                          ),
                        ],
                      ],
                    ),
                    if (concepto.isNotEmpty)
                      Text(concepto,
                          style: TextStyle(
                              fontSize: 12,
                              color: porValidar ? _gris : Colors.black54)),
                    if (fuente.isNotEmpty)
                      Text(fuente,
                          style: TextStyle(
                              fontSize: 11,
                              color: porValidar ? _gris : Colors.black38)),
                  ],
                ),
              ),
              if (monto.isNotEmpty)
                Text(monto.startsWith('\$') ? monto : '\$$monto',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colorMonto)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (tieneComp)
                TextButton.icon(
                  onPressed: () => _abrirLink(comprobante),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      foregroundColor: porValidar ? _gris : cessumRed),
                  icon: const Icon(Icons.attachment, size: 16),
                  label: const Text('Ficha del depósito'),
                ),
              // COMPROBANTE INSTITUCIONAL firmado por la Dirección de
              // Administración y Finanzas. Solo para pagos ya validados: uno
              // "Por validar" todavía no está asentado en los registros.
              if (!porValidar)
                TextButton.icon(
                  onPressed: _emitiendo ? null : () => _comprobante(p),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      foregroundColor: _verdeOk),
                  icon: const Icon(Icons.workspace_premium, size: 16),
                  label: const Text('Comprobante oficial'),
                ),
              if (_admin) ...[
                if (porValidar)
                  TextButton.icon(
                    onPressed: () => _validar(p),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        foregroundColor: _verdeOk),
                    icon: const Icon(Icons.verified, size: 16),
                    label: const Text('Validar'),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _invalidar(p),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        foregroundColor: _gris),
                    icon: const Icon(Icons.remove_done, size: 16),
                    label: const Text('Quitar'),
                  ),
                TextButton.icon(
                  onPressed: () => _editar(p),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6)),
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Editar'),
                ),
                TextButton.icon(
                  onPressed: () => _eliminar(p),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      foregroundColor: cessumRed),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Eliminar'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Pide a la institución el COMPROBANTE OFICIAL de un pago ya validado:
  /// un PDF con el encabezado de CESSUM, folio verificable y la firma de la
  /// Dirección de Administración y Finanzas.
  ///
  /// OJO con la ruta: esta pantalla lee la hoja PagosConsolidado (que se arma
  /// con los formularios de registro de pago), mientras que la pantalla del
  /// administrador lee la hoja Pagos. Son bases distintas y sus números de
  /// fila NO se corresponden, así que aquí va 'comprobante_pago_alumno' y no
  /// 'comprobante_pago'; mandar la fila del consolidado a la ruta del admin
  /// generaría el comprobante de otro pago.
  Future<void> _comprobante(Map<String, dynamic> p) async {
    if (_matricula.isEmpty) {
      _aviso('No encontramos tu matrícula en este dispositivo.');
      return;
    }
    setState(() => _emitiendo = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'comprobante_pago_alumno',
        'matricula': _matricula,
        'fila': '${p['fila']}',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdfUrl'] ?? '').toString();
      final folio = (data['folio'] ?? '').toString();
      // Un ok:true SIN pdfUrl no es un comprobante: es el Guardián
      // respondiendo a una acción que no reconoce (típicamente porque el
      // Code.gs se guardó pero no se publicó). Antes esto pintaba un diálogo
      // de éxito con el botón de descarga apagado, que no explicaba nada.
      if (pdf.isEmpty) {
        throw Exception('El servidor respondió sin comprobante. Falta '
            'publicar la versión nueva del Guardián en Apps Script.');
      }
      if (!mounted) return;
      // Se abre desde un botón del diálogo, no automáticamente: si se llama a
      // launchUrl después de esperar la respuesta, el navegador lo trata como
      // ventana emergente y la bloquea.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Comprobante listo',
              style: TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Tu comprobante quedó emitido con la firma de la Dirección '
                  'de Administración y Finanzas.',
                  style: TextStyle(fontSize: 13, height: 1.35)),
              if (folio.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Folio: $folio',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 10),
              const Text(
                  'Este documento acredita el pago ante la institución. No es '
                  'una factura (CFDI): si la necesitas, pídela a la Dirección '
                  'de Administración y Finanzas antes del cierre del mes.',
                  style: TextStyle(fontSize: 11.5, height: 1.35,
                      color: Colors.black54)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: pdf.isEmpty
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _abrirLink(pdf);
                    },
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Descargar PDF'),
            ),
          ],
        ),
      );
    } catch (e) {
      _aviso('$e'.replaceAll('Exception: ', ''));
    }
    if (mounted) setState(() => _emitiendo = false);
  }

  Future<void> _post(Map<String, dynamic> body, String okMsg) async {
    try {
      // (4-oct-2026) Validar, invalidar, editar y eliminar ahora exigen administrador: se manda quién actúa (correo real,
      // no el de «Ver como»), y la matrícula para que el Guardián compruebe que la fila sigue siendo de este alumno.
      final actor = (await SessionStore.realEmail()) ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({...body, 'actor': actor}))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso(okMsg);
      await _cargar();
    } catch (e) {
      final m = '$e'.replaceFirst('Exception: ', '');
      _aviso(m.isEmpty || m == 'Error' ? 'No se pudo completar la acción.' : 'No se pudo: $m');
    }
  }

  Future<void> _validar(Map<String, dynamic> p) async {
    final comprobante = (p['comprobante'] ?? '').toString();
    final tieneComp = comprobante.contains('http');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Validar pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fecha: ${p['fecha']}'),
            Text('Monto: \$${p['monto']}'),
            if ((p['concepto'] ?? '').toString().isNotEmpty)
              Text('Concepto: ${p['concepto']}'),
            const SizedBox(height: 8),
            if (tieneComp)
              OutlinedButton.icon(
                onPressed: () => _abrirLink(comprobante),
                icon: const Icon(Icons.attachment, size: 16),
                label: const Text('Revisar comprobante'),
              )
            else
              Text('Este pago no tiene comprobante adjunto.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            const SizedBox(height: 8),
            Text('Al validar, este pago se sumará al historial del alumno.',
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _verdeOk, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Validar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _post({'accion': 'pago_validar', 'fila': p['fila'], 'matricula': _matricula},
        'Pago validado. Ya suma en el historial.');
  }

  Future<void> _invalidar(Map<String, dynamic> p) async {
    await _post({'accion': 'pago_invalidar', 'fila': p['fila']},
        'Pago marcado como "Por validar".');
  }

  Future<void> _editar(Map<String, dynamic> p) async {
    final cMat = TextEditingController(text: _matricula);
    final cFecha = TextEditingController(text: (p['fecha'] ?? '').toString());
    final cMonto = TextEditingController(
        text: (p['monto'] ?? '').toString().replaceAll('\$', ''));
    final cConcepto =
        TextEditingController(text: (p['concepto'] ?? '').toString());
    final cComp =
        TextEditingController(text: (p['comprobante'] ?? '').toString());
    final guardar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar pago'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _campo('Matrícula', cMat),
              _campo('Fecha (dd/mm/aaaa)', cFecha),
              _campo('Monto', cMonto),
              _campo('Concepto', cConcepto),
              _campo('Link del comprobante', cComp),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (guardar != true) return;
    await _post({
      'accion': 'pago_consolidado_editar',
      'fila': p['fila'],
      'matricula': cMat.text.trim(),
      'nombre': _nombre,
      'fecha': cFecha.text.trim(),
      'monto': cMonto.text.trim(),
      'concepto': cConcepto.text.trim(),
      'comprobante': cComp.text.trim(),
    }, 'Pago actualizado.');
  }

  Future<void> _eliminar(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar pago'),
        content: Text('¿Eliminar el pago del ${p['fecha']} por '
            '\$${p['monto']}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: cessumRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _post({'accion': 'pago_consolidado_eliminar', 'fila': p['fila']},
        'Pago eliminado.');
  }

  Widget _campo(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context), height: 1.4)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

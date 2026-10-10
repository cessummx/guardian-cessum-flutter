// cobranza_screen.dart · CESSUM · (24-sep-2026)
//
// COBRANZA INTELIGENTE · fase 4 de los centros inteligentes.
// Parte del mismo cálculo de bajas por pago (cortes, gracia, pagos por
// validar) y del consolidado de pagos. Ordena los adeudos por urgencia
// (cortes vencidos) y por probabilidad de pago (comportamiento reciente),
// estima lo recuperable, y abre el Centro de comunicaciones prellenado
// con la audiencia «solo con adeudo» y un borrador en el tono de CESSUM:
// el envío siempre pasa por la vista previa con cuántos y quiénes.
// Base: GET cobranza (solo administración).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'centro_comunicaciones_screen.dart';
import 'centros_nav.dart';
import 'cessum_ui.dart';
import 'constants.dart';
import 'expediente_360_screen.dart';

class CobranzaScreen extends StatefulWidget {
  const CobranzaScreen({super.key});

  @override
  State<CobranzaScreen> createState() => _CobranzaScreenState();
}

class _CobranzaScreenState extends State<CobranzaScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  Map<String, dynamic>? _d;
  String _filtro = 'vencidos'; // vencidos | probables | todos
  final _busca = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final r = await http.get(Uri.parse('$guardianUrl?accion=cobranza')).timeout(const Duration(seconds: 240));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo calcular la cobranza.');
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = (m.contains('TimeoutException') || m.contains('ClientException') || m.contains('SocketException'))
            ? 'No se pudo cargar. Revise su conexión e intente de nuevo.'
            : m;
      });
    }
  }

  List<Map<String, dynamic>> get _alumnos => ((_d?['alumnos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  List<Map<String, dynamic>> get _visibles {
    final q = _busca.text.trim().toLowerCase();
    return _alumnos.where((a) {
      if (_filtro == 'vencidos' && (a['cortesVencidos'] as num? ?? 0) == 0) return false;
      if (_filtro == 'probables' && (a['probabilidadPago'] as num? ?? 0) < 60) return false;
      if (q.isNotEmpty && !'${a['nombre']} ${a['matricula']} ${a['programa']}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  String _dinero(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  void _recordatorio() {
    const asunto = 'Recordatorio de pago · CESSUM';
    const mensaje = 'Estimado(a) estudiante:\n\n'
        'Le recordamos que su colegiatura presenta un pago pendiente. Le invitamos a ponerse al corriente para continuar sin contratiempos con sus asignaturas.\n\n'
        'Si ya realizó el pago, suba su comprobante en la app en Pagos → Cuánto debo. Si necesita un acuerdo, escríbanos a contacto@cessum.mx y con gusto lo atendemos.\n\n'
        'Gracias por su confianza.';
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CentroComunicacionesScreen(soloAdeudo: true, asuntoInicial: asunto, mensajeInicial: mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final vis = _visibles;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Cobranza inteligente', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: _d == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              onPressed: _recordatorio,
              icon: const Icon(Icons.mail_outline),
              label: const Text('Recordatorio de pago'),
            ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.payments_outlined, size: 44, color: cessumFaint(context)),
                      const SizedBox(height: 10),
                      Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cessumInk(context))),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    children: [
                      _encabezado(),
                      const SizedBox(height: 12),
                      _cifras(),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'vencidos', label: Text('Cortes vencidos (${_d?['conCortesVencidos'] ?? 0})')),
                          ButtonSegment(value: 'probables', label: Text('Probables (${_d?['probables'] ?? 0})')),
                          ButtonSegment(value: 'todos', label: Text('Todos (${_d?['total'] ?? 0})')),
                        ],
                        selected: {_filtro},
                        onSelectionChanged: (s) => setState(() => _filtro = s.first),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _busca,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre, matrícula o programa…',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          filled: true,
                          fillColor: Theme.of(context).cardColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (vis.isEmpty)
                        Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Nada en esta vista.', style: TextStyle(color: cessumMuted(context))))),
                      for (final a in vis) _fila(a),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(onPressed: () => abrirPantallaCentro(context, 'pagosSeguimiento'), icon: const Icon(Icons.receipt_long_outlined, size: 18), label: const Text('Seguimiento de pagos')),
                        OutlinedButton.icon(onPressed: () => abrirPantallaCentro(context, 'bajasPago'), icon: const Icon(Icons.gavel, size: 18), label: const Text('Bajas por pago')),
                      ]),
                    ],
                  ),
                ),
    );
  }

  Widget _encabezado() {
    final n = (_d?['conCortesVencidos'] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n == 0 ? 'Sin cortes vencidos' : (n == 1 ? '1 alumno con corte vencido' : '$n alumnos con cortes vencidos'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('${_d?['total'] ?? 0} con pagos pendientes · ${_d?['generado'] ?? ''}. Ordenados por urgencia y por probabilidad de pago.', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
      ]),
    );
  }

  Widget _cifras() {
    Widget c(String n, String t, Color col) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).dividerColor)),
            child: Column(children: [
              Text(n, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: col)),
              Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
            ]),
          ),
        );
    final rec = (_d?['recuperableEstimado'] as num?) ?? 0;
    final prom = (_d?['pagoPromedio'] as num?) ?? 0;
    return Column(children: [
      Row(children: [
        c('${_d?['probables'] ?? 0}', 'con alta probabilidad de pagar', _verde),
        const SizedBox(width: 6),
        c(_dinero(rec), 'recuperable estimado', cessumGold),
        const SizedBox(width: 6),
        c(_dinero(prom), 'pago promedio registrado', cessumInk(context)),
      ]),
      const SizedBox(height: 6),
      Text('Estimación: cortes vencidos × pago promedio del consolidado. No sustituye el estado de cuenta de cada alumno.', style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: cessumMuted(context))),
    ]);
  }

  Widget _fila(Map<String, dynamic> a) {
    final prob = (a['probabilidadPago'] as num? ?? 0).toInt();
    final venc = (a['cortesVencidos'] as num? ?? 0).toInt();
    final cUrg = venc >= 2 ? cessumRed : (venc == 1 ? cessumGold : cessumMuted(context));
    final cProb = prob >= 60 ? _verde : (prob >= 40 ? cessumGold : cessumRed);
    final dias = (a['diasDesdeUltimoPago'] as num?)?.toInt();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cUrg.withValues(alpha: 0.45))),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Expediente360Screen(matricula: '${a['matricula']}'))),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: cUrg.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text('$venc', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cUrg))),
        ),
        title: Text('${a['nombre'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context))),
        subtitle: Text(
          [
            '${a['matricula']}',
            if ('${a['programa'] ?? ''}'.isNotEmpty) '${a['programa']}',
            venc > 0 ? '$venc corte(s) vencido(s)' : 'pago pendiente',
            if (dias != null) 'último pago hace $dias días' else 'sin pagos registrados',
            if ((a['porValidar'] as num? ?? 0) > 0) '${a['porValidar']} por validar',
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        trailing: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$prob%', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cProb)),
          Text('prob. de pago', style: TextStyle(fontSize: 9, color: cessumMuted(context))),
        ]),
      ),
    );
  }
}

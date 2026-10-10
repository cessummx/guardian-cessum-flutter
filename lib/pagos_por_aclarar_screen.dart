// ADMIN: Pagos por aclarar — pagos que no se pudieron vincular a un alumno.
//
// (ago-22) SE VOLVIÓ INMANEJABLE POR VOLUMEN, NO POR COMPLEJIDAD.
// Eran 87 tarjetas idénticas en una lista plana, sin buscador, sin filtro y
// sin orden: encontrar un pago concreto era ir bajando con el dedo. Y peor,
// no había forma de ver el bulto — cuánto dinero hay sin identificar, de qué
// meses viene, cuántos traen comprobante — que es lo que dice por dónde
// empezar y qué se puede resolver en tanda.
//
// Esta versión agrega, sobre los MISMOS datos que ya devuelve el Guardián:
//   · buscador por palabras (nombre, matrícula, motivo, fuente, monto, fecha)
//   · filtros por motivo, por comprobante y por si trae nombre
//   · orden por fecha o por monto
//   · panel de cifras: total, suma de dinero, con comprobante, sin nombre
//   · gráfica de barras por mes y reparto por motivo
// No se tocó el backend: todo se calcula en la pantalla.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'alumnos_service.dart';
import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'pagos_auditoria_ia_screen.dart';

class PagosPorAclararScreen extends StatefulWidget {
  const PagosPorAclararScreen({super.key});

  @override
  State<PagosPorAclararScreen> createState() => _PagosPorAclararScreenState();
}

/// Cómo se ordena la lista.
enum _Orden { fechaNueva, fechaVieja, montoAlto, montoBajo }

class _PagosPorAclararScreenState extends State<PagosPorAclararScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _pagos = [];

  final TextEditingController _q = TextEditingController();
  final Set<String> _motivosSel = {};
  // null = todos · true = solo con comprobante · false = solo sin comprobante
  bool? _conComprobante;
  bool _soloSinNombre = false;
  _Orden _orden = _Orden.fechaNueva;
  bool _resumenAbierto = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'pagos_sospechosos_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _pagos = (data['pagos'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) setState(() => _cargando = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar. Revisa tu conexión.';
        });
      }
    }
  }

  // ---------------------------------------------------------------- utilería

  String _norm(String s) {
    s = s.toLowerCase();
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
  }

  /// El monto llega como texto y puede traer signo, comas o espacios.
  double _monto(Map<String, dynamic> p) {
    final t = (p['monto'] ?? '')
        .toString()
        .replaceAll(RegExp(r'[^0-9.\-]'), '')
        .trim();
    return double.tryParse(t) ?? 0;
  }

  /// La fecha viene como dd/MM/yyyy. Si no se puede leer, no se inventa:
  /// devuelve null y esos pagos se agrupan aparte en vez de caer en un mes
  /// cualquiera.
  DateTime? _fecha(Map<String, dynamic> p) {
    final t = (p['fecha'] ?? '').toString().trim();
    final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(t);
    if (m == null) return null;
    final d = int.tryParse(m.group(1)!) ?? 1;
    final mes = int.tryParse(m.group(2)!) ?? 1;
    final a = int.tryParse(m.group(3)!) ?? 2000;
    if (mes < 1 || mes > 12 || d < 1 || d > 31) return null;
    return DateTime(a, mes, d);
  }

  bool _tieneComprobante(Map<String, dynamic> p) =>
      (p['comprobante'] ?? '').toString().contains('http');

  String _motivoDe(Map<String, dynamic> p) {
    final t = (p['motivo'] ?? '').toString().trim();
    return t.isEmpty ? 'Sin motivo' : t;
  }

  String _pesos(double v) {
    final entero = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < entero.length; i++) {
      if (i > 0 && (entero.length - i) % 3 == 0) buf.write(',');
      buf.write(entero[i]);
    }
    return '\$$buf';
  }

  static const List<String> _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];

  // ---------------------------------------------------------------- filtrado

  List<String> get _motivosDisponibles {
    final s = <String>{};
    for (final p in _pagos) {
      s.add(_motivoDe(p));
    }
    final l = s.toList()..sort();
    return l;
  }

  List<Map<String, dynamic>> get _filtrados {
    final palabras = _norm(_q.text.trim())
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final out = _pagos.where((p) {
      if (_motivosSel.isNotEmpty && !_motivosSel.contains(_motivoDe(p))) {
        return false;
      }
      if (_conComprobante != null && _tieneComprobante(p) != _conComprobante) {
        return false;
      }
      if (_soloSinNombre && (p['nombre'] ?? '').toString().trim().isNotEmpty) {
        return false;
      }
      if (palabras.isEmpty) return true;
      final heno = _norm([
        p['matricula'],
        p['nombre'],
        p['fecha'],
        p['monto'],
        p['motivo'],
        p['fuente'],
      ].map((e) => (e ?? '').toString()).join(' '));
      return palabras.every(heno.contains);
    }).toList();

    out.sort((a, b) {
      switch (_orden) {
        case _Orden.montoAlto:
          return _monto(b).compareTo(_monto(a));
        case _Orden.montoBajo:
          return _monto(a).compareTo(_monto(b));
        case _Orden.fechaVieja:
        case _Orden.fechaNueva:
          final fa = _fecha(a), fb = _fecha(b);
          // Los que no traen fecha legible se van al final SIEMPRE: no se
          // premian ni se castigan, simplemente no compiten por el orden.
          if (fa == null && fb == null) return 0;
          if (fa == null) return 1;
          if (fb == null) return -1;
          return _orden == _Orden.fechaNueva
              ? fb.compareTo(fa)
              : fa.compareTo(fb);
      }
    });
    return out;
  }

  bool get _hayFiltro =>
      _q.text.trim().isNotEmpty ||
      _motivosSel.isNotEmpty ||
      _conComprobante != null ||
      _soloSinNombre;

  void _limpiarFiltros() {
    setState(() {
      _q.clear();
      _motivosSel.clear();
      _conComprobante = null;
      _soloSinNombre = false;
    });
  }

  // ---------------------------------------------------------------- acciones

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _abrirLink(String url) async {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http')) u = 'https://$u';
    final uri = Uri.tryParse(u);
    if (uri == null) return;
    try {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el enlace.');
    }
  }

  Future<void> _asignar(Map<String, dynamic> p) async {
    final alumno = await Navigator.push<AlumnoInfo>(
      context,
      MaterialPageRoute(builder: (_) => const _AlumnoPicker()),
    );
    if (alumno == null) return;
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'pago_sospechoso_asignar',
                'fila': p['fila'],
                'matricula': alumno.matricula,
                'nombre': alumno.nombre,
              }))
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso('Pago asignado a ${alumno.nombre}.');
      await _cargar();
    } catch (_) {
      _aviso('No se pudo asignar.');
    }
  }

  /// (24-sep) La IA lee el comprobante y sugiere a qué alumno pertenece
  /// (nombre del ordenante, concepto y matrícula tecleada con error).
  Future<void> _sugerirIa(Map<String, dynamic> p) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'pago_sospechoso_ia', 'fila': '${p['fila']}'}))
          .timeout(const Duration(seconds: 120));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      d = {'ok': false, 'error': 'No se pudo conectar.'};
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (d['ok'] != true) {
      _aviso('${d['error'] ?? 'No se pudo generar la sugerencia.'}');
      return;
    }
    final cands = ((d['candidatos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final lect = Map<String, dynamic>.from((d['lectura'] as Map?) ?? {});
    final elegido = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.auto_awesome, color: cessumGold),
          SizedBox(width: 8),
          Expanded(child: Text('¿De quién es este pago?', style: TextStyle(fontSize: 17))),
        ]),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ('${lect['ordenante'] ?? ''}'.isNotEmpty || '${lect['concepto'] ?? ''}'.isNotEmpty)
                Text('El comprobante dice: ${'${lect['ordenante'] ?? ''}'.isNotEmpty ? 'paga ${lect['ordenante']}' : ''}'
                    '${'${lect['concepto'] ?? ''}'.isNotEmpty ? ' · concepto «${lect['concepto']}»' : ''}',
                    style: const TextStyle(fontSize: 12.5, height: 1.4)),
              const SizedBox(height: 8),
              if (cands.isEmpty)
                Text('${d['nota'] ?? ''}', style: const TextStyle(fontSize: 13))
              else
                for (final c in cands)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text('${c['nombre']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${c['matricula']} · ${c['programa']}\n${c['porque']}',
                          style: const TextStyle(fontSize: 11.5)),
                      isThreeLine: true,
                      trailing: Text(
                        ((c['puntaje'] as num?) ?? 0) >= 0.75 ? 'Alta' : 'Baja',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ((c['puntaje'] as num?) ?? 0) >= 0.75 ? const Color(0xFF1E7F52) : Colors.grey),
                      ),
                      onTap: () => Navigator.pop(ctx, c),
                    ),
                  ),
              const SizedBox(height: 6),
              Text('Toque al alumno para asignarle el pago. Confirme antes: es una sugerencia.',
                  style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
    if (elegido == null || !mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Asignar el pago?'),
        content: Text('Se asignará a ${elegido['nombre']} (${elegido['matricula']}).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Asignar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'pago_sospechoso_asignar',
                'fila': p['fila'],
                'matricula': elegido['matricula'],
                'nombre': elegido['nombre'],
              }))
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso('Pago asignado a ${elegido['nombre']}.');
      await _cargar();
    } catch (_) {
      _aviso('No se pudo asignar.');
    }
  }

  // ------------------------------------------------------------------ pintar

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Pagos por aclarar'),
        actions: [
          // (24-sep) Auditoría de comprobantes con IA.
          IconButton(
            tooltip: 'Auditoría de comprobantes con IA',
            icon: const Icon(Icons.policy_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PagosAuditoriaIaScreen())),
          ),
          PopupMenuButton<_Orden>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _orden = v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: _Orden.fechaNueva, child: Text('Más recientes primero')),
              PopupMenuItem(
                  value: _Orden.fechaVieja, child: Text('Más antiguos primero')),
              PopupMenuItem(
                  value: _Orden.montoAlto, child: Text('Monto mayor primero')),
              PopupMenuItem(
                  value: _Orden.montoBajo, child: Text('Monto menor primero')),
            ],
          ),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: cessumRed,
                              foregroundColor: Colors.white),
                          onPressed: _cargar,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_pagos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No hay pagos por aclarar. Todos quedaron vinculados a una '
            'matrícula válida.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, height: 1.4),
          ),
        ),
      );
    }
    final lista = _filtrados;
    return Column(
      children: [
        _buscador(),
        _chipsFiltro(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: lista.length + 2,
            itemBuilder: (_, i) {
              if (i == 0) return _resumen(lista);
              if (i == 1) return _contador(lista);
              return _tarjeta(lista[i - 2]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buscador() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: TextField(
        controller: _q,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, matrícula, monto, motivo o fecha',
          prefixIcon: const Icon(Icons.search, color: cessumRed),
          suffixIcon: _q.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _q.clear()),
                ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300)),
        ),
      ),
    );
  }

  Widget _chip(String texto, bool activo, VoidCallback onTap,
      {Color? color, int? cuenta}) {
    final c = color ?? cessumRed;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: activo ? c : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: activo ? c : Colors.grey.shade300),
          ),
          child: Text(
            cuenta == null ? texto : '$texto · $cuenta',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: activo ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _chipsFiltro() {
    final motivos = _motivosDisponibles;
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          if (_hayFiltro)
            _chip('Limpiar', false, _limpiarFiltros, color: Colors.black54),
          _chip(
              'Con comprobante',
              _conComprobante == true,
              () => setState(() =>
                  _conComprobante = _conComprobante == true ? null : true),
              cuenta: _pagos.where(_tieneComprobante).length),
          _chip(
              'Sin comprobante',
              _conComprobante == false,
              () => setState(() =>
                  _conComprobante = _conComprobante == false ? null : false),
              color: const Color(0xFFB07D12),
              cuenta: _pagos.where((p) => !_tieneComprobante(p)).length),
          _chip(
              'Sin nombre',
              _soloSinNombre,
              () => setState(() => _soloSinNombre = !_soloSinNombre),
              color: const Color(0xFFB07D12),
              cuenta: _pagos
                  .where((p) => (p['nombre'] ?? '').toString().trim().isEmpty)
                  .length),
          for (final m in motivos)
            _chip(
                m,
                _motivosSel.contains(m),
                () => setState(() {
                      if (!_motivosSel.remove(m)) _motivosSel.add(m);
                    }),
                cuenta: _pagos.where((p) => _motivoDe(p) == m).length),
        ],
      ),
    );
  }

  Widget _contador(List<Map<String, dynamic>> lista) {
    final suma = lista.fold<double>(0, (s, p) => s + _monto(p));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4, top: 4),
      child: Text(
        _hayFiltro
            ? '${lista.length} de ${_pagos.length} pago(s) · ${_pesos(suma)}'
            : '${_pagos.length} pago(s) sin alumno identificado · ${_pesos(suma)}',
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
    );
  }

  // ------------------------------------------------------- panel de cifras

  /// Cuánto dinero hay sin identificar, de qué meses viene y cómo se reparte
  /// por motivo. Es lo que decide por dónde empezar: 87 tarjetas iguales no
  /// dicen nada; "el 60% es de julio y son de una sola fuente" sí.
  Widget _resumen(List<Map<String, dynamic>> lista) {
    final base = _hayFiltro ? lista : _pagos;
    final suma = base.fold<double>(0, (s, p) => s + _monto(p));
    final conComp = base.where(_tieneComprobante).length;
    final sinNombre =
        base.where((p) => (p['nombre'] ?? '').toString().trim().isEmpty).length;
    final sinFecha = base.where((p) => _fecha(p) == null).length;

    // Agrupado por mes, del más viejo al más nuevo.
    final porMes = <String, _Cubo>{};
    for (final p in base) {
      final f = _fecha(p);
      if (f == null) continue;
      final k = '${f.year}-${f.month.toString().padLeft(2, '0')}';
      final c = porMes.putIfAbsent(k, () => _Cubo());
      c.n++;
      c.monto += _monto(p);
    }
    final claves = porMes.keys.toList()..sort();

    // Reparto por motivo.
    final porMotivo = <String, _Cubo>{};
    for (final p in base) {
      final c = porMotivo.putIfAbsent(_motivoDe(p), () => _Cubo());
      c.n++;
      c.monto += _monto(p);
    }
    final motivos = porMotivo.entries.toList()
      ..sort((a, b) => b.value.n.compareTo(a.value.n));

    final maxMes =
        claves.isEmpty ? 1 : claves.map((k) => porMes[k]!.n).reduce((a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _resumenAbierto = !_resumenAbierto),
            child: Row(
              children: [
                const Icon(Icons.insights, size: 18, color: cessumRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      _hayFiltro
                          ? 'Resumen de lo filtrado'
                          : 'Resumen de todo lo pendiente',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800)),
                ),
                Icon(_resumenAbierto ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black45),
              ],
            ),
          ),
          if (_resumenAbierto) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _cifra('Pagos', '${base.length}', cessumRed),
                _cifra('Dinero sin identificar', _pesos(suma), cessumRed),
                _cifra('Con comprobante', '$conComp de ${base.length}',
                    const Color(0xFF1E8E3E)),
                _cifra('Sin nombre', '$sinNombre', const Color(0xFFB07D12)),
              ],
            ),
            if (claves.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('POR MES',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: .6,
                      fontWeight: FontWeight.w800,
                      color: Colors.black45)),
              const SizedBox(height: 8),
              SizedBox(
                height: 108,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final k in claves)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${porMes[k]!.n}',
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black54)),
                              const SizedBox(height: 2),
                              Container(
                                height: 8 +
                                    62 * (porMes[k]!.n / maxMes),
                                decoration: BoxDecoration(
                                  color: cessumRed.withValues(alpha: 0.78),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(_etiquetaMes(k),
                                  style: const TextStyle(
                                      fontSize: 9.5, color: Colors.black45)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (sinFecha > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '$sinFecha pago(s) traen una fecha que no se puede leer y '
                    'no entran en la gráfica.',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFB07D12))),
              ),
            if (motivos.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('POR MOTIVO',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: .6,
                      fontWeight: FontWeight.w800,
                      color: Colors.black45)),
              const SizedBox(height: 8),
              for (final e in motivos.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(e.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12))),
                          Text('${e.value.n}  ·  ${_pesos(e.value.monto)}',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: base.isEmpty ? 0 : e.value.n / base.length,
                          minHeight: 6,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation(cessumGold),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  String _etiquetaMes(String k) {
    final p = k.split('-');
    final m = int.tryParse(p.length > 1 ? p[1] : '') ?? 1;
    final a = p.isNotEmpty ? p[0] : '';
    return '${_meses[(m - 1).clamp(0, 11)]}\n${a.length == 4 ? a.substring(2) : a}';
  }

  Widget _cifra(String etiqueta, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valor,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(etiqueta,
              style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- una tarjeta

  Widget _tarjeta(Map<String, dynamic> p) {
    final comp = (p['comprobante'] ?? '').toString();
    final tieneComp = comp.contains('http');
    final monto = (p['monto'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Matrícula registrada: "${p['matricula']}"',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              if (monto.isNotEmpty)
                Text(monto.startsWith('\$') ? monto : '\$$monto',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
            ],
          ),
          const SizedBox(height: 4),
          if ((p['nombre'] ?? '').toString().isNotEmpty)
            _linea(Icons.person_outline, (p['nombre']).toString()),
          _linea(Icons.event, (p['fecha'] ?? '').toString()),
          _linea(Icons.report_problem_outlined, (p['motivo'] ?? '').toString()),
          if ((p['fuente'] ?? '').toString().isNotEmpty)
            _linea(Icons.source_outlined, (p['fuente']).toString()),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (tieneComp)
                TextButton.icon(
                  onPressed: () => _abrirLink(comp),
                  style: TextButton.styleFrom(foregroundColor: cessumRed),
                  icon: const Icon(Icons.attachment, size: 16),
                  label: const Text('Comprobante'),
                ),
              if (tieneComp)
                TextButton.icon(
                  onPressed: () => _sugerirIa(p),
                  style: TextButton.styleFrom(foregroundColor: cessumGold),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Sugerir alumno'),
                ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => _asignar(p),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Asignar a alumno'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linea(IconData icon, String texto) {
    if (texto.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.black38),
          const SizedBox(width: 8),
          Expanded(
              child: Text(texto,
                  style: const TextStyle(
                      fontSize: 12.5, color: Colors.black54, height: 1.3))),
        ],
      ),
    );
  }
}

/// Acumulador para las gráficas: cuántos pagos y cuánto dinero.
class _Cubo {
  int n = 0;
  double monto = 0;
}

// ===================== SELECTOR DE ALUMNO =====================

class _AlumnoPicker extends StatefulWidget {
  const _AlumnoPicker();

  @override
  State<_AlumnoPicker> createState() => _AlumnoPickerState();
}

class _AlumnoPickerState extends State<_AlumnoPicker> {
  final TextEditingController _busqueda = TextEditingController();
  bool _cargando = true;
  List<AlumnoInfo> _todos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final lista = await AlumnosService.listarAlumnos();
      if (mounted) {
        setState(() {
          _todos = lista;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _norm(String s) {
    s = s.toLowerCase();
    const con = 'áàäâéèëêíìïîóòöôúùüûñ';
    const sin = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s;
  }

  List<AlumnoInfo> get _filtrados {
    final q = _norm(_busqueda.text.trim());
    if (q.isEmpty) return _todos;
    // (ago-22) Mismo criterio que el selector de admin: todas las palabras,
    // en cualquier orden. Buscar "paulina ibarra" no debe fallar porque el
    // padrón traiga un segundo nombre en medio.
    final palabras =
        q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return _todos.where((a) {
      final heno = _norm(
          '${a.nombre} ${a.correo} ${a.matricula} ${a.programa} ${a.generacion}');
      return palabras.every(heno.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Elegir alumno'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _busqueda,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o matrícula',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : lista.isEmpty
                    ? const Center(
                        child: Text('Sin resultados.',
                            style: TextStyle(color: Colors.black54)))
                    : ListView.builder(
                        itemCount: lista.length,
                        itemBuilder: (_, i) {
                          final a = lista[i];
                          return ListTile(
                            title: Text(a.nombre),
                            subtitle: Text(
                                '${a.matricula}  ·  ${a.programa}',
                                style: const TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right,
                                color: cessumRed),
                            onTap: () => Navigator.pop(context, a),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

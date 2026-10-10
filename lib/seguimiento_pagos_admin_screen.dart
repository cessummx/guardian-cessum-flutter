import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'alumnos_service.dart';
import 'mi_pagos_screen.dart';
import 'pagos_por_aclarar_screen.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'helpers.dart';

/// Seguimiento de pagos para administración: cuántos pagos lleva cada alumno
/// y su última fecha, con búsqueda. Lee la base consolidada (solo lectura).
class SeguimientoPagosAdminScreen extends StatefulWidget {
  const SeguimientoPagosAdminScreen({super.key});

  @override
  State<SeguimientoPagosAdminScreen> createState() =>
      _SeguimientoPagosAdminScreenState();
}

class _ResumenAlumno {
  final String matricula;
  final int totalMateria;
  final double sumaMateria;
  final int totalReins;
  final double sumaReins;
  final int porValidar;
  final String ultimaFecha;
  String nombre;
  _ResumenAlumno(this.matricula, this.totalMateria, this.sumaMateria,
      this.totalReins, this.sumaReins, this.porValidar, this.ultimaFecha,
      this.nombre);
}

class _SeguimientoPagosAdminScreenState
    extends State<SeguimientoPagosAdminScreen> {
  static const Color _verde = Color(0xFF1E8E3E);
  final TextEditingController _busqueda = TextEditingController();
  bool _cargando = true;
  bool _reconstruyendo = false;
  String? _error;
  List<_ResumenAlumno> _todos = [];
  Map<String, Map<String, dynamic>> _estado = {};
  String _correoActor = '';

  @override
  void initState() {
    super.initState();
    _cargarActor();
    _cargar();
  }

  Future<void> _cargarActor() async {
    final c = await SessionStore.validEmail();
    if (mounted && c != null) setState(() => _correoActor = c);
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // Nombres por matrícula desde alumnos.json
      final mapaNombres = <String, String>{};
      try {
        final alumnos = await AlumnosService.listarAlumnos();
        for (final a in alumnos) {
          if (a.matricula.trim().isNotEmpty) {
            mapaNombres[a.matricula.trim()] = a.nombre;
          }
        }
      } catch (_) {}

      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'pagos_seguimiento_resumen'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final lista = (data['alumnos'] as List<dynamic>? ?? []).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final mat = (m['matricula'] ?? '').toString();
        final nombrePadron = mapaNombres[mat] ?? '';
        final nombreGuardian = (m['nombre'] ?? '').toString();
        return _ResumenAlumno(
          mat,
          (m['totalMateria'] ?? 0) as int,
          ((m['sumaMateria'] ?? 0) as num).toDouble(),
          (m['totalReinscripcion'] ?? 0) as int,
          ((m['sumaReinscripcion'] ?? 0) as num).toDouble(),
          (m['porValidar'] ?? 0) as int,
          (m['ultimaFecha'] ?? '').toString(),
          nombrePadron.isNotEmpty ? nombrePadron : nombreGuardian,
        );
      }).toList();
      if (mounted) {
        setState(() {
          _todos = lista;
          _cargando = false;
        });
      }
      // Segunda carga: estado de cuenta (plan, pagado, ajuste, saldo).
      // No bloquea la pantalla si falla; el saldo simplemente no se muestra.
      try {
        final uri2 = Uri.parse(guardianUrl)
            .replace(queryParameters: {'accion': 'pagos_estado_cuenta'});
        final resp2 =
            await http.get(uri2).timeout(const Duration(seconds: 40));
        final data2 = jsonDecode(resp2.body) as Map<String, dynamic>;
        if (data2['ok'] == true) {
          final mapa = <String, Map<String, dynamic>>{};
          for (final e in (data2['alumnos'] as List<dynamic>? ?? [])) {
            final m = Map<String, dynamic>.from(e as Map);
            final mat = (m['matricula'] ?? '').toString();
            if (mat.isNotEmpty) mapa[mat] = m;
          }
          if (mounted) setState(() => _estado = mapa);
        }
      } catch (_) {}
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar. Revisa tu conexión.';
        });
      }
    }
  }

  Future<void> _reconstruir() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Actualizar historial'),
        content: const Text(
          'Se leerán de nuevo TODOS los formularios de pago para actualizar el '
          'historial. El proceso corre en segundo plano y puede tardar 1 o 2 '
          'minutos; te aviso cuando termine. ¿Continuar?',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _reconstruyendo = true);
    try {
      // 1) Disparar la reconstrucción en segundo plano (responde de inmediato).
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({'accion': 'pagos_reconstruir_iniciar'}),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      _aviso('Actualizando el historial en segundo plano… (1–2 min)');
      // 2) Sondear el estado hasta que termine.
      await _esperarReconstruccion();
    } catch (e) {
      if (mounted) setState(() => _reconstruyendo = false);
      _aviso('No se pudo iniciar la actualización. Intenta de nuevo.');
    }
  }

  /// Sondea el estado de la reconstrucción cada 8 s, hasta ~3.5 min.
  Future<void> _esperarReconstruccion() async {
    const maxIntentos = 26; // 26 x 8 s ≈ 3.5 min
    for (var i = 0; i < maxIntentos; i++) {
      await Future.delayed(const Duration(seconds: 8));
      if (!mounted) return;
      try {
        final uri = Uri.parse(guardianUrl).replace(
            queryParameters: {'accion': 'pagos_reconstruir_estado'});
        final resp = await http.get(uri).timeout(const Duration(seconds: 30));
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final estado = (data['estado'] ?? '').toString();
        if (estado == 'listo') {
          final validos = data['validos'] ?? 0;
          final sospechosos = data['sospechosos'] ?? 0;
          final fuentes = data['fuentes'] ?? 0;
          if (mounted) setState(() => _reconstruyendo = false);
          _aviso('Historial actualizado: $validos pagos válidos de $fuentes '
              'formularios. $sospechosos en revisión.');
          await _cargar();
          return;
        }
        if (estado == 'error') {
          if (mounted) setState(() => _reconstruyendo = false);
          _aviso('La actualización terminó con un error. '
              'Vuelve a intentarlo en un momento.');
          return;
        }
        // estado == 'ejecutando' -> seguimos esperando.
      } catch (_) {
        // Reintento silencioso en el siguiente ciclo.
      }
    }
    // Si tras el máximo no terminó, no bloqueamos: probablemente ya casi acaba.
    if (mounted) setState(() => _reconstruyendo = false);
    _aviso('Sigue procesando. Recarga en un momento con el botón de refrescar.');
  }

  void _abrirAlumno(_ResumenAlumno a) {
    if (a.porValidar <= 0) {
      _irADetalle(a);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long, color: cessumRed),
              title: const Text('Ver detalle de pagos'),
              onTap: () {
                Navigator.pop(ctx);
                _irADetalle(a);
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified, color: cessumGold),
              title: Text('Validar pagos por validar (${a.porValidar})'),
              onTap: () {
                Navigator.pop(ctx);
                _validarPagosDe(a);
              },
            ),
            // (ago-7) Comprobante institucional (firmado por Finanzas, con
            // QR) para alumnos que no requieren factura.
            ListTile(
              leading:
                  const Icon(Icons.picture_as_pdf, color: cessumRed),
              title: const Text('Comprobantes de pago (PDF)'),
              onTap: () {
                Navigator.pop(ctx);
                _comprobantesDe(a);
              },
            ),
          ],
        ),
      ),
    );
  }

  // (ago-7) Comprobantes de pago: lista TODOS los pagos del alumno y genera
  // el comprobante institucional (membrete, monto, leyenda no-CFDI, firma de
  // Finanzas y QR) por cada uno. El PDF se abre al instante.
  Future<void> _comprobantesDe(_ResumenAlumno a) async {
    List<Map<String, dynamic>> pagos = [];
    try {
      final uri = Uri.parse(guardianUrl).replace(
          queryParameters: {'accion': 'pagos_listar', 'q': a.matricula});
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == false) throw Exception('${d['error'] ?? ''}');
      pagos = ((d['pagos'] as List?) ?? (d['lista'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e) {
      // (4-oct-2026) Antes, una falla se veía como «no tiene pagos registrados».
      if (mounted) _aviso('No se pudieron cargar los pagos de este alumno. Intenta de nuevo.');
      return;
    }
    if (!mounted) return;
    if (pagos.isEmpty) {
      _aviso('Este alumno no tiene pagos registrados.');
      return;
    }
    bool generando = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
              'Comprobantes · ${a.nombre.isEmpty ? a.matricula : a.nombre}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: pagos.map((p) {
                final monto = (p['monto'] ?? 0).toString();
                final fecha = (p['fecha'] ??  '').toString();
                final concepto = (p['concepto'] ?? '').toString();
                final estatus = (p['estatus'] ?? '').toString();
                final rechazado = estatus.toLowerCase().contains('rechaz');
                return Card(
                  child: ListTile(
                    dense: true,
                    title: Text('\$$monto  ·  $fecha'),
                    subtitle: Text([
                      if (concepto.isNotEmpty) concepto,
                      if (estatus.isNotEmpty) estatus,
                    ].join('  ·  ')),
                    trailing: rechazado
                        ? const Text('Rechazado',
                            style: TextStyle(
                                fontSize: 11, color: Colors.red))
                        : TextButton.icon(
                            onPressed: generando
                                ? null
                                : () async {
                                    setLocal(() => generando = true);
                                    try {
                                      final uriC = Uri.parse(guardianUrl)
                                          .replace(queryParameters: {
                                        'accion': 'comprobante_pago',
                                        'fila': '${p['fila'] ?? 0}',
                                        'actor': 'admin',
                                      });
                                      final rc = await http
                                          .get(uriC)
                                          .timeout(const Duration(
                                              seconds: 90));
                                      final dc = jsonDecode(rc.body)
                                          as Map<String, dynamic>;
                                      if (dc['ok'] == true &&
                                          '${dc['pdfUrl'] ?? ''}'
                                              .isNotEmpty) {
                                        Helpers.abrirUrlExterna(
                                            '${dc['pdfUrl']}', context);
                                      } else {
                                        _aviso(
                                            'Error: ${dc['error'] ?? 'sin detalle'}');
                                      }
                                    } catch (e) {
                                      _aviso('Error: $e');
                                    } finally {
                                      setLocal(() => generando = false);
                                    }
                                  },
                            icon: const Icon(Icons.picture_as_pdf,
                                size: 16),
                            label: const Text('PDF',
                                style: TextStyle(fontSize: 12)),
                          ),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
          ],
        ),
      ),
    );
  }

  void _irADetalle(_ResumenAlumno a) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MiPagosScreen(
          matriculaForzada: a.matricula,
          nombreAlumno: a.nombre,
        ),
      ),
    );
  }

  Future<void> _validarPagosDe(_ResumenAlumno a) async {
    /* (4-oct-2026) FALLA GRAVE CORREGIDA. Esto listaba los pagos de la hoja «Pagos» (pagos_listar) y mandaba su número de fila
       a pago_validar, que valida esa fila en OTRA hoja (PagosConsolidado). La fila 15 de una no es la 15 de la otra: se validaba
       el pago de otro alumno y se le mandaba a esa persona un comprobante. Ahora se listan los pagos de la MISMA hoja que se
       valida (pagos_seguimiento_alumno), y la validación lleva la matrícula para que el Guardián compruebe la fila. */
    List<Map<String, dynamic>> pagos = [];
    String? falla;
    try {
      final uri = Uri.parse(guardianUrl).replace(
          queryParameters: {'accion': 'pagos_seguimiento_alumno', 'matricula': a.matricula});
      final r = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        pagos = ((data['pagos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        falla = '${data['error'] ?? 'respuesta inválida'}';
      }
    } catch (e) {
      falla = 'error de conexión';
    }
    if (!mounted) return;
    if (falla != null) {
      _aviso('No se pudieron cargar los pagos de este alumno ($falla). Intenta de nuevo.');
      return;
    }
    final porValidar = pagos
        .where((p) => (p['estatus'] ?? '').toString() == 'Por validar')
        .toList();
    if (porValidar.isEmpty) {
      _aviso('No hay pagos por validar para este alumno.');
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(
              'Validar pagos · ${a.nombre.isEmpty ? a.matricula : a.nombre}'),
          content: SizedBox(
            width: double.maxFinite,
            child: porValidar.isEmpty
                ? const Text('No quedan pagos por validar.')
                : ListView(
                    shrinkWrap: true,
                    children: porValidar.map((p) {
                      final monto = (p['monto'] ?? 0).toString();
                      final fecha = (p['fecha'] ?? '').toString();
                      final concepto = (p['concepto'] ?? '').toString();
                      return Card(
                        child: ListTile(
                          dense: true,
                          title: Text('\$$monto  ·  $fecha'),
                          subtitle: concepto.isEmpty ? null : Text(concepto),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: cessumGold,
                                foregroundColor: Colors.white),
                            onPressed: () async {
                              final okv =
                                  await _validarPagoFila(p['fila'] ?? 0, a.matricula);
                              if (okv) {
                                setLocal(() => porValidar.remove(p));
                                _aviso('Pago validado.');
                              } else {
                                _aviso('No se pudo validar.');
                              }
                            },
                            child: const Text('Validar'),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
          ],
        ),
      ),
    );
    _cargar();
  }

  Future<bool> _validarPagoFila(dynamic fila, String matricula) async {
    try {
      final actor = await SessionStore.validEmail() ?? '';
      final r = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(
                {'accion': 'pago_validar', 'fila': fila, 'actor': actor, 'matricula': matricula}),
          )
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  /// (7-oct-2026) Quita acentos (á/é/í/ó/ú/ü/ñ) antes de comparar. El
  /// buscador del Guardián (pagosListar, usado en Registro de pagos) ya
  /// normaliza así con normTxt_; esta pantalla solo bajaba a minúsculas, así
  /// que buscar "jose" no encontraba a "José" — un alumno con pagos reales
  /// parecía no existir. Caso reportado por Alejandro: el buscador "no
  /// arrojaba nada".
  String _sinAcentos(String s) {
    const mapa = {
      'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
      'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
      'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
      'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
      'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
      'ñ': 'n',
    };
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      buf.write(mapa[ch] ?? ch);
    }
    return buf.toString();
  }

  List<_ResumenAlumno> get _filtrados {
    final q = _sinAcentos(_busqueda.text.trim());
    if (q.isEmpty) return _todos;
    return _todos.where((a) {
      return _sinAcentos(a.matricula).contains(q) ||
          _sinAcentos(a.nombre).contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Seguimiento de pagos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view),
            tooltip: 'Copiar estado de cuenta (Excel)',
            onPressed: (_cargando || _estado.isEmpty) ? null : _copiarEstadoCuenta,
          ),
          IconButton(
            icon: const Icon(Icons.rule),
            tooltip: 'Pagos por aclarar',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PagosPorAclararScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumGold,
        foregroundColor: Colors.white,
        onPressed: _reconstruyendo ? null : _reconstruir,
        icon: _reconstruyendo
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.sync),
        label: Text(_reconstruyendo ? 'Actualizando…' : 'Actualizar historial'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _busqueda,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por matrícula o nombre',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
          ),
          if (_reconstruyendo)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  LinearProgressIndicator(color: cessumRed),
                  SizedBox(height: 4),
                  Text('Leyendo los formularios de pago...',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          Expanded(
            child: _cargando
                ? const Center(
                    child: CircularProgressIndicator(color: cessumRed))
                : _error != null
                    ? _vistaError()
                    : _todos.isEmpty
                        ? _vistaVacia()
                        : _filtrados.isEmpty
                            ? _vistaSinResultados()
                            : RefreshIndicator(
                            color: cessumRed,
                            onRefresh: _cargar,
                            child: ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 90),
                              children: [
                                _barraRecaudacion(),
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 8, left: 2),
                                  child: Text(
                                    '${_filtrados.length} alumno(s) con pagos',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black54),
                                  ),
                                ),
                                ..._filtrados.map(_tarjeta),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _barraRecaudacion() {
    // Totales sobre los alumnos filtrados (datos duros de lo pagado).
    final lista = _filtrados;
    final alumnos = lista.length;
    final recaudado = lista.fold<double>(
        0, (s, a) => s + a.sumaMateria + a.sumaReins);
    final porValidar = lista.fold<int>(0, (s, a) => s + a.porValidar);

    Widget bloque(String valor, String etiqueta, Color color) => Expanded(
          child: Column(
            children: [
              Text(valor,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: color)),
              const SizedBox(height: 2),
              Text(etiqueta,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10.5, color: Colors.black54)),
            ],
          ),
        );

    String dinero(double n) {
      final s = n.toStringAsFixed(0);
      final b = StringBuffer();
      for (int i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
        b.write(s[i]);
      }
      return '\$$b';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumRed.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          bloque('$alumnos', 'alumnos', cessumRed),
          Container(width: 1, height: 34, color: Colors.black12),
          bloque(dinero(recaudado), 'recaudado', _verde),
          Container(width: 1, height: 34, color: Colors.black12),
          bloque('$porValidar', 'por validar',
              porValidar > 0 ? cessumGold : Colors.black45),
        ],
      ),
    );
  }

  Widget _tarjeta(_ResumenAlumno a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: () => _abrirAlumno(a),
            leading: CircleAvatar(
              backgroundColor: cessumRed,
              child: Text('${a.totalMateria}',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            title: Text(
                a.nombre.isEmpty ? 'Matrícula ${a.matricula}' : a.nombre,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Matrícula: ${a.matricula}'
              '${a.totalReins > 0 ? '  ·  ${a.totalReins} reinsc.' : ''}'
              '${a.porValidar > 0 ? '  ·  ${a.porValidar} por validar' : ''}'
              '${a.ultimaFecha.isNotEmpty ? '  ·  últ.: ${a.ultimaFecha}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${a.sumaMateria.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: cessumRed)),
                const Text('colegiaturas',
                    style: TextStyle(fontSize: 10, color: Colors.black45)),
                if (a.sumaReins > 0)
                  Text('+ \$${a.sumaReins.toStringAsFixed(0)} reinsc.',
                      style: const TextStyle(fontSize: 10, color: cessumGold)),
              ],
            ),
          ),
          _franjaSaldo(a),
        ],
      ),
    );
  }

  void _copiarEstadoCuenta() {
    final b = StringBuffer();
    b.writeln('Matricula\tNombre\tPrograma\tModalidad\tGeneracion\t'
        'Plan\tPagado\tAjuste\tSaldo\tPlanDefinido');
    // Recorre los alumnos visibles (mismo orden que la lista filtrada).
    for (final a in _filtrados) {
      final e = _estado[a.matricula];
      final plan = ((e?['plan'] ?? 0) as num).toString();
      final pagado = ((e?['pagado'] ?? 0) as num).toString();
      final ajuste = ((e?['ajuste'] ?? 0) as num).toString();
      final saldoNum = e?['saldo'];
      final saldo = saldoNum == null ? '' : (saldoNum as num).toString();
      final prog = (e?['programa'] ?? '').toString();
      final modal = (e?['modalidad'] ?? '').toString();
      final gen = (e?['generacion'] ?? '').toString();
      final def = e?['planDefinido'] == true ? 'Sí' : 'No';
      b.writeln('${a.matricula}\t${a.nombre}\t$prog\t$modal\t$gen\t'
          '$plan\t$pagado\t$ajuste\t$saldo\t$def');
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Estado de cuenta (${_filtrados.length})');
  }

  Widget _franjaSaldo(_ResumenAlumno a) {
    final est = _estado[a.matricula];
    final planDef = est?['planDefinido'] == true;
    final saldo = (est?['saldo'] as num?)?.toDouble();
    final ajuste = ((est?['ajuste'] ?? 0) as num).toDouble();
    final plan = ((est?['plan'] ?? 0) as num).toDouble();

    Widget izquierda;
    if (est == null) {
      izquierda = const Text('Saldo: —',
          style: TextStyle(fontSize: 12, color: Colors.black38));
    } else if (!planDef || saldo == null) {
      izquierda = const Text('Plan no definido',
          style: TextStyle(
              fontSize: 12,
              color: cessumGold,
              fontWeight: FontWeight.w600));
    } else {
      final color = saldo > 0 ? cessumRed : _verde;
      izquierda = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Saldo: \$${saldo.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color)),
              const SizedBox(width: 6),
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
          ),
          Text(
            'Plan \$${plan.toStringAsFixed(0)}'
            '${ajuste != 0 ? '  ·  ajuste \$${ajuste.toStringAsFixed(0)}' : ''}',
            style: const TextStyle(fontSize: 10.5, color: Colors.black45),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 10),
      child: Row(
        children: [
          Expanded(child: izquierda),
          TextButton.icon(
            onPressed: () => _dialogoAjuste(a),
            style: TextButton.styleFrom(foregroundColor: cessumGold),
            icon: const Icon(Icons.percent, size: 16),
            label: const Text('Ajuste',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _dialogoAjuste(_ResumenAlumno a) async {
    String concepto = 'Beca';
    final montoCtrl = TextEditingController();
    final notaCtrl = TextEditingController();
    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Ajuste para ${a.nombre.isEmpty ? a.matricula : a.nombre}',
              style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Un descuento o beca RESTA al saldo. '
                'Usa monto positivo (ej. 2000).',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: concepto,
                decoration: const InputDecoration(
                    labelText: 'Concepto', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'Beca', child: Text('Beca')),
                  DropdownMenuItem(
                      value: 'Descuento', child: Text('Descuento')),
                  DropdownMenuItem(value: 'Convenio', child: Text('Convenio')),
                  DropdownMenuItem(value: 'Otro', child: Text('Otro')),
                ],
                onChanged: (v) => setLocal(() => concepto = v ?? 'Beca'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: montoCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Monto (\$)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notaCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (guardado != true) return;
    final monto =
        double.tryParse(montoCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (monto == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('El monto no puede ser 0.')));
      }
      return;
    }
    try {
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            body: jsonEncode({
              'accion': 'pagos_ajuste_agregar',
              'matricula': a.matricula,
              'concepto': concepto,
              'monto': monto,
              'nota': notaCtrl.text.trim(),
              'actor': _correoActor,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ajuste registrado.')));
        }
        await _cargar();
      } else {
        throw Exception(data['error'] ?? 'Error');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo registrar el ajuste.')));
      }
    }
  }

  Widget _vistaVacia() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.payments_outlined,
                color: Colors.black26, size: 52),
            const SizedBox(height: 12),
            const Text(
              'Aún no hay historial de pagos.\n'
              'Toca "Actualizar historial" para leer los formularios por '
              'primera vez.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  /// (7-oct-2026) ANTES: si la búsqueda no encontraba a nadie, la pantalla
  /// seguía mostrando "0 alumno(s) con pagos" y una lista en blanco, sin
  /// decir si de verdad no hay nadie con esos datos o si fue la búsqueda la
  /// que falló. Ahora se distingue de _vistaVacia(): ahí no hay historial
  /// en absoluto; aquí SÍ hay historial, solo que la búsqueda no encontró
  /// coincidencias — y se ofrece limpiarla en un toque.
  Widget _vistaSinResultados() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, color: Colors.black26, size: 52),
            const SizedBox(height: 12),
            Text(
              'No encontramos a nadie con "${_busqueda.text.trim()}".',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 4),
            Text(
              'Hay ${_todos.length} alumno(s) en el historial en total — '
              'revisa que la matrícula o el nombre estén bien escritos.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black38, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                _busqueda.clear();
                setState(() {});
              },
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Limpiar búsqueda'),
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
            ),
          ],
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
                style: const TextStyle(color: Colors.black54, height: 1.4)),
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

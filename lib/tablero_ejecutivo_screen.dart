import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

// =====================================================================
// PANTALLA: "Tablero ejecutivo institucional" (RECTORÍA / VICERRECTORÍA)
// ---------------------------------------------------------------------
// Una sola vista con los indicadores clave de toda la institución:
// matrícula, retención, egreso, bajas, riesgo, actividad, carga de
// validación, documentos emitidos y titulación en curso.
//
// CONTRATO (Code.gs -> tablero_ejecutivo):
//   { ok, generado,
//     matricula:{activa,egresados,bajas,total,retencion},
//     porPrograma:[{programa,activos}], porModalidad:{Virtual,Mixta,Otra},
//     riesgo:{alto,medio,bajo},
//     actividad:{activos7,activos30,sinAcceso},
//     academico:{validadas,pendientes},
//     documentos:{total,mes,porTipo:[{tipo,n}]},
//     titulacion:{total,porEtapa:[{etapa,n}]} }
// =====================================================================


class TableroEjecutivoScreen extends StatefulWidget {
  const TableroEjecutivoScreen({super.key});

  @override
  State<TableroEjecutivoScreen> createState() => _TableroEjecutivoScreenState();
}

class _TableroEjecutivoScreenState extends State<TableroEjecutivoScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _d = {};

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
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'tablero_ejecutivo'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _d = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el tablero.';
      });
    }
  }

  int _n(Map m, String k) {
    final v = m[k];
    if (v is num) return v.toInt();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tablero ejecutivo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: cessumRed),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _cargar,
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
                child: const Text('Reintentar',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final mat = (_d['matricula'] as Map?) ?? {};
    final mod = (_d['modalidad_'] as Map?) ?? (_d['porModalidad'] as Map?) ?? {};
    final riesgo = (_d['riesgo'] as Map?) ?? {};
    final act = (_d['actividad'] as Map?) ?? {};
    final acad = (_d['academico'] as Map?) ?? {};
    final docs = (_d['documentos'] as Map?) ?? {};
    final tit = (_d['titulacion'] as Map?) ?? {};
    final prog = ((_d['porPrograma'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final ret = mat['retencion'];
    final retTxt = (ret is num) ? '${ret.toStringAsFixed(1)}%' : '—';

    return RefreshIndicator(
      onRefresh: _cargar,
      color: cessumRed,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (_d['generado'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 2),
              child: Text('Actualizado el ${_d['generado']}',
                  style: TextStyle(fontSize: 12, color: cessumFaint(context))),
            ),

          // KPIs principales
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              _kpi('Matrícula activa', '${_n(mat, 'activa')}',
                  Icons.groups, cessumRed),
              _kpi('Retención', retTxt, Icons.trending_up,
                  Colors.green.shade700),
              _kpi('Egresados', '${_n(mat, 'egresados')}',
                  Icons.school, cessumGold),
              _kpi('Bajas', '${_n(mat, 'bajas')}',
                  Icons.person_off, Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 14),

          // Riesgo
          _seccion('Alerta de riesgo académico', [
            Row(
              children: [
                _segmento('Alto', _n(riesgo, 'alto'), cessumRed),
                _segmento('Medio', _n(riesgo, 'medio'), Colors.orange.shade800),
                _segmento('Estables', _n(riesgo, 'bajo'), Colors.green.shade700),
              ],
            ),
          ]),

          // Actividad
          _seccion('Actividad en la app', [
            Row(
              children: [
                _segmento('Activos 7 d', _n(act, 'activos7'),
                    Colors.green.shade700),
                _segmento('Activos 30 d', _n(act, 'activos30'),
                    Colors.teal.shade600),
                _segmento('Sin ingresar', _n(act, 'sinAcceso'),
                    Colors.blueGrey),
              ],
            ),
          ]),

          // Carga académica
          _seccion('Carga de calificaciones', [
            Row(
              children: [
                _segmento('Validadas', _n(acad, 'validadas'),
                    Colors.green.shade700),
                _segmento('Por validar', _n(acad, 'pendientes'),
                    Colors.orange.shade800),
              ],
            ),
          ]),

          // Modalidad
          _seccion('Matrícula por modalidad', [
            Row(
              children: [
                _segmento('Virtual', _n(mod, 'Virtual'), cessumRed),
                _segmento('Mixta', _n(mod, 'Mixta'), cessumGold),
                if (_n(mod, 'Otra') > 0)
                  _segmento('Otra', _n(mod, 'Otra'), Colors.blueGrey),
              ],
            ),
          ]),

          // Por programa (barras)
          if (prog.isNotEmpty)
            _seccion('Matrícula activa por programa',
                prog.map((p) => _barraPrograma(p, prog)).toList()),

          // Documentos
          _seccion('Documentos emitidos', [
            Row(
              children: [
                _segmento('Histórico', _n(docs, 'total'), cessumGold),
                _segmento('Este mes', _n(docs, 'mes'), cessumRed),
              ],
            ),
            ..._listaConteo((docs['porTipo'] as List?) ?? [], 'tipo'),
          ]),

          // Titulación
          _seccion('Titulación en curso', [
            _segmentoSolo('Trámites activos', _n(tit, 'total'), cessumRed),
            ..._listaConteo((tit['porEtapa'] as List?) ?? [], 'etapa'),
          ]),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ---- Componentes ----

  Widget _kpi(String etiqueta, String valor, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icono, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(valor,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1.05)),
              Text(etiqueta,
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seccion(String titulo, List<Widget> hijos) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...hijos,
        ],
      ),
    );
  }

  Widget _segmento(String etiqueta, int valor, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$valor',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(etiqueta,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          ],
        ),
      ),
    );
  }

  Widget _segmentoSolo(String etiqueta, int valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta,
              style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          Text('$valor',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _barraPrograma(Map<String, dynamic> p, List<Map<String, dynamic>> todos) {
    final activos = (p['activos'] is num) ? (p['activos'] as num).toInt() : 0;
    var maxV = 1;
    for (final t in todos) {
      final v = (t['activos'] is num) ? (t['activos'] as num).toInt() : 0;
      if (v > maxV) maxV = v;
    }
    final factor = (activos / maxV).clamp(0.04, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text((p['programa'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 8),
              Text('$activos',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Container(height: 8, color: cessumMuted(context).withValues(alpha: 0.15)),
                FractionallySizedBox(
                  widthFactor: factor,
                  child: Container(height: 8, color: cessumRed),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _listaConteo(List items, String campo) {
    if (items.isEmpty) return [];
    return [
      const SizedBox(height: 10),
      ...items.map((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        final n = (m['n'] is num) ? (m['n'] as num).toInt() : 0;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text((m[campo] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: cessumMuted(context).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$n',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }),
    ];
  }
}

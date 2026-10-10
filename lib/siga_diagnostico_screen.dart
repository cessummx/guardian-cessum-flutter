// ADMIN · SIGA: DIAGNÓSTICO (23-sep-2026, rehecho)
//
// Antes mostraba barras de «campos completos contra faltantes» de TODO el
// histórico junto: no decía qué impedía subir, por qué, qué tan grave era ni
// qué hacer. Ahora, para el ciclo y la carga elegidos:
//   · veredicto (verde / ámbar / rojo) y el SIGUIENTE PASO, con botón directo
//   · cada archivo en el orden del portal, con su semáforo
//   · cada problema interpretado: causa real, impacto, qué hacer y a quién
//     afecta (lista completa, con nombre y matrícula)
//   · lo que depende de la Secretaría (Oferta, beca, promedio vacío), que se
//     marca aquí y queda guardado con quién y cuándo
//   · salud de las fuentes de datos y última exportación
//   · generar el paquete desde aquí cuando esté listo
//
//   GET siga_ciclos_listar
//   GET siga_salud&ciclo&carga[&tipoPeriodo][&origen=asignaciones]
//   GET siga_confirmar&actor&clave&valor
//   GET siga_paquete&ciclo&carga[&tipoPeriodo][&origen]&soloValidos=1&esperar=1&actor
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'siga_equivalencias_screen.dart';
import 'siga_pendientes_screen.dart';

class SigaDiagnosticoScreen extends StatefulWidget {
  final String ciclo;
  final String carga;
  final String tipoPeriodo;
  final bool inicio;
  const SigaDiagnosticoScreen({
    super.key,
    this.ciclo = '',
    this.carga = '',
    this.tipoPeriodo = '',
    this.inicio = false,
  });

  @override
  State<SigaDiagnosticoScreen> createState() => _SigaDiagnosticoScreenState();
}

class _SigaDiagnosticoScreenState extends State<SigaDiagnosticoScreen> {
  static const Color _verde = Color(0xFF1E7F52);
  static const Color _ambar = Color(0xFFB7791F);

  String _actor = '';
  List<Map<String, dynamic>> _ciclos = [];
  String _ciclo = '';
  String _carga = '';
  String _tipoPeriodo = '';
  bool _inicio = false;

  Map<String, dynamic>? _d;
  bool _cargando = true;
  String _error = '';
  final Set<String> _guardandoConf = {};
  final Set<String> _decidiendo = {};
  bool _generando = false;
  Map<String, dynamic>? _paquete;

  @override
  void initState() {
    super.initState();
    _ciclo = widget.ciclo;
    _carga = widget.carga;
    _tipoPeriodo = widget.tipoPeriodo;
    _inicio = widget.inicio;
    _iniciar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp, {int segundos = 60}) async {
    // SIGA cerrado: toda consulta dice quién la hace.
    final q = {...qp};
    if (_actor.isNotEmpty) q.putIfAbsent('actor', () => _actor);
    // Las operaciones largas (diagnóstico y paquete) piden al puente que
    // espere más, como hacen las demás pantallas de procesos largos.
    if (segundos > 60) q.putIfAbsent('lento', () => '1');
    final r = await http
        .get(Uri.parse(guardianUrl).replace(queryParameters: q))
        .timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _iniciar() async {
    // Correo REAL del administrador: en «Ver como profesor», validEmail() da el del profesor y SIGA lo rechazaría.
    _actor = ((await SessionStore.realEmail()) ?? '').trim().toLowerCase();
    try {
      final d = await _get({'accion': 'siga_ciclos_listar'});
      _ciclos = ((d['ciclos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (_ciclo.isEmpty && _ciclos.isNotEmpty) {
        _ciclo = '${_ciclos.first['ciclo']}';
        _carga = '${_ciclos.first['carga']}';
        _tipoPeriodo = '${_ciclos.first['tipoPeriodo'] ?? ''}';
      }
    } catch (_) {
      // Sin la lista de ciclos se puede diagnosticar igual si vino un ciclo.
    }
    if (_ciclo.isEmpty) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No hay ciclos con generaciones asignadas. Asígnelas en «Equivalencias SIGA».';
      });
      return;
    }
    await _diagnosticar();
  }

  Future<void> _diagnosticar() async {
    setState(() {
      _cargando = true;
      _error = '';
      _paquete = null;
    });
    try {
      final d = await _get({
        'accion': 'siga_salud',
        'ciclo': _ciclo,
        'carga': _carga,
        if (_tipoPeriodo.isNotEmpty) 'tipoPeriodo': _tipoPeriodo,
        if (_inicio) 'origen': 'asignaciones',
      }, segundos: 240);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo diagnosticar.');
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  void _msg(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cessumRed : _verde,
    ));
  }

  Future<void> _confirmar(String clave, String valor) async {
    setState(() => _guardandoConf.add(clave));
    try {
      final d = await _get({'accion': 'siga_confirmar', 'actor': _actor, 'clave': clave, 'valor': valor});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se guardó.');
      _msg('Guardado.');
      await _diagnosticar();
    } catch (e) {
      _msg('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _guardandoConf.remove(clave));
  }

  /// Decisión de reporte para UN alumno en este ciclo y carga. No toca su
  /// expediente ni su grupo: solo si va o no en los archivos de este periodo.
  Future<void> _decidir(String mat, String nombre, String decision) async {
    final noRep = decision == 'no_reportar';
    final ctl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(noRep ? 'No reportar a $nombre' : '$nombre sí está cursando', style: const TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              noRep
                  ? 'Sale de Alumnos, Carga horaria y Calificaciones solo en $_ciclo carga $_carga. Su expediente, su grupo y su estatus no cambian. Se puede deshacer.'
                  : 'Se reporta en $_ciclo carga $_carga y el diagnóstico deja de señalarlo.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            maxLines: 2,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              labelText: noRep ? 'Motivo (obligatorio)' : 'Nota (opcional)',
              hintText: noRep ? 'Ej.: egresó en diciembre de 2024; la calificación es de un acta capturada tarde' : 'Ej.: recursa una materia',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: noRep ? cessumRed : _verde),
            onPressed: () {
              final t = ctl.text.trim();
              if (noRep && t.length < 5) return;
              Navigator.pop(ctx, t);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (motivo == null) return;
    setState(() => _decidiendo.add(mat));
    try {
      final d = await _get({
        'accion': 'siga_decision_alumno',
        'matricula': mat,
        'ciclo': _ciclo,
        'carga': _carga,
        'decision': decision,
        'motivo': motivo,
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se guardó.');
      _msg(noRep ? 'Listo: $nombre no se reporta en este periodo.' : 'Listo: $nombre se reporta.');
      await _diagnosticar();
    } catch (e) {
      _msg('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _decidiendo.remove(mat));
  }

  /// Marca egresado en el PADRÓN (las dos bases), en el programa del caso.
  /// Es la solución de fondo: deja de aparecer en todos los ciclos.
  Future<void> _marcarEgresado(String mat, String nombre, String programa) async {
    final ctl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$nombre ya egresó', style: const TextStyle(fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'Queda como egresado de $programa en el padrón. Conserva su historial, sigue en graduación y titulación, '
              'y deja de aparecer como alumno activo en todos los ciclos.',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            maxLines: 2,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Motivo (obligatorio)',
              hintText: 'Ej.: concluyó el plan en diciembre de 2024',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () {
              final t = ctl.text.trim();
              if (t.length < 5) return;
              Navigator.pop(ctx, t);
            },
            child: const Text('Marcar egresado'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (motivo == null) return;
    setState(() => _decidiendo.add(mat));
    try {
      final d = await _get({
        'accion': 'siga_decision_aplicar',
        'tipo': 'egresado',
        'matricula': mat,
        'ciclo': _ciclo,
        'carga': _carga,
        'programa': programa,
        'motivo': motivo,
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se aplicó.');
      _msg('$nombre quedó como egresado de $programa.');
      await _diagnosticar();
    } catch (e) {
      _msg('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _decidiendo.remove(mat));
  }

  Future<void> _deshacer(String mat, String nombre) async {
    setState(() => _decidiendo.add(mat));
    try {
      final d = await _get({'accion': 'siga_decision_alumno_quitar', 'matricula': mat, 'ciclo': _ciclo, 'carga': _carga});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo deshacer.');
      _msg('Decisión retirada${nombre.isNotEmpty ? ' para $nombre' : ''}.');
      await _diagnosticar();
    } catch (e) {
      _msg('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _decidiendo.remove(mat));
  }

  Future<void> _generarPaquete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generar el paquete', style: TextStyle(fontSize: 16)),
        content: Text(
            'Se generan en Drive los archivos de $_ciclo carga $_carga${_inicio ? ' (inicio de periodo)' : ''} '
            'solo con los renglones completos. Los alumnos apartados quedan fuera hasta completar sus datos. '
            'No se envía nada a nadie. Tarda uno o dos minutos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _generando = true);
    try {
      final d = await _get({
        'accion': 'siga_paquete',
        'ciclo': _ciclo,
        'carga': _carga,
        if (_tipoPeriodo.isNotEmpty) 'tipoPeriodo': _tipoPeriodo,
        if (_inicio) 'origen': 'asignaciones',
        'soloValidos': '1',
        'esperar': '1',
        'actor': _actor,
      }, segundos: 300);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se generó.');
      if (!mounted) return;
      setState(() {
        _paquete = d;
        _generando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generando = false);
      _msg('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _ir(String destino) {
    Widget? pantalla;
    switch (destino) {
      case 'pendientes':
        pantalla = SigaPendientesScreen(ciclo: _ciclo, carga: _carga, inicio: _inicio);
        break;
      case 'equivalencias':
      case 'periodos':
      case 'claves':
        pantalla = const SigaEquivalenciasScreen();
        break;
      case 'paquete':
        _generarPaquete();
        return;
      case 'confirmar_oferta':
        _msg('Marque abajo, en «Depende de la Secretaría», si la Oferta está registrada.');
        return;
      default:
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla!)).then((_) => _diagnosticar());
  }

  String _textoBoton(String destino) {
    switch (destino) {
      case 'pendientes':
        return 'Capturar en Pendientes SIGA';
      case 'equivalencias':
        return 'Ir a Equivalencias SIGA';
      case 'periodos':
        return 'Capturar periodos';
      case 'claves':
        return 'Asignar claves';
      case 'paquete':
        return 'Generar el paquete';
      case 'confirmar_oferta':
        return 'Ver cómo confirmarlo';
      default:
        return '';
    }
  }

  // Selector de ciclo y carga con buscador.
  Future<void> _elegirCiclo() async {
    final ctl = TextEditingController();
    final elegido = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final q = ctl.text.trim().toLowerCase();
        final lista = _ciclos.where((c) => '${c['etiqueta'] ?? ''} ${c['ciclo']} ${c['carga']}'.toLowerCase().contains(q)).toList();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: ctl,
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar ciclo o carga',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => setS(() {}),
                ),
              ),
              Expanded(
                child: ListView(children: [
                  for (final c in lista)
                    ListTile(
                      title: Text('${c['etiqueta'] ?? '${c['ciclo']} · carga ${c['carga']}'}', style: const TextStyle(fontSize: 13.5)),
                      selected: '${c['ciclo']}' == _ciclo && '${c['carga']}' == _carga &&
                          '${c['tipoPeriodo'] ?? ''}' == _tipoPeriodo,
                      onTap: () => Navigator.pop(ctx, c),
                    ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    ctl.dispose();
    if (elegido == null) return;
    setState(() {
      _ciclo = '${elegido['ciclo']}';
      _carga = '${elegido['carga']}';
      _tipoPeriodo = '${elegido['tipoPeriodo'] ?? ''}';
    });
    _diagnosticar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Diagnóstico SIGA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Volver a diagnosticar', onPressed: _cargando ? null : _diagnosticar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 40), children: [
        _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            onTap: _ciclos.isEmpty || _cargando ? null : _elegirCiclo,
            child: Row(children: [
              const Icon(Icons.event_note, color: cessumRed, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_ciclo.isEmpty ? 'Elegir ciclo y carga' : '$_ciclo · carga $_carga',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              if (_ciclos.isNotEmpty) const Icon(Icons.expand_more),
            ]),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeThumbColor: cessumRed,
            title: const Text('Inicio de periodo', style: TextStyle(fontSize: 13)),
            subtitle: const Text('Solo docentes nuevos, alumnos y carga horaria, como pide la SEC al arrancar el ciclo',
                style: TextStyle(fontSize: 11.5)),
            value: _inicio,
            onChanged: _cargando
                ? null
                : (v) {
                    setState(() => _inicio = v);
                    _diagnosticar();
                  },
          ),
        ])),
        if (_cargando)
          _caja(const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              CircularProgressIndicator(color: cessumRed),
              SizedBox(height: 12),
              Text('Revisando cada archivo como lo revisaría el portal…', textAlign: TextAlign.center),
            ]),
          ))
        else if (_error.isNotEmpty)
          _caja(Column(children: [
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: _diagnosticar,
              child: const Text('Reintentar'),
            ),
          ]))
        else if (_d != null)
          ..._reporte(_d!),
      ]),
    );
  }

  List<Widget> _reporte(Map<String, dynamic> d) {
    final nivel = '${d['nivel']}';
    final color = nivel == 'verde' ? _verde : (nivel == 'ambar' ? _ambar : cessumRed);
    final sig = Map<String, dynamic>.from((d['siguiente'] as Map?) ?? const {});
    final archivos = ((d['archivos'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final problemas = ((d['problemas'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final estructura = ((d['estructura'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final conf = ((d['confirmaciones'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final fuentes = ((d['fuentes'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final reglas = ((d['reglasDelPortal'] as List?) ?? []).map((x) => '$x').toList();
    final ultima = d['ultimaExportacion'] == null ? null : Map<String, dynamic>.from(d['ultimaExportacion'] as Map);
    final afectados = ((d['alumnosAfectados'] as List?) ?? []).length;

    return [
      // 1 · Veredicto y siguiente paso
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1.4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(nivel == 'verde' ? Icons.check_circle : (nivel == 'ambar' ? Icons.error_outline : Icons.block),
                color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(nivel == 'verde' ? 'Listo para subir' : (nivel == 'ambar' ? 'Casi listo' : 'No se puede subir todavía'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('${d['veredicto']}', style: const TextStyle(fontSize: 13.5, height: 1.4)),
          if ('${sig['texto'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Siguiente paso: ${sig['texto']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
          if (_textoBoton('${sig['destino'] ?? ''}').isNotEmpty) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: _generando ? null : () => _ir('${sig['destino']}'),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(_textoBoton('${sig['destino']}')),
            ),
          ],
          const SizedBox(height: 6),
          Text('Diagnóstico del ${d['generado']}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ]),
      ),

      // 2 · Archivos en el orden del portal
      _titulo('Archivos, en el orden en que se suben'),
      ...archivos.map((a) {
        final est = '${a['estado']}';
        final c = est == 'listo' ? _verde : (est == 'apartados' ? _ambar : cessumRed);
        final texto = est == 'listo'
            ? 'Listo: ${a['filas']} renglones sin error'
            : est == 'apartados'
                ? '${a['listos']} de ${a['filas']} listos · ${a['conError']} apartados'
                : est == 'vacio'
                    ? 'Sin renglones para este ciclo y carga'
                    : 'Ningún renglón completo';
        return _caja(Row(children: [
          CircleAvatar(radius: 13, backgroundColor: c, child: Text('${a['orden']}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          Expanded(child: Text('${a['formato']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Text(texto, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w700)),
        ]));
      }),

      // 3 · Qué está mal
      if (problemas.isNotEmpty) ...[
        _titulo('Qué está mal y cómo se resuelve',
            afectados > 0 ? '$afectados alumno(s) distintos; uno puede fallar en más de un archivo.' : null),
        ...problemas.map(_problema),
      ],
      if (estructura.isNotEmpty) ...[
        _titulo('Estructura', 'No es un error de un renglón, pero impide reportar completo'),
        ...estructura.map((e) => _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['tipo']}: ${e['detalle']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${e['causa']}', style: const TextStyle(fontSize: 12.5)),
              Text('Qué hacer: ${e['accion']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              if (_textoBoton('${e['destino']}').isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => _ir('${e['destino']}'), child: Text(_textoBoton('${e['destino']}'))),
                ),
            ]))),
      ],

      // Decisiones de reporte tomadas en este ciclo y carga
      if (((d['decisiones'] as List?) ?? []).isNotEmpty) ...[
        _titulo('Decisiones de reporte en este ciclo y carga', 'Quedan en la bitácora de SIGA; se pueden deshacer'),
        ...((d['decisiones'] as List).map((x) => Map<String, dynamic>.from(x as Map))).map((x) {
          final noRep = '${x['decision']}' == 'no_reportar';
          final mat = '${x['matricula']}';
          final nom = '${x['nombre'] ?? ''}';
          return _caja(Row(children: [
            Icon(noRep ? Icons.remove_circle_outline : Icons.check_circle_outline, color: noRep ? cessumRed : _verde, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${nom.isNotEmpty ? '$nom · ' : ''}$mat', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${noRep ? 'No se reporta' : 'Sí está cursando'}${'${x['motivo'] ?? ''}'.isNotEmpty ? ' · ${x['motivo']}' : ''}',
                    style: const TextStyle(fontSize: 12)),
                Text('${x['actor']} · ${x['fecha']}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
              ]),
            ),
            _decidiendo.contains(mat)
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))
                : TextButton(onPressed: () => _deshacer(mat, nom), child: const Text('Deshacer')),
          ]));
        }),
      ],

      // 4 · Lo que depende de la Secretaría
      _titulo('Depende de la Secretaría', 'Marque lo que ya confirmó: queda guardado con su correo y la fecha'),
      ...conf.map(_confirmacion),

      // 5 · Fuentes de datos
      if (fuentes.isNotEmpty) ...[
        _titulo('Fuentes de datos'),
        ...fuentes.map((f) {
          final ok = f['ok'] == true;
          final desc = ((f['descartadas'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
          return _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(ok ? Icons.check_circle : Icons.warning_amber, color: ok ? _verde : _ambar, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text('${f['nombre']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 4),
            Text('${f['detalle']}', style: const TextStyle(fontSize: 12.5)),
            for (final x in desc)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('• ${x['nombre'] != '' ? '${x['nombre']} (${x['matricula']})' : x['matricula']}: ${x['motivo']}',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              ),
          ]));
        }),
      ],

      // 6 · Paquete y última exportación
      _titulo('Paquete'),
      _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (ultima != null) ...[
          Text('Última exportación de este ciclo y carga: ${ultima['fecha']}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          Text('${ultima['registros']} registros · ${ultima['errores']} con error',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          if ('${ultima['carpetaUrl'] ?? ''}'.isNotEmpty)
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('${ultima['carpetaUrl']}'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Abrir la carpeta'),
            ),
          const Divider(),
        ] else
          Text('Todavía no se ha exportado este ciclo y carga.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed),
          onPressed: _generando ? null : _generarPaquete,
          icon: _generando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.folder_zip_outlined),
          label: Text(_generando ? 'Generando…' : 'Generar el paquete (solo válidos)'),
        ),
        if (_paquete != null) ...[
          const SizedBox(height: 10),
          Text('Folio ${_paquete!['folio'] ?? ''} · ${_paquete!['totalRegistros'] ?? 0} registros · ${_paquete!['generados'] ?? 0} archivo(s)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _verde)),
          if ('${_paquete!['carpetaUrl'] ?? ''}'.isNotEmpty)
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('${_paquete!['carpetaUrl']}'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Abrir la carpeta del paquete'),
            ),
        ],
      ])),

      // 7 · Reglas del portal
      if (reglas.isNotEmpty) ...[
        _titulo('Reglas del portal que conviene tener presentes'),
        _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final r in reglas)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $r', style: const TextStyle(fontSize: 12.5))),
        ])),
      ],
    ];
  }

  Widget _problema(Map<String, dynamic> p) {
    final ej = ((p['ejemplos'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final revisar = '${p['gravedad']}' == 'revisar';
    final colP = revisar ? _ambar : cessumRed;
    final decidibles = ej.where((e) => e['decidible'] == true).toList();
    return _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('${p['tipo']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: colP.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
          child: Text('${revisar ? 'Revisar' : 'Bloquea'} · ${p['casos']} · ${p['formato']}',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: colP)),
        ),
      ]),
      const SizedBox(height: 6),
      Text('Por qué pasa: ${p['causa']}', style: const TextStyle(fontSize: 12.5, height: 1.35)),
      const SizedBox(height: 3),
      Text('Qué hacer: ${p['accion']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35)),
      const SizedBox(height: 3),
      Text('${p['impacto']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      // Casos que se resuelven con una decisión: cada uno con sus dos botones, a la vista.
      if (decidibles.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (final e in decidibles)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: colP.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['nombre']} (${e['matricula']})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              Text('${e['detalle'] ?? ''}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              const SizedBox(height: 4),
              _decidiendo.contains('${e['matricula']}')
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))
                  : Wrap(spacing: 8, runSpacing: 4, children: [
                      if (e['puedeEgresar'] == true)
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: cessumRed, visualDensity: VisualDensity.compact),
                          onPressed: () => _marcarEgresado('${e['matricula']}', '${e['nombre']}', '${e['programa'] ?? ''}'),
                          child: const Text('Marcar egresado en el padrón'),
                        ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
                        onPressed: () => _decidir('${e['matricula']}', '${e['nombre']}', 'no_reportar'),
                        child: const Text('No reportar'),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: _verde, visualDensity: VisualDensity.compact),
                        onPressed: () => _decidir('${e['matricula']}', '${e['nombre']}', 'cursando'),
                        child: const Text('Sí está cursando'),
                      ),
                    ]),
            ]),
          ),
      ],
      if (ej.isNotEmpty && decidibles.isEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 6),
            title: Text('Ver los ${ej.length} caso(s)', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            children: [
              for (final e in ej)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: SelectableText('• ${e['texto']}', style: const TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      if (_textoBoton('${p['destino']}').isNotEmpty)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _ir('${p['destino']}'),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(_textoBoton('${p['destino']}')),
          ),
        ),
    ]));
  }

  Widget _confirmacion(Map<String, dynamic> c) {
    final clave = '${c['clave']}';
    final valor = '${c['valor']}';
    final col = valor == 'si' ? _verde : (valor == 'no' ? cessumRed : _ambar);
    return _caja(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(valor == 'si' ? Icons.check_circle : (valor == 'no' ? Icons.cancel : Icons.help_outline), color: col, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('${c['titulo']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 4),
      Text('${c['porQue']}', style: const TextStyle(fontSize: 12.5, height: 1.35)),
      const SizedBox(height: 3),
      Text('Cómo se confirma: ${c['como']}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
      const SizedBox(height: 6),
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final o in const [['si', 'Sí'], ['no', 'No'], ['pendiente', 'Pendiente']])
          ChoiceChip(
            label: Text(o[1]),
            selected: valor == o[0],
            selectedColor: col.withValues(alpha: 0.18),
            onSelected: _guardandoConf.contains(clave) || valor == o[0] ? null : (_) => _confirmar(clave, o[0]),
          ),
        if (_guardandoConf.contains(clave))
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed)),
      ]),
      if ('${c['fecha'] ?? ''}'.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Marcado por ${c['por']} el ${c['fecha']}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ),
    ]));
  }

  Widget _titulo(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ]),
      );

  Widget _caja(Widget hijo) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
        ),
        child: hijo,
      );
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'csv_export.dart';
import 'finanzas_graficas.dart' show FinGraficaLineas, FinGraficaBarras, FinSerie;   // (24-sep) mismas gráficas interactivas

/// Panel de administrador: accesos a la app.
///
/// (24-sep) Rehecho. Antes solo contaba entradas. Ahora dice quién NO está
/// entrando, que es lo que sirve para actuar:
///  · Adopción de los últimos 30 días: alumnos activos y docentes con
///    materia en curso que entraron.
///  · Sin entrar: nunca han entrado, o llevan 15 días o más sin hacerlo
///    (con su materia en curso, en el caso de los docentes).
///  · Buscador, filtro por rol, copiar correos y exportar CSV de cada vista.
/// La ruta accesos_listar ahora exige sesión de administrador.
class AccesosUsoScreen extends StatefulWidget {
  const AccesosUsoScreen({super.key});

  @override
  State<AccesosUsoScreen> createState() => _AccesosUsoScreenState();
}

class _AccesosUsoScreenState extends State<AccesosUsoScreen> with SingleTickerProviderStateMixin {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _recientes = [];
  List<Map<String, dynamic>> _conteo = [];
  List<Map<String, dynamic>> _sinAlumnos = [];
  List<Map<String, dynamic>> _sinDocentes = [];
  Map<String, dynamic> _adopcion = {};
  Map<String, dynamic> _tend = {};
  bool _recordando = false;
  String _registroDesde = '';
  int _umbral = 15;
  String _generado = '';
  late TabController _tab;
  final _q = TextEditingController();
  String _rol = 'todos'; // todos · alumno · docente · admin
  bool _sinVerDocentes = true; // en «Sin entrar»: docentes o alumnos

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging && mounted) setState(() {});
    });
    _cargar();
  }

  @override
  void dispose() {
    _tab.dispose();
    _q.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _lista(dynamic x) =>
      ((x as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'accesos_listar', 'lento': '1'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['sesion'] == 'requerida'
            ? 'Por seguridad, cierre sesión en la app y vuelva a entrar con su cuenta @cessum.mx.'
            : (data['error'] ?? 'El Guardián no respondió como se esperaba.'));
      }
      final ina = Map<String, dynamic>.from((data['inactivos'] as Map?) ?? const {});
      if (!mounted) return;
      setState(() {
        _recientes = _lista(data['accesos']);
        _conteo = _lista(data['conteo']);
        _sinAlumnos = _lista(ina['alumnos']);
        _sinDocentes = _lista(ina['docentes']);
        _umbral = (ina['umbralDias'] as num?)?.toInt() ?? 15;
        _adopcion = Map<String, dynamic>.from((data['adopcion'] as Map?) ?? const {});
        _tend = Map<String, dynamic>.from((data['tendencias'] as Map?) ?? const {});
        _registroDesde = '${data['registroDesde'] ?? ''}';
        _generado = '${data['generado'] ?? ''}';
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = m.contains('TimeoutException')
            ? 'El Guardián tardó demasiado en responder. Intente de nuevo en un momento.'
            : (m.startsWith('FormatException') ? 'La respuesta no se pudo leer. Intente de nuevo.' : m);
      });
    }
  }

  // ---------- filtros ----------
  bool _pasaRol(String rol) {
    final r = rol.toLowerCase();
    switch (_rol) {
      case 'alumno':
        return r.contains('alum');
      case 'docente':
        return r.contains('docen') || r.contains('profe');
      case 'admin':
        return r.contains('admin');
      default:
        return true;
    }
  }

  bool _pasaTexto(Map<String, dynamic> m) {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${m['nombre'] ?? ''} ${m['correo'] ?? ''} ${m['programa'] ?? ''} ${m['generacion'] ?? ''} ${(m['materias'] as List?)?.join(' ') ?? ''}'
        .toLowerCase()
        .contains(q);
  }

  List<Map<String, dynamic>> get _recientesVis =>
      _recientes.where((a) => _pasaRol('${a['rol'] ?? ''}') && _pasaTexto(a)).toList();
  List<Map<String, dynamic>> get _conteoVis => _conteo.where((a) => _pasaRol('${a['rol'] ?? ''}') && _pasaTexto(a)).toList();
  List<Map<String, dynamic>> get _sinVis => (_sinVerDocentes ? _sinDocentes : _sinAlumnos).where(_pasaTexto).toList();
  List<Map<String, dynamic>> get _adopcionVis => _lista(_tend['adopcionPorGrupo']).where(_pasaTexto).toList();

  /// Recordatorio a los docentes de «Sin entrar». SIEMPRE primero la vista
  /// previa (el Guardián no envía nada sin confirmar=1): a quién, cuántos y
  /// el texto exacto. Solo se envía si usted confirma.
  Future<void> _recordar() async {
    setState(() => _recordando = true);
    Map<String, dynamic> v;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'accesos_recordar_docentes', 'lento': '1'}))
          .timeout(const Duration(seconds: 90));
      v = jsonDecode(r.body) as Map<String, dynamic>;
      if (v['ok'] != true) throw Exception(v['error'] ?? 'No se pudo preparar la vista previa.');
    } catch (e) {
      if (mounted) {
        setState(() => _recordando = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _recordando = false);
    final dest = _lista(v['destinatarios']);
    final omit = (v['omitidosRecientes'] as num?)?.toInt() ?? 0;
    final muestra = '${v['muestraHtml'] ?? ''}'
        .replaceAll(RegExp(r'</p>\s*<p>'), '\n\n')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
    if (dest.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(omit > 0
              ? 'No hay a quién escribir: a los $omit restantes ya se les recordó en los últimos 7 días.'
              : 'No hay docentes a quienes recordar.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recordar a ${dest.length} docente(s)', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Se enviará UN correo individual a cada uno. A nadie más le llega nada.'
                  '${omit > 0 ? ' Se omiten $omit a quienes ya se les recordó en los últimos 7 días.' : ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final d in dest)
                Text('• ${d['nombre']} · ${d['correo']}', style: const TextStyle(fontSize: 12.5)),
              const Divider(height: 20),
              Text('Asunto: ${v['asunto'] ?? ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(muestra, style: const TextStyle(fontSize: 12.5, height: 1.4)),
              ),
              const SizedBox(height: 4),
              Text('Ejemplo con el primer docente; a cada uno le llegan su nombre y sus materias.',
                  style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Enviar ${dest.length} correo(s)'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _recordando = true);
    try {
      final r = await http
          .get(Uri.parse(guardianUrl)
              .replace(queryParameters: {'accion': 'accesos_recordar_docentes', 'confirmar': '1', 'lento': '1'}))
          .timeout(const Duration(minutes: 5));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se enviaron.');
      if (!mounted) return;
      final fall = ((d['fallidos'] as List?) ?? []).length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF1E7F52),
          content: Text('Enviados: ${d['enviados']}${fall > 0 ? ' · no se pudieron enviar: $fall' : ''}.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _recordando = false);
  }

  // ---------- acciones ----------
  void _exportar() {
    switch (_tab.index) {
      case 0:
        descargarCsv(
            'accesos_recientes.csv',
            construirCsv(['Fecha', 'Nombre', 'Correo', 'Rol', 'Plataforma'], [
              for (final a in _recientesVis) [a['fecha'], a['nombre'], a['correo'], a['rol'], a['plataforma']],
            ]));
        break;
      case 1:
        descargarCsv(
            'accesos_por_persona.csv',
            construirCsv(['Nombre', 'Correo', 'Rol', 'Ingresos', 'Último acceso'], [
              for (final c in _conteoVis) [c['nombre'], c['correo'], c['rol'], c['veces'], c['ultimo']],
            ]));
        break;
      case 3:
        descargarCsv(
            'adopcion_por_grupo.csv',
            construirCsv(['Programa', 'Generación', 'Alumnos activos', 'Entraron en 30 días', '%'], [
              for (final g in _adopcionVis) [g['programa'], g['generacion'], g['activos'], g['entraron30'], g['pct']],
            ]));
        break;
      default:
        descargarCsv(
            _sinVerDocentes ? 'docentes_sin_entrar.csv' : 'alumnos_sin_entrar.csv',
            construirCsv(
                _sinVerDocentes
                    ? ['Nombre', 'Correo', 'Materias en curso', 'Último acceso', 'Días sin entrar']
                    : ['Nombre', 'Correo', 'Programa', 'Generación', 'Grupo', 'Último acceso', 'Días sin entrar'],
                [
                  for (final m in _sinVis)
                    _sinVerDocentes
                        ? [m['nombre'], m['correo'], (m['materias'] as List?)?.join('; ') ?? '', m['nunca'] == true ? 'Nunca' : m['ultimo'], m['dias'] ?? '']
                        : [m['nombre'], m['correo'], m['programa'], m['generacion'], m['grupo'], m['nunca'] == true ? 'Nunca' : m['ultimo'], m['dias'] ?? ''],
                ]));
    }
  }

  void _copiarCorreos() {
    final correos = _sinVis.map((m) => '${m['correo'] ?? ''}').where((c) => c.isNotEmpty).toSet().toList();
    if (correos.isEmpty) return;
    Helpers.copiarAlPortapapeles(context, correos.join(', '), '${correos.length} correo(s)');
  }

  // ---------- interfaz ----------
  @override
  Widget build(BuildContext context) {
    final vacio = switch (_tab.index) {
      0 => _recientesVis.isEmpty,
      1 => _conteoVis.isEmpty,
      2 => _sinVis.isEmpty,
      _ => _adopcionVis.isEmpty,
    };
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Accesos y uso'),
        actions: [
          if (_tab.index == 2)
            IconButton(
                onPressed: _cargando || _sinVis.isEmpty ? null : _copiarCorreos,
                tooltip: 'Copiar los correos de esta lista',
                icon: const Icon(Icons.alternate_email)),
          IconButton(
              onPressed: _cargando || vacio ? null : _exportar,
              tooltip: 'Exportar esta vista a CSV',
              icon: const Icon(Icons.download)),
          IconButton(onPressed: _cargando ? null : _cargar, tooltip: 'Volver a cargar', icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true, // (24-sep) cuatro pestañas con contador: en celular no caben fijas
          indicatorColor: cessumGold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Recientes (${_recientes.length})'),
            Tab(text: 'Por persona (${_conteo.length})'),
            Tab(text: 'Sin entrar (${_sinAlumnos.length + _sinDocentes.length})'),
            const Tab(text: 'Tendencias'),
          ],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 40, color: cessumGold),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ]),
                  ),
                )
              : Column(children: [
                  _cabecera(),
                  Expanded(
                    child: TabBarView(
                      controller: _tab,
                      children: [_listaRecientes(), _listaConteo(), _listaSinEntrar(), _listaTendencias()],
                    ),
                  ),
                ]),
    );
  }

  Widget _cabecera() {
    final al = Map<String, dynamic>.from((_adopcion['alumnos'] as Map?) ?? const {});
    final dc = Map<String, dynamic>.from((_adopcion['docentes'] as Map?) ?? const {});
    String pct(num? a, num? b) => (b == null || b == 0) ? '—' : '${((a ?? 0) * 100 / b).round()}%';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_adopcion.isNotEmpty)
          Row(children: [
            Expanded(
                child: _kpi('Alumnos activos que entraron (30 días)', pct(al['entraron30'] as num?, al['activos'] as num?),
                    '${al['entraron30'] ?? 0} de ${al['activos'] ?? 0}')),
            const SizedBox(width: 8),
            Expanded(
                child: _kpi('Docentes en curso que entraron (30 días)', pct(dc['entraron30'] as num?, dc['enCurso'] as num?),
                    '${dc['entraron30'] ?? 0} de ${dc['enCurso'] ?? 0}')),
          ]),
        const SizedBox(height: 8),
        TextField(
          controller: _q,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar por nombre, correo, programa o materia',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _q.clear())),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        if (_tab.index < 2)
          Wrap(spacing: 6, children: [
            for (final r in const [
              ['todos', 'Todos'],
              ['alumno', 'Alumnos'],
              ['docente', 'Docentes'],
              ['admin', 'Administración'],
            ])
              ChoiceChip(
                label: Text(r[1]),
                selected: _rol == r[0],
                visualDensity: VisualDensity.compact,
                selectedColor: cessumRed.withValues(alpha: 0.15),
                onSelected: (_) => setState(() => _rol = r[0]),
              ),
          ])
        else if (_tab.index == 2)
          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ChoiceChip(
              label: Text('Docentes con materia en curso (${_sinDocentes.length})'),
              selected: _sinVerDocentes,
              visualDensity: VisualDensity.compact,
              selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: (_) => setState(() => _sinVerDocentes = true),
            ),
            ChoiceChip(
              label: Text('Alumnos activos (${_sinAlumnos.length})'),
              selected: !_sinVerDocentes,
              visualDensity: VisualDensity.compact,
              selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: (_) => setState(() => _sinVerDocentes = false),
            ),
          ]),
        if (_generado.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Actualizado: $_generado${_registroDesde.isNotEmpty ? ' · el registro de accesos existe desde el $_registroDesde' : ''}',
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          ),
      ]),
    );
  }

  Widget _kpi(String t, String v, String sub) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cessumRed)),
          Text(sub, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          Text(t, style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
        ]),
      );

  Widget _vacio(String t) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: cessumMuted(context)))));

  Widget _listaRecientes() {
    final l = _recientesVis;
    if (l.isEmpty) return _vacio('Sin accesos con este filtro.');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      itemCount: l.length,
      itemBuilder: (c, i) {
        final a = l[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.login, color: cessumGold, size: 20),
            title: Text('${a['nombre'] ?? ''}'.isNotEmpty ? '${a['nombre']}' : '${a['correo'] ?? ''}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${a['correo'] ?? ''}${'${a['rol'] ?? ''}'.isNotEmpty ? ' · ${a['rol']}' : ''}',
                style: const TextStyle(fontSize: 11.5)),
            trailing: Text('${a['fecha'] ?? ''}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          ),
        );
      },
    );
  }

  Widget _listaConteo() {
    final l = _conteoVis;
    if (l.isEmpty) return _vacio('Sin datos de uso con este filtro.');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      itemCount: l.length,
      itemBuilder: (c, i) {
        final p = l[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: cessumRed.withValues(alpha: 0.12),
              child: Text('${p['veces'] ?? 0}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cessumRed)),
            ),
            title: Text('${p['nombre'] ?? ''}'.isNotEmpty ? '${p['nombre']}' : '${p['correo'] ?? ''}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${p['correo'] ?? ''}${'${p['rol'] ?? ''}'.isNotEmpty ? ' · ${p['rol']}' : ''}\nÚltimo acceso: ${'${p['ultimo'] ?? ''}'.isNotEmpty ? p['ultimo'] : '—'}',
                style: const TextStyle(fontSize: 11.5)),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _listaSinEntrar() {
    final l = _sinVis;
    if (l.isEmpty) {
      return _vacio(_sinVerDocentes
          ? 'Todos los docentes con materia en curso han entrado en los últimos $_umbral días.'
          : 'Todos los alumnos activos han entrado en los últimos $_umbral días.');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      itemCount: l.length + 1,
      itemBuilder: (c, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Nunca han entrado, o llevan $_umbral días o más sin entrar. '
                  'Use el ícono @ de arriba para copiar sus correos.',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              if (_sinVerDocentes) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                  onPressed: _recordando ? null : _recordar,
                  icon: _recordando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))
                      : const Icon(Icons.mark_email_unread_outlined, size: 18),
                  label: const Text('Recordar a estos docentes (con vista previa)'),
                ),
              ],
            ]),
          );
        }
        final m = l[i - 1];
        final nunca = m['nunca'] == true;
        final dias = (m['dias'] as num?)?.toInt();
        final detalle = _sinVerDocentes
            ? 'En curso: ${(m['materias'] as List?)?.join(', ') ?? ''}'
            : '${m['programa'] ?? ''} · ${m['generacion'] ?? ''} · ${m['grupo'] ?? ''}';
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            dense: true,
            leading: Icon(nunca ? Icons.person_off_outlined : Icons.schedule,
                color: nunca ? cessumRed : const Color(0xFFB7791F), size: 22),
            title: Text('${m['nombre'] ?? ''}'.isNotEmpty ? '${m['nombre']}' : '${m['correo'] ?? ''}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text('${m['correo'] ?? ''}\n$detalle', style: const TextStyle(fontSize: 11.5)),
            isThreeLine: true,
            trailing: Text(
              nunca ? 'Nunca' : '$dias días',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: nunca ? cessumRed : const Color(0xFFB7791F)),
            ),
          ),
        );
      },
    );
  }

  // ---------- tendencias ----------
  static const _diasSem = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static String _entero(double v) => v.round().toString();

  Widget _tarjeta(String titulo, String sub, Widget hijo) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            Text(sub, style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            const SizedBox(height: 10),
            hijo,
          ]),
        ),
      );

  Widget _listaTendencias() {
    if (_tend.isEmpty) return _vacio('Todavía no hay datos suficientes para las tendencias.');
    final dias = _lista(_tend['porDia']);
    final horas = ((_tend['porHora'] as List?) ?? []).map((x) => (x as num).toDouble()).toList();
    final semD = ((_tend['porDiaSemana'] as List?) ?? []).map((x) => (x as num).toDouble()).toList();
    final sem = _lista(_tend['semanas']);
    final adop = _adopcionVis;
    String ddmm(String iso) => iso.length >= 10 ? '${iso.substring(8, 10)}/${iso.substring(5, 7)}' : iso;
    // Horas: de las 6 a las 23, que es cuando hay actividad real.
    final hDesde = 6;
    final horasVis = horas.length == 24 ? horas.sublist(hDesde) : horas;
    final picoH = horas.isEmpty ? -1 : horas.indexOf(horas.reduce((a, b) => a > b ? a : b));
    final picoD = semD.isEmpty ? -1 : semD.indexOf(semD.reduce((a, b) => a > b ? a : b));
    return ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 24), children: [
      _tarjeta(
        'Personas por día · últimos 30 días',
        'Cuántas personas distintas entraron cada día, y cuántos accesos hubo',
        FinGraficaLineas(
          etiquetas: [for (final d in dias) ddmm('${d['fecha']}')],
          series: [
            FinSerie('Personas', cessumRed, [for (final d in dias) (d['personas'] as num).toDouble()], grosor: 2.6),
            FinSerie('Accesos', cessumGold, [for (final d in dias) (d['accesos'] as num).toDouble()]),
          ],
          alto: 200,
          formato: _entero,
          formatoEje: _entero,
        ),
      ),
      _tarjeta(
        'Últimas 8 semanas',
        'Personas distintas por semana (de lunes a domingo), por rol: ¿el uso sube o baja?',
        FinGraficaLineas(
          etiquetas: [for (final w in sem) ddmm('${w['lunes']}')],
          series: [
            FinSerie('Todas', cessumRed, [for (final w in sem) (w['personas'] as num).toDouble()], grosor: 2.6),
            FinSerie('Alumnos', const Color(0xFF2B6CB0), [for (final w in sem) (w['alumnos'] as num).toDouble()]),
            FinSerie('Docentes', const Color(0xFF1E7F52), [for (final w in sem) (w['docentes'] as num).toDouble()]),
          ],
          alto: 190,
          formato: _entero,
          formatoEje: _entero,
        ),
      ),
      _tarjeta(
        'Horas pico · últimos 90 días',
        picoH >= 0 ? 'La hora con más accesos es de las $picoH:00 a las ${picoH + 1}:00' : 'Accesos por hora del día',
        FinGraficaBarras(
          grupos: [for (var h = hDesde; h < hDesde + horasVis.length; h++) '$h'],
          series: [FinSerie('Accesos', cessumRed, horasVis)],
          alto: 170,
          mostrarValores: false,
          formato: _entero,
          formatoEje: _entero,
        ),
      ),
      _tarjeta(
        'Días de la semana · últimos 90 días',
        picoD >= 0 ? 'El día con más accesos es el ${['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'][picoD]}' : 'Accesos por día',
        FinGraficaBarras(
          grupos: _diasSem,
          series: [FinSerie('Accesos', cessumGold, semD)],
          alto: 160,
          formato: _entero,
          formatoEje: _entero,
        ),
      ),
      _tarjeta(
        'Adopción por programa y generación',
        'Alumnos activos que entraron en los últimos 30 días · primero los grupos que menos la usan',
        adop.isEmpty
            ? Text('Sin grupos con este filtro.', style: TextStyle(color: cessumMuted(context)))
            : Column(children: [
                for (final g in adop)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('${g['programa']} · ${g['generacion']}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                        Text('${g['entraron30']} de ${g['activos']} · ${g['pct']}%',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: ((g['pct'] as num?) ?? 0) < 50 ? cessumRed : const Color(0xFF1E7F52))),
                      ]),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (((g['pct'] as num?) ?? 0) / 100).clamp(0.0, 1.0).toDouble(),
                          minHeight: 7,
                          backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
                          color: ((g['pct'] as num?) ?? 0) < 50 ? cessumRed : const Color(0xFF1E7F52),
                        ),
                      ),
                    ]),
                  ),
              ]),
      ),
    ]);
  }
}

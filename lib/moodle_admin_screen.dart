import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Integración con el Aula Virtual (Moodle, aula.cessum.mx).
/// Dos vistas: Panorama por curso (inscritos, activos, promedio) y la ficha
/// Moodle de un alumno (cursos, último acceso, calificación, progreso, tareas).
class MoodleAdminScreen extends StatefulWidget {
  const MoodleAdminScreen({super.key});

  @override
  State<MoodleAdminScreen> createState() => _MoodleAdminScreenState();
}

class _MoodleAdminScreenState extends State<MoodleAdminScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Aula Virtual (Moodle)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Panorama'),
              Tab(text: 'Por alumno'),
              Tab(text: 'Inactivos'),
              Tab(text: 'Conciliación'),
              Tab(text: 'Suspendidos'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PanoramaTab(),
            _AlumnoTab(),
            _InactivosTab(),
            _ConciliacionTab(),
            _SuspendidosTab(),
          ],
        ),
      ),
    );
  }
}

/* ===================== PANORAMA POR CURSO ===================== */

class _PanoramaTab extends StatefulWidget {
  const _PanoramaTab();

  @override
  State<_PanoramaTab> createState() => _PanoramaTabState();
}

class _PanoramaTabState extends State<_PanoramaTab>
    with AutomaticKeepAliveClientMixin {
  static const Color _verde = Color(0xFF1E8E3E);
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _cursos = [];
  String _moodleInfo = '';
  String _filtroCurso = '';

  @override
  bool get wantKeepAlive => true;

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
      // Prueba de conexión (versión de Moodle).
      try {
        final pr = await http
            .get(Uri.parse('$guardianUrl?accion=moodle_ping'))
            .timeout(const Duration(seconds: 40));
        final pd = jsonDecode(pr.body) as Map<String, dynamic>;
        if (pd['ok'] == true) {
          _moodleInfo = 'Moodle ${pd['moodle'] ?? ''} · '
              '${pd['usuarios'] ?? 0} usuarios · ${pd['cursos'] ?? 0} cursos';
        }
      } catch (_) {}

      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=moodle_panorama&dias=30'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _resumen = Map<String, dynamic>.from((data['resumen'] as Map?) ?? {});
        _cursos = ((data['cursos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo conectar con Moodle. Revisa que puente_moodle.php '
            'esté subido en la raíz del Aula.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              TextButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_resumen['cursos'] ?? 0} cursos · '
                  '${_resumen['inscritos'] ?? 0} inscripciones · '
                  '${_resumen['activos'] ?? 0} activos (30 días)',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                if (_moodleInfo.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(_moodleInfo,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _filtroCurso = v),
            decoration: InputDecoration(
              hintText: 'Buscar curso por nombre',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          ..._cursos
              .where((c) => _filtroCurso.trim().isEmpty
                  ? true
                  : (c['curso'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains(_filtroCurso.toLowerCase()))
              .map(_tarjetaCurso),
        ],
      ),
    );
  }

  Widget _tarjetaCurso(Map<String, dynamic> c) {
    final inscritos = (c['inscritos'] ?? 0) as int;
    final activos = (c['activos'] ?? 0) as int;
    final inactivos = (c['inactivos'] ?? 0) as int;
    final prom = c['promedio'];
    final ratio = inscritos > 0 ? activos / inscritos : 0.0;
    final color = ratio >= 0.7
        ? _verde
        : (ratio >= 0.4 ? cessumGold : cessumRed);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((c['curso'] ?? '').toString(),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: Colors.black12,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _chip('Inscritos', '$inscritos', Colors.black87),
                _chip('Activos', '$activos', _verde),
                _chip('Inactivos', '$inactivos',
                    inactivos > 0 ? cessumRed : Colors.black54),
                if (prom != null)
                  _chip('Promedio', prom.toString(), cessumGold),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String etiqueta, String valor, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$etiqueta: ',
            style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        Text(valor,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

/* ===================== FICHA MOODLE DEL ALUMNO ===================== */

class _AlumnoTab extends StatefulWidget {
  const _AlumnoTab();

  @override
  State<_AlumnoTab> createState() => _AlumnoTabState();
}

class _AlumnoTabState extends State<_AlumnoTab>
    with AutomaticKeepAliveClientMixin {
  static const Color _verde = Color(0xFF1E8E3E);
  final TextEditingController _matricula = TextEditingController();
  bool _buscando = false;
  String? _error;
  Map<String, dynamic>? _datos;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _matricula.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final mat = _matricula.text.trim();
    if (mat.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _buscando = true;
      _error = null;
      _datos = null;
    });
    try {
      final resp = await http
          .get(Uri.parse(
              '$guardianUrl?accion=moodle_alumno&matricula=${Uri.encodeComponent(mat)}&dias=30'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _datos = data;
        _buscando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buscando = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _matricula,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscar(),
                  decoration: InputDecoration(
                    labelText: 'Matrícula del alumno',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 14)),
                onPressed: _buscando ? null : _buscar,
                child: _buscando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Buscar'),
              ),
            ],
          ),
        ),
        Expanded(child: _resultado()),
      ],
    );
  }

  Widget _resultado() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_datos == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Escribe una matrícula para ver su actividad en el Aula Virtual.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }
    final d = _datos!;
    final enMoodle = d['enMoodle'] == true;
    final inscripciones = ((d['inscripciones'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final tareas = ((d['tareas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final actividad = Map<String, dynamic>.from((d['actividad'] as Map?) ?? {});

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (enMoodle ? _verde : cessumRed).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((d['nombre'] ?? 'Alumno').toString(),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('${d['matricula'] ?? ''} · ${d['correo'] ?? ''}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
              const SizedBox(height: 6),
              Text(
                enMoodle
                    ? 'Actividad reciente: ${actividad['eventos'] ?? 0} '
                        'acciones en ${actividad['dias'] ?? 30} días'
                        '${(actividad['ultimoEvento'] ?? '').toString().isNotEmpty ? ' · última: ${actividad['ultimoEvento']}' : ''}'
                    : 'Este alumno no se encontró en el Aula Virtual con ese correo.',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: enMoodle ? _verde : cessumRed),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (inscripciones.isNotEmpty) ...[
          const _Titulo('Cursos en el Aula'),
          ...inscripciones.map(_tarjetaInscripcion),
        ],
        if (tareas.isNotEmpty) ...[
          const SizedBox(height: 14),
          const _Titulo('Tareas'),
          ...tareas.map(_tarjetaTarea),
        ],
        if (enMoodle && inscripciones.isEmpty && tareas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sin cursos ni tareas registradas en el Aula.',
                style: TextStyle(color: Colors.black54)),
          ),
      ],
    );
  }

  Widget _tarjetaInscripcion(Map<String, dynamic> i) {
    final prog = i['progreso'];
    final calif = i['calificacion'];
    final califMax = i['calificacionMax'];
    final dias = i['diasSinEntrar'];
    final color = (dias == null)
        ? Colors.black45
        : (dias <= 7 ? _verde : (dias <= 20 ? cessumGold : cessumRed));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((i['curso'] ?? '').toString(),
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: color),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    (i['ultimoAcceso'] ?? '').toString().isEmpty
                        ? 'Nunca ha entrado a este curso'
                        : 'Último acceso: ${i['ultimoAcceso']}'
                            '${dias != null ? ' (hace $dias días)' : ''}',
                    style: TextStyle(fontSize: 11.5, color: color),
                  ),
                ),
              ],
            ),
            if (prog != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ((prog as int) / 100).clamp(0.0, 1.0),
                        minHeight: 7,
                        backgroundColor: Colors.black12,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(cessumGold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$prog%',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
            if (calif != null) ...[
              const SizedBox(height: 6),
              Text(
                'Calificación: $calif${califMax != null ? ' / $califMax' : ''}',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tarjetaTarea(Map<String, dynamic> t) {
    final entregado = t['entregado'] == true;
    final vencida = t['vencida'] == true;
    final color = entregado ? _verde : (vencida ? cessumRed : cessumGold);
    final estado = entregado ? 'Entregada' : (vencida ? 'Vencida' : 'Pendiente');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          entregado
              ? Icons.check_circle
              : (vencida ? Icons.error : Icons.assignment_outlined),
          color: color,
        ),
        title: Text((t['tarea'] ?? '').toString(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${t['curso'] ?? ''}'
          '${(t['fechaLimite'] ?? '').toString().isNotEmpty ? '\nLímite: ${t['fechaLimite']}' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
        isThreeLine: (t['fechaLimite'] ?? '').toString().isNotEmpty,
        trailing: Text(estado,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }
}

/* ===================== PESTAÑA INACTIVOS ===================== */

class _InactivosTab extends StatefulWidget {
  const _InactivosTab();

  @override
  State<_InactivosTab> createState() => _InactivosTabState();
}

class _InactivosTabState extends State<_InactivosTab>
    with AutomaticKeepAliveClientMixin {
  static const Color _verde = Color(0xFF1E8E3E);
  bool _cargando = true;
  String? _error;
  int _dias = 21;
  String _filtroInact = '';
  int _total = 0;
  List<Map<String, dynamic>> _alumnos = [];

  @override
  bool get wantKeepAlive => true;

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
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'moodle_inactivos',
        'dias': '$_dias',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _total = (data['total'] ?? 0) as int;
        _alumnos = ((data['alumnos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el reporte de inactividad.';
      });
    }
  }


  void _copiarExcel() {
    final sb = StringBuffer();
    sb.writeln('Nombre\tMatrícula\tPrograma\tGeneración\t'
        'Días sin conexión\tÚltima conexión');
    for (final a in _alumnos) {
      final ult = (a['nunca'] == true)
          ? 'Nunca'
          : (a['ultimaConexion'] ?? '').toString();
      sb.writeln('${a['nombre'] ?? ''}\t${a['matricula'] ?? ''}\t'
          '${a['programa'] ?? ''}\t${a['generacion'] ?? ''}\t'
          '${a['diasSinConexion'] ?? ''}\t$ult');
    }
    Helpers.copiarAlPortapapeles(context, sb.toString(), 'Tabla');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            children: [
              const Text('Sin entrar al Aula desde hace',
                  style: TextStyle(fontSize: 12.5)),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: _dias,
                items: const [
                  DropdownMenuItem(value: 7, child: Text('7 días')),
                  DropdownMenuItem(value: 15, child: Text('15 días')),
                  DropdownMenuItem(value: 21, child: Text('21 días')),
                  DropdownMenuItem(value: 30, child: Text('30 días')),
                ],
                onChanged: _cargando
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() => _dias = v);
                        _cargar();
                      },
              ),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(color: cessumRed))
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(
                              onPressed: _cargar,
                              child: const Text('Reintentar')),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: cessumRed,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: (_total > 0 ? cessumRed : _verde)
                                  .withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _total == 0
                                  ? 'Ningún alumno vigente lleva $_dias días o más sin entrar.'
                                  : '$_total alumno(s) vigentes sin entrar al Aula hace $_dias días o más.',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _total > 0 ? cessumRed : _verde),
                            ),
                          ),
                          if (_alumnos.isNotEmpty)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _copiarExcel,
                                icon: const Icon(Icons.grid_on, size: 18),
                                label: const Text('Copiar para Excel'),
                                style: TextButton.styleFrom(
                                    foregroundColor: cessumRed),
                              ),
                            ),
                          TextField(
                            onChanged: (v) =>
                                setState(() => _filtroInact = v),
                            decoration: InputDecoration(
                              hintText: 'Buscar por nombre o matrícula',
                              isDense: true,
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ..._alumnos.where((a) {
                            if (_filtroInact.trim().isEmpty) return true;
                            final q = _filtroInact.toLowerCase();
                            final n =
                                (a['nombre'] ?? '').toString().toLowerCase();
                            final m = (a['matricula'] ?? '')
                                .toString()
                                .toLowerCase();
                            return n.contains(q) || m.contains(q);
                          }).map(_tarjeta),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final nunca = a['nunca'] == true;
    final dias = a['diasSinConexion'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text((a['nombre'] ?? '').toString(),
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${a['matricula'] ?? ''} · ${a['programa'] ?? ''} ${a['generacion'] ?? ''}'
          '${(a['ultimaConexion'] ?? '').toString().isNotEmpty ? '\nÚltima conexión: ${a['ultimaConexion']}' : ''}',
          style: const TextStyle(fontSize: 11),
        ),
        isThreeLine: (a['ultimaConexion'] ?? '').toString().isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: cessumRed,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(nunca ? 'Nunca' : '$dias d',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            PopupMenuButton<String>(
              tooltip: 'Acciones',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) {
                if (v == 'baja') _solicitarBaja(a);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'baja',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.person_off_outlined),
                    title: Text('Solicitar baja'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _solicitarBaja(Map<String, dynamic> a) async {
    final nombre = (a['nombre'] ?? '').toString();
    final mat = (a['matricula'] ?? '').toString();
    if (mat.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ese alumno no tiene matrícula.')));
      return;
    }
    bool suspender = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          title: const Text('Solicitar baja'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¿Marcar como BAJA a $nombre (mat. $mat)?\n\n'
                'Dejará de contar como alumno vigente en la base de grupos. '
                'Se puede revertir desde Grupos → menú → Revertir baja.',
                style: const TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: suspender,
                activeColor: cessumRed,
                onChanged: (v) => setSt(() => suspender = v ?? true),
                title: const Text('También suspender su acceso al Aula Virtual',
                    style: TextStyle(fontSize: 13)),
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
              child: const Text('Dar de baja'),
            ),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'baja_marcar',
        'matricula': mat,
        'suspender': suspender ? '1' : '0',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      final marc = (data['marcadas'] ?? 0) as int;
      setState(() {
        _alumnos.remove(a);
        if (_total > 0) _total--;
      });
      String msg = marc == 0
          ? '$nombre ya estaba de baja.'
          : 'Baja registrada para $nombre.';
      if (suspender) {
        if (data['suspendidoAula'] == true) {
          msg += ' Acceso al Aula suspendido.';
        } else if (data.containsKey('suspendidoAula')) {
          msg += ' (Aula: ${data['suspenderError'] ?? 'no se pudo suspender'})';
        }
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo registrar la baja: $e')));
    }
  }
}

/* ===================== PESTAÑA CONCILIACIÓN ===================== */

class _ConciliacionTab extends StatefulWidget {
  const _ConciliacionTab();

  @override
  State<_ConciliacionTab> createState() => _ConciliacionTabState();
}

class _ConciliacionTabState extends State<_ConciliacionTab>
    with AutomaticKeepAliveClientMixin {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _resumen = {};
  List<Map<String, dynamic>> _faltan = [];
  List<Map<String, dynamic>> _bajasActivas = [];

  @override
  bool get wantKeepAlive => true;

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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=moodle_conciliacion'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _resumen = Map<String, dynamic>.from((data['resumen'] as Map?) ?? {});
        _faltan = ((data['faltanEnAula'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _bajasActivas = ((data['bajasActivasEnAula'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la conciliación con el Aula.';
      });
    }
  }


  void _copiarExcel() {
    final sb = StringBuffer();
    void seccion(String titulo, List<Map<String, dynamic>> datos) {
      sb.writeln(titulo);
      sb.writeln('Nombre\tMatrícula\tPrograma\tGeneración\tCorreo');
      for (final a in datos) {
        sb.writeln('${a['nombre'] ?? ''}\t${a['matricula'] ?? ''}\t'
            '${a['programa'] ?? ''}\t${a['generacion'] ?? ''}\t'
            '${a['correo'] ?? ''}');
      }
      sb.writeln('');
    }
    seccion('Faltan inscribir en el Aula', _faltan);
    seccion('Bajas activas en el Aula', _bajasActivas);
    Helpers.copiarAlPortapapeles(context, sb.toString(), 'Tabla');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Padrón: ${_resumen['activosPadron'] ?? 0} activos · '
              '${_resumen['bajasPadron'] ?? 0} bajas\n'
              'Aula: ${_resumen['usuariosAula'] ?? 0} usuarios',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
          if (_faltan.isNotEmpty || _bajasActivas.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _copiarExcel,
                icon: const Icon(Icons.grid_on, size: 18),
                label: const Text('Copiar para Excel'),
                style: TextButton.styleFrom(foregroundColor: cessumRed),
              ),
            ),
          const SizedBox(height: 16),
          _Titulo('Faltan inscribir en el Aula (${_faltan.length})'),
          if (_faltan.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 2),
              child: Text(
                  'Todos los alumnos vigentes tienen cuenta en el Aula.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            )
          else
            ..._faltan.map((a) => _tarjeta(a, cessumRed, creable: true)),
          const SizedBox(height: 16),
          _Titulo(
              'Bajas que siguen activas en el Aula (${_bajasActivas.length})'),
          if (_bajasActivas.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 2),
              child: Text('No hay bajas activas en el Aula.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            )
          else
            ..._bajasActivas.map((a) => _tarjeta(a, cessumGold, suspendible: true)),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> a, Color color,
      {bool suspendible = false, bool creable = false}) {
    final correo = (a['correo'] ?? '').toString();
    Widget? accion;
    if (suspendible && correo.isNotEmpty) {
      accion = TextButton(
        onPressed: () => _suspender(correo, (a['nombre'] ?? '').toString()),
        style: TextButton.styleFrom(foregroundColor: cessumRed),
        child: const Text('Suspender'),
      );
    } else if (creable && correo.isNotEmpty) {
      accion = TextButton(
        onPressed: () => _crear(
          correo,
          (a['nombre'] ?? '').toString(),
          (a['matricula'] ?? '').toString(),
        ),
        style: TextButton.styleFrom(foregroundColor: const Color(0xFF1E8E3E)),
        child: const Text('Crear'),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(Icons.person_outline, color: color),
        title: Text((a['nombre'] ?? '').toString(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${a['matricula'] ?? ''} · ${a['programa'] ?? ''} ${a['generacion'] ?? ''}'
          '\n$correo',
          style: const TextStyle(fontSize: 11),
        ),
        isThreeLine: true,
        trailing: accion,
      ),
    );
  }

  Future<void> _crear(String correo, String nombre, String matricula) async {
    if (matricula.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Este alumno no tiene matrícula; no se puede crear.')));
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Crear cuenta en el Aula',
            style: TextStyle(fontSize: 16)),
        content: Text(
          'Se creará la cuenta de "$nombre" en el Aula Virtual.\n\n'
          'Usuario: $matricula\n'
          'Contraseña: se generará una temporal (deberá cambiarla al entrar).\n\n'
          'No se inscribe en cursos ni se envía correo. ¿Continuar?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E3E),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final uri = Uri.parse('$guardianUrl?accion=moodle_crear_usuario'
          '&email=${Uri.encodeComponent(correo)}'
          '&nombre=${Uri.encodeComponent(nombre)}'
          '&matricula=${Uri.encodeComponent(matricula)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        final usuario = (data['username'] ?? matricula).toString();
        final pass = (data['passwordTemporal'] ?? '').toString();
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Cuenta creada',
                style: TextStyle(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Comparta estos datos con $nombre:',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 10),
                Text('Usuario: $usuario',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text('Contraseña temporal: $pass',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Deberá cambiar la contraseña al iniciar sesión.',
                    style: TextStyle(fontSize: 11.5, color: Colors.black54)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Helpers.copiarAlPortapapeles(
                    context,
                    'Aula CESSUM\nUsuario: $usuario\nContraseña temporal: $pass',
                    'Datos de acceso'),
                child: const Text('Copiar datos'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Listo'),
              ),
            ],
          ),
        );
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo crear: ${data['error'] ?? 'error'}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo conectar con el Aula.')));
    }
  }

  Future<void> _suspender(String correo, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Suspender en el Aula', style: TextStyle(fontSize: 16)),
        content: Text(
          'Se suspenderá la cuenta de "$nombre" en el Aula Virtual. '
          'No podrá iniciar sesión hasta que se reactive. ¿Continuar?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Suspender'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final uri = Uri.parse('$guardianUrl?accion=moodle_suspender'
          '&email=${Uri.encodeComponent(correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cuenta de $nombre suspendida en el Aula.')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo suspender: ${data['error'] ?? 'error'}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo conectar con el Aula.')));
    }
  }
}


/* ===================== PESTAÑA SUSPENDIDOS ===================== */

class _SuspendidosTab extends StatefulWidget {
  const _SuspendidosTab();

  @override
  State<_SuspendidosTab> createState() => _SuspendidosTabState();
}

class _SuspendidosTabState extends State<_SuspendidosTab>
    with AutomaticKeepAliveClientMixin {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _usuarios = [];

  @override
  bool get wantKeepAlive => true;

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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=moodle_suspendidos'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _usuarios = ((data['usuarios'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar la lista de suspendidos.';
      });
    }
  }

  Future<void> _reactivar(String correo, String nombre) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reactivar en el Aula', style: TextStyle(fontSize: 16)),
        content: Text(
          'Se reactivara la cuenta de "$nombre" en el Aula Virtual y podra '
          'volver a iniciar sesion. Continuar?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E3E),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reactivar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final uri = Uri.parse('$guardianUrl?accion=moodle_reactivar'
          '&email=${Uri.encodeComponent(correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Cuenta de $nombre reactivada en el Aula.')));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('No se pudo reactivar: ${data['error'] ?? 'error'}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo conectar con el Aula.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            TextButton(onPressed: _cargar, child: const Text('Reintentar')),
          ],
        ),
      );
    }
    if (_usuarios.isEmpty) {
      return RefreshIndicator(
        color: cessumRed,
        onRefresh: _cargar,
        child: ListView(
          children: const [
            SizedBox(height: 80),
            Center(
              child: Text('No hay cuentas suspendidas en el Aula.',
                  style: TextStyle(color: Colors.black54)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: _usuarios.length,
        itemBuilder: (ctx, i) {
          final u = _usuarios[i];
          final correo = (u['correo'] ?? '').toString();
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.block, color: cessumRed),
              title: Text((u['nombre'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(
                '$correo'
                '${(u['ultimaConexion'] ?? '').toString().isNotEmpty ? '\nUltima conexion: ${u['ultimaConexion']}' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
              isThreeLine: (u['ultimaConexion'] ?? '').toString().isNotEmpty,
              trailing: TextButton(
                onPressed: () =>
                    _reactivar(correo, (u['nombre'] ?? '').toString()),
                style:
                    TextButton.styleFrom(foregroundColor: const Color(0xFF1E8E3E)),
                child: const Text('Reactivar'),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String texto;
  const _Titulo(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Text(texto,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cessumRed)),
    );
  }
}

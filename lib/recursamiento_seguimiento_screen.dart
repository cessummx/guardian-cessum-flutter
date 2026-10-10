// =====================================================================
//  recursamiento_seguimiento_screen.dart · CESSUM · (24-sep-2026)
//  SEGUIMIENTO DE RECURSAMIENTOS (administración)
//
//  Dos pestañas:
//   1. Reprobados: todos los alumnos con materias reprobadas. Por materia:
//      si está agendada ahora (con fechas y cierre), si ya la solicitó, el
//      último aviso (y si el correo salió) y el último contacto por WhatsApp.
//      Arriba, lo que urge: materias agendadas que nadie ha solicitado.
//   2. Avisos enviados: cada vez que se agendó una materia, a quién se le
//      avisó y cómo quedó cada correo (Enviado / Falló / Sin correo /
//      Encolado / Pendiente por tope), con «Reenviar».
//  En las dos: botón de WhatsApp con el mensaje ya redactado y «Marcar
//  contactado», que se registra a mano (fecha, quién y nota).
//
//  Guardián: GET recurso_reprobados_panel · GET recurso_avisos_panel
//            POST recurso_contacto_marcar · POST recurso_aviso_reenviar
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class RecursamientoSeguimientoScreen extends StatefulWidget {
  const RecursamientoSeguimientoScreen({super.key});

  @override
  State<RecursamientoSeguimientoScreen> createState() => _RecursamientoSeguimientoScreenState();
}

class _RecursamientoSeguimientoScreenState extends State<RecursamientoSeguimientoScreen> {
  // Reprobados
  bool _cargandoR = true;
  String _errorR = '';
  List<Map<String, dynamic>> _alumnos = [];
  Map<String, dynamic> _resumen = {};
  final _busca = TextEditingController();
  String _filtro = 'urgentes'; // urgentes | sinContacto | conTelefono | todos
  // Avisos
  bool _cargandoA = true;
  String _errorA = '';
  List<Map<String, dynamic>> _grupos = [];
  final Set<String> _ocupados = {};

  static const _verde = Color(0xFF1E7F52);

  @override
  void initState() {
    super.initState();
    _cargarReprobados();
    _cargarAvisos();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp) async {
    final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: qp)).timeout(const Duration(seconds: 120));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargarReprobados() async {
    setState(() {
      _cargandoR = true;
      _errorR = '';
    });
    try {
      final d = await _get({'accion': 'recurso_reprobados_panel'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar.');
      _alumnos = ((d['alumnos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _resumen = Map<String, dynamic>.from((d['resumen'] as Map?) ?? {});
    } catch (e) {
      _errorR = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargandoR = false);
  }

  Future<void> _cargarAvisos() async {
    setState(() {
      _cargandoA = true;
      _errorA = '';
    });
    try {
      final d = await _get({'accion': 'recurso_avisos_panel', 'dias': '60'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar.');
      _grupos = ((d['grupos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      _errorA = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargandoA = false);
  }

  void _aviso(String t, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : _verde,
      duration: const Duration(seconds: 5),
      content: Text(t),
    ));
  }

  String _n(String s) {
    s = s.toLowerCase();
    const a = 'áàäâéèëêíìïîóòöôúùüûñ';
    const b = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  // ---------------- WhatsApp ----------------

  String _mensajeWhatsApp(String nombre, Map<String, dynamic> m) {
    final pn = nombre.trim().isEmpty ? '' : ' ${nombre.trim().split(' ').first}';
    final materia = '${m['materia'] ?? ''}';
    if (m['agendada'] == true || '${m['periodo'] ?? ''}'.isNotEmpty) {
      return 'Hola$pn, te saluda Vicerrectoría Académica de CESSUM. La materia «$materia» está agendada'
          '${'${m['periodo'] ?? ''}'.isNotEmpty ? ' ${m['periodo']}' : ''}. Como la tienes pendiente, puedes solicitarla '
          'en la app de CESSUM, en el apartado Recursamientos'
          '${'${m['cierre'] ?? ''}'.isNotEmpty ? ' (inscripción abierta hasta el ${m['cierre']})' : ''}. '
          'Quedamos atentos para acompañarte.';
    }
    return 'Hola$pn, te saluda Vicerrectoría Académica de CESSUM. Te escribimos para dar seguimiento a tu materia '
        'pendiente «$materia». En cuanto se agende te avisaremos; mientras tanto, cualquier duda estamos a tus órdenes.';
  }

  Future<void> _whatsApp(String telefono, String nombre, String matricula, Map<String, dynamic> m, {String? mensaje}) async {
    final tel = telefono.replaceAll(RegExp(r'\D'), '');
    final numero = tel.length == 10 ? '52$tel' : tel;
    final url = Uri.parse('https://wa.me/$numero?text=${Uri.encodeComponent(mensaje ?? _mensajeWhatsApp(nombre, m))}');
    await launchUrl(url, webOnlyWindowName: '_blank');
    if (!mounted) return;
    await _marcarContactado(nombre, matricula, m, preguntar: true);
  }

  Future<void> _marcarContactado(String nombre, String matricula, Map<String, dynamic> m, {bool preguntar = false}) async {
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(preguntar ? '¿Se le escribió por WhatsApp?' : 'Marcar contactado por WhatsApp',
            style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$nombre · $matricula', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${m['materia'] ?? ''}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: nota,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: 'Nota (opcional)',
                hintText: 'Ej. Respondió que la solicita esta semana',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(preguntar ? 'No se envió' : 'Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _verde),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar contactado'),
          ),
        ],
      ),
    );
    final texto = nota.text.trim();
    nota.dispose();
    if (ok != true || !mounted) return;
    try {
      final d = await _post({
        'accion': 'recurso_contacto_marcar',
        'matricula': matricula,
        'nombre': nombre,
        'clave': '${m['clave'] ?? ''}',
        'materia': '${m['materia'] ?? ''}',
        'canal': 'WhatsApp',
        'nota': texto,
      });
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      _aviso('Contacto por WhatsApp registrado.');
      await Future.wait([_cargarReprobados(), _cargarAvisos()]);
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  /// (24-sep) Mensaje de WhatsApp redactado con IA con TODAS las materias
  /// pendientes del alumno. Se revisa y edita antes de abrir WhatsApp.
  Future<void> _mensajeIa(Map<String, dynamic> a) async {
    final tel = '${a['telefono'] ?? ''}';
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    Map<String, dynamic> d;
    try {
      d = await _get({'accion': 'recurso_ia_mensaje', 'matricula': '${a['matricula']}'});
    } catch (_) {
      d = {'ok': false, 'error': 'No se pudo conectar.'};
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (d['ok'] != true) {
      _aviso('${d['error'] ?? 'No se pudo redactar el mensaje.'}', error: true);
      return;
    }
    final ctl = TextEditingController(text: '${d['mensaje'] ?? ''}');
    final enviar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mensaje para ${'${a['nombre']}'.split(' ').first}', style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: ctl, minLines: 6, maxLines: 12, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 6),
            Text('Redactado con IA: revíselo y ajústelo antes de enviarlo.',
                style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
            onPressed: tel.isEmpty ? null : () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.chat, size: 16),
            label: Text(tel.isEmpty ? 'Sin teléfono' : 'Abrir WhatsApp'),
          ),
        ],
      ),
    );
    final texto = ctl.text.trim();
    ctl.dispose();
    if (enviar != true || !mounted) return;
    final mats = ((a['materias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final m = mats.isNotEmpty ? mats.first : <String, dynamic>{'materia': 'Materias pendientes'};
    await _whatsApp(tel, '${a['nombre']}', '${a['matricula']}', m, mensaje: texto);
  }

  Future<void> _juntarCelulares() async {
    try {
      final d = await _get({'accion': 'celulares_consolidar'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo.');
      _aviso('Celulares agregados: ${d['agregados']} · alumnos con celular: ${d['conCelular']} de ${d['alumnosActivos']} activos.');
      await _cargarReprobados();
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _reenviar(Map<String, dynamic> a) async {
    final k = 'f${a['fila']}';
    setState(() => _ocupados.add(k));
    try {
      final d = await _post({'accion': 'recurso_aviso_reenviar', 'fila': a['fila']});
      _aviso(d['ok'] == true ? 'Correo reenviado.' : 'No salió: ${d['error'] ?? d['estado'] ?? ''}', error: d['ok'] != true);
      await _cargarAvisos();
    } catch (e) {
      _aviso('$e', error: true);
    }
    if (mounted) setState(() => _ocupados.remove(k));
  }

  // ---------------- Vista ----------------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Seguimiento de recursamientos'),
          actions: [
            IconButton(
              tooltip: 'Juntar celulares de las demás hojas',
              icon: const Icon(Icons.contact_phone_outlined),
              onPressed: _juntarCelulares,
            ),
            IconButton(
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _cargarReprobados();
                _cargarAvisos();
              },
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Reprobados'), Tab(text: 'Avisos enviados')],
          ),
        ),
        body: TabBarView(children: [_tabReprobados(), _tabAvisos()]),
      ),
    );
  }

  // ---- Pestaña 1: Reprobados ----

  List<Map<String, dynamic>> get _visibles {
    final q = _n(_busca.text);
    return _alumnos.where((a) {
      final mats = ((a['materias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (_filtro == 'urgentes' && !mats.any((m) => m['agendada'] == true && '${m['solicitud']}'.isEmpty)) return false;
      if (_filtro == 'sinContacto' && mats.any((m) => m['contacto'] != null)) return false;
      if (_filtro == 'conTelefono' && '${a['telefono']}'.isEmpty) return false;
      if (q.isEmpty) return true;
      final texto = _n('${a['nombre']} ${a['matricula']} ${a['programa']} ${mats.map((m) => m['materia']).join(' ')}');
      return texto.contains(q);
    }).toList();
  }

  Widget _tabReprobados() {
    if (_cargandoR) return const Center(child: CircularProgressIndicator(color: cessumRed));
    if (_errorR.isNotEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_errorR, textAlign: TextAlign.center),
        TextButton(onPressed: _cargarReprobados, child: const Text('Reintentar')),
      ]));
    }
    final vis = _visibles;
    Widget dato(String t, dynamic n, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text('${n ?? 0}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
            Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
          ]),
        );
    return RefreshIndicator(
      onRefresh: _cargarReprobados,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          dato('alumnos con\nreprobadas', _resumen['alumnos'], cessumRed),
          dato('agendadas y\nsin solicitud', _resumen['agendadasSinSolicitud'], cessumGold),
          dato('agendadas\nsin aviso', _resumen['sinAviso'], cessumRed),
          dato('correos con\nproblema', _resumen['correoConProblema'], cessumRed),
          dato('contactados\npor WhatsApp', _resumen['contactadosWhatsApp'], _verde),
          dato('alumnos sin\nteléfono', _resumen['sinTelefono'], Colors.grey),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _busca,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar alumno, matrícula, programa o materia…',
            suffixIcon: _busca.text.isEmpty
                ? null
                : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _busca.clear())),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in const [
            ['urgentes', 'Agendada y sin solicitud'],
            ['sinContacto', 'Sin contactar'],
            ['conTelefono', 'Con teléfono'],
            ['todos', 'Todos'],
          ])
            ChoiceChip(
              label: Text(f[1], style: const TextStyle(fontSize: 12)),
              selected: _filtro == f[0],
              onSelected: (_) => setState(() => _filtro = f[0]),
            ),
        ]),
        const SizedBox(height: 6),
        Text('${vis.length} alumno(s) en esta vista', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 8),
        if (vis.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text('Nadie en esta vista.', style: TextStyle(color: cessumMuted(context)))),
          )
        else
          ...vis.map(_tarjetaAlumno),
      ]),
    );
  }

  Widget _tarjetaAlumno(Map<String, dynamic> a) {
    final mats = ((a['materias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final tel = '${a['telefono'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${a['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        Text(
          '${a['matricula']} · ${a['programa']}${'${a['generacion']}'.isNotEmpty ? ' · ${a['generacion']}' : ''}'
          '${'${a['grupo']}'.isNotEmpty ? ' · ${a['grupo']}' : ''}',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        Text(
          '${'${a['correo']}'.isNotEmpty ? a['correo'] : 'sin correo'} · ${tel.isNotEmpty ? 'tel. $tel' : 'sin teléfono'}',
          style: TextStyle(fontSize: 11.5, color: tel.isEmpty ? Colors.grey : cessumMuted(context)),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: cessumGold, visualDensity: VisualDensity.compact),
            onPressed: () => _mensajeIa(a),
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text('Mensaje con IA (todas sus materias)'),
          ),
        ),
        for (final m in mats) _filaMateria(a, m, tel),
      ]),
    );
  }

  Widget _filaMateria(Map<String, dynamic> a, Map<String, dynamic> m, String tel) {
    final agendada = m['agendada'] == true;
    final solicitud = '${m['solicitud'] ?? ''}';
    final aviso = m['aviso'] is Map ? Map<String, dynamic>.from(m['aviso'] as Map) : null;
    final contacto = m['contacto'] is Map ? Map<String, dynamic>.from(m['contacto'] as Map) : null;
    final urgente = agendada && solicitud.isEmpty;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (urgente ? cessumGold : Colors.grey).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: (urgente ? cessumGold : Colors.grey).withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${m['materia']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          Text('Calif. ${m['calificacion']}',
              style: const TextStyle(fontSize: 12, color: cessumRed, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 3),
        Text(
          agendada
              ? 'Agendada ${m['periodo']} · inscripción hasta el ${m['cierre']}'
              : 'No está agendada ahora',
          style: TextStyle(fontSize: 12, color: agendada ? _verde : cessumMuted(context), fontWeight: FontWeight.w600),
        ),
        Text(
          'Solicitud: ${solicitud.isEmpty ? 'no la ha solicitado' : solicitud}'
          ' · Aviso: ${aviso == null ? 'ninguno' : '${aviso['fecha']}${'${aviso['estado']}'.isNotEmpty ? ' (${aviso['estado']})' : ''}'}',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        if (contacto != null)
          Text(
            'WhatsApp: ${contacto['fecha']} por ${contacto['quien']}${'${contacto['nota']}'.isNotEmpty ? ' · «${contacto['nota']}»' : ''}',
            style: const TextStyle(fontSize: 11.5, color: _verde, fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), visualDensity: VisualDensity.compact),
            onPressed: tel.isEmpty ? null : () => _whatsApp(tel, '${a['nombre']}', '${a['matricula']}', m),
            icon: const Icon(Icons.chat, size: 16),
            label: Text(tel.isEmpty ? 'Sin teléfono' : 'Escribir por WhatsApp'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: _verde, visualDensity: VisualDensity.compact),
            onPressed: () => _marcarContactado('${a['nombre']}', '${a['matricula']}', m),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Marcar contactado'),
          ),
        ]),
      ]),
    );
  }

  // ---- Pestaña 2: Avisos enviados ----

  Color _colorEstado(String e) {
    if (e.startsWith('Enviado')) return _verde;
    if (e.startsWith('Sin correo') || e.contains('formato anterior')) return Colors.grey;
    if (e.startsWith('Encolado') || e.startsWith('Pendiente')) return cessumGold;
    return cessumRed;
  }

  Widget _tabAvisos() {
    if (_cargandoA) return const Center(child: CircularProgressIndicator(color: cessumRed));
    if (_errorA.isNotEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_errorA, textAlign: TextAlign.center),
        TextButton(onPressed: _cargarAvisos, child: const Text('Reintentar')),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _cargarAvisos,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Text('Cada vez que se agendó una materia en los últimos 60 días: a quién se le avisó y cómo quedó cada correo.',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        const SizedBox(height: 10),
        if (_grupos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text('Sin avisos en este periodo.', style: TextStyle(color: cessumMuted(context)))),
          ),
        for (final g in _grupos) _tarjetaGrupo(g),
      ]),
    );
  }

  Widget _tarjetaGrupo(Map<String, dynamic> g) {
    final cuentas = Map<String, dynamic>.from((g['cuentas'] as Map?) ?? {});
    final alumnos = ((g['alumnos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final problemas = alumnos.where((a) => !'${a['estadoCorreo']}'.startsWith('Enviado')).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text('${g['materia']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${g['programa']}${'${g['grupoOfertado']}'.isNotEmpty ? ' · ${g['grupoOfertado']}' : ''}'
            '${'${g['periodo']}'.isNotEmpty ? ' · ${g['periodo']}' : ''} · avisado el ${g['fecha']}',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final e in cuentas.entries)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: _colorEstado(e.key).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text('${e.key}: ${e.value}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _colorEstado(e.key))),
              ),
          ]),
        ]),
        trailing: problemas > 0
            ? Text('$problemas por atender', style: const TextStyle(fontSize: 11.5, color: cessumRed, fontWeight: FontWeight.w700))
            : const Icon(Icons.check_circle, color: _verde),
        children: [for (final a in alumnos) _filaAviso(g, a)],
      ),
    );
  }

  Widget _filaAviso(Map<String, dynamic> g, Map<String, dynamic> a) {
    final est = '${a['estadoCorreo']}';
    final tel = '${a['telefono'] ?? ''}';
    final contacto = a['contacto'] is Map ? Map<String, dynamic>.from(a['contacto'] as Map) : null;
    final m = {
      'materia': g['materia'],
      'clave': a['clave'],
      'periodo': g['periodo'],
      'agendada': '${g['periodo']}'.isNotEmpty,
      'cierre': '',
    };
    final k = 'f${a['fila']}';
    final puedeReenviar = !est.startsWith('Enviado') && !est.contains('formato anterior');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: cessumMuted(context).withValues(alpha: 0.15)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${a['nombre'].toString().isNotEmpty ? a['nombre'] : a['matricula']}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: _colorEstado(est).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(est, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _colorEstado(est))),
          ),
        ]),
        Text(
          '${a['matricula']}${'${a['tipo']}'.isNotEmpty ? ' · ${a['tipo']}' : ''} · '
          '${'${a['correo']}'.isNotEmpty ? a['correo'] : 'sin correo'} · ${tel.isNotEmpty ? 'tel. $tel' : 'sin teléfono'}',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
        if (contacto != null)
          Text('WhatsApp: ${contacto['fecha']} por ${contacto['quien']}',
              style: const TextStyle(fontSize: 11.5, color: _verde, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          if (puedeReenviar)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
              onPressed: _ocupados.contains(k) ? null : () => _reenviar(a),
              icon: const Icon(Icons.forward_to_inbox, size: 16),
              label: const Text('Reenviar correo'),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), visualDensity: VisualDensity.compact),
            onPressed: tel.isEmpty ? null : () => _whatsApp(tel, '${a['nombre']}', '${a['matricula']}', m),
            icon: const Icon(Icons.chat, size: 16),
            label: Text(tel.isEmpty ? 'Sin teléfono' : 'WhatsApp'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: _verde, visualDensity: VisualDensity.compact),
            onPressed: () => _marcarContactado('${a['nombre']}', '${a['matricula']}', m),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('Marcar contactado'),
          ),
        ]),
      ]),
    );
  }
}

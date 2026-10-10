// grabaciones_clase_screen.dart
// (ago-6) GRABACIONES DE CLASE + CONTADOR DE ASISTENCIA
// El alumno ve aquí las grabaciones de las sesiones síncronas de su grupo
// (sincronizadas desde Google Drive del organizador) y su contador de
// asistencia, tomado de los informes oficiales de Google Meet. El banner
// recuerda la regla de oro: entrar con el CORREO INSTITUCIONAL, porque es
// lo único que Google reporta y lo único que acredita la asistencia.
// En Maestría en Educación la asistencia síncrona es criterio de
// evaluación, y la pantalla se lo dice.
//
// (24-sep) REVISIÓN INTEGRAL
//  · Errores: si el Guardián rechaza la consulta (p. ej. sesión sin llave) se
//    muestra el MOTIVO real, no «revisa tu conexión». Una grabación sin enlace
//    ya no intenta abrir una dirección vacía: se avisa.
//  · Modo oscuro: los grises, cremas y cafés fijos pasan a colores del tema.
//  · Asistencia con porcentaje y color según el avance.
//  · Grabaciones agrupadas por materia (con cuántas hay) y buscador cuando son
//    más de seis.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'helpers.dart';
import 'cessum_ui.dart';
import 'student_autolink.dart';

class GrabacionesClaseScreen extends StatefulWidget {
  const GrabacionesClaseScreen({super.key});

  @override
  State<GrabacionesClaseScreen> createState() =>
      _GrabacionesClaseScreenState();
}

class _GrabacionesClaseScreenState extends State<GrabacionesClaseScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _d;
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
      _error = null;
    });
    try {
      final perfil = await StudentAutoLink.sincronizarPerfilGuardado();
      final mat = perfil?.matricula ?? '';
      if (mat.isEmpty) {
        throw Exception(
            'Tu perfil no tiene matrícula todavía. Complétalo para ver tus grabaciones.');
      }
      final r = await http
          .get(Uri.parse(
              '$guardianUrl?accion=grabaciones_clase&matricula=${Uri.encodeComponent(mat)}'))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        // (24-sep) El motivo real: sesión sin llave, matrícula no encontrada…
        throw Exception(d['error'] ?? 'No se pudieron cargar tus grabaciones.');
      }
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = msg.contains('TimeoutException') ||
                msg.contains('SocketException') ||
                msg.contains('ClientException') ||
                msg.contains('FormatException')
            ? 'No se pudieron cargar tus grabaciones. Revisa tu conexión e intenta de nuevo.'
            : msg;
      });
    }
  }

  void _abrir(Map<String, dynamic> g) {
    final url = '${g['url'] ?? ''}'.trim();
    if (url.isEmpty || url == 'null') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Esta grabación todavía no tiene enlace. Suele aparecer unas horas después de la sesión.')));
      return;
    }
    Helpers.abrirUrlExterna(url, context);
  }

  String _norm(String s) {
    s = s.toLowerCase();
    const a = 'áàäâéèëêíìïîóòöôúùüûñ';
    const b = 'aaaaeeeeiiiioooouuuun';
    for (var i = 0; i < a.length; i++) {
      s = s.replaceAll(a[i], b[i]);
    }
    return s.trim();
  }

  bool _coincide(Map<String, dynamic> g) {
    final q = _norm(_busca.text);
    if (q.isEmpty) return true;
    return _norm('${g['materia'] ?? ''} ${g['fecha'] ?? ''}').contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Grabaciones de clase',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Actualizar',
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_outlined,
                            size: 44, color: cessumFaint(context)),
                        const SizedBox(height: 10),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: cessumInk(context))),
                        const SizedBox(height: 12),
                        OutlinedButton(
                            onPressed: _cargar,
                            child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : _vista(),
    );
  }

  Widget _vista() {
    final d = _d!;
    final contador = Map<String, dynamic>.from(d['contador'] as Map? ?? {});
    final asistidas = (contador['asistidas'] as num?)?.toInt() ?? 0;
    final sesiones = (contador['sesiones'] as num?)?.toInt() ?? 0;
    final aplica = d['aplicaCriterio'] == true;
    final correo = '${d['correoInstitucional'] ?? ''}';
    List<Map<String, dynamic>> lista(String k) => ((d[k] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final grabaciones = lista('grabaciones');
    // (ago-8) Grabaciones de materias que el alumno YA CONCLUYÓ: sirven para
    // el examen de grado, para retomar un tema, para titulación.
    final historicas = lista('historicas');
    // (ago-9) Material abierto a toda la comunidad: talleres, conferencias,
    // la bienvenida. No pertenece a ninguna materia.
    final institucionales = lista('institucionales');

    final total = grabaciones.length + historicas.length + institucionales.length;
    final conBuscador = total > 6;
    final visibles = grabaciones.where(_coincide).toList();
    final histVisibles = historicas.where(_coincide).toList();
    final instVisibles = institucionales.where(_coincide).toList();

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bannerCorreo(correo),
          const SizedBox(height: 14),
          _contador(asistidas, sesiones, aplica),
          const SizedBox(height: 16),

          if (conBuscador) ...[
            TextField(
              controller: _busca,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por materia o fecha…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: _busca.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _busca.clear()),
                      ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          _titulo('🎥 GRABACIONES DISPONIBLES', cessumInk(context)),
          const SizedBox(height: 8),
          if (grabaciones.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                  'Aún no hay grabaciones publicadas de tu grupo. '
                  'Aparecen aquí unas horas después de cada sesión en vivo.',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
            )
          else if (visibles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Ninguna grabación coincide con la búsqueda.',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
            )
          else
            ..._porMateria(visibles),

          // Talleres, conferencias y sesiones abiertas de la institución.
          if (instVisibles.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.campaign_outlined, size: 18, color: cessumGold),
                const SizedBox(width: 6),
                Expanded(child: _titulo('TALLERES Y SESIONES ABIERTAS', cessumGold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                'Actividades de la institución abiertas a toda la comunidad. '
                'No son de una materia en particular.',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 8),
            for (final g in instVisibles) _tarjetaGrabacion(g),
          ],

          // Materias ya concluidas: plegadas, pero disponibles.
          if (histVisibles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: _busca.text.isNotEmpty,
                leading: const Icon(Icons.history, color: cessumGold, size: 22),
                title: Text('Materias que ya concluiste (${histVisibles.length})',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: cessumInk(context))),
                subtitle: Text('Tus clases anteriores siguen aquí para repasar.',
                    style: TextStyle(fontSize: 11, color: cessumMuted(context))),
                children: [..._porMateria(histVisibles)],
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _titulo(String t, Color c) => Text(t,
      style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: c));

  Widget _bannerCorreo(String correo) {
    final oscuro = cessumIsDark(context);
    final tinta = oscuro ? const Color(0xFFE9C98B) : const Color(0xFF6B4A0C);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: oscuro ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.badge, color: tinta, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                'Ingresa a tus sesiones en vivo con tu CORREO '
                'INSTITUCIONAL${correo.isNotEmpty ? ' ($correo)' : ''}. '
                'Es el único que Google reporta en la lista de '
                'asistencia: si entras con otro correo, tu '
                'asistencia NO se acredita.',
                style: TextStyle(
                    fontSize: 12, height: 1.45, fontWeight: FontWeight.w600, color: tinta)),
          ),
        ],
      ),
    );
  }

  Widget _contador(int asistidas, int sesiones, bool aplica) {
    final pct = sesiones > 0 ? (asistidas / sesiones).clamp(0.0, 1.0) : 0.0;
    final color = sesiones == 0
        ? cessumRed
        : (pct >= 0.8 ? _verde : (pct >= 0.6 ? cessumGold : cessumRed));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          const Text('MI ASISTENCIA A SESIONES EN VIVO',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: cessumRed)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(sesiones > 0 ? '$asistidas de $sesiones' : '—',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: color)),
              if (sesiones > 0) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${(pct * 100).round()}%',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800, color: color)),
                ),
              ],
            ],
          ),
          Text(
              // (ago-9) Si no hay lista no es culpa del alumno: la genera
              // Google al cerrar la reunión, y hay que decírselo.
              sesiones > 0
                  ? 'sesiones con lista de asistencia de Google Meet'
                  : 'Todavía no hay lista de asistencia de tu grupo. '
                      'No es algo que dependa de ti.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          if (sesiones == 0) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.08),
                border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                  'La lista se toma del informe que Google genera al '
                  'terminar cada sesión. Si tus clases en vivo no '
                  'aparecen aquí, coméntalo con tu profesor o con '
                  'Vicerrectoría: se activa del lado de la institución, '
                  'no del tuyo. Tu asistencia real la sigue teniendo tu '
                  'profesor.',
                  style: TextStyle(fontSize: 11.5, height: 1.4, color: cessumInk(context))),
            ),
          ],
          if (sesiones > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 10,
                backgroundColor: cessumMuted(context).withValues(alpha: 0.15),
                color: color,
              ),
            ),
          ],
          if (aplica) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                  '📋 En tu programa, la asistencia a las sesiones '
                  'síncronas es criterio de evaluación de tus docentes.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: cessumRed)),
            ),
          ],
        ],
      ),
    );
  }

  /// (24-sep) Agrupa por materia, en el orden en que llegan, con un encabezado
  /// que dice cuántas grabaciones tiene cada una.
  List<Widget> _porMateria(List<Map<String, dynamic>> lista) {
    final orden = <String>[];
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final g in lista) {
      final m = '${g['materia'] ?? ''}'.trim();
      final k = m.isEmpty ? 'Sesiones de clase' : m;
      if (!grupos.containsKey(k)) orden.add(k);
      grupos.putIfAbsent(k, () => []).add(g);
    }
    if (orden.length == 1) return grupos[orden.first]!.map(_tarjetaGrabacion).toList();
    final out = <Widget>[];
    for (final k in orden) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Row(children: [
          Expanded(
            child: Text(k,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: cessumInk(context))),
          ),
          Text('${grupos[k]!.length}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ]),
      ));
      out.addAll(grupos[k]!.map(_tarjetaGrabacion));
    }
    return out;
  }

  /// Una grabación.
  Widget _tarjetaGrabacion(Map<String, dynamic> g) {
    final asincronica = '${g['tipo'] ?? ''}' == 'Asincrónica';
    final sinEnlace = '${g['url'] ?? ''}'.trim().isEmpty || '${g['url']}' == 'null';
    final oscuro = cessumIsDark(context);
    final cafe = oscuro ? const Color(0xFFE9C98B) : const Color(0xFF8A5A0F);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.2)),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(sinEnlace ? Icons.hourglass_top : Icons.play_circle_fill,
            color: sinEnlace ? cessumFaint(context) : cessumRed, size: 32),
        title: Text(
            '${g['materia'] ?? ''}'.isNotEmpty ? '${g['materia']}' : 'Sesión de clase',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(context))),
        subtitle: Row(children: [
          Flexible(
            child: Text('${g['fecha'] ?? ''}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
            decoration: BoxDecoration(
              color: asincronica
                  ? cessumGold.withValues(alpha: 0.14)
                  : cessumRed.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(asincronica ? '📼 ASINCRÓNICA' : '🔴 SÍNCRONA',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: asincronica ? cafe : cessumRed)),
          ),
        ]),
        trailing: Icon(sinEnlace ? Icons.schedule : Icons.open_in_new,
            size: 16, color: cessumMuted(context)),
        onTap: () => _abrir(g),
      ),
    );
  }
}

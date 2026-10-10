// =====================================================================
//  pulso_admin_screen.dart · CESSUM · Aula CESSUM / El Guardián
//  PULSO INSTITUCIONAL — qué espera decisión y qué automatización se cayó.
//
//  Por qué existe: esos dos datos ya se calculaban, pero solo llegaban por
//  correo una vez al día. Si el correo se archiva o se pierde, nadie sabe
//  cuántos pagos llevan una semana sin validar ni que el escáner de
//  retroalimentación lleva 30 horas muerto. Aquí se ven cuando se quieran.
//
//  Backend (ambas rutas ya existen, ninguna envía correos):
//    GET resumen_vicerrectoria&prueba=1   → pendientes por rubro
//    GET latidos                          → última corrida de cada escáner
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class PulsoAdminScreen extends StatefulWidget {
  const PulsoAdminScreen({super.key});
  @override
  State<PulsoAdminScreen> createState() => _PulsoAdminScreenState();
}

class _PulsoAdminScreenState extends State<PulsoAdminScreen> {
  bool _cargando = true;
  String? _error;

  int _totalPendientes = 0;
  int _erroresApp = 0;
  List<Map<String, dynamic>> _bloques = [];
  List<Map<String, dynamic>> _modulos = [];
  Map<String, dynamic> _disparadores = {};
  String? _ejecutando;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
    final r = await http.get(uri).timeout(const Duration(seconds: 90));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // prueba=1 es deliberado: calcula los pendientes SIN mandar el correo
      // diario. Abrir el tablero no debe disparar notificaciones.
      final r = await _get({'accion': 'resumen_vicerrectoria', 'prueba': '1'});
      if (r['ok'] != true) throw Exception(r['error'] ?? 'Error');
      Map<String, dynamic> lat = {};
      try {
        lat = await _get({'accion': 'latidos'});
      } catch (_) {
        // el latido es complementario: si falla, los pendientes igual se ven
      }
      if (!mounted) return;
      setState(() {
        _totalPendientes = (r['totalPendientes'] ?? 0) as int;
        _erroresApp = (r['erroresApp24h'] ?? 0) as int;
        _bloques = (r['bloques'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _modulos = (lat['modulos'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _disparadores = lat['disparadores'] == null
            ? {}
            : Map<String, dynamic>.from(lat['disparadores'] as Map);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  /// Ejecuta la URL de arreglo de un módulo detenido (instalar su disparador).
  /// Se pide confirmación porque varias de esas rutas ponen a correr escáneres
  /// que mandan correos a alumnos o docentes.
  Future<void> _revivir(Map<String, dynamic> m) async {
    final arreglo = (m['arreglo'] ?? '').toString();
    if (arreglo.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reactivar ${m['modulo']}',
            style: const TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se va a ejecutar:\n$arreglo',
                style: const TextStyle(fontSize: 12.5, height: 1.35)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.08), // (24-sep) modo oscuro
                  border: Border.all(color: CC.goldBorder),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text(
                  '⚠ Esto deja el escáner corriendo solo. Si el módulo manda '
                  'avisos a alumnos o docentes, empezarán a salir en cuanto '
                  'encuentre algo pendiente. Si llevas días sin correrlo, '
                  'conviene sembrar primero en modo silencioso.',
                  style: TextStyle(fontSize: 11.5, height: 1.35)),
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
            child: const Text('Reactivar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ejecutando = (m['clave'] ?? '').toString());
    try {
      final url = guardianUrl + arreglo;
      final r = await http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: d['ok'] == true ? const Color(0xFF1E8E3E) : cessumRed,
        content: Text(d['ok'] == true
            ? 'Reactivado. Vuelve a revisar el pulso en unos minutos.'
            : '${d['error'] ?? 'No se pudo'}'),
      ));
      if (d['ok'] == true) _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
    if (mounted) setState(() => _ejecutando = null);
  }

  @override
  Widget build(BuildContext context) {
    final detenidos =
        _modulos.where((m) => m['detenido'] == true).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Pulso institucional'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Padding(
              padding: EdgeInsets.all(12), child: CessumSkeletonList())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off,
                            size: 46, color: cessumFaint(context)),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        ElevatedButton(
                            onPressed: _cargar,
                            child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
                    children: [
                      _cabecera(detenidos),
                      const SizedBox(height: 16),
                      _tituloSeccion('Esperando decisión'),
                      if (_bloques.isEmpty)
                        _vacio('Nada pendiente. Todo al corriente.')
                      else
                        ..._bloques.map(_tarjetaBloque),
                      const SizedBox(height: 18),
                      _tituloSeccion('Latido de las automatizaciones'),
                      if (_modulos.isEmpty)
                        _vacio('No se pudo leer el latido.')
                      else
                        ..._modulos.map(_tarjetaModulo),
                      if (_disparadores.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _listaDisparadores(),
                      ],
                      const SizedBox(height: 18),
                      _tituloSeccion('Revisiones de datos'),
                      _seccionRevisiones(),
                    ],
                  ),
                ),
    );
  }

  Widget _cabecera(int detenidos) {
    final hayProblema = detenidos > 0 || _erroresApp > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB11D29), Color(0xFF8E1720)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_totalPendientes',
                    style: CessumType.display(38, color: Colors.white)),
                const Text('asuntos esperando decisión',
                    style: TextStyle(fontSize: 12.5, color: Colors.white70)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _pastilla(
                  detenidos == 0
                      ? 'Todo corriendo'
                      : '$detenidos detenida(s)',
                  detenidos == 0),
              const SizedBox(height: 6),
              _pastilla(
                  _erroresApp == 0
                      ? 'Sin errores hoy'
                      : '$_erroresApp error(es) 24 h',
                  _erroresApp == 0),
              if (hayProblema) ...[
                const SizedBox(height: 6),
                const Text('revisa abajo',
                    style: TextStyle(fontSize: 10.5, color: Colors.white60)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _pastilla(String texto, bool bien) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withValues(alpha: bien ? 0.16 : 0.28),
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(bien ? Icons.check_circle : Icons.error_outline,
                size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(texto,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ],
        ),
      );

  Widget _tituloSeccion(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: cessumRed)),
      );

  Widget _vacio(String t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFEFF7EF),
            borderRadius: BorderRadius.circular(12)),
        child: Text(t,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF1B5E20))),
      );

  Widget _tarjetaBloque(Map<String, dynamic> b) {
    final dias = (b['dias'] ?? 0) as int;
    final urgente = dias >= 7;
    final extra = (b['extra'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: urgente ? cessumRed.withValues(alpha: 0.5) : cessumMuted(context).withValues(alpha: 0.18),
            width: urgente ? 1.4 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            alignment: Alignment.center,
            child: Text('${b['total'] ?? 0}',
                style: CessumType.display(24,
                    color: urgente ? cessumRed : cessumInk(context))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${b['titulo'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${b['donde'] ?? ''}',
                    style: TextStyle(
                        fontSize: 11.5, color: cessumMuted(context), height: 1.3)),
                if (dias > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                      'Lo más antiguo lleva $dias día${dias == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: urgente ? cessumRed : cessumGold)),
                ],
                if (extra.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(extra,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFC62828))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaModulo(Map<String, dynamic> m) {
    final detenido = m['detenido'] == true;
    final horas = m['horasSinLatir'];
    final ocupado = _ejecutando == (m['clave'] ?? '').toString();
    final color = detenido ? cessumRed : const Color(0xFF1E8E3E);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: detenido ? 0.5 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${m['modulo'] ?? ''}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Text(
                  horas == null
                      ? 'sin dato'
                      : (horas == 0 ? 'ahora mismo' : 'hace $horas h'),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 18),
            child: Text(
                'Última corrida: ${(m['ultimo'] ?? '—')}'
                '${(m['filas'] ?? 0) != 0 ? '  ·  ${m['filas']} registros' : ''}'
                '${(m['nota'] ?? '').toString().isNotEmpty ? '\n${m['nota']}' : ''}',
                style: TextStyle(
                    fontSize: 11, color: cessumMuted(context), height: 1.35)),
          ),
          if (detenido) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact),
                onPressed: ocupado ? null : () => _revivir(m),
                icon: ocupado
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow, size: 17),
                label: const Text('Reactivar',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// (ago-9) Los diagnósticos que hasta hoy solo se podían correr pegando
  /// URLs en el navegador. Todos son de SOLO LECTURA: no escriben hojas ni
  /// envían correos, así que se pueden correr sin miedo cuantas veces sea.
  /// Lo que devuelven se muestra en un diálogo con el conteo y los primeros
  /// renglones; el detalle completo sigue disponible por URL para quien lo
  /// necesite exportar.
  Widget _seccionRevisiones() {
    final revisiones = <Map<String, dynamic>>[
      {
        'accion': 'siga_materias_sin_clave',
        'titulo': 'Materias sin clave (bloquean SIGA)',
        'detalle':
            'Agrupa por materia, no por alumno: siete errores pueden ser una '
            'sola materia repetida.',
        'icono': Icons.vpn_key_outlined,
        'lista': 'detalle',
        'campos': ['materia', 'programa', 'alumnosAfectados', 'claveSugerida'],
      },
      {
        'accion': 'titulacion_fotos_diag',
        'titulo': 'Fotografías del título incompletas',
        'detalle':
            'Quién eligió impresión en CESSUM y le falta un archivo. Revisa '
            'los de estado "soloPago": puede que ahí estén sus fotos.',
        'icono': Icons.photo_camera_outlined,
        'lista': 'casos',
        'campos': ['nombre', 'matricula', 'estado', 'estatusFotos'],
      },
      {
        'accion': 'grabaciones_huerfanas',
        'titulo': 'Grabaciones sin materia',
        'detalle':
            'Clases grabadas que no cuadran con ninguna asignación. Si una es '
            'real, puede faltar también su acta y el pago del docente.',
        'icono': Icons.videocam_off_outlined,
        'lista': 'clases',
        'campos': ['materia', 'etiqueta', 'sesiones', 'veredicto'],
      },
      {
        'accion': 'grabaciones_inst_listar',
        'titulo': 'Grabaciones sin publicar',
        'detalle':
            'Talleres y sesiones abiertas que hoy no ve nadie. Puedes '
            'marcarlas como institucionales para toda la comunidad.',
        'icono': Icons.campaign_outlined,
        'lista': 'candidatas',
        'campos': ['titulo', 'fecha'],
      },
    ];
    return Column(
      children: [
        for (final r in revisiones)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(r['icono'] as IconData,
                  color: cessumGold, size: 22),
              title: Text(r['titulo'] as String,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              subtitle: Text(r['detalle'] as String,
                  style: TextStyle(
                      fontSize: 11.5, color: cessumMuted(context), height: 1.3)),
              trailing: _ejecutando == r['accion']
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cessumRed))
                  : const Icon(Icons.play_circle_outline,
                      color: cessumRed, size: 24),
              onTap: _ejecutando == null ? () => _correrRevision(r) : null,
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
              color: const Color(0xFFEFF7EF),
              borderRadius: BorderRadius.circular(10)),
          child: const Text(
              'Estas revisiones solo leen: no cambian nada ni envían correos. '
              'Córrelas cuando quieras.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF1B5E20))),
        ),
      ],
    );
  }

  Future<void> _correrRevision(Map<String, dynamic> r) async {
    setState(() => _ejecutando = r['accion'] as String);
    try {
      final d = await _get({'accion': r['accion'] as String});
      if (!mounted) return;
      if (d['ok'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text('${d['error'] ?? 'No se pudo'}')));
      } else {
        final lista = (d[r['lista']] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        await _verResultado(r, lista);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
    if (mounted) setState(() => _ejecutando = null);
  }

  Future<void> _verResultado(
      Map<String, dynamic> r, List<Map<String, dynamic>> lista) async {
    final campos = (r['campos'] as List).cast<String>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r['titulo'] as String,
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 520,
          child: lista.isEmpty
              ? const Text('Nada que revisar aquí. Todo en orden.',
                  style: TextStyle(fontSize: 13))
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${lista.length} caso(s)',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: cessumRed)),
                      const SizedBox(height: 8),
                      // Se muestran los primeros 25: el diálogo es para
                      // decidir si hay que actuar, no para trabajar la lista
                      // completa. Esa sigue estando en la URL.
                      for (final it in lista.take(25))
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                              color: cessumMuted(context).withValues(alpha: 0.08), // (24-sep) modo oscuro
                              borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final c in campos)
                                if ((it[c] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 2),
                                    child: Text('${it[c]}',
                                        style: TextStyle(
                                            fontSize: c == campos.first
                                                ? 12.5
                                                : 11.5,
                                            height: 1.3,
                                            fontWeight: c == campos.first
                                                ? FontWeight.w700
                                                : FontWeight.w400,
                                            color: c == campos.first
                                                ? cessumInk(context)
                                                : cessumMuted(context))),
                                  ),
                            ],
                          ),
                        ),
                      if (lista.length > 25)
                        Text('… y ${lista.length - 25} más.',
                            style: TextStyle(
                                fontSize: 11.5, color: cessumMuted(context))),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _listaDisparadores() {
    final nombres = _disparadores.keys.toList()..sort();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.schedule, color: cessumGold, size: 20),
        title: Text('Disparadores instalados (${nombres.length})',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
        subtitle: Text(
            'Uno instalado que truena a diario se ve igual de vivo aquí: '
            'el latido de arriba es el que dice la verdad.',
            style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
        children: [
          for (final n in nombres)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.bolt, size: 14, color: cessumGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(n,
                        style: const TextStyle(fontSize: 11.5)),
                  ),
                  if ((_disparadores[n] ?? 1) != 1)
                    Text('×${_disparadores[n]}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFC62828))),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Helpers.abrirUrlExterna(
                  'https://script.google.com/home/triggers', context),
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('Administrar en Apps Script',
                  style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

// menu_dinamico_screen.dart · Aula CESSUM
// ---------------------------------------------------------------------------
// (31-ago-2026) MENÚ DECLARATIVO.
//
// El menú deja de ser código: se lee de la hoja `Menu` del Guardián
// (GET menu_dinamico&actor=correo). Cada fila es una tarjeta con grupo,
// orden, icono, roles, la PANTALLA a la que abre (por nombre) y, si quiere,
// un contador que se pinta como insignia. Nueva función = una fila en la
// hoja. Quitar = Activo NO. Nada que recompilar.
//
// La navegación por nombre se resuelve en MenuRegistro: un mapa
// nombre → constructor. Aquí vienen registradas las cuatro pantallas nuevas
// de la convocatoria; las existentes se suman con UNA línea cada una desde
// cualquier archivo (por ejemplo en main.dart, antes de runApp):
//
//   MenuRegistro.registrar('bajas', (params, actor) => BajasListaScreen());
//   MenuRegistro.registrar('centro_datos', (params, actor) => CentroDatosScreen());
//
// y desde ese momento la hoja puede referirse a 'bajas' o 'centro_datos'.
// `pantalla: url` con params {"url": "..."} muestra el enlace para copiar.
//
// ENGANCHE (una sola tarjeta en el menú actual, la última que se escribe a mano):
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => MenuDinamicoScreen(actor: correoDelAdmin)));
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'avisos_admin_screen.dart';
import 'convocatoria_docente_screen.dart';
import 'diplomado_admin_screen.dart';
import 'resultados_fase2_screen.dart';

const String _kGuardianMenu = 'https://app.cessum.mx/guardian.php';

/// Constructor de una pantalla a partir de sus parámetros y el correo del usuario.
typedef ConstructorPantalla = Widget Function(Map<String, dynamic> params, String actor);

/// Registro nombre → pantalla. Las pantallas de este archivo vienen puestas;
/// las demás se agregan con MenuRegistro.registrar(...) desde donde convenga.
class MenuRegistro {
  static final Map<String, ConstructorPantalla> _pantallas = {
    'convocatoria_docente': (p, a) => ConvocatoriaDocenteScreen(actor: a),
    'resultados_fase2': (p, a) => ResultadosFase2Screen(actor: a),
    'diplomado_admin': (p, a) => DiplomadoAdminScreen(actor: a),
    'avisos_admin': (p, a) => AvisosAdminScreen(actor: a),
  };

  static void registrar(String nombre, ConstructorPantalla c) => _pantallas[nombre] = c;
  static bool existe(String nombre) => _pantallas.containsKey(nombre);
  static Widget? construir(String nombre, Map<String, dynamic> params, String actor) {
    final c = _pantallas[nombre];
    return c == null ? null : c(params, actor);
  }
  static List<String> nombres() => _pantallas.keys.toList()..sort();
}

class MenuDinamicoScreen extends StatefulWidget {
  /// Correo del usuario. Si viene vacío (`const MenuDinamicoScreen()`), la
  /// pantalla lo pide una vez y lo recuerda mientras dure la sesión.
  final String actor;
  /// Rol adicional a pedir (docente/alumno) cuando el correo no es de admin.
  final String rol;
  final String titulo;
  const MenuDinamicoScreen({super.key, this.actor = '', this.rol = '', this.titulo = 'Menú'});

  static String actorMemoria = '';

  @override
  State<MenuDinamicoScreen> createState() => _MenuDinamicoScreenState();
}

class _MenuDinamicoScreenState extends State<MenuDinamicoScreen> {
  static const Color rojo = Color(0xFFB11D29);
  static const Color rojoOsc = Color(0xFF8E1621);
  static const Color oro = Color(0xFFA56B16);
  static const Color verde = Color(0xFF1E7A38);
  static const Color crema = Color(0xFFF7F3EA);
  static const Color linea = Color(0xFFE8DFCE);
  static const Color gris = Color(0xFF6E6E6E);

  Map<String, dynamic>? _menu;
  bool _cargando = false;
  String _error = '';
  bool _pideCorreo = false;
  final _correoCtrl = TextEditingController();
  String get _actor => widget.actor.trim().isNotEmpty ? widget.actor.trim() : MenuDinamicoScreen.actorMemoria;

  // Iconos por nombre (los que usa la hoja). Si no está, cae en `apps`.
  static const Map<String, IconData> _iconos = {
    'apps': Icons.apps,
    'co_present': Icons.co_present_outlined,
    'grading': Icons.grading_outlined,
    'workspace_premium': Icons.workspace_premium_outlined,
    'notifications': Icons.notifications_outlined,
    'open_in_new': Icons.open_in_new,
    'school': Icons.school_outlined,
    'people': Icons.people_outline,
    'person': Icons.person_outline,
    'payments': Icons.payments_outlined,
    'receipt': Icons.receipt_long_outlined,
    'assignment': Icons.assignment_outlined,
    'fact_check': Icons.fact_check_outlined,
    'event': Icons.event_outlined,
    'schedule': Icons.schedule_outlined,
    'chat': Icons.chat_bubble_outline,
    'description': Icons.description_outlined,
    'folder': Icons.folder_outlined,
    'settings': Icons.settings_outlined,
    'health': Icons.health_and_safety_outlined,
    'storage': Icons.storage_outlined,
    'badge': Icons.badge_outlined,
    'campaign': Icons.campaign_outlined,
    'verified': Icons.verified_outlined,
    'history': Icons.history,
    'report': Icons.report_problem_outlined,
    'person_remove': Icons.person_remove_outlined,
    'edit_calendar': Icons.edit_calendar_outlined,
    'video': Icons.videocam_outlined,
    'image': Icons.image_outlined,
    'table': Icons.table_chart_outlined,
    'search': Icons.search,
  };

  @override
  void initState() {
    super.initState();
    if (_actor.isEmpty) { _pideCorreo = true; } else { _cargar(); }
  }

  @override
  void dispose() {
    _correoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (_actor.isEmpty) { setState(() => _pideCorreo = true); return; }
    setState(() { _cargando = true; _error = ''; _pideCorreo = false; });
    try {
      final q = {'accion': 'menu_dinamico', 'actor': _actor, if (widget.rol.isNotEmpty) 'rol': widget.rol, '_ts': DateTime.now().millisecondsSinceEpoch.toString()};
      final r = await http.get(Uri.parse(_kGuardianMenu).replace(queryParameters: q)).timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map<String, dynamic> || j['ok'] != true) throw Exception((j is Map ? j['error'] : null) ?? 'Respuesta inesperada');
      setState(() { _menu = j; _cargando = false; });
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      setState(() { _cargando = false; _error = msg; _pideCorreo = msg.toLowerCase().contains('rol'); });
    }
  }

  Widget _vistaCorreo() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.alternate_email, size: 48, color: oro),
          const SizedBox(height: 12),
          Text(_error.isNotEmpty ? _error : 'Escribe tu correo institucional para cargar tu menú.', textAlign: TextAlign.center, style: const TextStyle(color: gris)),
          const SizedBox(height: 16),
          TextField(
            controller: _correoCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo @cessum.mx', border: OutlineInputBorder()),
            onSubmitted: (_) { MenuDinamicoScreen.actorMemoria = _correoCtrl.text.trim().toLowerCase(); _cargar(); },
          ),
          const SizedBox(height: 12),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () { MenuDinamicoScreen.actorMemoria = _correoCtrl.text.trim().toLowerCase(); _cargar(); }, child: const Text('Entrar')),
        ]),
      );

  void _abrir(Map<String, dynamic> t) {
    final pantalla = (t['pantalla'] ?? '').toString();
    final params = (t['params'] is Map) ? Map<String, dynamic>.from(t['params'] as Map) : <String, dynamic>{};
    if (pantalla == 'url') {
      final url = (params['url'] ?? '').toString();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(t['titulo'].toString()),
          content: SelectableText(url),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rojo),
              onPressed: () async { await Clipboard.setData(ClipboardData(text: url)); if (ctx.mounted) Navigator.pop(ctx); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enlace copiado'), backgroundColor: verde, behavior: SnackBarBehavior.floating)); },
              child: const Text('Copiar enlace'),
            ),
          ],
        ),
      );
      return;
    }
    final w = MenuRegistro.construir(pantalla, params, _actor);
    if (w == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pantalla no registrada'),
          content: Text('La hoja Menu apunta a "$pantalla", pero la app no la tiene registrada. Se registra con una línea:\n\nMenuRegistro.registrar(\'$pantalla\', (p, a) => TuPantalla());\n\nRegistradas: ${MenuRegistro.nombres().join(', ')}'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
        ),
      );
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => w)).then((_) => _cargar());
  }

  @override
  Widget build(BuildContext context) {
    final m = _menu;
    return Scaffold(
      backgroundColor: crema,
      appBar: AppBar(
        backgroundColor: rojo,
        foregroundColor: Colors.white,
        title: Text(widget.titulo),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _pideCorreo
          ? _vistaCorreo()
          : _cargando && m == null
          ? const Center(child: CircularProgressIndicator(color: rojo))
          : m == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, size: 44, color: gris),
                  const SizedBox(height: 10),
                  Text(_error, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
                ])))
              : RefreshIndicator(
                  color: rojo,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                    children: [
                      ...((m['grupos'] as List?) ?? []).map((g) => _grupo(g as Map<String, dynamic>)),
                      if (((m['grupos'] as List?) ?? []).isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Sin tarjetas para este rol. Agrega filas en la hoja Menu del Guardián.', textAlign: TextAlign.center, style: TextStyle(color: gris))),
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text('Menú leído de la hoja Menu · ${m['generado']} · roles: ${((m['roles'] as List?) ?? []).join(', ')}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: gris)),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _grupo(Map<String, dynamic> g) {
    final tarjetas = ((g['tarjetas'] as List?) ?? []).cast<Map<String, dynamic>>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
        child: Text(g['grupo'].toString().toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: oro)),
      ),
      LayoutBuilder(builder: (ctx, c) {
        final cols = c.maxWidth > 700 ? 3 : 2;
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(spacing: 10, runSpacing: 10, children: tarjetas.map((t) => SizedBox(width: w, child: _tarjeta(t))).toList());
      }),
    ]);
  }

  Widget _tarjeta(Map<String, dynamic> t) {
    final icono = _iconos[(t['icono'] ?? 'apps').toString()] ?? Icons.apps;
    final badge = t['badge'];
    final nuevo = t['nuevo'] == true;
    final registrada = (t['pantalla'] ?? '') == 'url' || MenuRegistro.existe((t['pantalla'] ?? '').toString());
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _abrir(t),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: registrada ? linea : oro.withOpacity(.6)), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: rojo.withOpacity(.08), borderRadius: BorderRadius.circular(10)), child: Icon(icono, color: rojoOsc)),
              const Spacer(),
              if (badge is num && badge > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: rojo, borderRadius: BorderRadius.circular(12)),
                  child: Text('${badge.toInt()}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                )
              else if (nuevo)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: oro.withOpacity(.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text('NUEVO', style: TextStyle(color: oro, fontSize: 9.5, fontWeight: FontWeight.w800)),
                ),
            ]),
            const SizedBox(height: 10),
            Text(t['titulo'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.2)),
            if ((t['subtitulo'] ?? '').toString().isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 3), child: Text(t['subtitulo'].toString(), style: const TextStyle(fontSize: 12, color: gris, height: 1.3), maxLines: 3, overflow: TextOverflow.ellipsis)),
            if (!registrada)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text('pantalla sin registrar en la app', style: TextStyle(fontSize: 10.5, color: oro.withOpacity(.9)))),
          ]),
        ),
      ),
    );
  }
}

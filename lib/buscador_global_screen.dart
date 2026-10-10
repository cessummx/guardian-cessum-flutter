// Pantalla de administrador: "Buscador global".
//
// Un solo campo para encontrar alumnos o profesores por nombre, matrícula o
// correo, y saltar a la acción correcta (cambiar de programa / editar docente).
//
// Acción del Guardián:
//   POST buscar_global -> {ok, alumnos:[...], profesores:[...]}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'localizador_alumnos_screen.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cambiar_programa_screen.dart';
import 'avance_multiprograma_screen.dart';
import 'profesores_admin_screen.dart';

class BuscadorGlobalScreen extends StatefulWidget {
  const BuscadorGlobalScreen({super.key});

  @override
  State<BuscadorGlobalScreen> createState() => _BuscadorGlobalScreenState();
}

class _BuscadorGlobalScreenState extends State<BuscadorGlobalScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _buscando = false;
  bool _yaBusco = false;
  String _bienvActiva = '';
  String _actor = '';
  List<Map<String, dynamic>> _alumnos = [];
  List<Map<String, dynamic>> _profes = [];
  List<Map<String, dynamic>> _grupos = [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _alEscribir(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() {
        _alumnos = [];
        _profes = [];
        _grupos = [];
        _yaBusco = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), _buscar);
  }

  Future<void> _buscar() async {
    final q = _ctrl.text.trim();
    if (q.length < 2) return;
    setState(() => _buscando = true);
    try {
      _actor = (await SessionStore.realEmail()) ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(
                  {'accion': 'buscar_global', 'actor': _actor, 'q': q}))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _alumnos = ((data['alumnos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _profes = ((data['profesores'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _grupos = ((data['grupos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _alumnos = [];
        _profes = [];
        _grupos = [];
      }
    } catch (_) {
      _alumnos = [];
      _profes = [];
      _grupos = [];
    }
    if (mounted) {
      setState(() {
        _buscando = false;
        _yaBusco = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscador global'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _alEscribir,
              onSubmitted: (_) => _buscar(),
              decoration: InputDecoration(
                hintText: 'Nombre, matrícula o correo…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cessumRed)),
                      )
                    : (_ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _ctrl.clear();
                              _alEscribir('');
                            },
                          )
                        : null),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(child: _resultados()),
        ],
      ),
    );
  }

  Widget _resultados() {
    if (!_yaBusco) {
      return _centro(Icons.search, 'Escribe para buscar alumnos, profesores o grupos.');
    }
    if (_alumnos.isEmpty && _profes.isEmpty && _grupos.isEmpty) {
      return _centro(Icons.search_off, 'Sin resultados para "${_ctrl.text.trim()}".');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        if (_alumnos.isNotEmpty) ...[
          _encabezado('Alumnos', _alumnos.length),
          ..._alumnos.map(_tarjetaAlumno),
        ],
        if (_profes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _encabezado('Profesores', _profes.length),
          ..._profes.map(_tarjetaProfesor),
        ],
        if (_grupos.isNotEmpty) ...[
          const SizedBox(height: 12),
          _encabezado('Grupos', _grupos.length),
          ..._grupos.map(_tarjetaGrupo),
        ],
      ],
    );
  }

  Widget _tarjetaGrupo(Map<String, dynamic> g) {
    final programa = (g['programa'] ?? '').toString();
    final generacion = (g['generacion'] ?? '').toString();
    final grupo = (g['grupo'] ?? '').toString();
    final alumnos = (g['alumnos'] as num?)?.toInt() ?? 0;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LocalizadorAlumnosScreen(
            initialPrograma: programa.isEmpty ? null : programa,
            initialGeneracion: generacion.isEmpty ? null : generacion,
            initialGrupo: grupo.isEmpty ? null : grupo,
          ),
        ),
      ),
      child: Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.groups, color: cessumGold, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  programa.isEmpty ? 'Grupo $grupo' : programa,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (generacion.isNotEmpty) 'Gen. $generacion',
                    if (grupo.isNotEmpty) 'Grupo $grupo',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$alumnos alumnos',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cessumRed)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: Colors.black38),
        ],
      ),
      ),
    );
  }

  Widget _centro(IconData ic, String txt) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ic, size: 52, color: cessumMuted(context)),
              const SizedBox(height: 12),
              Text(txt,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cessumMuted(context))),
            ],
          ),
        ),
      );

  Widget _encabezado(String t, int n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('$t · $n',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cessumMuted(context))),
      );

  void _msg(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? cessumRed : const Color(0xFF1E8E3E),
    ));
  }

  Future<void> _enviarBienvenida(Map<String, dynamic> a) async {
    final mat = '${a['matricula'] ?? ''}'.trim();
    final nombre = '${a['nombre'] ?? ''}'.trim();
    if (mat.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Correo de bienvenida'),
        content: Text('¿Enviar el correo de bienvenida a $nombre?\n\n'
            'Se manda a su correo institucional con sus accesos a app.cessum.mx.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _bienvActiva = mat);
    try {
      if (_actor.isEmpty) _actor = (await SessionStore.realEmail()) ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'correo_bienvenida',
                'actor': _actor,
                'matricula': mat,
                'correo': '${a['correo'] ?? ''}',
                'nombre': nombre,
                'programa': '${a['programa'] ?? ''}',
              }))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _msg(
        data['ok'] == true
            ? 'Correo de bienvenida enviado a ${data['enviadoA'] ?? nombre}.'
            : '${data['error'] ?? 'No se pudo enviar.'}',
        error: data['ok'] != true,
      );
    } catch (e) {
      _msg('No me pude conectar. Intenta de nuevo.', error: true);
    }
    if (mounted) setState(() => _bienvActiva = '');
  }

  Widget _tarjetaAlumno(Map<String, dynamic> a) {
    final baja = '${a['estatus'] ?? ''}'.toLowerCase() == 'baja';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${a['nombre'] ?? ''}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cessumIsDark(context)
                            ? Colors.white
                            : Colors.black87)),
              ),
              if (baja)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: const Text('Baja',
                      style: TextStyle(fontSize: 11, color: cessumRed)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${a['matricula'] ?? ''} · ${a['programa'] ?? ''}\n'
            '${a['generacion'] ?? ''} · ${a['grupo'] ?? ''}',
            style: TextStyle(fontSize: 12, color: cessumMuted(context)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AvanceMultiprogramaScreen(
                          matriculaInicial: '${a['matricula'] ?? ''}'),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumGold,
                    side: const BorderSide(color: cessumGold),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  icon: const Icon(Icons.timeline, size: 16),
                  label: const Text('Avance'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CambiarProgramaScreen(
                          matriculaInicial: '${a['matricula'] ?? ''}'),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Cambiar programa'),
                ),
                OutlinedButton.icon(
                  onPressed: _bienvActiva == '${a['matricula'] ?? ''}'
                      ? null
                      : () => _enviarBienvenida(a),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E8E3E),
                    side: const BorderSide(color: Color(0xFF1E8E3E)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  icon: _bienvActiva == '${a['matricula'] ?? ''}'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF1E8E3E)))
                      : const Icon(Icons.mark_email_read_outlined, size: 16),
                  label: const Text('Bienvenida'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaProfesor(Map<String, dynamic> p) {
    final titulo = '${p['titulo'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: cessumRed.withValues(alpha: 0.12),
            child:
                const Icon(Icons.school_outlined, color: cessumRed, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${titulo.isEmpty ? '' : '$titulo '}${p['nombre'] ?? ''}',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cessumIsDark(context)
                            ? Colors.white
                            : Colors.black87)),
                const SizedBox(height: 2),
                Text('${p['correo'] ?? ''}',
                    style:
                        TextStyle(fontSize: 12, color: cessumMuted(context))),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Editar docentes',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const ProfesoresAdminScreen()),
            ),
            icon: const Icon(Icons.edit_outlined, color: cessumGold),
          ),
        ],
      ),
    );
  }
}

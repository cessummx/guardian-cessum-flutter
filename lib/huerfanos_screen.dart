// SALUD DE DATOS: matrículas huérfanas — decisión caso por caso.
//
// (ago-24) Los reportes ya decían qué pasa y qué se podría hacer. Lo que
// faltaba era el lugar donde decidir: cada caso necesita una salida distinta
// y ninguna se puede automatizar sin cometer un error caro.
//
// 59 matrículas tienen calificaciones y no existen como alumno. No sobran 59
// filas: faltan 45 alumnos — personas con expediente completo que el sistema
// no reconoce. Karla Lorena con 22 materias, Celia con 15, Zulema con 15.
// Perder a un egresado no es un detalle contable: es no poder expedirle
// constancia, kardex ni título a alguien que terminó sus estudios aquí.
//
// Cuatro salidas por caso, y cada una deja rastro de quién decidió:
//   · Dar de alta   con el estatus que corresponda (Activo, BAJA, EGRESADO)
//   · Reasignar     la matrícula estaba mal tecleada
//   · Eliminar      filas basura de una importación — respalda antes
//   · Dejar así     se revisó y se decide no tocar
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class HuerfanosScreen extends StatefulWidget {
  const HuerfanosScreen({super.key});

  @override
  State<HuerfanosScreen> createState() => _HuerfanosScreenState();
}

class _HuerfanosScreenState extends State<HuerfanosScreen> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _casos = [];
  Map<String, dynamic> _resumen = {};
  String _filtro = '';
  final _q = TextEditingController();

  static const _ambar = Color(0xFFB07D12);
  static const _verde = Color(0xFF1E8E3E);
  static const _azul = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), duration: const Duration(seconds: 5)));
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final u = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'huerfanos_calificaciones',
        'tope': '200',
      });
      final r = await http.get(u).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _casos = ((d['casos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _resumen = Map<String, dynamic>.from(
            (d['resumen'] as Map?) ?? const <String, dynamic>{});
        _cargando = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _q.text.trim().toLowerCase();
    return _casos.where((c) {
      if (_filtro.isNotEmpty && (c['clase'] ?? '') != _filtro) return false;
      if (q.isEmpty) return true;
      return '${c['matricula']} ${c['nombre']} ${c['programa']}'
          .toLowerCase()
          .contains(q);
    }).toList();
  }

  Color _colorClase(String c) {
    if (c.contains('alumno real')) return _verde;
    if (c.contains('mal tecleada')) return _azul;
    if (c.contains('basura')) return cessumRed;
    return _ambar;
  }

  Future<bool> _resolver(Map<String, dynamic> cuerpo) async {
    try {
      final correo = await SessionStore.realEmail(); // (24-sep) correo real
      cuerpo['actor'] = correo ?? '';
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(cuerpo))
          .timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        _aviso(d['error']?.toString() ?? 'No se pudo aplicar.');
        return false;
      }
      _aviso((d['nota'] ?? 'Listo.').toString());
      return true;
    } catch (e) {
      _aviso('Error de conexión: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------- alta

  Future<void> _darDeAlta(Map<String, dynamic> c) async {
    final programa =
        TextEditingController(text: (c['programa'] ?? '').toString());
    final generacion = TextEditingController();
    final nombre = TextEditingController(text: (c['nombre'] ?? '').toString());
    final correo = TextEditingController();
    final grupoLibre = TextEditingController();
    final notas = TextEditingController();
    // EGRESADO por omisión solo cuando el historial lo sostiene. Con pocas
    // materias no hay nada que sostenga esa afirmación.
    final mats = (c['materias'] ?? 0) is num ? (c['materias'] as num) : 0;
    var estatus = mats >= 12 ? 'EGRESADO' : 'Activo';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setL) => AlertDialog(
          title: const Text('Dar de alta en el padrón',
              style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${c['matricula']} · $mats materia(s)',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _campo(nombre, 'Nombre'),
                  _campo(programa, 'Programa'),
                  _campo(generacion, 'Generación',
                      ayuda: 'Formato 23-2. Se guarda como texto para que '
                          'Sheets no la convierta en fecha.'),
                  _campo(correo, 'Correo (opcional)'),
                  const SizedBox(height: 4),
                  Text('ESTATUS',
                      style: TextStyle(
                          fontSize: 11,
                          letterSpacing: .5,
                          fontWeight: FontWeight.w800,
                          color: cessumFaint(context))),
                  const SizedBox(height: 4),
                  for (final op in const [
                    ['EGRESADO', 'Concluyó sus estudios. No cuenta como '
                        'activo y puede recibir constancia, kardex y título.'],
                    ['BAJA', 'Abandonó. Su historial se conserva pero no '
                        'aparece como alumno vigente.'],
                    ['Activo', 'Sigue cursando. Hay que decir en qué grupo.'],
                  ])
                    RadioListTile<String>(
                      value: op[0],
                      groupValue: estatus,
                      onChanged: (v) => setL(() => estatus = v ?? estatus),
                      activeColor: cessumRed,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(op[0],
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      subtitle: Text(op[1],
                          style: const TextStyle(fontSize: 11.5, height: 1.3)),
                    ),
                  if (estatus == 'Activo') ...[
                    const SizedBox(height: 6),
                    _campo(grupoLibre, 'Grupo',
                        ayuda: 'Como aparece en asignaciones: "1 - entre '
                            'semana", "2 - sabatino", "1 - mixta".'),
                  ],
                  _campo(notas, 'Nota de por qué (opcional)',
                      ayuda: 'Queda registrada junto con tu nombre.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx2, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx2, true),
              child: const Text('Dar de alta'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final grupo = estatus == 'Activo' ? grupoLibre.text.trim() : estatus;
    if (grupo.isEmpty) {
      _aviso('Falta decir en qué grupo queda.');
      return;
    }
    final hecho = await _resolver({
      'accion': 'huerfano_resolver',
      'decision': 'alta',
      'matricula': c['matricula'],
      'nombre': nombre.text.trim(),
      'programa': programa.text.trim(),
      'generacion': generacion.text.trim(),
      'correo': correo.text.trim(),
      'grupo': grupo,
      'notas': notas.text.trim(),
    });
    if (hecho) await _cargar();
  }

  // ----------------------------------------------------------- reasignar

  Future<void> _reasignar(Map<String, dynamic> c) async {
    final destino = TextEditingController(
        text: (c['gemeloEnPadron'] ?? '').toString());
    final notas = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mover a la matrícula correcta',
            style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${c['nombre']}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  'Sus ${c['materias']} calificación(es) pasan de '
                  '${c['matricula']} a la matrícula que indiques. La vieja '
                  'deja de existir.',
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 12),
              _campo(destino, 'Matrícula correcta',
                  ayuda: 'Debe existir en el padrón. Se respalda antes de '
                      'mover nada.'),
              _campo(notas, 'Nota (opcional)'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _azul, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mover calificaciones'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hecho = await _resolver({
      'accion': 'huerfano_resolver',
      'decision': 'reasignar',
      'matricula': c['matricula'],
      'matriculaCorrecta': destino.text.trim(),
      'notas': notas.text.trim(),
    });
    if (hecho) await _cargar();
  }

  // ------------------------------------------------------------ eliminar

  Future<void> _eliminar(Map<String, dynamic> c) async {
    final notas = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar estas calificaciones',
            style: TextStyle(fontSize: 17, color: cessumRed)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${c['matricula']} · ${c['nombre']}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                  'Se borran ${c['materias']} fila(s) de la hoja '
                  'Calificaciones. Se genera un respaldo antes, pero esto no '
                  'se deshace desde la app.',
                  style: const TextStyle(fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 8),
              const Text(
                  'Úsalo solo cuando sea basura evidente: matrícula sin forma '
                  'de matrícula, o el nombre con la calificación pegada. Si '
                  'hay duda, es un alumno.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: cessumRed)),
              const SizedBox(height: 10),
              _campo(notas, 'Por qué se elimina'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No, dejarlo')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hecho = await _resolver({
      'accion': 'huerfano_resolver',
      'decision': 'eliminar',
      'matricula': c['matricula'],
      'notas': notas.text.trim(),
    });
    if (hecho) await _cargar();
  }

  Future<void> _ignorar(Map<String, dynamic> c) async {
    final notas = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dejarlo como está', style: TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'El caso deja de aparecer en la lista. Queda registrado con '
                  'tu nombre y la razón, para que dentro de un mes se sepa por '
                  'qué se dejó pasar.',
                  style: TextStyle(fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 10),
              _campo(notas, 'Razón'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _ambar, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar revisado'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hecho = await _resolver({
      'accion': 'huerfano_resolver',
      'decision': 'ignorar',
      'matricula': c['matricula'],
      'notas': notas.text.trim(),
    });
    if (hecho) await _cargar();
  }

  Widget _campo(TextEditingController c, String label, {String? ayuda}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          helperText: ayuda,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Matrículas huérfanas'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No se pudo cargar: $_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cessumMuted(context))),
                  ),
                )
              : _cuerpo(),
    );
  }

  Widget _cuerpo() {
    final lista = _visibles;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Tienen calificaciones pero no existen como alumno en el '
                  'padrón. Cada caso necesita una decisión distinta.',
                  style: TextStyle(fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 10),
              TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar por matrícula, nombre o programa',
                  prefixIcon: const Icon(Icons.search, color: cessumRed),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor)),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              _chip('Todos', _filtro.isEmpty, () => setState(() => _filtro = '')),
              for (final e in _resumen.entries)
                _chip('${e.key} · ${e.value}', _filtro == e.key,
                    () => setState(() => _filtro = e.key),
                    color: _colorClase(e.key)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${lista.length} caso(s)',
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                        'No queda ningún caso pendiente aquí.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cessumMuted(context))),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  itemCount: lista.length,
                  itemBuilder: (_, i) => _tarjeta(lista[i]),
                ),
        ),
      ],
    );
  }

  Widget _chip(String t, bool activo, VoidCallback onTap, {Color? color}) {
    final c = color ?? cessumRed;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: activo ? c : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: activo ? c : Theme.of(context).dividerColor),
          ),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: activo ? Colors.white : cessumInk(context))),
        ),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> c) {
    final clase = (c['clase'] ?? '').toString();
    final col = _colorClase(clase);
    final gemelo = (c['gemeloEnPadron'] ?? '').toString();
    final filas = ((c['filas'] as List?) ?? []).join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${c['matricula']} · ${c['nombre']}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: col.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${c['materias']} materias',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: col)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text('${c['programa']}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 6),
          Text('${c['motivo']}',
              style: TextStyle(fontSize: 12, height: 1.35, color: col)),
          if (filas.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('Filas en Calificaciones: $filas',
                  style:
                      TextStyle(fontSize: 11, color: cessumFaint(context))),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _verde,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _darDeAlta(c),
                icon: const Icon(Icons.person_add_alt, size: 16),
                label: const Text('Dar de alta',
                    style: TextStyle(fontSize: 12.5)),
              ),
              if (gemelo.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _azul,
                      side: const BorderSide(color: _azul),
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _reasignar(c),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: Text('Mover a $gemelo',
                      style: const TextStyle(fontSize: 12.5)),
                )
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _azul,
                      side: const BorderSide(color: _azul),
                      visualDensity: VisualDensity.compact),
                  onPressed: () => _reasignar(c),
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Reasignar',
                      style: TextStyle(fontSize: 12.5)),
                ),
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: _ambar,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _ignorar(c),
                icon: const Icon(Icons.done_all, size: 16),
                label: const Text('Dejar así',
                    style: TextStyle(fontSize: 12.5)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: cessumRed,
                    visualDensity: VisualDensity.compact),
                onPressed: () => _eliminar(c),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Eliminar',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

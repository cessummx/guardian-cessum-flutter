import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'siga_screen.dart';
import 'auth/session_store.dart';

/// CENTRO DE DATOS (solo admin). Reúne en una pantalla las acciones de
/// mantenimiento que antes había que correr a mano por URL:
///   1. Actas — reabrir un acta cerrada por error o validarla.
///   2. Alumno — ver sus dos bases (Grupos vs override) y arreglar el desfase.
///   3. Salud de datos — overrides que contradicen la base, fantasmas, bajas.
///   4. Bajas — marcar una baja tocando las dos bases a la vez.
///   5. Agenda y calendario (3-oct-2026) — auditoría de la hoja de asignaciones,
///      normalización de horas/tipos/nombres, estados «SI», duplicadas y las
///      series del calendario que se quedaron sin fila. Todo con vista previa
///      antes de escribir, y aviso explícito de a quién le llegaría correo.
/// Todas las acciones de escritura mandan el correo de sesión como actor y
/// quedan en la auditoría del backend.
class CentroDatosScreen extends StatefulWidget {
  const CentroDatosScreen({super.key});

  @override
  State<CentroDatosScreen> createState() => _CentroDatosScreenState();
}

class _CentroDatosScreenState extends State<CentroDatosScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _actor = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    SessionStore.realEmail().then((v) {
      if (mounted) setState(() => _actor = v ?? '');
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Centro de datos'),
        actions: [
          // (ago-6) Cabina SIGA: los 5 exportables de la SEC desde la app.
          IconButton(
            tooltip: 'SIGA · Exportables SEC',
            icon: const Icon(Icons.account_balance),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => SigaScreen(actor: _actor)),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: cessumGold,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Actas'),
            Tab(text: 'Alumno'),
            Tab(text: 'Salud de datos'),
            Tab(text: 'Bajas'),
            Tab(text: 'Agenda y calendario'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ActasTab(actor: _actor),
          _AlumnoTab(actor: _actor),
          _SaludTab(actor: _actor),
          _BajasTab(actor: _actor),
          _AgendaTab(actor: _actor),
        ],
      ),
    );
  }
}

// ---------- helpers compartidos ----------

Future<Map<String, dynamic>> _get(Map<String, String> params) async {
  final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
  final resp = await http.get(uri).timeout(const Duration(seconds: 60));
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

Color _colorEstadoActa(String e) {
  if (e == 'Validada') return const Color(0xFF1E8E3E);
  if (e == 'Parcial') return cessumGold;
  return cessumRed;
}

Widget _cajaInfo(String texto, {Color? color}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: (color ?? cessumGold).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(texto, style: const TextStyle(fontSize: 12.5, height: 1.4)),
  );
}

// =====================================================================
//  1) ACTAS — reabrir / validar
// =====================================================================
class _ActasTab extends StatefulWidget {
  final String actor;
  const _ActasTab({required this.actor});

  @override
  State<_ActasTab> createState() => _ActasTabState();
}

class _ActasTabState extends State<_ActasTab> {
  final _busca = TextEditingController();
  List<Map<String, dynamic>> _actas = [];
  bool _cargando = false;
  bool _busco = false;
  String? _trabajando; // clave del acta en proceso

  Future<void> _buscar() async {
    setState(() {
      _cargando = true;
      _busco = true;
    });
    try {
      final data = await _get({
        'accion': 'actas_estado_listar',
        'q': _busca.text.trim(),
      });
      _actas = ((data['actas'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      _actas = [];
    }
    if (mounted) setState(() => _cargando = false);
  }

  String _clave(Map<String, dynamic> a) =>
      '${a['programa']}|${a['generacion']}|${a['grupo']}|${a['materia']}|${a['ciclo']}|${a['periodo']}';

  Future<void> _accionActa(Map<String, dynamic> a, bool reabrir) async {
    final motivoCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reabrir ? 'Reabrir acta' : 'Validar acta',
            style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${a['materia']}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${a['programa']} · ${a['generacion']} · ${a['grupo']}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 12),
            Text(
              reabrir
                  ? 'Regresa el acta a "Pendiente" para que el docente pueda '
                      'capturar de nuevo. Queda registrado en la auditoría.'
                  : 'Cierra el acta. El docente ya no podrá modificar '
                      'calificaciones.',
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
            if (reabrir) ...[
              const SizedBox(height: 10),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo (recomendado)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: reabrir ? cessumRed : const Color(0xFF1E8E3E),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(reabrir ? 'Reabrir' : 'Validar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _trabajando = _clave(a));
    try {
      final params = {
        'accion': reabrir ? 'reabrir_acta' : 'validar_acta',
        'actor': widget.actor,
        'programa': (a['programa'] ?? '').toString(),
        'generacion': (a['generacion'] ?? '').toString(),
        'grupo': (a['grupo'] ?? '').toString(),
        'materia': (a['materia'] ?? '').toString(),
        'ciclo': (a['ciclo'] ?? '').toString(),
        'periodo': (a['periodo'] ?? '').toString(),
      };
      if (reabrir) params['motivo'] = motivoCtrl.text.trim();
      final data = await _get(params);
      if (!mounted) return;
      if (data['ok'] == true) {
        final n = data['reabiertas'] ?? data['validadas'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: reabrir ? cessumRed : const Color(0xFF1E8E3E),
          content: Text(reabrir
              ? 'Acta reabierta ($n calificaciones). Ya aparece para capturar.'
              : 'Acta validada ($n calificaciones).'),
        ));
        _buscar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo: ${data['error'] ?? 'error'}')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error de conexión.')));
      }
    } finally {
      if (mounted) setState(() => _trabajando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _cajaInfo(
            'Busca una materia para ver el estado de su acta y reabrirla '
            '(si se cerró antes de tiempo) o validarla.'),
        TextField(
          controller: _busca,
          decoration: InputDecoration(
            labelText: 'Materia, programa o generación',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: TextButton(
                onPressed: _cargando ? null : _buscar,
                child: const Text('Buscar')),
          ),
          onSubmitted: (_) => _buscar(),
        ),
        const SizedBox(height: 12),
        if (_cargando)
          const Center(child: CircularProgressIndicator(color: cessumRed))
        else if (_busco && _actas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Sin resultados.', textAlign: TextAlign.center),
          )
        else
          ..._actas.map(_tarjetaActa),
      ],
    );
  }

  Widget _tarjetaActa(Map<String, dynamic> a) {
    final estado = (a['estado'] ?? '').toString();
    final col = _colorEstadoActa(estado);
    final enProceso = _trabajando == _clave(a);
    final validada = estado == 'Validada';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text((a['materia'] ?? '').toString(),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: col.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(estado,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: col)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('${a['programa']} · ${a['generacion']} · ${a['grupo']}',
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            Text('${a['validadas']} de ${a['total']} calificaciones validadas',
                style: const TextStyle(fontSize: 11, color: Colors.black45)),
            const SizedBox(height: 6),
            if (enProceso)
              const Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cessumRed)),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (validada || estado == 'Parcial')
                    TextButton.icon(
                      onPressed: () => _accionActa(a, true),
                      icon: const Icon(Icons.lock_open, size: 16),
                      label: const Text('Reabrir'),
                      style: TextButton.styleFrom(foregroundColor: cessumRed),
                    ),
                  if (!validada)
                    TextButton.icon(
                      onPressed: () => _accionActa(a, false),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('Validar'),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF1E8E3E)),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
//  2) ALUMNO — ver las dos bases y arreglar el desfase
// =====================================================================
class _AlumnoTab extends StatefulWidget {
  final String actor;
  const _AlumnoTab({required this.actor});

  @override
  State<_AlumnoTab> createState() => _AlumnoTabState();
}

class _AlumnoTabState extends State<_AlumnoTab> {
  final _mat = TextEditingController();
  Map<String, dynamic>? _diag;
  bool _cargando = false;
  bool _busco = false;

  Future<void> _buscar() async {
    final mat = _mat.text.trim();
    if (mat.isEmpty) return;
    setState(() {
      _cargando = true;
      _busco = true;
      _diag = null;
    });
    try {
      _diag = await _get({'accion': 'diag_padron_alumno', 'matricula': mat});
    } catch (_) {
      _diag = null;
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _borrarOverride() async {
    final mat = _mat.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar override', style: TextStyle(fontSize: 16)),
        content: const Text(
          'Borra el override de padrón de este alumno. Úsalo cuando la base '
          'de Grupos ya tiene el dato correcto y el override viejo lo está '
          'pisando. Queda en la auditoría.',
          style: TextStyle(fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar override'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() => _cargando = true);
    try {
      final data = await _get({
        'accion': 'padron_override_borrar',
        'matricula': mat,
        'actor': widget.actor,
      });
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Color(0xFF1E8E3E),
            content: Text('Override eliminado. Vuelve a mandar el cambio.')));
        _buscar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo: ${data['error'] ?? 'error'}')));
        setState(() => _cargando = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final override = _diag?['override'];
    final tieneOverride = override is Map;
    final filas = (_diag?['filasEnGrupos'] as List?) ?? [];
    final idPadron = (_diag?['identificadoPorPadron'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _cajaInfo(
            'Escribe una matrícula para ver sus dos bases: la de Grupos (real) '
            'y el override de padrón (que le gana). Si no coinciden, el alumno '
            'se ve mal en la app.'),
        TextField(
          controller: _mat,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Matrícula',
            prefixIcon: const Icon(Icons.badge),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: TextButton(
                onPressed: _cargando ? null : _buscar,
                child: const Text('Ver')),
          ),
          onSubmitted: (_) => _buscar(),
        ),
        const SizedBox(height: 12),
        if (_cargando)
          const Center(child: CircularProgressIndicator(color: cessumRed))
        else if (_busco && _diag != null) ...[
          _bloque('En la base de Grupos', const Color(0xFF1E8E3E),
              filas.isEmpty
                  ? ['(sin fila — puede estar de baja o ser fantasma)']
                  : filas
                      .map((f) =>
                          '${f['programa']} · ${f['generacion']} · ${f['grupo']}')
                      .toList()),
          _bloque(
              'Override de padrón (le gana a lo de arriba)',
              tieneOverride ? cessumRed : Colors.black38,
              tieneOverride
                  ? [
                      '${override['programa']} · ${override['generacion']} · ${override['grupo']}'
                          '${(override['estatus'] ?? '').toString().isNotEmpty ? ' · ${override['estatus']}' : ''}'
                    ]
                  : ['(sin override — todo bien por este lado)']),
          _bloque('Lo que la app usa', cessumGold,
              idPadron.isEmpty
                  ? ['(nada)']
                  : idPadron
                      .map((f) =>
                          '${f['programa']} · ${f['generacion']} · ${f['grupo']}')
                      .toList()),
          if (tieneOverride) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
                onPressed: _borrarOverride,
                icon: const Icon(Icons.cleaning_services, size: 18),
                label: const Text('Quitar override (usar lo de Grupos)'),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Solo si la base de Grupos ya está correcta. Si lo que está mal '
              'es Grupos, corrige eso primero desde "Mover grupo".',
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ] else if (_busco)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No se encontró.', textAlign: TextAlign.center),
          ),
      ],
    );
  }

  Widget _bloque(String titulo, Color color, List<String> lineas) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          ...lineas.map((l) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(l, style: const TextStyle(fontSize: 12.5)),
              )),
        ],
      ),
    );
  }
}

// =====================================================================
//  3) SALUD DE DATOS — overrides que contradicen la base
// =====================================================================
class _SaludTab extends StatefulWidget {
  final String actor;
  const _SaludTab({required this.actor});

  @override
  State<_SaludTab> createState() => _SaludTabState();
}

class _SaludTabState extends State<_SaludTab> {
  Map<String, dynamic>? _r;
  bool _cargando = false;
  bool _corri = false;

  Future<void> _correr() async {
    setState(() {
      _cargando = true;
      _corri = true;
    });
    try {
      _r = await _get({'accion': 'diag_overrides_vs_grupos'});
    } catch (_) {
      _r = null;
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _borrar(String mat) async {
    setState(() => _cargando = true);
    try {
      final data = await _get({
        'accion': 'padron_override_borrar',
        'matricula': mat,
        'actor': widget.actor,
      });
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Override eliminado.')));
        _correr();
      } else {
        setState(() => _cargando = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choques = (_r?['choques'] as List?) ?? [];
    final fantasmas = (_r?['huerfanos'] as List?) ?? [];
    final bajas = (_r?['bajas'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _cajaInfo(
            'Revisa los overrides de padrón que contradicen la base de Grupos. '
            'Cada "choque" es un cambio que no se pegó; los "fantasmas" son '
            'alumnos sin fila real.'),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12)),
            onPressed: _cargando ? null : _correr,
            icon: const Icon(Icons.health_and_safety, size: 18),
            label: const Text('Revisar salud de datos'),
          ),
        ),
        const SizedBox(height: 12),
        if (_cargando)
          const Center(child: CircularProgressIndicator(color: cessumRed))
        else if (_corri && _r != null) ...[
          if (choques.isEmpty && fantasmas.isEmpty)
            _cajaInfo('Sin conflictos. Todo cuadra 👍',
                color: const Color(0xFF1E8E3E)),
          if (choques.isNotEmpty) ...[
            const Text('Choques (un cambio que no se pegó)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 6),
            ...choques.map((c) => _tarjetaChoque(
                Map<String, dynamic>.from(c as Map), true)),
          ],
          if (fantasmas.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Fantasmas (sin fila en Grupos)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            const SizedBox(height: 6),
            ...fantasmas.map((c) => _tarjetaChoque(
                Map<String, dynamic>.from(c as Map), false)),
          ],
          if (bajas.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Bajas correctas: ${bajas.length} (nada que corregir)',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ],
      ],
    );
  }

  Widget _tarjetaChoque(Map<String, dynamic> c, bool esChoque) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Matrícula ${c['matricula']}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                children: [
                  const TextSpan(
                      text: 'Override: ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: (c['overrideDice'] ?? '').toString()),
                ],
              ),
            ),
            if (esChoque)
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  children: [
                    const TextSpan(
                        text: 'Base: ',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: (c['baseDice'] ?? '').toString()),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _borrar((c['matricula'] ?? '').toString()),
                icon: const Icon(Icons.cleaning_services, size: 15),
                label: Text(esChoque
                    ? 'Quitar override (usar Grupos)'
                    : 'Quitar override fantasma'),
                style: TextButton.styleFrom(foregroundColor: cessumRed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
//  4) BAJAS — marca la baja en las dos bases
// =====================================================================
class _BajasTab extends StatefulWidget {
  final String actor;
  const _BajasTab({required this.actor});

  @override
  State<_BajasTab> createState() => _BajasTabState();
}

class _BajasTabState extends State<_BajasTab> {
  final _mat = TextEditingController();
  bool _cargando = false;
  String? _resultado;

  Future<void> _marcar() async {
    final mat = _mat.text.trim();
    if (mat.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar baja en Grupos',
            style: TextStyle(fontSize: 16)),
        content: Text(
          'Marca la fila de la matrícula $mat como BAJA en la base de Grupos, '
          'para que deje de aparecer en captura, boletas, actas y "Sin '
          'maestro". Úsalo cuando ya diste la baja en el padrón pero el '
          'alumno sigue apareciendo.',
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Marcar baja'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _cargando = true;
      _resultado = null;
    });
    try {
      final data = await _get({'accion': 'baja_marcar', 'matricula': mat});
      if (!mounted) return;
      if (data['ok'] == true) {
        final ya = data['yaEstaba'] == true;
        _resultado = ya
            ? 'Esa matrícula ya estaba marcada como baja.'
            : 'Baja marcada: ${data['nombre'] ?? ''} '
                '(${data['programa'] ?? ''} ${data['generacion'] ?? ''}).';
      } else {
        _resultado = 'No se pudo: ${data['error'] ?? 'error'}';
      }
    } catch (_) {
      _resultado = 'Error de conexión.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _cajaInfo(
            'Si diste de baja a un alumno en el padrón pero sigue apareciendo '
            'en grupos, actas o captura, es porque su fila en la base de '
            'Grupos no quedó marcada. Aquí la marcas.'),
        TextField(
          controller: _mat,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Matrícula a dar de baja',
            prefixIcon: const Icon(Icons.person_off),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: TextButton(
                onPressed: _cargando ? null : _marcar,
                child: const Text('Marcar')),
          ),
          onSubmitted: (_) => _marcar(),
        ),
        const SizedBox(height: 12),
        if (_cargando)
          const Center(child: CircularProgressIndicator(color: cessumRed)),
        if (_resultado != null)
          _cajaInfo(_resultado!, color: const Color(0xFF1E8E3E)),
      ],
    );
  }
}

// =====================================================================
//  5) AGENDA Y CALENDARIO — revisiones con vista previa (3-oct-2026)
// =====================================================================
// Cada tarjeta corresponde a una ruta del Guardián que ya existía por URL.
// «Revisar» solo lee. «Aplicar» pide confirmación y manda aplicar=1&prueba=0
// (la convención de las reparaciones del Guardián). El barrido del calendario
// tiene dos formas de aplicar, porque una de ellas manda correo a alumnos.

Future<Map<String, dynamic>> _getLargo(Map<String, String> params) async {
  final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
  final resp = await http.get(uri).timeout(const Duration(seconds: 240));
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

class _AgendaTab extends StatefulWidget {
  final String actor;
  const _AgendaTab({required this.actor});
  @override
  State<_AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends State<_AgendaTab> {
  final Map<String, Map<String, dynamic>?> _res = {};
  final Map<String, bool> _ocupado = {};
  final Map<String, String> _error = {};
  final TextEditingController _dias = TextEditingController(text: '60');

  Future<void> _correr(String clave, Map<String, String> params) async {
    setState(() { _ocupado[clave] = true; _error[clave] = ''; });
    try {
      final j = await _getLargo({...params, 'actor': widget.actor});
      if (!mounted) return;
      setState(() { _res[clave] = j; _ocupado[clave] = false; if (j['ok'] != true) _error[clave] = '${j['error'] ?? 'No se pudo.'}'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _ocupado[clave] = false; _error[clave] = 'Error de conexión o tiempo agotado: $e'; });
    }
  }

  Future<bool> _confirmar(String titulo, String texto, {String boton = 'Sí, aplicar'}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(titulo),
        content: Text(texto, style: const TextStyle(height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context, true), child: Text(boton)),
        ],
      ),
    );
    return r == true;
  }

  int _n(dynamic v) => int.tryParse('${v ?? 0}') ?? 0;

  // Pinta una lista de mapas como renglones compactos «clave: valor · clave: valor».
  Widget _renglones(dynamic lista, {int max = 40}) {
    if (lista is! List || lista.isEmpty) return const SizedBox.shrink();
    final filas = lista.take(max).map((e) {
      if (e is Map) {
        return e.entries.where((kv) => '${kv.value ?? ''}'.isNotEmpty && kv.value is! Map && kv.value is! List)
            .map((kv) => '${kv.key}: ${kv.value}').join(' · ');
      }
      return '$e';
    }).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...filas.map((f) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Text('· $f', style: const TextStyle(fontSize: 12, height: 1.35)))),
      if (lista.length > max) Text('… y ${lista.length - max} más', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
    ]);
  }

  Widget _nota(Map<String, dynamic>? j) {
    if (j == null) return const SizedBox.shrink();
    final nota = '${j['nota'] ?? ''}';
    if (nota.isEmpty) return const SizedBox.shrink();
    final esPrueba = j['prueba'] == true || j['aplicado'] == false;
    return _cajaInfo(nota, color: esPrueba ? cessumGold : const Color(0xFF1E8E3E));
  }

  Widget _tarjeta({required String clave, required String titulo, required String descripcion, required Map<String, String> ver,
      required Widget Function(Map<String, dynamic> j) cuerpo, List<Widget> Function(Map<String, dynamic> j)? acciones}) {
    final j = _res[clave];
    final ocupado = _ocupado[clave] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(descripcion, style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
              onPressed: ocupado ? null : () => _correr(clave, ver),
              icon: ocupado ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search, size: 16),
              label: Text(ocupado ? 'Revisando…' : (j == null ? 'Revisar (solo lee)' : 'Volver a revisar')),
            ),
            if (j != null && j['ok'] == true && acciones != null && !ocupado) ...acciones(j),
          ]),
          if ((_error[clave] ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: _cajaInfo(_error[clave]!, color: cessumRed)),
          if (j != null && j['ok'] == true) ...[const SizedBox(height: 10), _nota(j), cuerpo(j)],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      _cajaInfo('Primero «Revisar»: ninguna de estas tarjetas escribe hasta que tocas «Aplicar» y confirmas. Lo que puede mandar correo a alumnos o docentes lo dice antes de hacerlo.'),

      _tarjeta(
        clave: 'aud', titulo: 'Auditoría de la hoja de asignaciones',
        descripcion: 'Qué está mal y cuántas filas: estados «SI», duplicadas, horas sin formato, tipo de sesión que contradice al grupo, nombres de docente con variantes, enlaces de aula inválidos, historial reconstruido duplicado, vencidas, sin correo.',
        ver: const {'accion': 'asignaciones_auditoria'},
        cuerpo: (j) {
          final lectura = (j['lectura'] is List) ? (j['lectura'] as List).map((e) => '$e').toList() : <String>[];
          final hall = (j['hallazgos'] is Map) ? Map<String, dynamic>.from(j['hallazgos'] as Map) : <String, dynamic>{};
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${j['filas'] ?? ''} filas revisadas', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            ...lectura.map((l) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $l', style: const TextStyle(fontSize: 12.5, height: 1.4)))),
            const SizedBox(height: 6),
            ...hall.entries.where((e) => e.value is List && (e.value as List).isNotEmpty).map((e) => ExpansionTile(
              tilePadding: EdgeInsets.zero, dense: true,
              title: Text('${e.key} (${(e.value as List).length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              children: [Align(alignment: Alignment.centerLeft, child: _renglones(e.value, max: 30))],
            )),
          ]);
        },
      ),

      _tarjeta(
        clave: 'norm', titulo: 'Normalizar la agenda (horas, tipo de sesión, fechas, nombres)',
        descripcion: 'Escribe cada hora como «HH:mm - HH:mm», deriva el tipo de sesión del grupo, pone las fechas en formato y deja un solo nombre por docente (el de su fila más reciente). No manda correos ni toca el calendario.',
        ver: const {'accion': 'asignaciones_normalizar'},
        cuerpo: (j) {
          final pc = (j['porCampo'] is Map) ? Map<String, dynamic>.from(j['porCampo'] as Map) : <String, dynamic>{};
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${j['totalCambios'] ?? 0} cambio(s): ${pc.entries.map((e) => '${e.value} ${e.key}').join(' · ')}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            if ((j['horasIlegibles'] is List) && (j['horasIlegibles'] as List).isNotEmpty) ...[
              const SizedBox(height: 8), const Text('Horas ilegibles (no se tocan; corrígelas a mano):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)), _renglones(j['horasIlegibles'])],
            if ((j['horasSoloInicio'] is List) && (j['horasSoloInicio'] as List).isNotEmpty) ...[
              const SizedBox(height: 8), const Text('Horas que solo traen la de inicio (falta el término):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)), _renglones(j['horasSoloInicio'])],
            if ((j['nombresCanonicos'] is List) && (j['nombresCanonicos'] as List).isNotEmpty) ...[
              const SizedBox(height: 8), const Text('Docentes con el nombre escrito de varias formas:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ...((j['nombresCanonicos'] as List).map((e) => e is Map ? Text('· ${e['correo']} → usará «${e['usa']}» (había: ${(e['variantes'] as List?)?.join(' / ') ?? ''})', style: const TextStyle(fontSize: 12)) : const SizedBox.shrink()))],
            if ((j['cambios'] is List) && (j['cambios'] as List).isNotEmpty)
              ExpansionTile(tilePadding: EdgeInsets.zero, dense: true, title: const Text('Ver los cambios fila por fila', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                children: [Align(alignment: Alignment.centerLeft, child: _renglones(j['cambios'], max: 120))]),
          ]);
        },
        acciones: (j) => [
          if (j['prueba'] == true && _n(j['totalCambios']) > 0)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () async {
                if (await _confirmar('Normalizar la hoja', 'Se escribirán ${j['totalCambios']} cambios en la hoja de asignaciones. No se manda ningún correo ni se toca el calendario. ¿Aplicar?')) {
                  _correr('norm', const {'accion': 'asignaciones_normalizar', 'aplicar': '1', 'prueba': '0'});
                }
              },
              icon: const Icon(Icons.save_outlined, size: 16), label: Text('Aplicar ${j['totalCambios']} cambios')),
        ],
      ),

      _tarjeta(
        clave: 'si', titulo: 'Estados de invitación «SI»',
        descripcion: 'El recordatorio de fin de materia pisó el estado de la invitación con «SI». Las seguras (la materia ya corrió con ese docente) se restauran a «Aceptada»; las dudosas se listan y se deciden aparte. Sin correos.',
        ver: const {'accion': 'asignaciones_estado_si_reparar'},
        cuerpo: (j) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${j['totalConEstadoSI'] ?? 0} con «SI» · ${j['seRestauraranAAceptada'] ?? 0} seguras · ${_n(j['totalConEstadoSI']) - _n(j['seRestauraranAAceptada'])} dudosas', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ...j.entries.where((e) => e.value is List && (e.value as List).isNotEmpty && e.key != 'lectura').map((e) => ExpansionTile(
            tilePadding: EdgeInsets.zero, dense: true, title: Text('${e.key} (${(e.value as List).length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            children: [Align(alignment: Alignment.centerLeft, child: _renglones(e.value, max: 60))])),
        ]),
        acciones: (j) => [
          if (j['prueba'] == true && _n(j['seRestauraranAAceptada']) > 0)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () async {
                if (await _confirmar('Restaurar estados', 'Se pondrá «Aceptada» en ${j['seRestauraranAAceptada']} fila(s) seguras. Las dudosas no se tocan. No se manda ningún correo. ¿Aplicar?')) {
                  _correr('si', const {'accion': 'asignaciones_estado_si_reparar', 'aplicar': '1', 'prueba': '0'});
                }
              },
              icon: const Icon(Icons.check_circle_outline, size: 16), label: Text('Restaurar ${j['seRestauraranAAceptada']} seguras')),
        ],
      ),

      _tarjeta(
        clave: 'dup', titulo: 'Asignaciones duplicadas',
        descripcion: 'Misma materia asignada dos veces al mismo grupo. Las copias exactas se desactivan (Activa = NO, con una nota; no se borra nada). Las que tienen datos distintos solo se listan para que decidas. Sin correos.',
        ver: const {'accion': 'asignaciones_duplicadas_reparar'},
        cuerpo: (j) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${j['copiasExactasADesactivar'] ?? 0} copia(s) exacta(s) · ${j['duplicadasConDatosDistintos'] ?? 0} con datos distintos', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          if ((j['aDesactivar'] is List) && (j['aDesactivar'] as List).isNotEmpty) ...[const SizedBox(height: 8), const Text('Copias exactas:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)), _renglones(j['aDesactivar'], max: 60)],
          if ((j['distintas'] is List) && (j['distintas'] as List).isNotEmpty) ...[const SizedBox(height: 8), const Text('Con datos distintos (decide tú):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            ...((j['distintas'] as List).map((g) => g is Map ? Padding(padding: const EdgeInsets.only(bottom: 6), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${g['programa'] ?? ''} ${g['generacion'] ?? ''} ${g['grupo'] ?? ''} · ${g['materia'] ?? ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)), _renglones(g['filas'])])) : const SizedBox.shrink()))],
        ]),
        acciones: (j) => [
          if (j['prueba'] == true && _n(j['copiasExactasADesactivar']) > 0)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () async {
                if (await _confirmar('Desactivar copias exactas', 'Se desactivarán ${j['copiasExactasADesactivar']} fila(s) duplicadas (Activa = NO). No se borra nada ni se manda correo. ¿Aplicar?')) {
                  _correr('dup', const {'accion': 'asignaciones_duplicadas_reparar', 'aplicar': '1', 'prueba': '0'});
                }
              },
              icon: const Icon(Icons.content_copy, size: 16), label: Text('Desactivar ${j['copiasExactasADesactivar']} copias')),
        ],
      ),

      _tarjeta(
        clave: 'cal', titulo: 'Calendario: clases sin fila (series fantasma)',
        descripcion: 'Series del calendario que ya no tienen asignación en la hoja: quedaron de filas borradas y los alumnos las siguen viendo. Puedes quitarlas sin avisar (solo desaparecen de sus calendarios) o con el correo de cancelación de Google.',
        ver: {'accion': 'asignaciones_calendario_huerfanos', 'dias': _dias.text.trim().isEmpty ? '60' : _dias.text.trim()},
        cuerpo: (j) {
          final h = (j['huerfanos'] is List) ? (j['huerfanos'] as List) : const [];
          final inv = h.fold<int>(0, (a, e) => a + (e is Map ? _n(e['invitados']) : 0));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${j['seriesDeClase'] ?? 0} series de clase revisadas en ${j['dias']} días · ${h.length} sin fila · $inv invitados en total', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ...h.map((e) => e is Map ? Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(
              '· ${e['titulo']} — Meet ${e['codigoMeet']} — primera sesión ${'${e['primeraSesion'] ?? ''}'.replaceAll('T', ' ').substring(0, '${e['primeraSesion'] ?? ''}'.length >= 16 ? 16 : '${e['primeraSesion'] ?? ''}'.length)} — ${e['sesionesEnVentana']} sesiones — ${e['invitados']} invitados${'${e['aula'] ?? ''}'.isNotEmpty ? ' — aula ${e['aula']}' : ''}${e['quitado'] == true ? ' — QUITADA' : ''}',
              style: const TextStyle(fontSize: 12.5, height: 1.4))) : const SizedBox.shrink()),
            if ((j['errores'] is List) && (j['errores'] as List).isNotEmpty) _cajaInfo('Calendarios que no se pudieron leer: ${(j['errores'] as List).join(' · ')}', color: cessumRed),
          ]);
        },
        acciones: (j) {
          final h = (j['huerfanos'] is List) ? (j['huerfanos'] as List) : const [];
          final inv = h.fold<int>(0, (a, e) => a + (e is Map ? _n(e['invitados']) : 0));
          if (j['aplicado'] == true || h.isEmpty) return [];
          return [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () async {
                if (await _confirmar('Quitar sin avisar', 'Se quitarán ${h.length} serie(s) del calendario. A sus $inv invitados (alumnos y docentes) simplemente les desaparece la clase del calendario: NO se manda ningún correo. Si ya les llegó un recordatorio, avísales tú por otro medio. ¿Quitar?', boton: 'Quitar sin avisar')) {
                  _correr('cal', {'accion': 'asignaciones_calendario_huerfanos', 'dias': _dias.text.trim(), 'aplicar': '1'});
                }
              },
              icon: const Icon(Icons.event_busy, size: 16), label: Text('Quitar ${h.length} sin avisar')),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
              onPressed: () async {
                if (await _confirmar('Quitar y mandar cancelación', 'Se quitarán ${h.length} serie(s) y Google mandará el correo de CANCELACIÓN a sus $inv invitados (alumnos y docentes), con el título de cada clase. ¿Quitar y avisar?', boton: 'Quitar y avisar a $inv')) {
                  _correr('cal', {'accion': 'asignaciones_calendario_huerfanos', 'dias': _dias.text.trim(), 'aplicar': '1', 'notificar': '1'});
                }
              },
              icon: const Icon(Icons.mail_outline, size: 16), label: Text('Quitar y avisar a $inv invitados')),
          ];
        },
      ),
      Row(children: [
        const Text('Días a revisar en el calendario: ', style: TextStyle(fontSize: 12.5)),
        SizedBox(width: 70, child: TextField(controller: _dias, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()), style: const TextStyle(fontSize: 13))),
      ]),
      const SizedBox(height: 24),
    ]);
  }
}

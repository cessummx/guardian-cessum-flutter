import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'constants.dart';
import 'cessum_ui.dart';
// (24-sep) La sesión REAL (lib/auth/). lib/session_store.dart es una copia vieja que debe
// borrarse: no expira la llave al cerrar sesión ni conoce «Ver como profesor».
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Panel de administrador para ajustar el monto de pago de forma puntual,
/// por alumno, por generación o por programa. Muestra también la beca del
/// alumno consultado (tipo, %, y el pago real ya con beca).
class AjustePagosAdminScreen extends StatefulWidget {
  const AjustePagosAdminScreen({super.key});

  @override
  State<AjustePagosAdminScreen> createState() => _AjustePagosAdminScreenState();
}

class _AjustePagosAdminScreenState extends State<AjustePagosAdminScreen> {
  String _ambito = 'alumno';
  final _cClave = TextEditingController();
  final _cMonto = TextEditingController();
  final _cNota = TextEditingController();

  bool _cargando = true;
  String? _errorLista; // (24-sep) antes se callaba y parecía que no había ajustes
  bool _guardando = false;
  bool _consultando = false;
  List<Map<String, dynamic>> _overrides = [];
  Map<String, dynamic>? _consulta; // resultado de consulta por alumno

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cClave.dispose();
    _cMonto.dispose();
    _cNota.dispose();
    super.dispose();
  }

  Future<String> _actor() async => (await SessionStore.realEmail()) ?? '';

  String _money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _errorLista = null;
    });
    try {
      final actor = await _actor();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pago_override_listar',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _overrides = (data['overrides'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _errorLista = (data['error'] ?? 'No se pudo cargar la lista de ajustes.').toString();
      }
    } catch (_) {
      _errorLista = 'No se pudo cargar la lista de ajustes. Intente de nuevo.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  String get _labelClave {
    switch (_ambito) {
      case 'generacion':
        return 'Generación (ej. 26-2)';
      case 'programa':
        return 'Programa (idéntico al padrón)';
      default:
        return 'Matrícula del alumno';
    }
  }

  Future<void> _consultarAlumno() async {
    final mat = _cClave.text.trim();
    if (_ambito != 'alumno' || mat.isEmpty) {
      _aviso('Escribe la matrícula del alumno para consultar.');
      return;
    }
    setState(() {
      _consultando = true;
      _consulta = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mi_pago_mensual',
        'matricula': mat,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _consulta = data;
      } else {
        _aviso(data['error']?.toString() ?? 'No se encontró al alumno.');
      }
    } catch (_) {
      _aviso('Error al consultar.');
    }
    if (mounted) setState(() => _consultando = false);
  }

  /// (24-sep) A quién afecta el ajuste, según el padrón activo.
  Future<Map<String, dynamic>?> _alcance(String clave) async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'pago_override_alcance',
            'ambito': _ambito,
            'clave': clave,
          }))
          .timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo revisar el alcance.');
      return d;
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''));
      return null;
    }
  }

  /// Muestra a quién afecta y devuelve la clave con la que se debe guardar
  /// (la escrita, o la corregida), o null si se cancela.
  Future<String?> _confirmarAlcance(Map<String, dynamic> a, String clave, String monto) async {
    final total = (a['total'] as num?)?.toInt() ?? 0;
    final correcta = '${a['escrituraCorrecta'] ?? ''}';
    final sug = ((a['sugerencias'] as List?) ?? []).map((e) => '$e').toList();
    final muestra = ((a['muestra'] as List?) ?? []).map((e) => '$e').toList();
    final grupos = Map<String, dynamic>.from((a['porGrupo'] as Map?) ?? const {});
    final montoTxt = _money(num.tryParse(monto.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            correcta.isNotEmpty
                ? 'Así no se aplicaría a nadie'
                : (total == 0 ? 'No coincide con ningún alumno activo' : 'Afectará a $total alumno(s)'),
            style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (correcta.isNotEmpty) ...[
                Text('El programa debe escribirse exactamente como en el padrón: «$correcta». '
                    'Así como está («$clave») el ajuste no se aplicaría a ningún alumno.',
                    style: const TextStyle(fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 8),
                Text('Con la escritura correcta afecta a $total alumno(s) activos.',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ] else if (total == 0) ...[
                Text('«$clave» no coincide con ningún alumno activo. Si es un error de captura, elija la opción correcta:',
                    style: const TextStyle(fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 8),
                for (final x in sug)
                  TextButton(
                    style: TextButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: cessumRed),
                    onPressed: () => Navigator.pop(ctx, x),
                    child: Text('Usar «$x»'),
                  ),
                if (sug.isEmpty)
                  const Text('No encontré nada parecido.', style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 6),
                const Text('Si es a propósito (por ejemplo, una generación que aún no inicia), puede guardarlo de todos modos.',
                    style: TextStyle(fontSize: 12)),
              ] else ...[
                Text('Nuevo monto base: $montoTxt. Si alguno tiene beca, la beca se aplica encima.',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final e in grupos.entries) Text('• ${e.key}: ${e.value}', style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                for (final m in muestra) Text(m, style: const TextStyle(fontSize: 12)),
                if (total > muestra.length) Text('… y ${total - muestra.length} más.', style: const TextStyle(fontSize: 12)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          if (correcta.isNotEmpty)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, correcta),
              child: Text('Usar «$correcta» y guardar'),
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, clave),
              child: Text(total == 0 ? 'Guardar de todos modos' : 'Guardar para $total'),
            ),
        ],
      ),
    );
  }

  Future<void> _guardar() async {
    var clave = _cClave.text.trim();
    final monto = _cMonto.text.trim();
    if (clave.isEmpty) {
      _aviso('Falta la clave (${_labelClave.toLowerCase()}).');
      return;
    }
    if (monto.isEmpty) {
      _aviso('Escribe el monto.');
      return;
    }
    // (24-sep) Antes de guardar: a quién afecta (y si la clave está bien escrita).
    setState(() => _guardando = true);
    final alc = await _alcance(clave);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (alc == null) return;
    final usar = await _confirmarAlcance(alc, clave, monto);
    if (usar == null || !mounted) return;
    clave = usar;
    _cClave.text = usar;
    setState(() => _guardando = true);
    try {
      final actor = await _actor();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'pago_override_guardar',
                'actor': actor,
                'ambito': _ambito,
                'clave': clave,
                'monto': monto,
                'nota': _cNota.text.trim(),
              }))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _aviso('Ajuste guardado: ${_money(num.tryParse(monto) ?? 0)}.');
        _cMonto.clear();
        _cNota.clear();
        await _cargar();
      } else {
        _aviso(data['error']?.toString() ?? 'No se pudo guardar.');
      }
    } catch (_) {
      _aviso('Error al guardar.');
    }
    if (mounted) setState(() => _guardando = false);
  }

  Future<void> _eliminar(Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar ajuste'),
        content: Text(
            '¿Eliminar el ajuste de ${o['ambito']} "${o['clave']}" (${_money((o['monto'] ?? 0) as num)})?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final actor = await _actor();
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'pago_override_eliminar',
                'actor': actor,
                'fila': o['fila'],
              }))
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _aviso('Ajuste eliminado.');
        await _cargar();
      } else {
        _aviso(data['error']?.toString() ?? 'No se pudo eliminar.');
      }
    } catch (_) {
      _aviso('Error al eliminar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Ajuste de pagos'),
        actions: [
          IconButton(
              onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _formCard(),
                if (_ambito == 'alumno' && _consulta != null) ...[
                  const SizedBox(height: 12),
                  _consultaCard(),
                ],
                const SizedBox(height: 18),
                const Text('Ajustes registrados',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                if (_errorLista != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_errorLista!, style: const TextStyle(color: cessumRed, fontWeight: FontWeight.w600)),
                  )
                else if (_overrides.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Aún no hay ajustes.',
                        style: TextStyle(color: cessumMuted(context))),
                  )
                else
                  ..._overrides.map(_overrideTile),
              ],
            ),
    );
  }

  Widget _formCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nuevo ajuste de pago',
              style: TextStyle(
                  color: cessumRed, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _ambito,
            decoration: const InputDecoration(
              labelText: 'Aplicar a',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'alumno', child: Text('Un alumno')),
              DropdownMenuItem(
                  value: 'generacion', child: Text('Una generación')),
              DropdownMenuItem(value: 'programa', child: Text('Un programa')),
            ],
            onChanged: (v) => setState(() {
              _ambito = v ?? 'alumno';
              _consulta = null;
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cClave,
                  decoration: InputDecoration(
                    labelText: _labelClave,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              if (_ambito == 'alumno') ...[
                const SizedBox(width: 8),
                _consultando
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cessumRed)))
                    : OutlinedButton(
                        onPressed: _consultarAlumno,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: cessumRed,
                            side: const BorderSide(color: cessumRed)),
                        child: const Text('Consultar'),
                      ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cMonto,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Monto de pago (MXN)',
              hintText: 'Ej. 1350',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cNota,
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_guardando ? 'Guardando…' : 'Guardar ajuste'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Prioridad: alumno sobre generación sobre programa. Si el alumno tiene beca, este monto es la base y la beca se aplica encima.',
            style: TextStyle(color: cessumMuted(context), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _consultaCard() {
    final c = _consulta!;
    final esBeca = c['esBeca'] == true;
    final porc = (c['porcentaje'] ?? 0) as num;
    final normal = (c['montoNormalGrupo'] ?? c['montoMensual'] ?? 0) as num;
    final conBeca = (c['montoMensual'] ?? 0) as num;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c['programa'] ?? ''} · Gen. ${c['generacion'] ?? ''}',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: cessumInk(context))),
          const SizedBox(height: 8),
          _kv('Monto habitual', _money(normal)),
          if (esBeca) ...[
            _kv('Beca', '$porc% de descuento'),
            _kv('Pago real con beca', _money(conBeca), destacado: true),
          ] else
            _kv('Beca', 'Sin beca aplicada'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
              width: 150,
              child: Text(k,
                  style: TextStyle(color: cessumMuted(context), fontSize: 13))),
          Text(v,
              style: TextStyle(
                  fontWeight: destacado ? FontWeight.bold : FontWeight.w600,
                  color: destacado ? cessumRed : cessumInk(context),
                  fontSize: destacado ? 16 : 13.5)),
        ],
      ),
    );
  }

  Widget _overrideTile(Map<String, dynamic> o) {
    final amb = (o['ambito'] ?? '').toString();
    final iconos = {
      'alumno': Icons.person,
      'generacion': Icons.groups,
      'programa': Icons.school,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(iconos[amb] ?? Icons.tune, color: cessumRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${o['clave']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('$amb${(o['nota'] ?? '').toString().isNotEmpty ? ' · ${o['nota']}' : ''}',
                    style: TextStyle(
                        color: cessumMuted(context), fontSize: 12)),
              ],
            ),
          ),
          Text(_money((o['monto'] ?? 0) as num),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: cessumRed)),
          IconButton(
            onPressed: () => _eliminar(o),
            icon: Icon(Icons.delete_outline, color: cessumFaint(context)),
          ),
        ],
      ),
    );
  }
}

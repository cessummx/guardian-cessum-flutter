// Pantalla de administrador: "Avance por programa".
//
// Para alumnos con continuidad (p. ej. maestría + doctorado): busca por
// matrícula y muestra el avance de CADA programa por separado — materias
// acreditadas, avance contra el plan y promedio.
//
// Detección de programas (en el Guardián): unión de los programas en que el
// alumno está inscrito (base de grupos) y de los que tiene materias
// acreditadas (calificaciones).
//
// Acción del Guardián:
//   POST avance_multiprograma -> {ok, alumno, multiPrograma, programas:[...]}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class AvanceMultiprogramaScreen extends StatefulWidget {
  final String? matriculaInicial;
  final bool soloPropio; // true: alumno viendo su propio avance (sin buscador)
  const AvanceMultiprogramaScreen(
      {super.key, this.matriculaInicial, this.soloPropio = false});

  @override
  State<AvanceMultiprogramaScreen> createState() =>
      _AvanceMultiprogramaScreenState();
}

class _AvanceMultiprogramaScreenState
    extends State<AvanceMultiprogramaScreen> {
  final _matricula = TextEditingController();
  bool _buscando = false;
  bool _yaBusco = false;
  bool _generandoFicha = false;
  String _actor = '';
  Map<String, dynamic>? _alumno;
  bool _multi = false;
  List<Map<String, dynamic>> _programas = [];

  @override
  void initState() {
    super.initState();
    final mi = widget.matriculaInicial;
    if (mi != null && mi.trim().isNotEmpty) {
      _matricula.text = mi.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) => _buscar());
    } else if (widget.soloPropio) {
      // El backend resuelve la matrícula del propio alumno por su correo.
      WidgetsBinding.instance.addPostFrameCallback((_) => _buscar());
    }
  }

  @override
  void dispose() {
    _matricula.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    var mat = _matricula.text.trim();
    if (mat.isEmpty && !widget.soloPropio) {
      _aviso('Escribe la matrícula o el nombre.', error: true);
      return;
    }
    // Si escribió un nombre (no solo dígitos), resolver a matrícula primero.
    if (!widget.soloPropio &&
        mat.isNotEmpty &&
        !RegExp(r'^\d+$').hasMatch(mat)) {
      final resuelta = await _resolverPorNombre(mat);
      if (resuelta == null) return;
      mat = resuelta;
      _matricula.text = mat;
    }
    setState(() {
      _buscando = true;
      _programas = [];
      _alumno = null;
    });
    try {
      _actor = (await SessionStore.realEmail()) ?? '';
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'avance_multiprograma',
                'actor': _actor,
                'matricula': mat,
              }))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _alumno = data['alumno'] is Map
            ? Map<String, dynamic>.from(data['alumno'] as Map)
            : null;
        _multi = data['multiPrograma'] == true;
        _programas = ((data['programas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _aviso('${data['error'] ?? 'No se pudo consultar.'}', error: true);
      }
    } catch (e) {
      _aviso('Error: $e', error: true);
    }
    if (mounted) {
      setState(() {
        _buscando = false;
        _yaBusco = true;
      });
    }
  }

  // Resuelve un nombre a matrícula con buscar_alumno. Si hay varias
  // coincidencias, muestra un diálogo para elegir.
  Future<String?> _resolverPorNombre(String q) async {
    setState(() => _buscando = true);
    List<Map<String, dynamic>> matches = [];
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'buscar_alumno', 'q': q}))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        matches = ((data['alumnos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _buscando = false);
    if (matches.isEmpty) {
      _aviso('No se encontró ningún alumno con "$q".', error: true);
      return null;
    }
    final porMat = <String, Map<String, dynamic>>{};
    for (final m in matches) {
      porMat[(m['matricula'] ?? '').toString()] = m;
    }
    final unicos = porMat.values.toList();
    if (unicos.length == 1) {
      return (unicos.first['matricula'] ?? '').toString();
    }
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('¿Cuál alumno?'),
        children: unicos.map((m) {
          final nom = (m['nombre'] ?? '').toString();
          final prog = (m['programa'] ?? '').toString();
          final mmat = (m['matricula'] ?? '').toString();
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, mmat),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('$nom\n$mmat · $prog',
                  style: const TextStyle(fontSize: 13)),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : cessumGold,
    ));
  }

  Future<void> _descargarFicha() async {
    final mat = (_alumno?['matricula'] ?? _matricula.text).toString().trim();
    if (mat.isEmpty) {
      _aviso('Primero busca un alumno.', error: true);
      return;
    }
    setState(() => _generandoFicha = true);
    try {
      final actor =
          _actor.isNotEmpty ? _actor : ((await SessionStore.realEmail()) ?? '');
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'ficha_alumno_pdf',
                'actor': actor,
                'matricula': mat,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && (data['pdfUrl'] ?? '').toString().isNotEmpty) {
        await launchUrl(Uri.parse(data['pdfUrl'].toString()),
            mode: LaunchMode.externalApplication);
        _aviso('Ficha generada. Se abrió la descarga del PDF.');
      } else {
        _aviso('${data['error'] ?? 'No se pudo generar la ficha.'}',
            error: true);
      }
    } catch (e) {
      _aviso('Error al generar la ficha: $e', error: true);
    }
    if (mounted) setState(() => _generandoFicha = false);
  }

  Widget _botonFicha() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _generandoFicha ? null : _descargarFicha,
          style: OutlinedButton.styleFrom(
            foregroundColor: cessumRed,
            side: const BorderSide(color: cessumRed),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _generandoFicha
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cessumRed))
              : const Icon(Icons.picture_as_pdf),
          label: Text(_generandoFicha
              ? 'Generando ficha…'
              : 'Descargar ficha PDF (360°)'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.soloPropio ? 'Mi avance' : 'Avance por programa'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.soloPropio)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _matricula,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Matrícula o nombre',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onSubmitted: (_) => _buscar(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _buscando ? null : _buscar,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white),
                    child: _buscando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Buscar'),
                  ),
                ),
              ],
            ),
          if (!widget.soloPropio) const SizedBox(height: 16),
          if (widget.soloPropio && _buscando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                  child: CircularProgressIndicator(color: cessumRed)),
            ),
          if (_alumno != null) _cabeceraAlumno(),
          if (_alumno != null && !widget.soloPropio) _botonFicha(),
          if (_yaBusco && _programas.isEmpty && !_buscando)
            Padding(
              padding: const EdgeInsets.only(top: 30),
              child: Center(
                child: Text('Sin información de programas para este alumno.',
                    style: TextStyle(color: cessumMuted(context))),
              ),
            ),
          ..._programas.map(_tarjetaPrograma),
        ],
      ),
    );
  }

  Widget _cabeceraAlumno() {
    final a = _alumno!;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${a['nombre'] ?? ''}',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: cessumIsDark(context) ? Colors.white : cessumInk(context))),
          const SizedBox(height: 2),
          Text('Matrícula ${a['matricula'] ?? ''}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          if (_multi) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Continuidad · ${_programas.length} programas',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7A5210))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaPrograma(Map<String, dynamic> p) {
    final avance = p['avancePct'];
    final tieneAvance = avance is num;
    final pct = tieneAvance ? (avance).toDouble() : 0.0;
    final validadas = p['validadas'] ?? 0;
    final total = p['totalPlan'] ?? 0;
    final promedio = p['promedio'];
    final materias = (p['materias'] as List?) ?? [];
    final esActual = p['esActual'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: esActual
                ? cessumRed.withValues(alpha: 0.45)
                : cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: esActual,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('${p['programa'] ?? ''}',
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: cessumIsDark(context)
                                ? Colors.white
                                : cessumInk(context))),
                  ),
                  if (esActual)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: cessumRed.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20)),
                      child: const Text('Actual',
                          style: TextStyle(fontSize: 11, color: cessumRed)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                  '${p['generacion'] ?? ''}'
                  '${(p['grupo'] ?? '').toString().isEmpty ? '' : ' · ${p['grupo']}'}'
                  '${p['inscrito'] == true ? ' · inscrito' : ''}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tieneAvance) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: cessumMuted(context).withValues(alpha: 0.18),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(cessumRed),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                        tieneAvance
                            ? '$pct% · $validadas de $total materias'
                            : '$validadas materias acreditadas',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: cessumIsDark(context)
                                ? Colors.white70
                                : cessumInk(context))),
                    if (promedio is num)
                      Text('Promedio: $promedio',
                          style: TextStyle(
                              fontSize: 12.5, color: cessumMuted(context))),
                    if (!tieneAvance)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: cessumGold.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Plan no cargado',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF7A5210))),
                      ),
                  ],
                ),
              ],
            ),
          ),
          children: [
            if (materias.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Sin materias registradas en este programa.',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              )
            else
              ...materias.map((m) => _filaMateria(
                  Map<String, dynamic>.from(m as Map))),
          ],
        ),
      ),
    );
  }

  Widget _filaMateria(Map<String, dynamic> m) {
    final val = '${m['estatus'] ?? ''}'.toLowerCase() == 'validada';
    final cal = m['calificacion'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(val ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16, color: val ? const Color(0xFF1E8E3E) : cessumFaint(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${m['materia'] ?? ''}',
                    style: TextStyle(
                        fontSize: 13,
                        color: cessumIsDark(context)
                            ? Colors.white
                            : cessumInk(context))),
                if ((m['periodo'] ?? '').toString().isNotEmpty ||
                    (m['ciclo'] ?? '').toString().isNotEmpty)
                  Text(
                      [
                        '${m['periodo'] ?? ''}',
                        '${m['ciclo'] ?? ''}'
                      ].where((x) => x.isNotEmpty).join(' · '),
                      style:
                          TextStyle(fontSize: 11, color: cessumMuted(context))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${cal ?? ''}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cessumIsDark(context) ? Colors.white : cessumInk(context))),
        ],
      ),
    );
  }
}

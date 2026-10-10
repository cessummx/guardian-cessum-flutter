// =====================================================================
//  EXPEDIENTES (4-oct-2026) · Acuerdo 17/11/17 y titulación
//  Revisión de los documentos de cada alumno, juntando cuatro fuentes:
//  los formularios de inscripción de Google (los descubre solo en el
//  Drive), el expediente documental de la app, el expediente de
//  titulación (lo aprobado por Control Escolar) y la verificación del
//  Art. 62. Empareja solo por matrícula, CURP o correo, nunca por nombre.
//  Dos vistas: lo que exige el Acuerdo 17/11/17 para el expediente de
//  ingreso, y lo que el alumno aporta para titularse.
//  Ruta: expedientes_barrido (solo lectura).
// =====================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

const Color _verde = Color(0xFF1E7B34);
const Color _azul = Color(0xFF2F5D8A);
const Color _ambar = Color(0xFFB7791F);

const _docsOrden = ['actaNacimiento', 'curp', 'kardex', 'titulo', 'cedula'];
const _docsCorto = {
  'actaNacimiento': 'Acta',
  'curp': 'CURP',
  'kardex': 'Certificado',
  'titulo': 'Título previo',
  'cedula': 'Cédula previa',
};

class ExpedientesScreen extends StatefulWidget {
  const ExpedientesScreen({super.key});
  @override
  State<ExpedientesScreen> createState() => _ExpedientesScreenState();
}

class _ExpedientesScreenState extends State<ExpedientesScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  bool _titulacion = false;       // false = Acuerdo 17/11/17
  String _estado = 'incompletos'; // todos · incompletos · completos · sinNada
  String _programa = '';
  String _faltaDoc = '';
  String _q = '';
  /// Los formularios piden la CURP como texto: con esto, la CURP registrada y válida cuenta como cumplida.
  bool _curpDato = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final actor = (await SessionStore.realEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'expedientes_barrido', 'actor': actor, if (_curpDato) 'curpDato': '1'});
      final r = await http.get(uri).timeout(const Duration(seconds: 240));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() { _cargando = false; _d = d; if (d['ok'] != true) _error = '${d['error'] ?? 'No se pudo revisar.'}'; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _error = 'No se pudo completar el barrido (conexión o tiempo). Intenta de nuevo en un momento.'; });
    }
  }

  List<Map<String, dynamic>> _l(dynamic v) => (v is List) ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
  int _n(dynamic v) => int.tryParse('${v ?? 0}'.split('.').first) ?? 0;
  List<String> _falta(Map<String, dynamic> a) => ((a[_titulacion ? 'faltaTitulacion' : 'faltaAcuerdo'] as List?) ?? []).map((e) => '$e').toList();

  List<Map<String, dynamic>> get _filtrados {
    final q = _q.trim().toLowerCase();
    return _l(_d['alumnos']).where((a) {
      final f = _falta(a);
      if (_estado == 'incompletos' && f.isEmpty) return false;
      if (_estado == 'completos' && f.isNotEmpty) return false;
      if (_estado == 'sinNada' && a['sinNingunDocumento'] != true) return false;
      if (_programa.isNotEmpty && '${a['programa']}' != _programa) return false;
      if (_faltaDoc.isNotEmpty && !f.contains(_faltaDoc)) return false;
      if (q.isNotEmpty && !'${a['nombre']} ${a['matricula']}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  (Color, IconData) _estilo(String e) {
    switch (e) {
      case 'Aprobado': return (_verde, Icons.verified);
      case 'En revisión': return (_azul, Icons.hourglass_top);
      case 'En expediente': return (Colors.teal, Icons.folder_open);
      case 'Del formulario': return (cessumGold, Icons.assignment_outlined);
      case 'Solo el dato': return (_ambar, Icons.text_fields);
      case 'Rechazado': return (cessumRed, Icons.cancel_outlined);
      default: return (cessumRed, Icons.remove_circle_outline);
    }
  }

  Future<void> _abrir(String url) async {
    if (!url.startsWith('http')) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Expedientes'),
        actions: [IconButton(tooltip: 'Volver a revisar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: cessumRed), SizedBox(height: 14),
                Text('Revisando formularios de inscripción, expediente de la app, titulación y Art. 62…\nPuede tardar uno o dos minutos.', textAlign: TextAlign.center),
              ])))
          : _error.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: cessumRed))))
              : _contenido(),
    );
  }

  Widget _contenido() {
    final lista = _filtrados;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 4), child: _cabecera())),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(14, 6, 14, 6), child: _filtros())),
      SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Text('${lista.length} alumno(s)', style: TextStyle(fontSize: 12, color: cessumMuted(context))))),
      SliverList(delegate: SliverChildBuilderDelegate((ctx, i) => Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: _tarjeta(lista[i])), childCount: lista.length)),
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 30), child: _fuentes())),
    ]);
  }

  Widget _cabecera() {
    final r = Map<String, dynamic>.from((_d['resumen'] as Map?) ?? {});
    final total = _n(r['alumnos']);
    final completos = _n(r[_titulacion ? 'completosTitulacion' : 'completosAcuerdo']);
    final faltan = _l(r['faltantesPorDocumento']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cessumRed, borderRadius: BorderRadius.circular(16), border: const Border(bottom: BorderSide(color: cessumGold, width: 4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<bool>(
          style: SegmentedButton.styleFrom(backgroundColor: Colors.white24, foregroundColor: Colors.white, selectedBackgroundColor: Colors.white, selectedForegroundColor: cessumRed),
          segments: const [
            ButtonSegment(value: false, label: Text('Acuerdo 17/11/17'), icon: Icon(Icons.gavel, size: 16)),
            ButtonSegment(value: true, label: Text('Titulación'), icon: Icon(Icons.school, size: 16)),
          ],
          selected: {_titulacion},
          onSelectionChanged: (s) => setState(() { _titulacion = s.first; _faltaDoc = ''; }),
        ),
        const SizedBox(height: 8),
        FilterChip(
          label: Text('Aceptar la CURP registrada como cumplida', style: TextStyle(fontSize: 12, color: _curpDato ? cessumRed : Colors.white)),
          selected: _curpDato,
          selectedColor: Colors.white,
          checkmarkColor: cessumRed,
          backgroundColor: Colors.white24,
          side: BorderSide.none,
          onSelected: (v) { setState(() => _curpDato = v); _cargar(); },
        ),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$completos', style: const TextStyle(fontSize: 40, height: 1, fontWeight: FontWeight.w800, color: Colors.white)),
          Padding(padding: const EdgeInsets.only(bottom: 4, left: 6), child: Text('de $total con expediente completo', style: const TextStyle(color: Color(0xFFF6EBD3), fontSize: 13.5, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: total == 0 ? 0 : completos / total, minHeight: 8, backgroundColor: Colors.white24, color: cessumGold)),
        const SizedBox(height: 8),
        Text('${_n(r['sinNingunDocumento'])} sin ningún documento en ninguna fuente · ${_n(r['art62Verificados'])} con antecedente verificado (Art. 62) · corte ${_d['generado'] ?? ''}',
            style: const TextStyle(color: Color(0xFFF7DCDC), fontSize: 11.5)),
        if (!_titulacion && faltan.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Lo que más falta (toca para ver quiénes):', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final f in faltan)
              ChoiceChip(
                label: Text('${f['documento']} · ${f['alumnos']}', style: TextStyle(fontSize: 12, color: _faltaDoc == '${f['clave']}' ? cessumRed : Colors.white)),
                selected: _faltaDoc == '${f['clave']}',
                selectedColor: Colors.white,
                backgroundColor: Colors.white24,
                side: BorderSide.none,
                onSelected: (s) => setState(() { _faltaDoc = s ? '${f['clave']}' : ''; if (s) _estado = 'incompletos'; }),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _filtros() {
    final programas = _l(_d['porPrograma']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o matrícula', prefixIcon: const Icon(Icons.search), isDense: true,
          filled: true, fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
        onChanged: (v) => setState(() => _q = v),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 38,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final e in [('incompletos', 'Incompletos'), ('completos', 'Completos'), ('sinNada', 'Sin ningún documento'), ('todos', 'Todos')])
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
              label: Text(e.$2), selected: _estado == e.$1, selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: (_) => setState(() => _estado = e.$1))),
        ]),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 38,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('Todos los programas'), selected: _programa.isEmpty,
              selectedColor: cessumGold.withValues(alpha: 0.2), onSelected: (_) => setState(() => _programa = ''))),
          for (final p in programas)
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
              label: Text('${p['programa']} · ${p['completos']}/${p['total']}'),
              selected: _programa == '${p['programa']}', selectedColor: cessumGold.withValues(alpha: 0.2),
              onSelected: (s) => setState(() => _programa = s ? '${p['programa']}' : ''))),
        ]),
      ),
    ]);
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final docs = Map<String, dynamic>.from((a['docs'] as Map?) ?? {});
    final f = _falta(a);
    final requeridos = a['nivel'] == 'lic' ? ['actaNacimiento', 'curp', 'kardex'] : ['actaNacimiento', 'curp', 'titulo', 'cedula'];
    final completo = f.isEmpty;
    final a62 = '${a['art62'] ?? ''}';
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _detalle(a),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: completo ? _verde : (a['sinNingunDocumento'] == true ? cessumRed : _ambar), width: 5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${a['nombre']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
              if (a['enTitulacion'] == true)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: _azul.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Text('En titulación', style: TextStyle(fontSize: 10.5, color: _azul, fontWeight: FontWeight.w700))),
            ]),
            Text('${a['matricula']} · ${a['programa']} · ${a['generacion']}${'${a['grupo'] ?? ''}'.isNotEmpty ? ' · ${a['grupo']}' : ''}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in requeridos) _chipDoc(c, Map<String, dynamic>.from((docs[c] as Map?) ?? {})),
              if (!_titulacion) _chipArt62(a62),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _chipDoc(String clave, Map<String, dynamic> d) {
    final e = '${d['estado'] ?? 'Falta'}';
    final (color, icono) = _estilo(e);
    final url = '${d['url'] ?? ''}';
    return InkWell(
      onTap: url.startsWith('http') ? () => _abrir(url) : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: e == 'Falta' ? Colors.transparent : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: e == 'Falta' ? 0.7 : 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 4),
          Text(_docsCorto[clave] ?? clave, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }

  Widget _chipArt62(String e) {
    final ok = RegExp('verificad', caseSensitive: false).hasMatch(e) && !RegExp('pendiente|no ', caseSensitive: false).hasMatch(e);
    final color = ok ? _verde : (e == 'Sin registro' ? Colors.grey : _ambar);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.6))),
      child: Text('Art. 62: $e', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  void _detalle(Map<String, dynamic> a) {
    final docs = Map<String, dynamic>.from((a['docs'] as Map?) ?? {});
    final etiquetas = Map<String, dynamic>.from((_d['etiquetas'] as Map?) ?? {});
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), children: [
          Text('${a['nombre']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('${a['matricula']} · ${a['programa']} · ${a['generacion']} · ${a['estatus']}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          const SizedBox(height: 10),
          for (final c in _docsOrden)
            Builder(builder: (_) {
              final d = Map<String, dynamic>.from((docs[c] as Map?) ?? {});
              final e = '${d['estado'] ?? 'Falta'}';
              final (color, icono) = _estilo(e);
              final url = '${d['url'] ?? ''}';
              final requerido = a['nivel'] == 'lic' ? ['actaNacimiento', 'curp', 'kardex'].contains(c) : c != 'kardex';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(icono, color: color),
                title: Text('${etiquetas[c] ?? c}${requerido ? '' : '  (no se exige en este nivel)'}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: Text([
                  e,
                  if ('${d['fuente'] ?? ''}'.isNotEmpty) 'de: ${d['fuente']}',
                  if ('${d['coincidioPor'] ?? ''}'.isNotEmpty) 'identificado por ${d['coincidioPor']}',
                  if ('${d['valor'] ?? ''}'.isNotEmpty) '${d['valor']}',
                  if ('${d['nota'] ?? ''}'.isNotEmpty) '${d['nota']}',
                ].join(' · '), style: TextStyle(fontSize: 12, color: color)),
                trailing: url.startsWith('http') ? IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => _abrir(url)) : null,
              );
            }),
          const Divider(),
          Text('Verificación del antecedente (Art. 62): ${a['art62']}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Text('«Del formulario» significa que el documento está en la inscripción pero aún no pasa por la revisión de Control Escolar. '
              'Los documentos se emparejan solo por matrícula, CURP o correo; nunca por nombre.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.45)),
        ]),
      ),
    );
  }

  Widget _fuentes() {
    final f = _l(_d['fuentes']);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: const Icon(Icons.source_outlined, color: cessumGold),
        title: Text('Fuentes revisadas · ${f.length} formulario(s)', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: const Text('Más el expediente de la app, Titulación y Art. 62', style: TextStyle(fontSize: 11.5)),
        children: [
          for (final x in f)
            ListTile(
              dense: true,
              leading: Icon(x['ok'] == true ? Icons.check_circle : Icons.error_outline, color: x['ok'] == true ? _verde : cessumRed, size: 20),
              title: Text('${x['nombre']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              subtitle: Text(x['ok'] == true
                  ? '${x['filas']} respuesta(s) · documentos: ${((x['documentos'] as List?) ?? []).join(', ')} · identifica por: ${((x['identificadores'] as List?) ?? []).join(', ')} · ${x['emparejados']} documento(s) usados'
                  : '${x['error']}', style: const TextStyle(fontSize: 11.5)),
            ),
        ],
      ),
    );
  }
}
